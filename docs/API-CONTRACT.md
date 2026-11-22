# API Contract (v1.7, owned by Person 2: Rujan Dhamala, Aakash Thakur)

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
- Volunteer categories: A = general, B = driver, C = healthcare. Driver = A+B, doctor = A+C, manpower = A. A volunteer who is more than one type holds the union: driver + doctor = A+B+C.
- `volunteer_type`: `manpower | driver | doctor`. `role`: `volunteer | admin`.
- `volunteer_types`: array of `volunteer_type` on a sign-up request (`create-upload-urls`, `submit-volunteer-application`) and on `volunteer_applications`. `volunteer_type` stays as the primary type (doctor, then driver, then manpower) and is what `profiles.volunteer_type` holds. `profiles.categories` is the source of truth for what a volunteer may do.

## LIVE endpoints

### POST `/functions/v1/submit-request`  (anonymous allowed; optional volunteer JWT)

A signed-in active volunteer gets name and phone prefilled from their profile and the request is linked to them.

Resource request or donation offer (needs `items`):

```json
{ "kind": "resource_request", "requester_name": "Test Person", "requester_phone": "9800000000",
  "lat": 27.7172, "lng": 85.3240, "urgency": "high", "notes": "optional", "address_note": "optional",
  "items": [ { "item_type": "drinking_water", "qty": 50 } ] }
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

Rules: every unit is a **kit**: `qty` must be a whole number from 1 and `unit` is not needed (any other unit sent is stored as `kit`; a fraction is refused with `invalid_items`). Phone is a Nepal mobile (`98XXXXXXXX` or `+97798XXXXXXXX`); 1-20 items; `volunteers_needed` 1-100; `lat`/`lng` must be inside Nepal **and inside the pilot district's `bounds`** (read the config with `public-api/district`; the `app_settings` table itself is not public). The DB trigger then sets `district_id` from the point; `district` is `null` if the point is in no polygon. `lng` comes first inside the stored point, but the JSON uses `lat` and `lng` by name.
Rate limit: **5 requests per phone number per hour** (`+97798...` and `98...` count as the same phone). The 6th returns HTTP 429.
Atomic: the request and its items are created by the `submit_request` RPC in one transaction, so a failure never leaves a request without items.
Errors: `invalid_kind | invalid_name | invalid_phone | invalid_location | outside_service_area | invalid_urgency | invalid_volunteers_needed | invalid_items | too_many_requests (429) | bad_json | db_error (500)`.
Keep `tracking_token`: only its hash is stored, so it cannot be shown again.

### POST `/functions/v1/get-route`  (any signed-in, active user)

```json
{ "locations": [ { "lat": 27.705, "lng": 85.32 }, { "lat": 27.72, "lng": 85.33 } ], "costing": "auto", "save": false }
```

- `locations`: 2 to 10 points (`lng` or `lon`). All must be inside Nepal's rough box unless you send `strict_nepal: false` (default is strict).
- `costing`: `auto | bicycle | pedestrian | motorcycle` (default `auto`). `costing_options`: optional small object passed to Valhalla.
- `save: true` stores the route in `routes` (migration `20261122000010_routes.sql`) and returns its id. Optional `assignment_id` (only with `save: true`) links it to an assignment you hold; admins may link any.
- Response `data`: `{ route_id, summary: { length (km), time (s) }, shape, legs: [{ shape, length, time }], trip }`. `shape` is the first leg's encoded polyline (precision 6) and is kept for older clients; with three or more points (driver, hub, requester) draw every entry of `legs`. `route_id` is `null` unless saved.
- Clients can read their own saved rows from `routes` (RLS); admins read all. Only the function writes.
  Errors: `unauthorized (401) | account_suspended (403) | bad_json | invalid_locations | invalid_coordinate | out_of_bounds | invalid_costing_options | invalid_assignment_id | not_found (404) | routing_upstream_error (502) | routing_network_error (502) | db_insert_failed (500)`.

### POST `/functions/v1/get-offer-route`  (active volunteer; migration `20261122170000_offer_route_points.sql`)

Route preview for an offer **before or after accepting**, built on the server from the exact points. An open offer only shows an approximate position (about 1 km) and never the hub, so the app cannot build this route itself.

```json
{ "id": "<assignment id>", "lat": 28.95, "lng": 80.17, "costing": "auto" }
```

- `id`: the assignment (offer) id from `offers`, `offers/nearby` or `assignments/detail`. `lat` and `lng`: the driver's current position, inside Nepal's rough box. `costing`: `auto | bicycle | pedestrian | motorcycle` (default `auto`; anything else becomes `auto`).
- Who may ask: the same rule as `assignments/detail`. An open offer that is still `offered`, unclaimed, on a request in `awaiting_assignment`, not declined by you, and open to your categories (`_tier_open_to`); or your own assignment that is not finished. Everything else is `not_found`.
- Stops, in order after the driver: `donation_offer` donor then central inventory; `resource_request` central inventory then requester; manpower, healthcare and transport the requester only. The hub is read live from `app_settings` `central_inventory`.
- Response `data`: `{ kind, assignment_type, costing, shape_precision, summary: { length (km), time (s) }, legs: [{ to, shape, length, time }] }`. One leg per stop; `to` is `donor`, `central inventory` or `requester`. `shape` is an encoded polyline with **precision `shape_precision` (5)**, the same encoding `get-route` requests. Draw every leg.
- Deliberately **not** returned: the coordinates of the donor, requester or hub, street names, turn-by-turn steps, any name or phone. The ends of the lines still lead to the place, so treat the lines as sensitive. Nothing is saved.
- Points come from `offer_route_points(p_user, p_id)`, which only `service_role` can run (it returns exact coordinates); the function checks the caller's JWT and passes the user id in.
  Errors: `unauthorized (401) | forbidden (403) | not_found (404) | bad_json | invalid_id | invalid_location | out_of_bounds | hub_not_configured (500) | routing_upstream_error (502) | routing_network_error (502) | db_error (500)`.

### Auth and volunteer functions

`admin-login`, `volunteer-login`, `auth-me`, `send-signup-otp`, `verify-signup-otp`, `create-upload-urls`, `submit-volunteer-application` (now needs `email_verification_token`), `approve-volunteer`, `admin-set-account-status`, `request-password-reset`, `verify-reset-otp`, `reset-password`: see [`api-auth.md`](api-auth.md).

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
- `admin_approve_request(p_id uuid, p_items jsonb = null)`: `p_items` is `[{ "item_id": uuid, "approved_qty": number }]`; items left out are approved at the requested quantity, and `approved_qty` cannot exceed `requested_qty`. For `resource_request` it reserves stock FIFO from `ready_to_ship` lots under row locks; if stock is short the whole call rolls back. It creates the request's assignments in the same transaction, sets status `awaiting_assignment`, and returns the assignment IDs. Errors: `forbidden | not_found | invalid_state | invalid_items | nothing_approved | insufficient_stock | hub_not_configured | nothing_to_deliver | invalid_volunteers_needed` (the `insufficient_stock` error details hold the item type).
- `admin_decline_request(p_id uuid, p_reason text)`: reason 2-300 characters; only from `pending_admin_review`. Errors: `forbidden | not_found | invalid_state | invalid_reason`.
- `admin_dashboard_counts()` returns `{ requests_by_status, assignments_by_state, open_offers, open_incidents, pending_applications, stock_available }`.
- `create_assignments(p_id uuid)`: only from `approved`; sets status `awaiting_assignment`. What it creates per kind:

| Request kind           | Assignments                                                        | Tier | `route_snapshot` |
| ---------------------- | ------------------------------------------------------------------ | ---- | ------------------ |
| `resource_request`   | 1 `delivery`                                                     | B    | hub, requester     |
| `donation_offer`     | 1 `pickup`                                                       | B    | donor, hub         |
| `manpower_request`   | `volunteers_needed` x `manpower`, `escalate_at` = now + 60 s | A    | requester          |
| `healthcare_request` | `volunteers_needed` x `healthcare`                             | C    | requester          |
| `transport_request`  | `volunteers_needed` x `transport`                              | B    | requester          |

  `items_snapshot` is `[{ item_type, qty, unit }]` (approved quantities). Route points are `{ label, lat, lng }`; the driver's own position is not included. Errors: `forbidden | not_found | invalid_state | already_assigned | hub_not_configured | nothing_to_deliver | invalid_volunteers_needed`.

**Volunteer (active volunteer; otherwise `forbidden`)**

- `my_offers()` returns open offers the volunteer may take: not declined by them, request still `awaiting_assignment`. Tier A is visible to volunteers with exactly `{A}` until `escalate_at`, then to everyone holding A; tier B needs B; tier C needs C. Offers carry only `approx_lat` / `approx_lng` (2 decimals), `district`, `items`, `urgency`, no requester name or phone.
- `nearby_offers(p_lat, p_lng, p_radius_km = 100)` returns eligible, redacted offers within the supplied radius (0.1–100 km), with `assignment_id` and rounded `distance_km` for map-based claiming. It applies active-volunteer, decline, assignment-state, one-volunteer-per-request and tier checks; callers claim the returned `assignment_id` using `claim_assignment`. Errors: `unauthorized | forbidden | invalid_location`. Edge route: `POST /functions/v1/volunteer-api/offers/nearby` with `{ lat, lng, radius_km? }`.
- `my_assignment_detail(p_id)`: for your own assignment it adds `route`, and `requester { name, phone, lat, lng, address_note, notes }`. For an open eligible offer you get the redacted view. Anything else is `not_found`.
- `claim_assignment(p_id)`: one atomic conditional update; returns the same detail as `my_assignment_detail`. A volunteer can hold only one assignment per request. Sets the request to `assigned` once no open slot is left. Errors: `already_claimed | not_eligible | not_found | already_on_request | not_available`.
- `decline_assignment(p_id)` returns `{ id, released }`. Declining an open offer hides it from you. Declining your own `accepted` assignment releases it back to everyone else (`released: true`, request goes back to `awaiting_assignment`). Later states return `invalid_state`.

### Progress, OTP and tracking (migration `20261122000005_rpc_progress_otp_tracking.sql`)

**Public / requester (anon or signed-in).** The requester proves ownership with `p_ref` (the 8-character `public_ref`) plus `p_token` (the `tracking_token` shown once at submit). A wrong ref or token returns `not_found` for both, so nothing leaks about which part was wrong.

- `get_tracking(p_ref, p_token)` returns `{ public_ref, kind, status, urgency, decline_reason, created_at, approved_at, picked_up_at, fulfilled_at, otp_purpose, can_update_pickup_qty, incident_status, hub_received_at, items[], assignments[] }`.
  - `hub_received_at` is set once the admin has counted the donation at the hub (`admin_receive_donation`); the donor screen shows "delivered to hub" from it. Otherwise `null`.
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

| Assignment type                             | Moves                                                                                                                                                     |
| ------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `delivery`                                | `accepted` -> `en_route_to_pickup` -> (`picked_up` only through `driver_verify_otp`, purpose `hub_pickup`) -> `en_route_to_destination` (`delivered` only through `driver_verify_otp`, purpose `delivery`) |
| `pickup`                                  | `accepted` -> `en_route_to_pickup` (`picked_up` only through `driver_verify_otp`, purpose `pickup`) -> `en_route_to_destination` (`delivered` only through `driver_verify_otp`, purpose `hub_dropoff`, after the hub count) |
| `manpower`, `healthcare`, `transport` | `accepted` -> `en_route_to_destination` -> `delivered`, or `accepted` -> `delivered` directly                                                   |

  A request with a single assignment becomes `in_progress` on the first move. A request with several slots stays `assigned` until the last one is delivered, so a released slot can still show up in `my_offers`. The request becomes `fulfilled` when no assignment is left open. Errors: `unauthorized | forbidden | not_found | invalid_state | invalid_transition | otp_required`. `otp_required` means you tried to skip an OTP step (`delivery` -> `delivered` or `pickup` -> `picked_up`).

- `driver_verify_otp(p_id, p_purpose, p_code, p_confirmed = false)`. Four purposes (migrations `20261123000100` to `20261123000300`):

| `p_purpose` | Assignment | Whose code | Moves the job to |
| --- | --- | --- | --- |
| `pickup` | `pickup` (donation) | donor, via `requester_get_otp` | `picked_up` (in transit; **no stock is created**) |
| `hub_dropoff` | `pickup` (donation) | admin, via `admin_issue_otp`, only after the hub count | `delivered`; donation request `fulfilled` |
| `hub_pickup` | `delivery` (resource request) | admin, via `admin_issue_otp` | `picked_up`; stock stays reserved |
| `delivery` | `delivery` (resource request) | requester, via `requester_get_otp` | `delivered`; reserved stock dispatched; request `fulfilled` |

  Spaces in `p_code` are ignored. **Wrong codes do not raise an error**, because an error would roll back the attempt counter. Instead the result is `{ ok: false, reason }`:

| `reason`           | Meaning                                                                                                                                                                                                                |
| -------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `invalid_otp`      | Wrong code. `attempts_left` tells how many tries remain (5 per code).                                                                                                                                                |
| `otp_locked`       | 5 wrong attempts on this code; the requester must issue a new one.                                                                                                                                                     |
| `otp_expired`      | Older than 15 minutes.                                                                                                                                                                                                 |
| `otp_used`         | Already verified.                                                                                                                                                                                                      |
| `otp_not_issued`   | No code has been issued yet (the donor or requester has not asked, or the admin has not issued the hub code).                                                                                                                                                                            |
| `quantity_changed` | Pickup only: the donor changed a quantity (lowered, raised or added an item). The result carries `items: [{ item_id, item_type, unit, expected_qty, qty }]`. The code stays unused; show the new quantities and call again with `p_confirmed = true`. |

  Success returns `{ ok: true, state, ... }`:

- pickup: `{ ok: true, state: "picked_up", quantity_changed, items: [{ item_type, qty, unit }] }`. Confirmed quantities (donor quantity if changed, else approved) are stored as `confirmed_qty` only. The job is in transit; **inventory lots are created later by the hub count** (`admin_receive_donation`). The request gets `picked_up_at`.
- hub_dropoff: `{ ok: true, state: "delivered", request_status: "fulfilled" }`. Only after the hub count; before it the call is `invalid_state`. Donations picked up before the hub count existed already have their lots and count as counted.
- hub_pickup: `{ ok: true, state: "picked_up", request_status }`. The driver now holds the items; the reservation stays until the requester's `delivery` code.
- delivery: `{ ok: true, state: "delivered", request_status: "fulfilled" }`. Reserved stock is dispatched (lot quantity and reservation updated), `confirmed_qty` is set to the approved quantity, the request becomes `fulfilled`.
- Raised errors: `unauthorized | forbidden | not_found | invalid_purpose | invalid_state | nothing_to_pick_up`. An assignment that is not yours is `not_found`. `invalid_purpose` also means the purpose does not fit the assignment type.

### Map and volunteer extras (migration `20261122000006_rpc_map_volunteer.sql`)

- `map_markers()` (**anon-callable**, migration `20261122160000_public_map_completed_only.sql`): the public Explore map for people who are not logged in. Array of `{ key, layer, kind, urgency, lat, lng, item_types, at }`, newest first, max 500. No name, phone, id or `public_ref`; coordinates rounded to 2 decimals; `key` is a one-way hash so the app can diff markers. Only completed work is returned, in two layers:

| `layer`     | Colour | Contains                                                                                                                                           | `at`           |
| ------------- | ------ | -------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------- |
| `pickup`    | blue   | `kind = donation_offer`, `picked_up_at` within the last 6 h (the driver has entered the donor's OTP). It stays here after the drop at the hub. | `picked_up_at` |
| `fulfilled` | green  | `kind = resource_request`, status `fulfilled` or `partially_fulfilled`, `fulfilled_at` within the last 12 h                                | `fulfilled_at` |

  Everything else is never returned: pending, approved, open, being picked up or delivered, declined and cancelled requests, and every other kind (manpower, healthcare, transport). The old `donation` and `need` layers no longer exist.

- `admin_map_markers()` (admin): `{ hub, requests[], volunteers[] }`. `hub` is the `central_inventory` setting. `requests[]` are exact positions of everything open (including `pending_admin_review` and `partially_fulfilled`) plus fulfilled in the last 12 h (max 1000): `{ id, public_ref, kind, status, urgency, requester_name, district, lat, lng, open_incidents, assignments { total, claimed }, created_at, updated_at }`. `volunteers[]` are in-progress assignments that reported a position in the last 30 minutes: `{ assignment_id, request_id, public_ref, assignment_type, state, volunteer_id, volunteer_name, volunteer_phone, lat, lng, updated_at }`. Errors: `forbidden`.
- `update_my_location(p_id, p_lat, p_lng)` (volunteer): live position for one of your own assignments; one row per assignment (upsert). Returns `{ ok: true, updated_at }`. Allowed while the assignment is `accepted`, `en_route_to_pickup`, `picked_up` or `en_route_to_destination` and the request is `assigned` or `in_progress`. Coordinates must be inside Nepal's rough box (lat 26.3-30.5, lng 80.0-88.3). Not audited (called every few seconds). Requesters only see it through `get_tracking` while `en_route_*`. Errors: `unauthorized | forbidden | invalid_location | not_found | invalid_state`.
- `my_stats()` (volunteer): `{ claimed_total, active, completed, disputed, completed_last_30_days, last_completed_at, completed_by_type, declined_offers }`. Counts are zero (and `last_completed_at` null) for a volunteer with no assignments. Errors: `unauthorized | forbidden`.
- `my_requests()` (active volunteer): newest first, own request summaries submitted while signed in: `{ public_ref, kind, status, urgency, district, created_at, approved_at, picked_up_at, fulfilled_at, volunteers_needed, items[] }`. Items include requested, approved, donor and confirmed quantities. Tracking tokens are never returned; the app can track only requests whose one-time token is still saved locally. Errors: `unauthorized | forbidden`.
- `register_device_token(p_token, p_platform)` (volunteer): `p_platform` is `android | ios | web`; token 20-4096 characters, no whitespace. A token already stored moves to the caller. Only the 10 most recently seen tokens per volunteer are kept. Returns `{ id, platform }`. Errors: `unauthorized | forbidden | invalid_token | invalid_platform`. (Pushes are sent by the `send-push` function, see "Push notifications" below.)

### Inventory, incidents and audit (migration `20261122000007_rpc_inventory_incidents.sql`)

All admin only (`forbidden` for anyone else).

- `admin_import_stock(p_items)`: 1-50 rows, all-or-nothing. Each row: `{ item_type, qty, unit?, phase?, provider_name?, provider_contact?, condition_note? }`. `qty` is a number above 0 and up to 1,000,000; `unit` is always stored as `kit` and `qty` must be a whole number (a fraction is refused with `invalid_quantity`); `phase` is `received` (default), `processing` or `ready_to_ship`. Every row becomes its own lot plus a movement and the call writes one audit row. Only `ready_to_ship` stock can be reserved by `admin_approve_request`. Returns `{ lots: [{ id, item_type, unit, quantity, phase }] }`. Errors: `forbidden | invalid_items | invalid_phase`.
- `admin_move_lot(p_id, p_phase, p_qty = null, p_reason = null)`: moves a lot or part of it. Allowed moves:

| From              | To                                                                |
| ----------------- | ----------------------------------------------------------------- |
| `received`      | `processing`, `ready_to_ship`, `adjusted`                   |
| `processing`    | `ready_to_ship`, `adjusted`                                   |
| `ready_to_ship` | `processing`, `adjusted` (only the part that is not reserved) |

  `dispatched`, `consumed`, `returned` and `adjusted` lots cannot be moved. `p_qty` defaults to everything movable (quantity minus reserved). A partial move **splits** the lot: the source keeps the rest and a new lot in the target phase gets `p_qty`. `adjusted` is a write-off and needs `p_reason` (2-300 characters). Returns `{ source_lot_id, lot_id, from_phase, phase, qty, split }`. Errors: `forbidden | invalid_phase | invalid_reason | not_found | invalid_transition | lot_reserved | invalid_qty`.

- `admin_list_incidents(p_status = null)`: filter is `open | under_review | resolved | dismissed`. Open first, then under review, then closed; newest first inside each group; max 500. Each row: `{ id, status, incident_type, reporter_note, reported_shortfall, resolution, admin_notes, created_at, request { id, public_ref, kind, status, requester_name, requester_phone, district, items[] }, assignment { id, assignment_type, state, volunteer_id, volunteer_name, volunteer_phone } }`. Errors: `forbidden | invalid_status`.
- `admin_resolve_incident(p_id, p_status, p_resolution = null, p_notes = null)`: `open` -> `under_review | resolved | dismissed`, `under_review` -> `resolved | dismissed`. `resolved` and `dismissed` are final and need `p_resolution` (2-500 characters). `p_notes` (max 1000) replaces `admin_notes` when sent. A **dismissed** incident (the report was not valid) puts a `partially_fulfilled` request back to `fulfilled` once no other incident on it is open. A **resolved** one leaves it `partially_fulfilled`. The assignment stays `disputed`. Returns `{ id, status, resolution, admin_notes, request_status }`. Errors: `forbidden | invalid_status | invalid_resolution | invalid_note | not_found | invalid_state`.
- `admin_list_audit(p_limit = 100, p_before = null, p_action = null, p_entity = null)`: newest first, 1-200 rows per page. Returns `{ items[], next_before }`; send `next_before` back as `p_before` for the next page (`null` means no older rows). Optional exact-match filters on `action` and `entity`. Each item: `{ id, date, action, actor_id, actor_name, entity, entity_id, detail, prev_hash, hash_value }`. Chain verification itself stays with `verify_audit_chain()` (service role). Errors: `forbidden | invalid_limit`.

Audit actions written by these RPCs: `hub_received`, `hub_pickup_confirmed`, `hub_dropoff_completed`, `otp_issued`, `otp_locked`, `donor_qty_changed`, `pickup_confirmed`, `delivery_completed`, `assignment_state_changed`, `incident_opened`, `stock_imported`, `lot_moved`, `incident_under_review`, `incident_resolved`, `incident_dismissed`.

### Push notifications (migration `20261122000009_push_outbox.sql`, function `send-push`)

Not an API the apps call. The database queues a push and the `send-push` Edge Function sends it through FCM to the tokens stored by `register_device_token`.

| `data.type` | When                                                                                              | Who is told                                                                                                                                                                                                                    |
| ------------- | ------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `new_offer` | An assignment is created as `offered`, or a volunteer releases an accepted one back to the pool | Volunteers who can see it in `my_offers` at that moment: tier A goes to exactly `{A}` first, tier B to holders of B, tier C to holders of C. Not anyone who declined it or already holds an assignment on the same request |
| `escalated` | A tier A assignment is still unclaimed after `escalate_at`                                      | Volunteers with A plus another category (the ones who could not see it before). Checked once a minute, so it can arrive up to a minute after `escalate_at`                                                                   |
| `low_stock` | Ready-to-ship stock of a category falls below its reserve level (once per drop; re-armed when stock recovers or the level is changed) | Every registered device seen in the last 90 days, volunteers and normal users (`push_recipients_all()`), paged so it is not cut off at 1000 |

- Payload `data`: `{ type, assignment_id, request_id }`, all strings. **IDs only**: no OTP, name, phone or location. The notification text is generic ("Delivery needs a driver", "Open the app to view and claim it."). The app opens the offer with `my_assignment_detail(assignment_id)` or refreshes `my_offers()`.
- `low_stock` payload `data`: `{ type: "low_stock", item_type }`. No personal data; the text says stock is running low.
- One push per volunteer per request, even when a manpower request needs several volunteers.
- A push is a nudge, not the source of truth: it can be late or missed, so the app must still refresh `my_offers()` on open and while the offers screen is visible.
- A token FCM reports as unregistered is deleted from `device_tokens`. The app should call `register_device_token` on every start and whenever FCM rotates the token.
- Nothing is sent until the one-time setup is done on the project (vault entries, function secrets, FCM; see `docs/DEMO-SETUP.md` step 5 and run `scripts/check_push_setup.sql`).
- Not covered yet: requester notifications (requesters have no account or token), pushes for state changes after a claim.
- Function: `POST /functions/v1/send-push` with header `x-push-secret`. Responses: `200 { claimed, groups, sent, failed, invalid_tokens_removed, dry_run }`; errors `401 unauthorized | 500 misconfigured | claim_failed | 503 fcm_not_configured`.

## Hub flow, reserve levels and driver issues (migrations `20261122141000` to `20261123000300`)

**Kits.** Every unit is a kit and every quantity is a whole number, on `request_items` and `inventory_lots` (check constraints plus a trigger, migration `20261122181000_kit_units_whole_numbers.sql`). A unit sent by an app becomes `kit`; a fraction is refused with `invalid_quantity` (`invalid_items` in `submit-request`).

**Donation flow at the hub.** Pickup (donor code) -> `admin_receive_donation` (count) -> `admin_issue_otp` (hub_dropoff code) -> driver enters it. Stock exists only from the count. Donated stock joins the reserve count once the admin moves the new `received` lot to `ready_to_ship`.

- `admin_receive_donation(p_id uuid, p_items jsonb)` (admin; edge route `assignments/receive`; migration `20261123000100_hub_receive_count.sql`): `p_id` is the pickup assignment; `p_items` is `[{ "item_id": uuid, "qty": n }]`, the whole kits counted per item (items left out count as 0; whole numbers 0 to 1,000,000). Creates one `received` lot per counted item plus a movement (reason `hub receipt`) and runs the reserve check. If any count differs from what the driver confirmed it opens a `hub_shortfall` incident tied to that assignment and driver. Works once per job and only while the job is `picked_up` / `en_route_to_destination`. Returns `{ assignment_id, lots_created, items: [{ item_id, item_type, unit, expected_qty, counted_qty }], shortfall, incident_id }`. Errors: `forbidden | not_found | invalid_state | invalid_items | invalid_quantity | already_received`. The incident does not block finishing; the admin resolves it in Incidents.
- `admin_issue_otp(p_id uuid)` (admin; edge route `assignments/issue-otp`; migrations `20261123000200` and `20261123000300`): chooses the purpose from the job. A `pickup` job that is `picked_up` / `en_route_to_destination` gets a `hub_dropoff` code, and only after the count; a `delivery` job that is `accepted` / `en_route_to_pickup` gets a `hub_pickup` code. The job needs a volunteer and the request must be `assigned` or `in_progress`. Code: 6 digits, stored hashed, 15 minutes, 5 attempts, at most 10 codes per assignment and purpose per hour; a new code cancels the live one. Returns `{ code, purpose, expires_at, assignment_id }`. **The code is shown once**: the admin reads it to the driver. Errors: `forbidden | not_found | invalid_state | not_received | too_many_requests`. `not_received` = the donation has not been counted yet.
- `driver_report_issue(p_id uuid, p_type text, p_note text)` (volunteer; edge route `assignments/report-issue`; migrations `20261122191000` and `20261123000300`): the driver refuses the items or reports a mismatch. `p_type` is `pickup_refused` or `items_mismatch`; `p_note` is 2-500 characters. Works on your own `pickup` job before the donor's code, and on your own `delivery` job before the `hub_pickup` code (the incident type is then `hub_pickup_refused` or `hub_items_mismatch`). It opens an incident that keeps the reporting driver, releases the job back to offers with that driver excluded, and sets the request back to `awaiting_assignment`. For a resource request the reserved stock is **kept** (another driver delivers it); the admin can decline the request from the incident to release it. Returns `{ incident_id, released: true }`. Errors: `unauthorized | forbidden | not_found | invalid_type | invalid_note | invalid_state`.
- Incident types in `admin_list_incidents`: `short_delivery`, `hub_shortfall`, `pickup_refused`, `items_mismatch`, `hub_pickup_refused`, `hub_items_mismatch`.

**Reserve levels and low-stock push** (migrations `20261122141000`, `20261122182000`, `20261122183000`).

- `admin_list_reserve_levels()` (admin; edge route `stock/reserve-levels`) returns `[{ item_type, min_qty, stock, below_reserve, last_alert_at }]`. `stock` counts only lots in phase `ready_to_ship`, quantity minus reserved, the same rule as approval.
- `admin_set_reserve_level(p_item_type, p_min_qty)` (admin; edge route `stock/reserve-levels/set`): whole kits, 0 = alert off (0 to 1,000,000). Runs the check at once. Changing a level re-arms the alert, so a category already below its new level alerts once straight away; the same value again does not. Starting values are a placeholder of 10 kits per category and start silent. Errors: `forbidden | invalid_items | invalid_qty`.
- `register_public_device_token(p_token, p_platform)` (**anon-callable**; edge route `public-api/device-token`): same rules as `register_device_token`, no login. It never changes the owner of a token that already belongs to a volunteer.
- `get_district_config()` (**anon-callable**; edge route `public-api/district`) returns the `district` map config (name, center, bounds, zoom). `app_settings` itself is closed.

## PLANNED

Everything below is still to build; the UI should mock it.

- Nothing is planned right now.

`submit_request(p jsonb, p_profile uuid)` is LIVE but **service role only**; it is called by the `submit-request` Edge Function, never from a client.

**Callable without signing in:** `get_tracking`, `requester_get_otp`, `requester_update_pickup_qty`, `requester_confirm_delivery`, `map_markers`, `register_public_device_token` and `get_district_config`. Every other RPC above needs a signed-in user and checks the role inside. Helper functions are closed by migration `20261122000011_function_privileges.sql` (only `is_admin` stays open on purpose); check with `scripts/check_function_privileges.sql` after every `db push`.

## Decisions still open

| Decision                                                                     | Current choice                                                                                    |
| ---------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| Field names `requester_name` / `requester_phone` vs `name` / `phone` | Code uses `requester_*`. Change the contract, not the app, if Person 1 already sends otherwise. |
| One pilot district or all Nepal                                              | Pilot district is Kanchanpur (migration `20261122122624_kanchanpur_seed.sql`); polygons for every district are loaded. Config is read through `public-api/district`.             |
| Who sees a general request in the first 60 s                                 | Built in `my_offers()`: exactly category A first, then everyone with A.                         |
| Public map                                                                   | RPC `map_markers()`, not a view.                                                                |
| Who reads the OTP                                                            | Donor for pickup, requester for delivery, both through `requester_get_otp`.                     |

### Inventory repositories (migration `20261122120000_inventory_repository_sync.sql`)

- Every lot, reservation and movement carries `inventory_repository_id`; it is NOT NULL. A reservation always has its lot's repository (trigger plus composite foreign key).
- `admin_import_stock`: each row accepts optional `repository_id` (uuid, default FWU-SOE). Unknown id raises `invalid_repository`. Each returned lot includes `repository_id`.
- `admin_move_lot`: a split keeps the source lot's repository. The audit detail includes `repository_id`.
- `admin_approve_request`: reserves from repositories in the request's district first, then others, FIFO inside each group.
- Donation lots are created at the hub count (`admin_receive_donation`), not at pickup, in the repository nearest to the donation request (fallback FWU-SOE).
- `admin_inventory_reconcile()` (admin, edge route `stock/reconcile`): `{ ok, issues[] }`. Issue types: `reserved_mismatch`, `stale_reservation`, `reservation_not_ready`.
- View `inventory_available_by_repository` (service role / admin JWT through RLS): availability per repository and item type. `inventory_available` is unchange
