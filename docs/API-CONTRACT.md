
# API Contract (v1, owned by Person 2: Rujan Dhamala, Aakash Thakur)

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
{ "data": { "public_ref": "AB12CD34", "tracking_token": "<shown once>", "status": "pending_admin_review", "district": "KATHMANDU" }, "error": null }
```

Rules: phone is a Nepal mobile (`98XXXXXXXX` or `+97798XXXXXXXX`); 1-20 items; `volunteers_needed` 1-100; `lat`/`lng` inside the rough Nepal box (the DB trigger sets `district_id` from the point; `district` is `null` if the point is in no polygon). `lng` comes first inside the stored point, but the JSON uses `lat` and `lng` by name.
Errors: `invalid_kind | invalid_name | invalid_phone | invalid_location | invalid_urgency | invalid_volunteers_needed | invalid_items | bad_json | db_error`.
Keep `tracking_token`: only its hash is stored, so it cannot be shown again.
**Known gaps:** no phone rate limit yet, and request + items are two inserts (a crash between them can leave a request without items).

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

## PLANNED RPCs (not implemented; UI should mock these)

Build order and signatures follow the Backend Playbook. Every RPC will call `append_audit_log(...)` and be granted explicitly (`revoke ... from public, anon` first).

**Public / requester (anon-callable, token-hash checked)**

- `get_tracking(p_ref, p_token)`, `requester_get_otp(p_ref, p_token, p_purpose)`, `requester_update_pickup_qty(...)`, `requester_confirm_delivery(...)`
- `map_markers()`: rounded to 2 decimals, pickups from the last 6 h, fulfilled from the last 12 h

**Admin (`is_admin()` inside)**

- `admin_list_requests(p_status, p_kind)`, `admin_approve_request(p_id, p_items)` (reserves stock with row locks), `admin_decline_request(p_id, p_reason)`, `create_assignments(p_id)`
- `admin_import_stock(...)`, `admin_move_lot(...)`, `admin_list_incidents()`, `admin_resolve_incident(...)`, `admin_dashboard_counts()`, `admin_list_audit()`, `admin_map_markers()`

**Volunteer (authenticated, eligibility checked in the DB)**

- `my_offers()` (exactly category A for the first 60 s via `escalate_at`, then everyone with A), `my_assignment_detail(p_id)`, `claim_assignment(p_id)` (single atomic update; errors `already_claimed | not_eligible | not_found`), `decline_assignment(p_id)`
- `update_assignment_state(p_id, p_state)` (forward only), `update_my_location(...)`, `my_stats()`, `register_device_token(...)`
- `driver_verify_otp(p_id, p_purpose, p_code, p_confirmed)`: 15-minute expiry, 5-attempt lock, quantity-changed handling

`submit_request` will move into one transactional RPC (service role only) with the 5-requests-per-phone-per-hour limit; the Edge Function will call it. The request payload above stays the same.

## Decisions still open

| Decision                                                                     | Current choice                                                                                    |
| ---------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| Field names `requester_name` / `requester_phone` vs `name` / `phone` | Code uses `requester_*`. Change the contract, not the app, if Person 1 already sends otherwise. |
| One pilot district or all Nepal                                              | Seeded `district` row is Kathmandu (pilot); polygons for every district are loaded.             |
| Who sees a general request in the first 60 s                                 | Exactly category A first, then everyone with A.                                                   |
| Public map                                                                   | RPC `map_markers()`, not a view.                                                                |
| Who reads the OTP                                                            | Donor for pickup, requester for delivery, both through `requester_get_otp`.                     |
