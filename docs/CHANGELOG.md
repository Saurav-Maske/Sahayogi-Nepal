# Contract and backend changelog

Newest first. Anything that changes a payload, table, function or seed behaviour gets a line here.

## 2026-11-22 (RPC parts 3 to 5)

- **Migration `20261122000005_rpc_progress_otp_tracking.sql`:** `update_assignment_state` (forward-only), `driver_verify_otp` (15-minute expiry, 5-attempt lock, quantity-changed handling), `requester_get_otp`, `requester_update_pickup_qty`, `requester_confirm_delivery`, `get_tracking`, plus internal helpers `_request_id_by_token` and `_active_otp_assignment` (no client grant). The four requester RPCs and `get_tracking` are callable without signing in; the token hash is checked inside.
- **Migration `20261122000006_rpc_map_volunteer.sql`:** `map_markers` (anon-callable, rounded to 2 decimals, pickup layer 6 h, fulfilled layer 12 h), `admin_map_markers`, `update_my_location`, `my_stats`, `register_device_token`.
- **Migration `20261122000007_rpc_inventory_incidents.sql`:** `admin_import_stock`, `admin_move_lot` (partial moves split the lot), `admin_list_incidents`, `admin_resolve_incident`, `admin_list_audit` (keyset pagination, optional action/entity filter). Every function checks `is_admin()` first.
- **Behaviour:** a wrong OTP does not raise an error. `driver_verify_otp` returns `{ ok: false, reason }` (`invalid_otp | otp_locked | otp_expired | otp_used | otp_not_issued | quantity_changed`) so the attempt counter is not rolled back. Wrong ref or token on the requester RPCs is always `not_found`.
- **Behaviour:** each `requester_get_otp` call issues a new code and cancels the previous live one (only a hash is stored, so a code cannot be shown twice). Limit: 10 codes per assignment and purpose per hour.
- **Behaviour:** `delivery -> delivered` and `pickup -> picked_up` cannot be set with `update_assignment_state` (error `otp_required`); only `driver_verify_otp` does that. Delivery OTP dispatches the reserved stock; pickup OTP adds `received` lots from the confirmed quantities.
- **Behaviour:** a short-delivery report sets the assignment to `disputed` and the request to `partially_fulfilled`. Dismissing the incident puts the request back to `fulfilled`; resolving it keeps `partially_fulfilled`.
- **Audit:** new actions `otp_issued`, `otp_locked`, `donor_qty_changed`, `pickup_confirmed`, `delivery_completed`, `assignment_state_changed`, `incident_opened`, `incident_under_review | resolved | dismissed`, `stock_imported`, `lot_moved`. `update_my_location` is not audited on purpose.
- **Contract:** v1.2. Planned RPC list replaced by LIVE sections; one `docs/samples/<rpc>.json` per new RPC added. Only push notifications and the `routes` table remain planned.
- **Docs:** README status updated; `REMOTE-SEED.md` links corrected to `REMOTE_SEED.md`.
- **Known:** the admin app still calls `admin_review_request`, `admin_set_accepted_qty` and `admin_review_volunteer`, which do not exist. The live names are `admin_approve_request` and `admin_decline_request`; there is no volunteer-review or accepted-quantity RPC yet (volunteers go through `approve-volunteer`).

## 2026-11-22 (RPC parts 1 and 2)

- **Migration `20261122000003_rpc_admin_requests.sql`:** `admin_list_requests`, `admin_approve_request` (FIFO stock reservation under row locks, all-or-nothing), `admin_decline_request`, `admin_dashboard_counts`. Granted to `authenticated`, `is_admin()` checked inside.
- **Migration `20261122000004_rpc_assignments.sql`:** `create_assignments`, `my_offers`, `my_assignment_detail`, `claim_assignment`, `decline_assignment`, plus the internal `_tier_open_to` helper (no client grant). The exactly-{A}-for-60-s rule is now live in `my_offers` and `claim_assignment`.
- **Behaviour:** offers and unclaimed detail expose only an approximate location (2 decimals) and no requester contact; the exact route and requester name/phone appear after a claim.
- **Behaviour:** a volunteer can hold only one assignment per request (`already_on_request`); declining your own accepted assignment releases it back to the pool.
- **Contract:** v1.1, new LIVE RPC section; samples added under `docs/samples/`.

## 2026-11-22

- **Fix:** `requireDriver` / `requireDoctor` tested `profiles.role` (only `volunteer | admin`), so they rejected every driver and doctor. They now check `categories` (`B` / `C`) on an active volunteer. All role guards share one profile lookup.
- **Audit:** every Edge Function now writes through `audit()` (`append_audit_log`) instead of inserting into `audit_logs` directly, which could put ids out of chain order. Affects `approve-volunteer`, `admin-set-account-status`, `admin-login`.
- **Migration `20261122000002_submit_request_rpc.sql`:** new `submit_request` RPC (service role only): request + items in one transaction, 5-per-phone-per-hour limit, pilot-district bounds check, audit row.
- **`submit-request` changes:** response now includes `request_id`; new errors `outside_service_area` and `too_many_requests` (429). Locations outside the pilot district's bounds are now rejected (before: anywhere in Nepal). Field names stay `requester_name` / `requester_phone`.
- **Config:** `get-route` listed explicitly in `config.toml`. Unused guard imports removed from `get-route`.
- **Postman:** donation sample moved from Pokhara to Lalitpur so it is inside the pilot bounds.
- **Seed:** `20261122000001_seed_app_settings.sql` seeds `app_settings` rows `district` (pilot: Kathmandu, public-readable) and `central_inventory` (hub, not public). Hub coordinates are a placeholder.
- **Seed:** `supabase/seeds/nepal_districts.sql` is now idempotent (upserts instead of `DELETE`), safe to re-run on a hosted project.
- **Scripts:** `seed_extra.mjs` fills every table (applications, assignments in every state, events, OTP challenges, incidents, reservations, locations, device tokens, auth attempts, audit log, checkpoint).
- **Scripts:** `reset_demo_remote.mjs` clears operational tables on a hosted project and reseeds. `audit_logs` is never cleared.
- **Scripts:** scripts read flags from `.env` so they work on Windows PowerShell.
- **Docs:** API contract rewritten to match the code (v1). Old v0 items (`rice`, `district` field, `SN-` prefix, `public_map_markers` view) removed.

## 2026-11-21

- Audit log rebuilt as an append-only hash chain (`append_audit_log`, `verify_audit_chain`, 2-hourly checkpoint). Columns are now `date` and `hash_value`.
- Nepal districts with polygons; `requests.district_id` is set by trigger from the point. `districts.lat/lng` dropped.
- Added `get-route` (Valhalla), login and password-reset functions, volunteer application flow.