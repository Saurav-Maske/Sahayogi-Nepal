import { corsHeaders, fail, ok } from "../_shared/cors.ts";
import { adminClient, requireUser } from "../_shared/auth.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  const u = await requireUser(req);
  if (!u) return fail("unauthenticated", "Sign in required.", 401);
  const { data: p } = await adminClient().from("profiles")
    .select("id, full_name, email, phone, role, volunteer_type, categories, account_status, last_login_at")
    .eq("id", u.user.id).maybeSingle();
  if (!p) return fail("no_profile", "No profile for this account.", 403);
  if (p.account_status !== "active") return fail("account_suspended", "This account is suspended.", 403);
  return ok({ profile: p });
});