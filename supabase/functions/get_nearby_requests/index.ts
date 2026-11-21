// supabase/functions/get_nearby_requests/index.ts
//
// ASSUMPTIONS (change to match your tables):
//   requests:  loc (PostGIS point, hex EWKB), status ('open' = needs help),
//              kind (resource_request | donation_offer | healthcare_request | ...)
//   profiles:  id, role (one value or a list, e.g. ["A","B"]), account_status ('active')
//
// Visibility rules:
//   - kinds listed in RESTRICTED_KINDS are only visible to the roles that own them
//   - every other kind is visible to everyone
//   - admins see everything

import { corsHeaders, fail, ok } from "../_shared/cors.ts";
import { adminClient, readJson, requireUser } from "../_shared/auth.ts";

const TABLE = "requests";
const LOC_COLUMN = "loc";
const KIND_COLUMN = "kind";
const VISIBLE_STATUSES = ["open", "partially_fulfilled","awaiting_assignment"]; // add "in_progress" if wanted

// role letter -> kinds only that role may see. Add a kind here to lock it down.
const RESTRICTED_KINDS: Record<string, string[]> = {
  B: ["resource_request", "donation_offer"],
  C: ["healthcare_request"],
};

const DEFAULT_RADIUS_KM = 10;
const MAX_RADIUS_KM = 50;
const DEFAULT_LIMIT = 50;
const MAX_LIMIT = 100;
const MAX_SCAN = 1000; // open rows examined per call

// Accepts "B", "b", ["A","B"], "A, B" and returns ["A","B"] (uppercase, trimmed).
const rolesOf = (role: unknown): string[] =>
  ([] as unknown[]).concat(role ?? [])
    .flatMap((r) => String(r).split(","))
    .map((r) => r.trim().toUpperCase())
    .filter(Boolean);

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

  const little = bytes[0] === 1;       // 01 = little-endian, 00 = big-endian
  let offset = 1;
  const type = view.getUint32(offset, little);
  offset += 4;
  if ((type & 0x20000000) !== 0) offset += 4;  // skip SRID (E6100000 = 4326)
  if ((type & 0x1fffffff) !== 1) return null;   // 1 = Point; anything else is not handled
  if (bytes.length < offset + 16) return null;

  return { lon: view.getFloat64(offset, little), lat: view.getFloat64(offset + 8, little) };
}

function haversineKm(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
  return 2 * 6371 * Math.asin(Math.sqrt(h));
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return fail("method_not_allowed", "POST only", 405);

  // Not signed in is allowed: guests see the unrestricted kinds only.
  const caller = await requireUser(req);

  const b = await readJson(req);
  if (
    typeof b?.lat !== "number" || typeof b?.lon !== "number" ||
    !Number.isFinite(b.lat) || !Number.isFinite(b.lon) ||
    Math.abs(b.lat) > 90 || Math.abs(b.lon) > 180
  ) {
    return fail("invalid_input", "lat and lon are required, as valid numbers.");
  }

  const radiusKm = Math.min(
    Math.max(Number(b.radius_km ?? DEFAULT_RADIUS_KM) || DEFAULT_RADIUS_KM, 0.1),
    MAX_RADIUS_KM,
  );
  const limit = Math.min(
    Math.max(Math.trunc(Number(b.limit ?? DEFAULT_LIMIT)) || DEFAULT_LIMIT, 1),
    MAX_LIMIT,
  );

  // What may this caller see? Decided by their profile, never by the request body.
  // Guests, users without a profile, inactive accounts and users with no matching
  // role all end up with no roles, which means unrestricted kinds only.
  const sb = adminClient();
  let roles: string[] = [];

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
    if (profile?.account_status === "active") roles = rolesOf(profile.role);
  }

  const isAdmin = roles.includes("ADMIN");

  // Restricted kinds this caller is NOT allowed to see.
  const allowedRestricted = new Set(roles.flatMap((r) => RESTRICTED_KINDS[r] ?? []));
  const blockedKinds = Object.values(RESTRICTED_KINDS).flat()
    .filter((k) => !allowedRestricted.has(k));

  let query = sb
    .from(TABLE)
    .select("*") // narrow to the columns the app needs
    .in("status", VISIBLE_STATUSES)
    .limit(MAX_SCAN);

  if (!isAdmin && blockedKinds.length > 0) {
    // "kind is null OR kind not in (...)": a plain NOT IN would also drop rows whose kind is null.
    query = query.or(`${KIND_COLUMN}.is.null,${KIND_COLUMN}.not.in.(${blockedKinds.join(",")})`);
  }

  const { data, error } = await query;

  if (error) {
    console.error("get_nearby_requests query failed:", error.message);
    return fail("query_failed", "Could not load nearby requests.", 500);
  }

  const requests = (data ?? [])
    .flatMap((row: Record<string, unknown>) => {
      const p = parsePoint(row[LOC_COLUMN]);
      if (!p) return []; // skip rows with no usable location
      const { [LOC_COLUMN]: _raw, ...rest } = row;
      return [{ ...rest, lat: p.lat, lon: p.lon, distance_km: haversineKm(b.lat, b.lon, p.lat, p.lon) }];
    })
    .filter((r) => r.distance_km <= radiusKm)
    .sort((a, c) => a.distance_km - c.distance_km)
    .slice(0, limit);

  return ok({ count: requests.length, radius_km: radiusKm, requests });
});