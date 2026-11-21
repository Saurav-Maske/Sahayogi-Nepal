# Contract and backend changelog

Newest first. Anything that changes a payload, table, function or seed behaviour gets a line here.

## 2026-11-22 (push notifications)

- **Migration `20261122000009_push_outbox.sql`:** new `push_outbox` table (no client access), triggers that queue a `new_offer` row when an assignment is inserted as `offered` or released back to the pool, `_push_enqueue_escalations()` (tier A, once per assignment), `_push_kick()` (calls the function through `pg_net`), and service-role-only `push_claim_batch(p_limit)` and `push_recipients(p_assignment, p_kind)`. pg_cron job `push-escalations` runs every minute (queues escalations and retries failed rows); `purge-push-outbox` deletes finished rows after 7 days.
- **Edge Function `send-push`** plus `_shared/fcm.ts` (FCM HTTP v1, service-account JWT, no SDK). Listed in `config.toml` with `verify_jwt = false`; it is protected by the `x-push-secret` header instead.
- **Behaviour:** who gets a push uses the same rule as `my_offers`. Payload is IDs only (`type`, `assignment_id`, `request_id`); the OTP is never pushed. Dead tokens are removed. A row is tried up to 5 times.
- **Setup (once per project):** secrets `PUSH_WEBHOOK_SECRET`, `FCM_SERVICE_ACCOUNT` (and `PUSH_DRY_RUN=true` locally only); two vault entries `push_function_url` and `push_secret`; `supabase functions deploy send-push`. Without the vault entries nothing is sent and the outbox just waits.
- **Not audited on purpose:** no business state changes and the volume would flood the hash chain.
- **Flutter (Person 1):** call `register_device_token` on start and on token refresh; handle `data.type` `new_offer | escalated` by opening the offer or refreshing `my_offers()`; create a high-importance Android channel.
- **Contract:** v1.3. The Push notifications section replaces the planned item.

## 2026-11-22 (email OTP for sign-up and forgot password)

- **Migration `20261122000008_email_otp.sql`:** new `email_otps` table (one row per email + purpose, HMAC hashes only, no client access), `auth_attempts.kind` now also allows `otp_send | otp_verify`, new column `volunteer_applications.email_verified_at`, `purge_email_otps()` and `revoke_user_sessions(uuid)` (both service role only).
- **Volunteer sign-up:** new `send-signup-otp` and `verify-signup-otp`. `submit-volunteer-application` now requires `email_verification_token` (from `verify-signup-otp`) and returns `403 email_not_verified` without it. The token is spent only when the application is saved. **Breaking for the Flutter registration form:** it must add the email-code step before submitting.
- **Forgot password:** `request-password-reset` now emails a 6-digit code instead of a link (same generic 200 answer). New `verify-reset-otp` (returns a one-time `reset_token`) and `reset-password` (sets the new password, signs out every session, clears failed-login counters, audit action `password_reset`).
- **Behaviour:** code valid 10 min, 5 guesses per code (counted before comparing, so parallel guesses cannot bypass it), 60 s resend cooldown, sign-up token 30 min, reset token 10 min, both single use and bound to the email. Limits per hour: 5 codes per email and 15 per IP; 10 wrong codes per email and 30 per IP per 15 min.
- **Behaviour:** `reset-password` also confirms the email, so a volunteer whose invite link expired can set a first password this way. The invite link flow for newly approved volunteers is unchanged.
- **Email delivery:** OTP emails go out through Gmail SMTP from the functions (`GMAIL_ADDRESS`, `GMAIL_APP_PASSWORD` in `supabase/functions/.env`). New optional vars `OTP_PEPPER`, `MAIL_FROM_NAME`, `OTP_DEV_LOG` (local only: prints the code in the `functions serve` terminal).
- **Config:** four new functions listed in `config.toml` with `verify_jwt = false`.
- **Web:** `web/set-password` now offers email, code, new password when there is no valid link (replaces "Send me a new link").
- **Docs/Postman:** `api-auth.md` v2, new Postman requests under Auth and Volunteer application, new rows in the test matrix.
- **Known:** Flutter `volunteer_login_screen.dart` still shows "Password reset is not connected yet" and the registration screen does not send the token. Both are Person 1 work against this contract. `create-upload-urls` is still open to anyone (IP-throttled), not gated by the email token.

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