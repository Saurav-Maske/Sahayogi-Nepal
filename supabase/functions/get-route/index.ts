import { corsHeaders, fail, ok } from "../_shared/cors.ts";
import { adminClient, readJson, requireUser } from "../_shared/auth.ts";

declare const Deno: {
  env: { get(name: string): string | undefined };
  serve(handler: (req: Request) => Response | Promise<Response>): void;
};

const VALHALLA_URL =
  Deno.env.get("VALHALLA_URL") ?? "https://valhalla1.openstreetmap.de";
const VALHALLA_CLIENT_ID =
  Deno.env.get("VALHALLA_CLIENT_ID") ?? "nepal-relief-routing";
const VALHALLA_PROXY_SECRET = Deno.env.get("VALHALLA_PROXY_SECRET");

// Optional Nepal bounds check (matching your intake function)
const LAT_MIN = 26.3, LAT_MAX = 30.5, LNG_MIN = 80.0, LNG_MAX = 88.3;
const ALLOWED_COSTINGS = ["auto", "bicycle", "pedestrian", "motorcycle"];

type LatLngInput = {
  lat: number;
  lon?: number;
  lng?: number;
};

function normalizeLocation(loc: unknown): { lat: number; lon: number } | null {
  if (!loc || typeof loc !== "object") return null;
  const raw = loc as LatLngInput;
  const lon = typeof raw.lon === "number" ? raw.lon : raw.lng;
  if (typeof raw.lat !== "number" || typeof lon !== "number") return null;
  if (!Number.isFinite(raw.lat) || !Number.isFinite(lon)) return null;
  return { lat: raw.lat, lon };
}

function inNepalBounds(pt: { lat: number; lon: number }): boolean {
  return (
    pt.lat >= LAT_MIN &&
    pt.lat <= LAT_MAX &&
    pt.lon >= LNG_MIN &&
    pt.lon <= LNG_MAX
  );
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return fail("method_not_allowed", "POST only", 405);
  }

  // Require an authenticated user (remove this block if anonymous routing is allowed)
  const caller = await requireUser(req);
  if (!caller) return fail("unauthorized", "Authentication required", 401);


  const b = await readJson(req);
  if (!b || typeof b !== "object") {
    return fail("bad_json", "Invalid JSON.");
  }

  const body = b as {
    locations?: unknown[];
    costing?: string;
    costing_options?: Record<string, unknown>;
    save?: boolean;
    strict_nepal?: boolean;
  };

  if (!Array.isArray(body.locations) || body.locations.length < 2) {
    return fail(
      "invalid_locations",
      "Provide at least two locations with lat and lon/lng.",
      400
    );
  }

  const locations: { lat: number; lon: number }[] = [];
  for (const item of body.locations) {
    const pt = normalizeLocation(item);
    if (!pt) {
      return fail(
        "invalid_coordinate",
        "Each location must have finite numeric lat and lon/lng values.",
        400
      );
    }
    if (body.strict_nepal && !inNepalBounds(pt)) {
      return fail(
        "out_of_bounds",
        "Coordinates must be inside Nepal bounds.",
        400
      );
    }
    locations.push(pt);
  }

  const costing =
    typeof body.costing === "string" && ALLOWED_COSTINGS.includes(body.costing)
      ? body.costing
      : "auto";

  const valhallaHeaders: Record<string, string> = {
    "Content-Type": "application/json",
    "X-Client-Id": VALHALLA_CLIENT_ID,
  };
  if (VALHALLA_PROXY_SECRET) {
    valhallaHeaders["x-valhalla-key"] = VALHALLA_PROXY_SECRET;
  }

  let valhallaData: Record<string, unknown>;
  try {
    const res = await fetch(`${VALHALLA_URL}/route`, {
      method: "POST",
      headers: valhallaHeaders,
      body: JSON.stringify({
        locations,
        costing,
        ...(body.costing_options ? { costing_options: body.costing_options } : {}),
        directions_options: { units: "kilometers" },
      }),
    });

    if (!res.ok) {
      const errText = await res.text();
      return fail(
        "routing_upstream_error",
        `Valhalla returned ${res.status}: ${errText}`,
        502
      );
    }

    valhallaData = await res.json();
  } catch (err) {
    return fail(
      "routing_network_error",
      `Failed to reach routing service: ${String(err)}`,
      502
    );
  }

  const trip = valhallaData.trip as
    | {
        summary?: { length?: number; time?: number };
        legs?: Array<{ shape?: string }>;
      }
    | undefined;
  const summary = trip?.summary;
  const shape = trip?.legs?.[0]?.shape ?? null;

  let savedRouteId: string | null = null;
  if (body.save && summary && shape) {
    const db = adminClient();
    const origin = locations[0];
    const dest = locations[locations.length - 1];

    const { data: inserted, error: dbError } = await db
      .from("routes")
      .insert({
        user_id: caller.user.id,
        origin_lat: origin.lat,
        origin_lon: origin.lon,
        dest_lat: dest.lat,
        dest_lon: dest.lon,
        costing,
        distance_km: summary.length ?? null,
        duration_sec: summary.time ?? null,
        shape,
      })
      .select("id")
      .single();

    if (dbError) {
      return fail("db_insert_failed", dbError.message, 500);
    }
    savedRouteId = inserted?.id ?? null;
  }

  return ok({
    route_id: savedRouteId,
    summary: summary ?? null,
    shape,
    trip: valhallaData.trip ?? null,
  });
});