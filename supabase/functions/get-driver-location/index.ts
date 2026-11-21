// supabase/functions/get_driver_location/index.ts
//
// ASSUMPTIONS (change to match your tables):
//   driver_latest_location: assign_id, volunteer_id, tracking_number, loc (hex EWKB), updated_at
//                           tracking_number = SHA-256 of the raw token, lowercase hex
//   assignment:             id, request_id, volunteer_id (the driver)
//   assignment_current_event (view, see the migration): assignment_id, event_type
//                           (live = latest event is accepted .. en_route_to_destination)
//   requests:               id, requester_id (may be null for anonymous requesters)
//   profiles:               id, role (one value or a list), account_status
//
// Who may read driver locations, always for ACTIVE assignments only:
//   - anyone holding the raw tracking token: body { tracking_token } (no account needed)
//   - a signed-in user who is the request's requester: body { request_id }
//   - admins: body { request_id } or { volunteer_id }
// Everyone else gets the same 404, so nothing can be probed.
//
// One driver location at a time: the response is a single position.

import { corsHeaders, fail, ok } from "../_shared/cors.ts";
import { adminClient, readJson, requireUser } from "../_shared/auth.ts";

const DLL_TABLE = "driver_latest_location";
const ASSIGNED_TABLE = "assignment";
const ASSIGNED_DRIVER_COLUMN = "volunteer_id";
const MAX_TOKEN_LENGTH = 256;

// Location sharing is live from acceptance until delivery is confirmed (otp_verified).
// "offered", "otp_verified" and any other event type are not live.
const ACTIVE_VIEW = "assignment_current_event";
const TRACKABLE_EVENTS = ["accepted", "en_route_to_pickup", "picked_up", "en_route_to_destination"];
const NOT_AVAILABLE = () => fail("not_found", "No driver location is available.", 404);

// Accepts "B", "b", ["A","B"], "A, B" and returns ["A","B"] (uppercase, trimmed).
const rolesOf = (role: unknown): string[] =>
  ([] as unknown[]).concat(role ?? [])
    .flatMap((r) => String(r).split(","))
    .map((r) => r.trim().toUpperCase())
    .filter(Boolean);

// SHA-256 as lowercase hex, the form the token is stored in.
async function sha256Hex(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

// Decodes a PostGIS point. Accepts hex EWKB/WKB, or a GeoJSON Point object.
function parsePoint(value: unknown): { lon: number; lat: number } | null {
  if (value && typeof value === "object") {
    const c = (value as { coordinates?: unknown }).coordinates;
    if (Array.isArray(c) && typeof c[0] === "number" && typeof c[1] === "number") {
      return { lon: c[0], lat: c[1] };
    }
    return null;
  }
  if (typeof value !== "string" || value.length < 42 || value.length % 2 !== 0) return null;

  const pairs = value.match(/../g);
  if (!pairs) return null;
  const bytes = Uint8Array.from(pairs.map((h) => parseInt(h, 16)));
  const view = new DataView(bytes.buffer);

  const little = bytes[0] === 1;
  let offset = 1;
  const type = view.getUint32(offset, little);
  offset += 4;
  if ((type & 0x20000000) !== 0) offset += 4; // skip SRID
  if ((type & 0x1fffffff) !== 1) return null;  // 1 = Point
  if (bytes.length < offset + 16) return null;

  return { lon: view.getFloat64(offset, little), lat: view.getFloat64(offset + 8, little) };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return fail("method_not_allowed", "POST only", 405);

  // May be null: tracking-token holders don't need an account.
  const caller = await requireUser(req);

  const b = await readJson(req);
  const trackingToken = typeof b?.tracking_token === "string" ? b.tracking_token.trim() : null;
  const requestId = typeof b?.request_id === "string" ? b.request_id : null;
  const volunteerId = typeof b?.volunteer_id === "string" ? b.volunteer_id : null;

  if (!trackingToken && !requestId && !volunteerId) {
    return fail("invalid_input", "Provide tracking_token (or request_id / volunteer_id if signed in).");
  }
  if (!caller && !trackingToken) {
    return fail("unauthorized", "Sign in or provide a tracking token.", 401);
  }

  const sb = adminClient();

  // Is the caller an admin? Decided from their profile, never from the body.
  let isAdmin = false;
  if (caller) {
    const { data: profile, error: profileErr } = await sb
      .from("profiles")
      .select("role, account_status")
      .eq("id", caller.user.id)
      .maybeSingle();
    if (profileErr) {
      console.error("profile lookup failed:", profileErr.message);
      return fail("profile_failed", "Could not verify your account.", 500);
    }
    // A caller with no profile (e.g. an anonymous requester) is simply not an admin.
    isAdmin = profile?.account_status === "active" && rolesOf(profile.role).includes("ADMIN");
  }

  // 1. Candidate assignments this caller is allowed to track (active or not, filtered in step 2).
  let candidateIds: string[] = [];

  if (trackingToken && trackingToken.length <= MAX_TOKEN_LENGTH) {
    // Hash what was sent and look it up. The raw token never touches the database.
    const hash = await sha256Hex(trackingToken);
    const { data, error } = await sb.from(DLL_TABLE).select("assign_id").eq("tracking_number", hash);
    if (error) {
      console.error("tracking number lookup failed:", error.message);
      return fail("lookup_failed", "Could not load the driver location.", 500);
    }
    candidateIds = (data ?? []).map((r: { assign_id: string }) => r.assign_id);
  }

  if (!candidateIds.length && requestId && caller) {
    const { data: request, error: reqErr } = await sb
      .from("requests")
      .select("id, requester_id")
      .eq("id", requestId)
      .maybeSingle();
    if (reqErr) {
      console.error("request lookup failed:", reqErr.message);
      return fail("lookup_failed", "Could not load the request.", 500);
    }
    const isOwner = !!request?.requester_id && request.requester_id === caller.user.id;
    if (request && (isAdmin || isOwner)) {
      const { data, error } = await sb.from(ASSIGNED_TABLE).select("id").eq("request_id", request.id);
      if (error) {
        console.error("assignment lookup failed:", error.message);
        return fail("lookup_failed", "Could not load the assignment.", 500);
      }
      candidateIds = (data ?? []).map((r: { id: string }) => r.id);
    }
  }

  if (!candidateIds.length && volunteerId && isAdmin) {
    const { data, error } = await sb.from(ASSIGNED_TABLE).select("id").eq(ASSIGNED_DRIVER_COLUMN, volunteerId);
    if (error) {
      console.error("assignment lookup failed:", error.message);
      return fail("lookup_failed", "Could not load the assignment.", 500);
    }
    candidateIds = (data ?? []).map((r: { id: string }) => r.id);
  }

  if (!candidateIds.length) return NOT_AVAILABLE(); // bad token, someone else's request, or not allowed

  // 2. Keep only assignments that are live, judged by each assignment's latest event.
  const { data: active, error: activeErr } = await sb
    .from(ACTIVE_VIEW)
    .select("assignment_id")
    .in("assignment_id", candidateIds)
    .in("event_type", TRACKABLE_EVENTS);
  if (activeErr) {
    console.error("active assignment lookup failed:", activeErr.message);
    return fail("lookup_failed", "Could not load the assignment.", 500);
  }
  const activeIds = (active ?? []).map((r: { assignment_id: string }) => r.assignment_id);
  if (!activeIds.length) return NOT_AVAILABLE(); // not accepted yet, or delivery already confirmed

  // 3. Read the drivers' latest positions.
  const { data: rows, error } = await sb
    .from(DLL_TABLE)
    .select("assign_id, volunteer_id, loc, updated_at")
    .in("assign_id", activeIds);
  if (error) {
    console.error("driver location lookup failed:", error.message);
    return fail("query_failed", "Could not load the driver location.", 500);
  }
  if (!rows?.length) return NOT_AVAILABLE();

  // One driver at a time. If more than one row is live (e.g. a hand-over in progress),
  // return the most recently updated one.
  type Row = { assign_id: string; volunteer_id: string; loc: unknown; updated_at: string | null };
  const timeOf = (r: Row) => Date.parse(r.updated_at ?? "") || 0;
  const r = [...(rows as Row[])].sort((a, c) => timeOf(c) - timeOf(a))[0];

  const point = parsePoint(r.loc);
  const ageSeconds = r.updated_at
    ? Math.max(0, Math.round((Date.now() - new Date(r.updated_at).getTime()) / 1000))
    : null;

  return ok({
    // ids are for admins only; requesters and token holders just get the position
    ...(isAdmin ? { assign_id: r.assign_id, volunteer_id: r.volunteer_id } : {}),
    // null until the driver's first ping after being assigned
    location: point ? { lat: point.lat, lon: point.lon } : null,
    updated_at: r.updated_at ?? null,
    age_seconds: point ? ageSeconds : null,
  });
});