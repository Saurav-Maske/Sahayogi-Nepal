# API Contract (v1.1, owned by Person 2: Rujan Dhamala, Aakash Thakur)

Change this file in the same PR as the code, and add a line to `docs/CHANGELOG.md`.
Auth, login and volunteer sign-up endpoints are in [`api-auth.md`](api-auth.md).

All responses: `{ "data": <obj|null>, "error": { "code": string, "message": string } | null }`
IDs: UUID. `public_ref`: random 8-character code, non-sequential. Timestamps: ISO-8601 UTC.
Base URL: `https://<ref>.supabase.co` (local `http://127.0.0.1:54321`). Functions: `POST {BASE}/functions/v1/<name>`.
Headers: `apikey: <ANON_KEY>`, `Content-Type: application/json`, plus `Authorization: Bearer <token>` where noted.

**Status legend:** LIVE = deployed in this repo. PLANNED = specified but not implemented; do not call it yet.

## Enums

- `request_kind`: `resource_request | manpower_request | donation_offer | healthcare_request | transport_request`
- `request_status`: `pending_admin_review | approved | declined | awaiting_assignment | assigned | in_progress | fulfilled | partially_fulfilled | cancelled`
- `assignment_type`: `manpower | delivery | pickup | healthcare | transport`
- `assignment_state`: `offered | accepted | declined | expired | en_route_to_pickup | picked_up | en_route_to_destination | delivered | disputed | cancelled`
- `inventory_phase`: `received | processing | ready_to_ship | reserved | dispatched | consumed | returned | adjusted`
- `item_type`: `food | cloth | temp_shelter | medical_supplies | drinking_water`
- `urgency`: `low | normal | high | critical`
- Volunteer categories: A = general, B = driver, C = healthcare. Driver = A+B, doctor = A+C, manpower = A.
- `volunteer_type`: `manpower | driver | doctor`. `role`: `volunteer | admin`.

## LIVE endpoints

### POST `/functions/v1/submit-request`  (anonymous allowed; optional volunteer JWT)

A signed-in active volunteer gets name and phone prefilled from their profile and the request is linked to them.

Resource request or donation offer (needs `items`):

```json
{ "kind": "resource_request", "requester_name": "Test Person", "requester_phone": "9800000000",
  "lat": 27.7172, "lng": 85.3240, "urgency": "high", "notes": "optional", "address_note": "optional",
  "items": [ { "item_type": "drinking_water", "qty": 50, "unit": "litre" } ] }
```

Manpower, healthcare or transport request (needs `volunteers_needed`, no items):

```json
{ "kind": "manpower_request", "requester_name": "Test Person", "requester_phone": "9800000000",
  "lat": 27.7172, "lng": 85.3240, "volunteers_needed": 3 }
```

Response 201:

```json
{ "data": { "request_id": "<uuid>", "public_ref": "AB12CD34", "tracking_token": "<shown once>", "status": "pending_admin_review", "district": "KATHMANDU" }, "error": null }
```

Rules: phone is a Nepal mobile (`98XXXXXXXX` or `+97798XXXXXXXX`); 1-20 items; `volunteers_needed` 1-100; `lat`/`lng` must be inside Nepal **and inside the pilot district's `bounds`** (the public `app_settings` row `district`). The DB trigger then sets `district_id` from the point; `district` is `null` if the point is in no polygon. `lng` comes first inside the stored point, but the JSON uses `lat` and `lng` by name.
Rate limit: **5 requests per phone number per hour** (`+97798...` and `98...` count as the same phone). The 6th returns HTTP 429.
Atomic: the request and its items are created by the `submit_request` RPC in one transaction, so a failure never leaves a request without items.
Errors: `invalid_kind | invalid_name | invalid_phone | invalid_location | outside_service_area | invalid_urgency | invalid_volunteers_needed | invalid_items | too_many_requests (429) | bad_json | db_error (500)`.
Keep `tracking_token`: only its hash is stored, so it cannot be shown again.

### POST `/functions/v1/get-route`  (any signed-in user)

```json
{ "locations": [ { "lat": 27.705, "lng": 85.32 }, { "lat": 27.72, "lng": 85.33 } ], "costing": "auto", "strict_nepal": true, "save": false }
```

`costing`: `auto | bicycle | pedestrian | motorcycle`. Response `data`: `{ route_id, summary: { length (km), time (s) }, shape (encoded polyline), trip }`.
Errors: `unauthorized | bad_json | invalid_locations | invalid_coordinate | out_of_bounds | routing_upstream_error | routing_network_error`.
**Known gap:** `save: true` inserts into a `routes` table that has no migration yet, so keep `save` false until one is added.

### Auth and volunteer functions

`admin-login`, `volunteer-login`, `auth-me`, `request-password-reset`, `create-upload-urls`, `submit-volunteer-application`, `approve-volunteer`, `admin-set-account-status`: see [`api-auth.md`](api-auth.md).

### Tables readable through the SDK (RLS applies)

- `app_settings` row `key = 'district'` is public-readable: `{ name, center: {lat,lng}, bounds: {south,west,north,east}, zoom }`. Other keys (including `central_inventory`) are server-only.
- `districts` (id, name, province, geom) is public-readable.
- Admin JWT only: `volunteer_applications`, `requests`, `request_items`, `inventory_*`, `assignments`, `incidents`. The admin audit timeline will use `admin_list_audit()` (PLANNED), because direct reads of `audit_logs` have no policy.

### Realtime

`incidents` has Realtime enabled. Re-fetch authoritative state after an event; do not trust the payload alone.

## LIVE RPCs (call with the signed-in user's JWT)

Call with the SDK: `supabase.rpc('<name>', { ...args })`. Unlike Edge Functions, RPCs return the raw JSON (no `{ data, error }` wrapper from us); a failure arrives as `error.message` holding one of the codes below. One request and response per RPC is in `docs/samples/`.

**Admin (`is_admin()` inside; anyone else gets `forbidden`)**

- `admin_list_requests(p_status text = null, p_kind text = null)` returns an array, critical urgency first then oldest first (max 500). Each row: `id, public_ref, kind, status, requester_name, requester_phone, urgency, notes, address_note, volunteers_needed, decline_reason, district, lat, lng, created_at, approved_at, picked_up_at, fulfilled_at, items[], assignments { total, open, claimed }`. Errors: `forbidden | invalid_status | invalid_kind`.
- `admin_approve_request(p_id uuid, p_items jsonb = null)`: `p_items` is `[{ "item_id": uuid, "approved_qty": number }]`; items left out are approved at the requested quantity, and `approved_qty` cannot exceed `requested_qty`. For `resource_request` it reserves stock FIFO from `ready_to_ship` lots under row locks; if stock is short the whole call rolls back. Sets status `approved`. Errors: `forbidden | not_found | invalid_state | invalid_items | nothing_approved | insufficient_stock` (the error `details` holds the item type).
- `admin_decline_request(p_id uuid, p_reason text)`: reason 2-300 characters; only from `pending_admin_review`. Errors: `forbidden | not_found | invalid_state | invalid_reason`.
- `admin_dashboard_counts()` returns `{ requests_by_status, assignments_by_state, open_offers, open_incidents, pending_applications, stock_available }`.
- `create_assignments(p_id uuid)`: only from `approved`; sets status `awaiting_assignment`. What it creates per kind:

| Request kind | Assignments | Tier | `route_snapshot` |
| --- | --- | --- | --- |
| `resource_request` | 1 `delivery` | B | hub, requester |
| `donation_offer` | 1 `pickup` | B | donor, hub |
| `manpower_request` | `volunteers_needed` x `manpower`, `escalate_at` = now + 60 s | A | requester |
| `healthcare_request` | `volunteers_needed` x `healthcare` | C | requester |
| `transport_request` | `volunteers_needed` x `transport` | B | requester |

  `items_snapshot` is `[{ item_type, qty, unit }]` (approved quantities). Route points are `{ label, lat, lng }`; the driver's own position is not included. Errors: `forbidden | not_found | invalid_state | already_assigned | hub_not_configured | nothing_to_deliver | invalid_volunteers_needed`.

**Volunteer (active volunteer; otherwise `forbidden`)**

- `my_offers()` returns open offers the volunteer may take: not declined by them, request still `awaiting_assignment`. Tier A is visible to volunteers with exactly `{A}` until `escalate_at`, then to everyone holding A; tier B needs B; tier C needs C. Offers carry only `approx_lat` / `approx_lng` (2 decimals), `district`, `items`, `urgency`, no requester name or phone.
- `my_assignment_detail(p_id)`: for your own assignment it adds `route`, and `requester { name, phone, lat, lng, address_note, notes }`. For an open eligible offer you get the redacted view. Anything else is `not_found`.
- `claim_assignment(p_id)`: one atomic conditional update; returns the same detail as `my_assignment_detail`. A volunteer can hold only one assignment per request. Sets the request to `assigned` once no open slot is left. Errors: `already_claimed | not_eligible | not_found | already_on_request | not_available`.
- `decline_assignment(p_id)` returns `{ id, released }`. Declining an open offer hides it from you. Declining your own `accepted` assignment releases it back to everyone else (`released: true`, request goes back to `awaiting_assignment`). Later states return `invalid_state`.

## PLANNED RPCs (not implemented; UI should mock these)

Build order and signatures follow the Backend Playbook. Every RPC will call `append_audit_log(...)` and be granted explicitly (`revoke ... from public, anon` first).

**Public / requester (anon-callable, token-hash checked)**

- `get_tracking(p_ref, p_token)`, `requester_get_otp(p_ref, p_token, p_purpose)`, `requester_update_pickup_qty(...)`, `requester_confirm_delivery(...)`
- `map_markers()`: rounded to 2 decimals, pickups from the last 6 h, fulfilled from the last 12 h

**Admin (`is_admin()` inside)**

- `admin_import_stock(...)`, `admin_move_lot(...)`, `admin_list_incidents()`, `admin_resolve_incident(...)`, `admin_list_audit()`, `admin_map_markers()`

**Volunteer (authenticated, eligibility checked in the DB)**

- `update_assignment_state(p_id, p_state)` (forward only), `update_my_location(...)`, `my_stats()`, `register_device_token(...)`
- `driver_verify_otp(p_id, p_purpose, p_code, p_confirmed)`: 15-minute expiry, 5-attempt lock, quantity-changed handling

`submit_request(p jsonb, p_profile uuid)` is LIVE but **service role only**; it is called by the `submit-request` Edge Function, never from a client.

## Decisions still open

| Decision                                                                     | Current choice                                                                                    |
| ---------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| Field names `requester_name` / `requester_phone` vs `name` / `phone` | Code uses `requester_*`. Change the contract, not the app, if Person 1 already sends otherwise. |
| One pilot district or all Nepal                                              | Seeded `district` row is Kathmandu (pilot); polygons for every district are loaded.             |
| Who sees a general request in the first 60 s                                 | Built in `my_offers()`: exactly category A first, then everyone with A.                           |
| Public map                                                                   | RPC `map_markers()`, not a view.                                                                |
| Who reads the OTP                                                            | Donor for pickup, requester for delivery, both through `requester_get_otp`.                     |