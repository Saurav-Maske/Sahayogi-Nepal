// Public intake. Service role is used SERVER-SIDE ONLY; clients get no anonymous INSERT on tables.
// A signed-in volunteer may call this too: name/phone default to their profile and the request is linked to them.
// The request and its items are created by the submit_request RPC in ONE transaction (see migration
// 20261122000002_submit_request_rpc.sql), which also enforces the 5-per-phone-per-hour limit and the district bounds.
import { corsHeaders, fail, ok } from "../_shared/cors.ts";
import { adminClient, NEPAL_PHONE_RE, readJson, requireUser, sha256 } from "../_shared/auth.ts";

declare const Deno: {
  env: { get(name: string): string | undefined };
  serve(handler: (req: Request) => Response | Promise<Response>): void;
};

const ITEM_KINDS = ["resource_request", "donation_offer"]; // need an items[] list
const VOLUNTEER_KINDS = ["manpower_request", "healthcare_request", "transport_request"]; // need volunteers_needed
const ITEM_TYPES = ["food", "cloth", "temp_shelter", "medical_supplies", "drinking_water"];
const URGENCY = ["low", "normal", "high", "critical"];
// Cheap pre-check (rough bounding box of Nepal). The RPC then enforces the pilot district's own bounds.
const LAT_MIN = 26.3, LAT_MAX = 30.5, LNG_MIN = 80.0, LNG_MAX = 88.3;

// Codes the submit_request RPC raises (error.message) that are the caller's fault, with the message to show.
const RPC_CLIENT_ERRORS: Record<string, string> = {
  invalid_kind: "Unknown request kind.",
  invalid_name: "Name required (2-120 chars).",
  invalid_phone: "Enter a valid Nepal mobile number.",
  invalid_location: "lat and lng (inside Nepal) are required.",
  outside_service_area: "This location is outside the area we currently serve.",
  invalid_urgency: "urgency must be low, normal, high or critical.",
  invalid_volunteers_needed: "volunteers_needed must be a whole number from 1 to 100.",
  invalid_items: `1-20 items, each with item_type (${ITEM_TYPES.join(", ")}), qty > 0 and unit.`,
  too_many_requests: "Too many requests from this phone number. Please try again in an hour.",
};

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
    if (bad) return fail("invalid_items", RPC_CLIENT_ERRORS.invalid_items);
  }

  // The token is shown to the requester ONCE; only its hash is stored.
  const token = crypto.randomUUID() + crypto.randomUUID();
  const { data, error } = await sb.rpc("submit_request", {
    p: {
      kind, requester_name, requester_phone, lat: b.lat, lng: b.lng, urgency, volunteers_needed,
      address_note: b.address_note ? String(b.address_note).slice(0, 300) : null,
      notes: b.notes ? String(b.notes).slice(0, 1000) : null,
      items: items.length ? items.map((i) => ({ item_type: i.item_type, qty: Number(i.qty), unit: String(i.unit) })) : null,
      tracking_token_hash: await sha256(token),
    },
    p_profile: profile?.id ?? null,
  });

  if (error || !data) {
    const msg = error?.message ?? "";
    if (msg === "too_many_requests") return fail(msg, RPC_CLIENT_ERRORS[msg], 429);
    if (msg in RPC_CLIENT_ERRORS) return fail(msg, RPC_CLIENT_ERRORS[msg]);
    console.error("submit_request failed:", msg);
    return fail("db_error", "Could not create request.", 500);
  }

  return ok({
    request_id: data.request_id,
    public_ref: data.public_ref,
    tracking_token: token,
    status: data.status,
    district: data.district,
  }, 201);
});
