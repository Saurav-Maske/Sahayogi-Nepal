// Public intake. Service role is used SERVER-SIDE ONLY; clients get no anonymous INSERT on tables.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { corsHeaders, ok, fail } from "../_shared/cors.ts";

const KINDS = ["resource_request","manpower_request","donation_offer","healthcare_request","transport_request"];

async function sha256(s: string) {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return fail("method_not_allowed", "POST only", 405);

  let b: any;
  try { b = await req.json(); } catch { return fail("bad_json", "Invalid JSON"); }

  if (!KINDS.includes(b.kind)) return fail("invalid_kind", "Unknown request kind");
  if (!b.requester_name || String(b.requester_name).length > 120) return fail("invalid_name", "Name required (max 120)");
  if (!/^\+?[0-9]{7,15}$/.test(String(b.requester_phone ?? ""))) return fail("invalid_phone", "Valid phone required");
  if (!b.district) return fail("invalid_district", "District required");
  const items = Array.isArray(b.items) ? b.items : [];
  if (items.length < 1 || items.length > 20 || items.some((i: any) => !i.item_type || !(Number(i.qty) > 0) || !i.unit))
    return fail("invalid_items", "1–20 items with item_type, qty>0, unit");

  // TODO(Person 2): rate limiting, CAPTCHA, duplicate detection.
  const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });

  const token = crypto.randomUUID() + crypto.randomUUID();
  const hasPoint = Number.isFinite(b.lat) && Number.isFinite(b.lng);
  const { data: reqRow, error } = await sb.from("requests").insert({
    kind: b.kind, requester_name: b.requester_name, requester_phone: b.requester_phone,
    district: b.district, urgency: b.urgency ?? "normal", notes: b.notes ?? null,
    location: hasPoint ? `SRID=4326;POINT(${b.lng} ${b.lat})` : null,
    tracking_token_hash: await sha256(token),
  }).select("id, public_ref, status").single();
  if (error) return fail("db_error", "Could not create request", 500);

  const { error: ie } = await sb.from("request_items").insert(
    items.map((i: any) => ({ request_id: reqRow.id, item_type: i.item_type, qty: Number(i.qty), unit: i.unit })));
  if (ie) return fail("db_error", "Could not save items", 500);

  return ok({ public_ref: reqRow.public_ref, tracking_token: token, status: reqRow.status }, 201);
});
