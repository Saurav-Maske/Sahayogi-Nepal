// Public intake. Service role is used SERVER-SIDE ONLY; clients get no anonymous INSERT on tables.
// A signed-in volunteer may call this too: name/phone default to their profile and the request is linked to them.
import { corsHeaders, fail, ok } from "../_shared/cors.ts";
import { adminClient, NEPAL_PHONE_RE, readJson, requireUser, sha256 } from "../_shared/auth.ts";

const ITEM_KINDS = ["resource_request", "donation_offer"]; // need an items[] list
const VOLUNTEER_KINDS = ["manpower_request", "healthcare_request", "transport_request"]; // need volunteers_needed
const ITEM_TYPES = ["food", "cloth", "temp_shelter", "medical_supplies", "drinking_water"];
const URGENCY = ["low", "normal", "high", "critical"];
// Rough bounding box of Nepal; the DB trigger then picks the exact district from the point.
const LAT_MIN = 26.3, LAT_MAX = 30.5, LNG_MIN = 80.0, LNG_MAX = 88.3;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return fail("method_not_allowed", "POST only", 405);

  const b = await readJson(req);
  if (!b) return fail("bad_json", "Invalid JSON.");

  const kind = String(b.kind ?? "");
  if (![...ITEM_KINDS, ...VOLUNTEER_KINDS].includes(kind)) return fail("invalid_kind", "Unknown request kind.");

  const sb = adminClient();

  // Optional login: volunteers get name/phone pre-filled from their profile.
  const caller = await requireUser(req);
  let profile: { id: string; full_name: string; phone: string | null } | null = null;
  if (caller) {
    const { data } = await sb.from("profiles").select("id, full_name, phone, account_status").eq("id", caller.user.id).maybeSingle();
    if (data && data.account_status === "active") profile = data;
  }

  const requester_name = String(b.requester_name ?? profile?.full_name ?? "").trim();
  const requester_phone = String(b.requester_phone ?? profile?.phone ?? "").replace(/[\s-]/g, "");
  if (requester_name.length < 2 || requester_name.length > 120) return fail("invalid_name", "Name required (2-120 chars).");
  if (!NEPAL_PHONE_RE.test(requester_phone)) return fail("invalid_phone", "Enter a valid Nepal mobile number.");

  if (!Number.isFinite(b.lat) || !Number.isFinite(b.lng) ||
      b.lat < LAT_MIN || b.lat > LAT_MAX || b.lng < LNG_MIN || b.lng > LNG_MAX) {
    return fail("invalid_location", "lat and lng (inside Nepal) are required.");
  }

  const urgency = String(b.urgency ?? "normal");
  if (!URGENCY.includes(urgency)) return fail("invalid_urgency", "urgency must be low, normal, high or critical.");

  let volunteers_needed: number | null = null;
  let items: { item_type: string; qty: number; unit: string }[] = [];

  if (VOLUNTEER_KINDS.includes(kind)) {
    volunteers_needed = Number(b.volunteers_needed);
    if (!Number.isInteger(volunteers_needed) || volunteers_needed < 1 || volunteers_needed > 100) {
      return fail("invalid_volunteers_needed", "volunteers_needed must be a whole number from 1 to 100.");
    }
  } else {
    items = Array.isArray(b.items) ? b.items : [];
    const bad = items.length < 1 || items.length > 20 || items.some((i: any) =>
      !ITEM_TYPES.includes(String(i?.item_type)) || !(Number(i?.qty) > 0) || Number(i.qty) > 1_000_000 ||
      !i?.unit || String(i.unit).length > 20);
    if (bad) return fail("invalid_items", `1-20 items, each with item_type (${ITEM_TYPES.join(", ")}), qty > 0 and unit.`);
  }

  const token = crypto.randomUUID() + crypto.randomUUID();
  const { data: row, error } = await sb.from("requests").insert({
    kind, requester_name, requester_phone,
    requester_profile_id: profile?.id ?? null,
    location: `SRID=4326;POINT(${b.lng} ${b.lat})`, // longitude first; district_id is set by trigger
    address_note: b.address_note ? String(b.address_note).slice(0, 300) : null,
    urgency, notes: b.notes ? String(b.notes).slice(0, 1000) : null,
    volunteers_needed,
    tracking_token_hash: await sha256(token),
  }).select("id, public_ref, status, district_id").single();
  if (error || !row) {
    console.error("request insert failed:", error?.message);
    return fail("db_error", "Could not create request.", 500);
  }

  if (items.length) {
    const { error: ie } = await sb.from("request_items").insert(
      items.map((i) => ({ request_id: row.id, item_type: i.item_type, requested_qty: Number(i.qty), unit: String(i.unit) })));
    if (ie) {
      console.error("items insert failed:", ie.message);
      await sb.from("requests").delete().eq("id", row.id); // do not leave a request with no items
      return fail("db_error", "Could not save items.", 500);
    }
  }

  let district: string | null = null;
  if (row.district_id) {
    const { data: d } = await sb.from("districts").select("name").eq("id", row.district_id).maybeSingle();
    district = d?.name ?? null;
  }
  return ok({ public_ref: row.public_ref, tracking_token: token, status: row.status, district }, 201);
});