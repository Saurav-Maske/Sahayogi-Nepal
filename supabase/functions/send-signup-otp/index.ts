import { corsHeaders, fail, ok } from "../_shared/cors.ts";
import { adminClient, clientIp, EMAIL_RE, readJson, recordAttempt, sha256, tooMany } from "../_shared/auth.ts";
import { CODE_TTL_MIN, issueOtp, RESEND_COOLDOWN_S } from "../_shared/otp.ts";
import { sendOtpEmail } from "../_shared/mailer.ts";

declare const Deno: {
  env: { get(name: string): string | undefined };
  serve(handler: (req: Request) => Response | Promise<Response>): void;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return fail("method_not_allowed", "POST only", 405);

  const body = await readJson(req);
  const email = String(body?.email ?? "").trim().toLowerCase();
  if (!EMAIL_RE.test(email) || email.length > 254) return fail("invalid_email", "A valid email is required.");

  const sb = adminClient();
  const ip = clientIp(req);
  const idHash = await sha256(`signup:${email}`);
  if (await tooMany(sb, { kind: "otp_send", identHash: idHash, ip, identMax: 5, ipMax: 15, windowMin: 60 })) {
    return fail("too_many_attempts", "Too many codes requested. Try again later.", 429);
  }
  await recordAttempt(sb, "otp_send", idHash, ip, false);

  // Same rule the application step enforces, checked early so nobody fills the whole form for nothing.
  const { data: profile } = await sb.from("profiles").select("id").eq("email", email).maybeSingle();
  const { data: live } = await sb.from("volunteer_applications").select("id")
    .eq("email", email).in("review_status", ["submitted", "under_review", "approved"]).limit(1);
  if (profile || live?.length) {
    return fail("application_exists", "An application or account with this email already exists.", 409);
  }

  const issued = await issueOtp(sb, email, "signup", ip);
  if ("cooldown" in issued) {
    return fail("resend_too_soon", `Wait ${issued.cooldown} seconds before asking for a new code.`, 429, { retry_after_seconds: issued.cooldown });
  }
  if ("error" in issued) return fail("otp_failed", "Could not create a code. Try again.", 500);

  if (!(await sendOtpEmail(email, issued.code, "signup", CODE_TTL_MIN))) {
    return fail("email_failed", "Could not send the email. Try again in a moment.", 502);
  }
  return ok({ message: "A 6-digit code has been sent to your email.", expires_in: CODE_TTL_MIN * 60, resend_after: RESEND_COOLDOWN_S });
});