import { corsHeaders, fail, ok } from "../_shared/cors.ts";
import { adminClient, audit, clientIp, EMAIL_RE, passwordProblem, readJson, recordAttempt, sha256, tooMany } from "../_shared/auth.ts";
import { claimToken, releaseToken } from "../_shared/otp.ts";

declare const Deno: {
  env: { get(name: string): string | undefined };
  serve(handler: (req: Request) => Response | Promise<Response>): void;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return fail("method_not_allowed", "POST only", 405);

  const body = await readJson(req);
  const email = String(body?.email ?? "").trim().toLowerCase();
  const token = String(body?.reset_token ?? "");
  const password = String(body?.new_password ?? "");
  if (!EMAIL_RE.test(email) || email.length > 254) return fail("invalid_email", "Enter a valid email address.");
  const weak = passwordProblem(password);
  if (weak) return fail("weak_password", weak);

  const sb = adminClient();
  const ip = clientIp(req);
  const idHash = await sha256(email);
  if (await tooMany(sb, { kind: "otp_verify", identHash: await sha256(`reset-final:${email}`), ip, identMax: 10, ipMax: 30, windowMin: 15, failuresOnly: true })) {
    return fail("too_many_attempts", "Too many attempts. Try again later.", 429);
  }

  const { data: p } = await sb.from("profiles").select("id, account_status").eq("email", email).maybeSingle();
  const badSession = async () => {
    await recordAttempt(sb, "otp_verify", await sha256(`reset-final:${email}`), ip, false);
    return fail("invalid_token", "This reset session is invalid or has expired. Start again.", 400);
  };
  if (!p || p.account_status !== "active") return await badSession();
  if (!(await claimToken(sb, email, "reset", token))) return await badSession();

  // email_confirm: true also finishes an invitation that was never accepted, so this works as a fallback for an expired invite link.
  const { error } = await sb.auth.admin.updateUserById(p.id, { password, email_confirm: true });
  if (error) {
    await releaseToken(sb, email, "reset");
    console.error("reset-password update failed:", error.message);
    return fail("weak_password", "That password is not accepted. Choose another one.", 400);
  }

  const { error: rErr } = await sb.rpc("revoke_user_sessions", { p_user_id: p.id });
  if (rErr) console.error("revoke_user_sessions failed:", rErr.message);
  await sb.from("auth_attempts").delete().eq("kind", "login").eq("identifier", idHash).eq("success", false);
  await audit(sb, { action: "password_reset", actorId: p.id, entity: "auth", entityId: p.id, detail: { ip } });

  return ok({ message: "Your password has been changed. Sign in with your new password." });
});