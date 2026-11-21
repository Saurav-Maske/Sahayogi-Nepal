import { corsHeaders, fail, ok } from "../_shared/cors.ts";
import { adminClient, anonClient, clientIp, EMAIL_RE, readJson, recordAttempt, sha256, tooMany } from "../_shared/auth.ts";

declare const Deno: {
  env: { get(name: string): string | undefined };
  serve(handler: (req: Request) => Response | Promise<Response>): void;
};

const GENERIC = { message: "If that email belongs to an account, a link to set your password has been sent." };

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return fail("method_not_allowed", "POST only", 405);

  const body = await readJson(req);
  const email = String(body?.email ?? "").trim().toLowerCase();
  if (!EMAIL_RE.test(email) || email.length > 254) return fail("invalid_email", "Enter a valid email address.", 400);

  const sb = adminClient();
  const ip = clientIp(req);
  const idHash = await sha256(email);

  if (await tooMany(sb, { kind: "reset", identHash: idHash, ip, identMax: 3, ipMax: 10, windowMin: 60 })) {
    return fail("too_many_attempts", "Too many requests. Try again later.", 429);
  }
  await recordAttempt(sb, "reset", idHash, ip, false);

  const { data: p } = await sb.from("profiles").select("id, account_status").eq("email", email).maybeSingle();
  if (p && p.account_status === "active") {
    const { error } = await anonClient().auth.resetPasswordForEmail(email, { redirectTo: Deno.env.get("SET_PASSWORD_URL")! });
    if (error) console.error("resetPasswordForEmail failed:", error.message); // never leak to the caller
  }
  return ok(GENERIC);
});