import { corsHeaders, fail, ok } from "./cors.ts";
import { adminClient, clientIp, EMAIL_RE, readJson, recordAttempt, sha256, tooMany } from "./auth.ts";
import type { OtpPurpose } from "./mailer.ts";

declare const Deno: {
  env: { get(name: string): string | undefined };
  serve(handler: (req: Request) => Response | Promise<Response>): void;
};

type Sb = ReturnType<typeof adminClient>;

export const CODE_TTL_MIN = 10;                       // how long the 6-digit code works
export const TOKEN_TTL_MIN: Record<OtpPurpose, number> = { signup: 30, reset: 10 }; // how long the proof token works
export const MAX_ATTEMPTS = 5;                        // guesses per code
export const RESEND_COOLDOWN_S = 60;

const enc = new TextEncoder();
const hex = (b: ArrayBuffer) => Array.from(new Uint8Array(b)).map((x) => x.toString(16).padStart(2, "0")).join("");

// HMAC key: OTP_PEPPER if set, otherwise the service-role key (never leaves the server either way).
async function hmac(message: string): Promise<string> {
  const secret = Deno.env.get("OTP_PEPPER") || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!; // `||`: an empty OTP_PEPPER= line must fall back too
  const key = await crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return hex(await crypto.subtle.sign("HMAC", key, enc.encode(message)));
}

// Constant-time string compare (both inputs are fixed-length hex).
function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

// Uniform 6-digit code (rejection sampling, no modulo bias).
export function generateCode(): string {
  const limit = 4_294_000_000; // largest multiple of 1_000_000 below 2^32
  const buf = new Uint32Array(1);
  do { crypto.getRandomValues(buf); } while (buf[0] >= limit);
  return String(buf[0] % 1_000_000).padStart(6, "0");
}

function generateToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

const codeHash = (email: string, purpose: OtpPurpose, code: string) => hmac(`code|${purpose}|${email}|${code}`);
const tokenHash = (email: string, purpose: OtpPurpose, token: string) => hmac(`token|${purpose}|${email}|${token}`);

// Creates (or replaces) the single live code for this email + purpose.
export async function issueOtp(sb: Sb, email: string, purpose: OtpPurpose, ip: string):
  Promise<{ code: string } | { cooldown: number } | { error: true }> {
  const { data: prev } = await sb.from("email_otps").select("sent_at").eq("email", email).eq("purpose", purpose).maybeSingle();
  if (prev) {
    const wait = RESEND_COOLDOWN_S - Math.floor((Date.now() - new Date(prev.sent_at).getTime()) / 1000);
    if (wait > 0) return { cooldown: wait };
  }
  const code = generateCode();
  const now = Date.now();
  const { error } = await sb.from("email_otps").upsert({
    email, purpose, code_hash: await codeHash(email, purpose, code),
    sent_at: new Date(now).toISOString(), expires_at: new Date(now + CODE_TTL_MIN * 60_000).toISOString(),
    attempts: 0, verified_at: null, token_hash: null, token_expires_at: null, used_at: null, ip,
  }, { onConflict: "email,purpose" });
  if (error) { console.error("issueOtp failed:", error.message); return { error: true }; }
  return { code };
}

export type VerifyResult =
  | { ok: true; token: string; expiresIn: number }
  | { ok: false; reason: "invalid_otp" | "otp_expired" | "otp_locked"; attemptsLeft?: number };

// Checks a code. Every guess is counted BEFORE it is compared, and the counter update is conditional,
// so parallel guesses cannot get past the 5-attempt limit.
export async function verifyOtp(sb: Sb, email: string, purpose: OtpPurpose, code: string): Promise<VerifyResult> {
  const { data: row } = await sb.from("email_otps").select("*").eq("email", email).eq("purpose", purpose).maybeSingle();
  if (!row || row.verified_at) return { ok: false, reason: "invalid_otp" };
  if (new Date(row.expires_at).getTime() < Date.now()) return { ok: false, reason: "otp_expired" };
  if (row.attempts >= MAX_ATTEMPTS) return { ok: false, reason: "otp_locked" };

  const { data: bumped } = await sb.from("email_otps").update({ attempts: row.attempts + 1 })
    .eq("id", row.id).eq("attempts", row.attempts).select("id");
  if (!bumped?.length) return { ok: false, reason: "invalid_otp", attemptsLeft: Math.max(0, MAX_ATTEMPTS - row.attempts - 1) };

  const left = MAX_ATTEMPTS - (row.attempts + 1);
  if (!safeEqual(row.code_hash, await codeHash(email, purpose, code))) {
    return left <= 0 ? { ok: false, reason: "otp_locked" } : { ok: false, reason: "invalid_otp", attemptsLeft: left };
  }

  const token = generateToken();
  const ttl = TOKEN_TTL_MIN[purpose];
  const { error } = await sb.from("email_otps").update({
    verified_at: new Date().toISOString(),
    token_hash: await tokenHash(email, purpose, token),
    token_expires_at: new Date(Date.now() + ttl * 60_000).toISOString(),
  }).eq("id", row.id).is("verified_at", null);
  if (error) { console.error("verifyOtp update failed:", error.message); return { ok: false, reason: "invalid_otp" }; }
  return { ok: true, token, expiresIn: ttl * 60 };
}

// Spends the proof token exactly once. Returns false for a wrong, expired or already used token.
export async function claimToken(sb: Sb, email: string, purpose: OtpPurpose, token: string): Promise<boolean> {
  if (!token || token.length > 200) return false;
  const { data: row } = await sb.from("email_otps").select("id, token_hash, token_expires_at, verified_at, used_at")
    .eq("email", email).eq("purpose", purpose).maybeSingle();
  if (!row || !row.verified_at || row.used_at || !row.token_hash || !row.token_expires_at) return false;
  if (new Date(row.token_expires_at).getTime() < Date.now()) return false;
  if (!safeEqual(row.token_hash, await tokenHash(email, purpose, token))) return false;
  const { data: claimed } = await sb.from("email_otps").update({ used_at: new Date().toISOString() })
    .eq("id", row.id).is("used_at", null).select("id");
  return !!claimed?.length;
}

// Gives the token back when the action it was spent on failed, so the person need not start over.
export const releaseToken = (sb: Sb, email: string, purpose: OtpPurpose) =>
  sb.from("email_otps").update({ used_at: null }).eq("email", email).eq("purpose", purpose);

// Shared handler for verify-signup-otp and verify-reset-otp.
export async function handleVerify(req: Request, purpose: OtpPurpose): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return fail("method_not_allowed", "POST only", 405);

  const body = await readJson(req);
  const email = String(body?.email ?? "").trim().toLowerCase();
  const otp = String(body?.otp ?? "").trim();
  if (!EMAIL_RE.test(email) || email.length > 254) return fail("invalid_email", "Enter a valid email address.");
  if (!/^\d{6}$/.test(otp)) return fail("invalid_otp", "Enter the 6-digit code.");

  const sb = adminClient();
  const ip = clientIp(req);
  const idHash = await sha256(`${purpose}:${email}`);
  if (await tooMany(sb, { kind: "otp_verify", identHash: idHash, ip, identMax: 10, ipMax: 30, windowMin: 15, failuresOnly: true })) {
    return fail("too_many_attempts", "Too many wrong codes. Try again in 15 minutes.", 429);
  }

  const r = await verifyOtp(sb, email, purpose, otp);
  if (!r.ok) {
    await recordAttempt(sb, "otp_verify", idHash, ip, false);
    if (r.reason === "otp_expired") return fail("otp_expired", "This code has expired. Request a new one.", 400);
    if (r.reason === "otp_locked") return fail("otp_locked", "Too many wrong codes. Request a new one.", 429);
    return fail("invalid_otp", "That code is not correct.", 400, r.attemptsLeft !== undefined ? { attempts_left: r.attemptsLeft } : {});
  }
  await recordAttempt(sb, "otp_verify", idHash, ip, true);
  return ok(purpose === "signup"
    ? { email_verification_token: r.token, expires_in: r.expiresIn }
    : { reset_token: r.token, expires_in: r.expiresIn });
}