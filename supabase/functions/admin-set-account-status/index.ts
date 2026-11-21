import { corsHeaders, fail, ok } from "../_shared/cors.ts";
import { adminClient, audit, readJson, requireAdmin } from "../_shared/auth.ts";

declare const Deno: {
  env: { get(name: string): string | undefined };
  serve(handler: (req: Request) => Response | Promise<Response>): void;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return fail("method_not_allowed", "POST only", 405);

  const caller = await requireAdmin(req);
  if (!caller) return fail("forbidden", "Admin access required.", 403);

  const b = await readJson(req);
  const status = String(b?.status ?? "");
  if (!b?.user_id || !["active", "suspended"].includes(status)) return fail("invalid_input", "user_id and status (active | suspended) required.");
  if (b.user_id === caller.id) return fail("invalid_input", "You cannot change your own status.");

  const sb = adminClient();
  const { data: target } = await sb.from("profiles").select("id").eq("id", b.user_id).maybeSingle();
  if (!target) return fail("not_found", "User not found.", 404);

  const { error: e1 } = await sb.from("profiles").update({ account_status: status }).eq("id", b.user_id);
  const { error: e2 } = await sb.auth.admin.updateUserById(b.user_id, { ban_duration: status === "suspended" ? "876000h" : "none" });
  if (e1 || e2) return fail("update_failed", "Could not update the account.", 500);

  await audit(sb, {
    action: status === "suspended" ? "account_suspended" : "account_reactivated", actorId: caller.id,
    entity: "profile", entityId: b.user_id, detail: { reason: b.reason ?? null },
  });
  return ok({ user_id: b.user_id, status });
});