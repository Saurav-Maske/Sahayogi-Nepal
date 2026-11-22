// Route preview for a volunteer, BEFORE or AFTER accepting. POST /functions/v1/get-offer-route
//
//   body: { id: <assignment id>, lat: <driver lat>, lng: <driver lng>, costing?: "auto" | "bicycle" | "pedestrian" | "motorcycle" }
//
// The route is built on the server from EXACT points (driver position, then the donor / hub / requester in the
// order of the request kind), because an open offer only shows an approximate position to the app. What goes
// back is only the route lines, distance and time: no coordinates of the donor or requester, no street names,
// no turn-by-turn steps. Nothing is saved.
//
//   donation_offer   : driver -> donor -> central inventory
//   resource_request : driver -> central inventory -> requester
//   other kinds      : driver -> requester
//
// The points come from the SQL function offer_route_points(), which only the service role can run and which
// applies the same visibility rule as my_assignment_detail (open eligible offer, or your own unfinished one).
import { corsHeaders, fail, ok } from "../_shared/cors.ts";
import { adminClient, readJson, requireUser } from "../_shared/auth.ts";

declare const Deno: {
  env: { get(name: string): string | undefined };
  serve(handler: (req: Request) => Response | Promise<Response>): void;
};

const VALHALLA_URL = Deno.env.get("VALHALLA_URL") || "https://valhalla1.openstreetmap.de";
const VALHALLA_CLIENT_ID = Deno.env.get("VALHALLA_CLIENT_ID") ?? "nepal-relief-routing";
const VALHALLA_PROXY_SECRET = Deno.env.get("VALHALLA_PROXY_SECRET");

// Rough bounding box of Nepal, same as get-route and submit-request.
const LAT_MIN = 26.3, LAT_MAX = 30.5, LNG_MIN = 80.0, LNG_MAX = 88.3;
const ALLOWED_COSTINGS = ["auto", "bicycle", "pedestrian", "motorcycle"];
const UPSTREAM_TIMEOUT_MS = 15_000;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Same encoding as get-route, so the app decodes both the same way.
const SHAPE_PRECISION = 5;

type Pt = { lat: number; lng: number; label?: string };

const finite = (v: unknown): v is number => typeof v === "number" && Number.isFinite(v);
const inNepal = (lat: number, lng: number) => lat >= LAT_MIN && lat <= LAT_MAX && lng >= LNG_MIN && lng <= LNG_MAX;

// Codes the SQL function raises, mapped to a status and a message that is safe to show.
const SQL_ERRORS: Record<string, [number, string]> = {
  unauthorized: [401, "Sign in required."],
  forbidden: [403, "You are not allowed to do this."],
  not_found: [404, "This offer is not available to you."],
  hub_not_configured: [500, "The central hub is not configured."],
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return fail("method_not_allowed", "POST only", 405);

  const caller = await requireUser(req);
  if (!caller) return fail("unauthorized", "Authentication required", 401);

  const body = await readJson(req);
  if (!body) return fail("bad_json", "Invalid JSON.");

  if (typeof body.id !== "string" || !UUID_RE.test(body.id)) return fail("invalid_id", "id must be an assignment UUID.");
  if (!finite(body.lat) || !finite(body.lng)) return fail("invalid_location", "lat and lng of the driver are required.");
  if (!inNepal(body.lat, body.lng)) return fail("out_of_bounds", "Your position must be inside Nepal bounds.");

  const costing = typeof body.costing === "string" && ALLOWED_COSTINGS.includes(body.costing) ? body.costing : "auto";

  // Exact points for this offer. The SQL function checks the volunteer and the visibility rule.
  const sb = adminClient();
  const { data, error } = await sb.rpc("offer_route_points", { p_user: caller.user.id, p_id: body.id });
  if (error) {
    const known = SQL_ERRORS[error.message ?? ""];
    if (known) return fail(error.message, known[1], known[0]);
    console.error("get-offer-route points failed:", error.message);
    return fail("db_error", "Something went wrong.", 500);
  }
  const points = (data?.points ?? []) as Pt[];
  if (!points.length || points.some((p) => !finite(p.lat) || !finite(p.lng))) {
    console.error("get-offer-route: offer_route_points returned no usable points");
    return fail("db_error", "Something went wrong.", 500);
  }

  // Driver first, then the offer's points in order. Each leg ends at points[i].
  const stops: Pt[] = [{ lat: body.lat, lng: body.lng }, ...points];
  const legTargets = points.map((p) => p.label ?? "stop");

  const headers: Record<string, string> = { "Content-Type": "application/json", "X-Client-Id": VALHALLA_CLIENT_ID };
  if (VALHALLA_PROXY_SECRET) headers["x-valhalla-key"] = VALHALLA_PROXY_SECRET;

  let valhalla: Record<string, any>;
  try {
    const res = await fetch(`${VALHALLA_URL}/route`, {
      method: "POST",
      headers,
      signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
      body: JSON.stringify({
        locations: stops.map((p) => ({ lat: p.lat, lon: p.lng })),
        costing,
        shape_format: "polyline5",
        directions_options: { units: "kilometers" },
      }),
    });
    if (!res.ok) {
      // Valhalla's own message is not for end users, and may echo the exact points: log the status only.
      console.error(`get-offer-route upstream ${res.status}`);
      return fail("routing_upstream_error", res.status === 400 ? "No route could be found for this offer." : "The routing service returned an error.", 502);
    }
    valhalla = await res.json();
  } catch (err) {
    console.error("get-offer-route network error:", String(err));
    return fail("routing_network_error", "Could not reach the routing service.", 502);
  }

  const trip = valhalla.trip as { summary?: { length?: number; time?: number }; legs?: Array<{ shape?: string; summary?: { length?: number; time?: number } }> } | undefined;
  const rawLegs = trip?.legs ?? [];
  if (!trip?.summary || rawLegs.length !== points.length || rawLegs.some((l) => !l.shape)) {
    console.error("get-offer-route: unexpected routing answer");
    return fail("routing_upstream_error", "The routing service returned no route.", 502);
  }

  // Only lines, distance (km) and time (seconds). `to` names the end of each leg.
  return ok({
    kind: data.kind,
    assignment_type: data.assignment_type,
    costing,
    shape_precision: SHAPE_PRECISION,
    summary: { length: trip.summary.length ?? null, time: trip.summary.time ?? null },
    legs: rawLegs.map((l, i) => ({
      to: legTargets[i],
      shape: l.shape as string,
      length: l.summary?.length ?? null,
      time: l.summary?.time ?? null,
    })),
  });
});