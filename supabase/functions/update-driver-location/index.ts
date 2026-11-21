// supabase/functions/update_driver_location/index.ts
//
// ASSUMPTIONS (change to match your tables):
//   assignment_current_event (view, see the migration): assignment_id, volunteer_id, event_type
//   driver_latest_location:  assign_id, volunteer_id, tracking_number, loc, updated_at
//                            (one row per assignment, created by the trigger on public.assignment)
// A ping updates the caller's rows for ALL of their live assignments. It never creates rows.

import { corsHeaders, fail, ok } from "../_shared/cors.ts";
import { adminClient, readJson, requireDriver } from "../_shared/auth.ts";

const DLL_TABLE = "driver_latest_location";
const ACTIVE_VIEW = "assignment_current_event";

// Location sharing is live from acceptance until delivery is confirmed (otp_verified).
// "offered", "otp_verified" and any other event type are not live.
const TRACKABLE_EVENTS = ["accepted", "en_route_to_pickup", "picked_up", "en_route_to_destination"];

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return fail("method_not_allowed", "POST only", 405);

  // The driver comes from the token, never from the request body.
  const driver = await requireDriver(req);
  if (!driver) return fail("forbidden", "An active driver account is required.", 403);

  const b = await readJson(req);
  if (
    typeof b?.lat !== "number" || typeof b?.lon !== "number" ||
    !Number.isFinite(b.lat) || !Number.isFinite(b.lon) ||
    Math.abs(b.lat) > 90 || Math.abs(b.lon) > 180
  ) {
    return fail("invalid_input", "lat and lon are required, as valid numbers.");
  }

  const sb = adminClient();

  // Which assignments of this driver are live right now (judged by their latest event)?
  const { data: active, error: assignErr } = await sb
    .from(ACTIVE_VIEW)
    .select("assignment_id")
    .eq("volunteer_id", driver.id)
    .in("event_type", TRACKABLE_EVENTS);

  if (assignErr) {
    console.error("assignment lookup failed:", assignErr.message);
    return fail("lookup_failed", "Could not verify your assignment.", 500);
  }
  if (!active?.length) {
    return fail("no_active_assignment", "You have no active assignment.", 403);
  }

  const now = new Date().toISOString();
  const { data: updated, error } = await sb
    .from(DLL_TABLE)
    .update({
      // Extended WKT: longitude first, then latitude. toFixed avoids scientific notation.
      loc: `SRID=4326;POINT(${b.lon.toFixed(7)} ${b.lat.toFixed(7)})`,
      updated_at: now,
    })
    .eq("volunteer_id", driver.id)
    .in("assign_id", active.map((a: { assignment_id: string }) => a.assignment_id))
    .select("assign_id");

  if (error) {
    console.error("driver location update failed:", error.message);
    return fail("update_failed", "Could not save your location.", 500);
  }
  if (!updated?.length) {
    return fail("not_found", "No location record exists for your active assignments.", 404);
  }

  return ok({ updated_at: now, assignments_updated: updated.length });
});