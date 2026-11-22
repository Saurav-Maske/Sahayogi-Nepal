import { corsHeaders, fail, ok } from "../_shared/cors.ts";
import { adminClient, clientIp, EMAIL_RE, readJson, recordAttempt, sha256, tooMany } from "../_shared/auth.ts";
import { CODE_TTL_MIN, issueOtp } from "../_shared/otp.ts";
import { sendOtpEmail } from "../_shared/mailer.ts";

declare const Deno: {
  env: { get(name: string): string | undefined };
  serve(handler: (req: Request) => Response | Promise<Response>): void;
};

// Same answer whether or not the account exists, so this endpoint cannot be used to find out who has an account.
const GENERIC = { message: "If that email belongs to an account, a 6-digit code has been sent.", expires_in: CODE_TTL_MIN * 60, resend_after: 60 };

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return fail("method_not_allowed", "POST only", 405);

  const body = await readJson(req);
  const email = String(body?.email ?? "").trim().toLowerCase();
  if (!EMAIL_RE.test(email) || email.length > 254) return fail("invalid_email", "Enter a valid email address.", 400);

  const sb = adminClient();
  const ip = clientIp(req);
  const idHash = await sha256(email);

  if (await tooMany(sb, { kind: "reset", identHash: idHash, ip, identMax: 5, ipMax: 15, windowMin: 60 })) {
    return fail("too_many_attempts", "Too many requests. Try again later.", 429);
  }
  await recordAttempt(sb, "reset", idHash, ip, false);

  const { data: p } = await sb.from("profiles").select("id, account_status").eq("email", email).maybeSingle();
  if (p && p.account_status === "active") {
    const issued = await issueOtp(sb, email, "reset", ip);
    // A cooldown or a send failure is logged, never shown: the caller must not learn whether the account exists.
    if ("code" in issued) {
      if (!(await sendOtpEmail(email, issued.code, "reset", CODE_TTL_MIN))) console.error("reset OTP email not sent");
    }
  }
  return ok(GENERIC);
});