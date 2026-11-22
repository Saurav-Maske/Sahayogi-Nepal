import { corsHeaders, fail, ok } from "../_shared/cors.ts";
import { adminClient, audit, readJson, requireAdmin } from "../_shared/auth.ts";
import { categoriesFor, primaryType, type VolunteerType } from "../_shared/volunteer_types.ts";

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
  const decision = String(b?.decision ?? "");
  const note = b?.note ? String(b.note).slice(0, 1000) : null;
  if (!b?.application_id || !["approve", "decline", "resend_invite"].includes(decision)) {
    return fail("invalid_input", "application_id and decision (approve | decline | resend_invite) required.");
  }

  const sb = adminClient();
  const { data: app } = await sb.from("volunteer_applications").select("*").eq("id", b.application_id).maybeSingle();
  if (!app) return fail("not_found", "Application not found.", 404);
  const redirectTo = Deno.env.get("SET_PASSWORD_URL")!;
  const now = new Date().toISOString();

  if (decision === "decline") {
    if (!["submitted", "under_review"].includes(app.review_status)) return fail("invalid_state", "Application already decided.", 409);
    if (!note || note.length < 3) return fail("reason_required", "A reason is required to decline.");
    await sb.from("volunteer_applications").update({
      review_status: "declined", review_note: note, reviewed_by: caller.id, reviewed_at: now,
    }).eq("id", app.id);
    await audit(sb, { action: "volunteer_declined", actorId: caller.id, entity: "volunteer_application", entityId: app.id, detail: { note } });
    return ok({ application_id: app.id, decision });
  }

  if (decision === "resend_invite") {
    if (app.review_status !== "approved") return fail("invalid_state", "Only approved applications can be re-invited.", 409);
    const { error } = await sb.auth.admin.inviteUserByEmail(app.email, { redirectTo });
    if (error) {
      // A user who already set their password cannot be re-invited: tell them to use "Forgot password".
      return fail("already_active", "This volunteer already has a password. Ask them to use Forgot password.", 409, { detail: error.message });
    }
    return ok({ application_id: app.id, decision });
  }

  if (!["submitted", "under_review"].includes(app.review_status)) return fail("invalid_state", "Application already decided.", 409);
  const email = String(app.email).toLowerCase();

  const { data: invited, error: invErr } = await sb.auth.admin.inviteUserByEmail(email, { redirectTo });
  if (invErr || !invited?.user) {
    return fail("invite_failed", "Could not send the invitation email.", 400, { detail: invErr?.message });
  }

  // Categories are the union over every type the applicant signed up for (driver + doctor = A, B, C).
  // Rows from before volunteer_types existed only have the single volunteer_type.
  const types: VolunteerType[] = Array.isArray(app.volunteer_types) && app.volunteer_types.length
    ? app.volunteer_types : [app.volunteer_type];
  const categories = categoriesFor(types);

  const { error: pErr } = await sb.from("profiles").upsert({
    id: invited.user.id, full_name: app.full_name, email, phone: app.phone,
    role: "volunteer", volunteer_type: primaryType(types),
    categories: categories.length ? categories : ["A"], account_status: "active",
  });
  if (pErr) {
    await sb.auth.admin.deleteUser(invited.user.id).catch(() => {}); // do not leave an orphan auth user
    console.error("profile upsert failed:", pErr.message);
    return fail("profile_failed", "Could not create the volunteer profile.", 500);
  }

  await sb.from("volunteer_applications").update({
    review_status: "approved", profile_id: invited.user.id, review_note: note,
    reviewed_by: caller.id, reviewed_at: now,
  }).eq("id", app.id);
  await audit(sb, {
    action: "volunteer_approved", actorId: caller.id, entity: "volunteer_application", entityId: app.id,
    detail: { profile_id: invited.user.id, volunteer_types: types, categories },
  });
  return ok({ application_id: app.id, decision, profile_id: invited.user.id });
});