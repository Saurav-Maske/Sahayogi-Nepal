// Routing through Valhalla for any signed-in, active user. With save: true the route is stored in `routes`
// (migration 20261122000010_routes.sql), optionally linked to one of the caller's own assignments.
import { corsHeaders, fail, ok } from "../_shared/cors.ts";
import { adminClient, readJson, requireUser } from "../_shared/auth.ts";

declare const Deno: {
  env: { get(name: string): string | undefined };
  serve(handler: (req: Request) => Response | Promise<Response>): void;
};

const VALHALLA_URL = Deno.env.get("VALHALLA_URL") || "https://valhalla1.openstreetmap.de";
const VALHALLA_CLIENT_ID = Deno.env.get("VALHALLA_CLIENT_ID") ?? "nepal-relief-routing";
const VALHALLA_PROXY_SECRET = Deno.env.get("VALHALLA_PROXY_SECRET");

// Rough bounding box of Nepal, same as submit-request.
const LAT_MIN = 26.3, LAT_MAX = 30.5, LNG_MIN = 80.0, LNG_MAX = 88.3;
const ALLOWED_COSTINGS = ["auto", "bicycle", "pedestrian", "motorcycle"];
const MAX_LOCATIONS = 10;
const UPSTREAM_TIMEOUT_MS = 15_000;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

type Pt = { lat: number; lon: number };
type Leg = { shape: string | null; length: number | null; time: number | null };

function normalizeLocation(loc: unknown): Pt | null {
  if (!loc || typeof loc !== "object") return null;
  const raw = loc as { lat?: unknown; lon?: unknown; lng?: unknown };
  const lon = typeof raw.lon === "number" ? raw.lon : raw.lng;
  if (typeof raw.lat !== "number" || typeof lon !== "number") return null;
  if (!Number.isFinite(raw.lat) || !Number.isFinite(lon)) return null;
  return { lat: raw.lat, lon };
}

const inNepal = (p: Pt) => p.lat >= LAT_MIN && p.lat <= LAT_MAX && p.lon >= LNG_MIN && p.lon <= LNG_MAX;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return fail("method_not_allowed", "POST only", 405);

  const caller = await requireUser(req);
  if (!caller) return fail("unauthorized", "Authentication required", 401);

  const sb = adminClient();
  const { data: profile } = await sb.from("profiles").select("id, role, account_status").eq("id", caller.user.id).maybeSingle();
  if (!profile || profile.account_status !== "active") return fail("account_suspended", "This account cannot use routing.", 403);

  const body = await readJson(req);
  if (!body) return fail("bad_json", "Invalid JSON.");

  if (!Array.isArray(body.locations) || body.locations.length < 2 || body.locations.length > MAX_LOCATIONS) {
    return fail("invalid_locations", `Provide 2 to ${MAX_LOCATIONS} locations with lat and lon/lng.`);
  }

  // Inside Nepal unless the caller explicitly sends strict_nepal: false (keeps the shared Valhalla server for relief use).
  const strictNepal = body.strict_nepal !== false;
  const locations: Pt[] = [];
  for (const item of body.locations) {
    const pt = normalizeLocation(item);
    if (!pt) return fail("invalid_coordinate", "Each location must have finite numeric lat and lon/lng values.");
    if (strictNepal && !inNepal(pt)) return fail("out_of_bounds", "Coordinates must be inside Nepal bounds.");
    locations.push(pt);
  }

  const costing = typeof body.costing === "string" && ALLOWED_COSTINGS.includes(body.costing) ? body.costing : "auto";

  let costingOptions: Record<string, unknown> | null = null;
  if (body.costing_options !== undefined && body.costing_options !== null) {
    const co = body.costing_options;
    if (typeof co !== "object" || Array.isArray(co) || JSON.stringify(co).length > 2000) {
      return fail("invalid_costing_options", "costing_options must be a small object.");
    }
    costingOptions = co as Record<string, unknown>;
  }

  const save = body.save === true;
  let assignmentId: string | null = null;
  if (body.assignment_id !== undefined && body.assignment_id !== null) {
    if (typeof body.assignment_id !== "string" || !UUID_RE.test(body.assignment_id)) {
      return fail("invalid_assignment_id", "assignment_id must be a UUID.");
    }
    if (!save) return fail("invalid_assignment_id", "assignment_id is only used together with save: true.");
    // Only the volunteer holding the assignment (or an admin) may attach a route to it.
    const { data: a } = await sb.from("assignments").select("id, volunteer_id").eq("id", body.assignment_id).maybeSingle();
    if (!a || (a.volunteer_id !== profile.id && profile.role !== "admin")) return fail("not_found", "Assignment not found.", 404);
    assignmentId = a.id;
  }

  const headers: Record<string, string> = { "Content-Type": "application/json", "X-Client-Id": VALHALLA_CLIENT_ID };
  if (VALHALLA_PROXY_SECRET) headers["x-valhalla-key"] = VALHALLA_PROXY_SECRET;

  let valhalla: Record<string, any>;
  try {
    const res = await fetch(`${VALHALLA_URL}/route`, {
      method: "POST",
      headers,
      signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
      body: JSON.stringify({
        locations, costing,
        ...(costingOptions ? { costing_options: costingOptions } : {}),
        directions_options: { units: "kilometers" },
      }),
    });
    if (!res.ok) {
      // Valhalla's own message (e.g. "no path could be found") is not for end users; log it, return a stable code.
      console.error(`get-route upstream ${res.status}:`, (await res.text()).slice(0, 500));
      return fail("routing_upstream_error", res.status === 400 ? "No route could be found between these points." : "The routing service returned an error.", 502);
    }
    valhalla = await res.json();
  } catch (err) {
    console.error("get-route network error:", String(err));
    return fail("routing_network_error", "Could not reach the routing service.", 502);
  }

  const trip = valhalla.trip as { summary?: { length?: number; time?: number }; legs?: Array<{ shape?: string; summary?: { length?: number; time?: number } }> } | undefined;
  const summary = trip?.summary ?? null;
  const legs: Leg[] = (trip?.legs ?? []).map((l) => ({ shape: l.shape ?? null, length: l.summary?.length ?? null, time: l.summary?.time ?? null }));
  const shape = legs[0]?.shape ?? null; // kept for older clients; use `legs` for routes with more than two points

  let routeId: string | null = null;
  if (save) {
    if (!summary || !shape) return fail("routing_upstream_error", "The routing service returned no route to save.", 502);
    const origin = locations[0], dest = locations[locations.length - 1];
    const { data: row, error } = await sb.from("routes").insert({
      user_id: profile.id, assignment_id: assignmentId,
      origin_lat: origin.lat, origin_lon: origin.lon, dest_lat: dest.lat, dest_lon: dest.lon,
      costing, distance_km: summary.length ?? null, duration_sec: summary.time ?? null, shape, legs,
    }).select("id").single();
    if (error) {
      console.error("get-route save failed:", error.message);
      return fail("db_insert_failed", "Could not save the route.", 500);
    }
    routeId = row?.id ?? null;
  }

  return ok({ route_id: routeId, summary, shape, legs, trip: valhalla.trip ?? null });
});