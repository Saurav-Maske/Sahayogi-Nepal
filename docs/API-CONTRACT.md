# API Contract (v1.2, owned by Person 2: Rujan Dhamala, Aakash Thakur)

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
- Admin JWT only: `volunteer_applications`, `requests`, `request_items`, `inventory_*`, `assignments`, `incidents`. The admin audit timeline uses `admin_list_audit()`, because direct reads of `audit_logs` have no policy.

### Realtime

`incidents` has Realtime enabled. Re-fetch authoritative state after an event; do not trust the payload alone.

## LIVE RPCs (signed-in user's JWT, except the public ones marked anon-callable)

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

### Progress, OTP and tracking (migration `20261122000005_rpc_progress_otp_tracking.sql`)

**Public / requester (anon or signed-in).** The requester proves ownership with `p_ref` (the 8-character `public_ref`) plus `p_token` (the `tracking_token` shown once at submit). A wrong ref or token returns `not_found` for both, so nothing leaks about which part was wrong.

- `get_tracking(p_ref, p_token)` returns `{ public_ref, kind, status, urgency, decline_reason, created_at, approved_at, picked_up_at, fulfilled_at, otp_purpose, can_update_pickup_qty, incident_status, items[], assignments[] }`.
  - `otp_purpose` is `delivery`, `pickup` or `null`: which OTP the requester can ask for right now.
  - `can_update_pickup_qty` is true only for a donation offer that has not been picked up yet.
  - `items[]`: `{ id, item_type, unit, requested_qty, approved_qty, donor_qty, confirmed_qty }`.
  - `assignments[]`: `{ assignment_type, state, volunteer_first_name, accepted_at, completed_at, location }`. Declined, expired and cancelled assignments are left out. `location` (`{ lat, lng, updated_at }`) is set only while the assignment is `en_route_to_pickup` or `en_route_to_destination` and the volunteer has reported a position; otherwise `null`. Only the volunteer's first name is shown.
  - Errors: `not_found`.
- `requester_get_otp(p_ref, p_token, p_purpose)` returns `{ code, purpose, expires_at }`. `p_purpose` is `delivery` (requester reads it to the driver) or `pickup` (donor reads it to the driver). Only a hash of the code is stored, so a code cannot be read back: **every call issues a fresh 6-digit code and cancels the previous live one.** Valid 15 minutes. Max 10 codes per assignment and purpose per hour.
  - Available while the assignment is `picked_up` / `en_route_to_destination` (delivery) or `accepted` / `en_route_to_pickup` (pickup).
  - Errors: `not_found | invalid_purpose | otp_not_available | too_many_requests`.
- `requester_update_pickup_qty(p_ref, p_token, p_items)`: `p_items` is `[{ "item_id": uuid, "qty": number }]`. Donor lowers quantities before pickup. A quantity can go down to 0 but never above the approved quantity, each item at most once, and at least one item must stay above 0. Items left out keep their value. Returns `{ items: [{ id, item_type, unit, approved_qty, qty }] }`. The driver sees the change at pickup (`quantity_changed` below).
  - Errors: `not_found | invalid_state | invalid_items`. `invalid_state` = not a donation offer, already picked up, or request not in `approved | awaiting_assignment | assigned | in_progress`.
- `requester_confirm_delivery(p_ref, p_token, p_full, p_note = null, p_shortfall = null)`: resource requests only, after the driver completed the delivery OTP (assignment `delivered`).
  - `p_full = true` returns `{ confirmed: true, request_status }`. Safe to repeat.
  - `p_full = false` opens a `short_delivery` incident, sets the assignment to `disputed` and the request to `partially_fulfilled`, and returns `{ incident_id, request_status: "partially_fulfilled", confirmed: false }`. `p_note` is required (2-500 characters). `p_shortfall` is optional: `[{ "item_id": uuid, "received_qty": number }]`, each between 0 and the approved quantity; it is stored as `confirmed_qty` and on the incident.
  - Errors: `not_found | invalid_items | invalid_state | invalid_note | already_reported`.

**Volunteer (active volunteer; otherwise `forbidden`, no session gives `unauthorized`).**

- `update_assignment_state(p_id, p_state)` moves your own assignment forward only. Returns `{ id, state, request_status }`. Allowed moves:

| Assignment type | Moves |
| --- | --- |
| `delivery` | `accepted` -> `en_route_to_pickup` -> `picked_up` -> `en_route_to_destination` (the last step, `delivered`, only through `driver_verify_otp`) |
| `pickup` | `accepted` -> `en_route_to_pickup` (`picked_up` only through `driver_verify_otp`) -> `en_route_to_destination` -> `delivered` |
| `manpower`, `healthcare`, `transport` | `accepted` -> `en_route_to_destination` -> `delivered`, or `accepted` -> `delivered` directly |

  A request with a single assignment becomes `in_progress` on the first move. A request with several slots stays `assigned` until the last one is delivered, so a released slot can still show up in `my_offers`. The request becomes `fulfilled` when no assignment is left open. Errors: `unauthorized | forbidden | not_found | invalid_state | invalid_transition | otp_required`. `otp_required` means you tried to skip an OTP step (`delivery` -> `delivered` or `pickup` -> `picked_up`).
- `driver_verify_otp(p_id, p_purpose, p_code, p_confirmed = false)`. `p_purpose` must match the assignment type (`pickup` or `delivery`). Spaces in `p_code` are ignored. **Wrong codes do not raise an error**, because an error would roll back the attempt counter. Instead the result is `{ ok: false, reason }`:

| `reason` | Meaning |
| --- | --- |
| `invalid_otp` | Wrong code. `attempts_left` tells how many tries remain (5 per code). |
| `otp_locked` | 5 wrong attempts on this code; the requester must issue a new one. |
| `otp_expired` | Older than 15 minutes. |
| `otp_used` | Already verified. |
| `otp_not_issued` | The requester has not asked for a code yet. |
| `quantity_changed` | Pickup only: the donor lowered a quantity. The result carries `items: [{ item_id, item_type, unit, expected_qty, qty }]`. The code stays unused; show the new quantities and call again with `p_confirmed = true`. |

  Success returns `{ ok: true, state, ... }`:
  - pickup: `{ ok: true, state: "picked_up", quantity_changed, items: [{ item_type, qty, unit }] }`. Confirmed quantities (donor quantity if lowered, else approved) are stored as `confirmed_qty` and added to inventory as `received` lots. The request gets `picked_up_at`.
  - delivery: `{ ok: true, state: "delivered", request_status: "fulfilled" }`. Reserved stock is dispatched (lot quantity and reservation updated), `confirmed_qty` is set to the approved quantity, the request becomes `fulfilled`.
  - Raised errors: `unauthorized | forbidden | not_found | invalid_purpose | invalid_state | nothing_to_pick_up`. An assignment that is not yours is `not_found`.

### Map and volunteer extras (migration `20261122000006_rpc_map_volunteer.sql`)

- `map_markers()` (**anon-callable**): array of `{ key, layer, kind, urgency, lat, lng, item_types, at }`, newest first, max 500. No name, phone, id or `public_ref`; coordinates rounded to 2 decimals; `key` is a one-way hash so the app can diff markers. Each request is in exactly one layer:

| `layer` | Contains |
| --- | --- |
| `fulfilled` | Status `fulfilled`, `fulfilled_at` within the last 12 h |
| `pickup` | Donation picked up within the last 6 h (and not yet `fulfilled`) |
| `donation` | Approved donation still waiting for pickup |
| `need` | Approved request of any other kind that is not finished |

  Pending, declined and cancelled requests are never shown. A donation that is fully delivered to the hub moves from `pickup` to `fulfilled` for 12 h, then drops off.
- `admin_map_markers()` (admin): `{ hub, requests[], volunteers[] }`. `hub` is the `central_inventory` setting. `requests[]` are exact positions of everything open (including `pending_admin_review` and `partially_fulfilled`) plus fulfilled in the last 12 h (max 1000): `{ id, public_ref, kind, status, urgency, requester_name, district, lat, lng, open_incidents, assignments { total, claimed }, created_at, updated_at }`. `volunteers[]` are in-progress assignments that reported a position in the last 30 minutes: `{ assignment_id, request_id, public_ref, assignment_type, state, volunteer_id, volunteer_name, volunteer_phone, lat, lng, updated_at }`. Errors: `forbidden`.
- `update_my_location(p_id, p_lat, p_lng)` (volunteer): live position for one of your own assignments; one row per assignment (upsert). Returns `{ ok: true, updated_at }`. Allowed while the assignment is `accepted`, `en_route_to_pickup`, `picked_up` or `en_route_to_destination` and the request is `assigned` or `in_progress`. Coordinates must be inside Nepal's rough box (lat 26.3-30.5, lng 80.0-88.3). Not audited (called every few seconds). Requesters only see it through `get_tracking` while `en_route_*`. Errors: `unauthorized | forbidden | invalid_location | not_found | invalid_state`.
- `my_stats()` (volunteer): `{ claimed_total, active, completed, disputed, completed_last_30_days, last_completed_at, completed_by_type, declined_offers }`. Counts are zero (and `last_completed_at` null) for a volunteer with no assignments. Errors: `unauthorized | forbidden`.
- `register_device_token(p_token, p_platform)` (volunteer): `p_platform` is `android | ios | web`; token 20-4096 characters, no whitespace. A token already stored moves to the caller. Only the 10 most recently seen tokens per volunteer are kept. Returns `{ id, platform }`. Errors: `unauthorized | forbidden | invalid_token | invalid_platform`. (Sending pushes is still PLANNED.)

### Inventory, incidents and audit (migration `20261122000007_rpc_inventory_incidents.sql`)

All admin only (`forbidden` for anyone else).

- `admin_import_stock(p_items)`: 1-50 rows, all-or-nothing. Each row: `{ item_type, qty, unit?, phase?, provider_name?, provider_contact?, condition_note? }`. `qty` is a number above 0 and up to 1,000,000; `unit` defaults to `unit` (max 20 characters); `phase` is `received` (default), `processing` or `ready_to_ship`. Every row becomes its own lot plus a movement and the call writes one audit row. Only `ready_to_ship` stock can be reserved by `admin_approve_request`. Returns `{ lots: [{ id, item_type, unit, quantity, phase }] }`. Errors: `forbidden | invalid_items | invalid_phase`.
- `admin_move_lot(p_id, p_phase, p_qty = null, p_reason = null)`: moves a lot or part of it. Allowed moves:

| From | To |
| --- | --- |
| `received` | `processing`, `ready_to_ship`, `adjusted` |
| `processing` | `ready_to_ship`, `adjusted` |
| `ready_to_ship` | `processing`, `adjusted` (only the part that is not reserved) |

  `dispatched`, `consumed`, `returned` and `adjusted` lots cannot be moved. `p_qty` defaults to everything movable (quantity minus reserved). A partial move **splits** the lot: the source keeps the rest and a new lot in the target phase gets `p_qty`. `adjusted` is a write-off and needs `p_reason` (2-300 characters). Returns `{ source_lot_id, lot_id, from_phase, phase, qty, split }`. Errors: `forbidden | invalid_phase | invalid_reason | not_found | invalid_transition | lot_reserved | invalid_qty`.
- `admin_list_incidents(p_status = null)`: filter is `open | under_review | resolved | dismissed`. Open first, then under review, then closed; newest first inside each group; max 500. Each row: `{ id, status, incident_type, reporter_note, reported_shortfall, resolution, admin_notes, created_at, request { id, public_ref, kind, status, requester_name, requester_phone, district, items[] }, assignment { id, assignment_type, state, volunteer_id, volunteer_name, volunteer_phone } }`. Errors: `forbidden | invalid_status`.
- `admin_resolve_incident(p_id, p_status, p_resolution = null, p_notes = null)`: `open` -> `under_review | resolved | dismissed`, `under_review` -> `resolved | dismissed`. `resolved` and `dismissed` are final and need `p_resolution` (2-500 characters). `p_notes` (max 1000) replaces `admin_notes` when sent. A **dismissed** incident (the report was not valid) puts a `partially_fulfilled` request back to `fulfilled` once no other incident on it is open. A **resolved** one leaves it `partially_fulfilled`. The assignment stays `disputed`. Returns `{ id, status, resolution, admin_notes, request_status }`. Errors: `forbidden | invalid_status | invalid_resolution | invalid_note | not_found | invalid_state`.
- `admin_list_audit(p_limit = 100, p_before = null, p_action = null, p_entity = null)`: newest first, 1-200 rows per page. Returns `{ items[], next_before }`; send `next_before` back as `p_before` for the next page (`null` means no older rows). Optional exact-match filters on `action` and `entity`. Each item: `{ id, date, action, actor_id, actor_name, entity, entity_id, detail, prev_hash, hash_value }`. Chain verification itself stays with `verify_audit_chain()` (service role). Errors: `forbidden | invalid_limit`.

Audit actions written by these RPCs: `otp_issued`, `otp_locked`, `donor_qty_changed`, `pickup_confirmed`, `delivery_completed`, `assignment_state_changed`, `incident_opened`, `stock_imported`, `lot_moved`, `incident_under_review`, `incident_resolved`, `incident_dismissed`.

## PLANNED

Everything below is still to build; the UI should mock it.

- Push notifications (FCM) that use the tokens stored by `register_device_token`.
- A `routes` table for `get-route` with `save: true` (see the known gap above).

`submit_request(p jsonb, p_profile uuid)` is LIVE but **service role only**; it is called by the `submit-request` Edge Function, never from a client.

**Callable without signing in:** `get_tracking`, `requester_get_otp`, `requester_update_pickup_qty`, `requester_confirm_delivery` and `map_markers`. Every other RPC above needs a signed-in user and checks the role inside. Older helper functions from the first migrations (`is_admin`, `audit_row_hash`, trigger functions, `fn_export_latest_audit_hash`) still carry the default public execute right; a clean-up migration should revoke it (see `TEST-MATRIX.md`, "Function privileges").

## Decisions still open

| Decision                                                                     | Current choice                                                                                    |
| ---------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| Field names `requester_name` / `requester_phone` vs `name` / `phone` | Code uses `requester_*`. Change the contract, not the app, if Person 1 already sends otherwise. |
| One pilot district or all Nepal                                              | Seeded `district` row is Kathmandu (pilot); polygons for every district are loaded.             |
| Who sees a general request in the first 60 s                                 | Built in `my_offers()`: exactly category A first, then everyone with A.                           |
| Public map                                                                   | RPC `map_markers()`, not a view.                                                                |
| Who reads the OTP                                                            | Donor for pickup, requester for delivery, both through `requester_get_otp`.                     |