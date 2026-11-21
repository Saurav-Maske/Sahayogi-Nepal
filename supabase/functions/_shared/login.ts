import { corsHeaders, fail, ok } from "./cors.ts";
import { adminClient, anonClient, audit, clientIp, EMAIL_RE, readJson, recordAttempt, sha256, tooMany } from "./auth.ts";

export async function handleLogin(req: Request, portal: "admin" | "volunteer"): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return fail("method_not_allowed", "POST only", 405);

  const body = await readJson(req);
  const email = String(body?.email ?? "").trim().toLowerCase();
  const password = String(body?.password ?? "");
  if (!EMAIL_RE.test(email) || email.length > 254 || password.length < 1 || password.length > 128) {
    return fail("invalid_credentials", "Incorrect email or password.", 401);
  }

  const sb = adminClient();
  const ip = clientIp(req);
  const idHash = await sha256(email); 

  if (await tooMany(sb, { kind: "login", identHash: idHash, ip, identMax: 5, ipMax: 30, windowMin: 15, failuresOnly: true })) {
    return fail("too_many_attempts", "Too many failed attempts. Try again in 15 minutes.", 429);
  }

  const { data, error } = await anonClient().auth.signInWithPassword({ email, password });
  if (error || !data.session || !data.user) {
    await recordAttempt(sb, "login", idHash, ip, false);
    return fail("invalid_credentials", "Incorrect email or password.", 401);
  }

  const { data: profile } = await sb.from("profiles")
    .select("id, full_name, email, phone, role, volunteer_type, categories, account_status")
    .eq("id", data.user.id).maybeSingle();

  if (!profile || profile.role !== portal) {
    await sb.auth.admin.signOut(data.session.access_token, "local").catch(() => {});
    await recordAttempt(sb, "login", idHash, ip, false);
    return fail("invalid_credentials", "Incorrect email or password.", 401);
  }
  if (profile.account_status !== "active") {
    await sb.auth.admin.signOut(data.session.access_token, "local").catch(() => {});
    return fail("account_suspended", "This account is suspended. Contact an administrator.", 403);
  }

  await sb.from("auth_attempts").delete().eq("kind", "login").eq("identifier", idHash).eq("success", false);
  await recordAttempt(sb, "login", idHash, ip, true);
  await sb.from("profiles").update({ last_login_at: new Date().toISOString() }).eq("id", profile.id);
  if (portal === "admin") {
    await audit(sb, { action: "admin_login", actorId: profile.id, entity: "auth", entityId: profile.id, detail: { ip } });
  }

  const s = data.session;
  return ok({
    session: {
      access_token: s.access_token, refresh_token: s.refresh_token,
      expires_in: s.expires_in, expires_at: s.expires_at, token_type: s.token_type,
    },
    profile: {
      id: profile.id, full_name: profile.full_name, email: profile.email, phone: profile.phone,
      role: profile.role, volunteer_type: profile.volunteer_type, categories: profile.categories,
    },
  });
}