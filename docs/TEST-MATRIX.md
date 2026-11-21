# Test matrix (owner: Person 4, Rujan Dhamala and Aakash Thakur)

Mark each cell: ✅ pass, ❌ fail, ⏳ blocked, blank = not run. All RPCs are built now (migrations `...000003` to `...000007`), so nothing is blocked on the backend.
Run against the demo project after `seed_demo.mjs` and `seed_extra.mjs`. Reset with `reset_demo_remote.mjs` between rehearsals.

| Test                  | Expected                                                                               | Needs                          | H24 | H30 | H36 | H42 |
| --------------------- | -------------------------------------------------------------------------------------- | ------------------------------ | --- | --- | --- | --- |
| Anonymous submit      | Created `pending_admin_review`; no PII or other requests readable                    | `submit-request` (live)      |     |     |     |     |
| Admin approval        | Admin only; approved qty ≤ available stock                                            | `admin_approve_request`      |     |     |     |     |
| Volunteer eligibility | A: general; B: +transport; C: +healthcare                                              | `my_offers`                  |     |     |     |     |
| 60 s escalation       | A-only offer opens to B and C after `escalate_at`                                    | `my_offers`                  |     |     |     |     |
| Double accept         | Only one claim succeeds                                                                | `claim_assignment`           |     |     |     |     |
| Donation pickup       | Donor can lower qty before OTP; confirmed qty lands in inventory as `received`       | `driver_verify_otp`          |     |     |     |     |
| Delivery OTP          | Single-use, expires in 15 min, locks after 5 attempts, bound to assignment and purpose | `driver_verify_otp`          |     |     |     |     |
| Short delivery        | Incident in admin queue; request not marked fully fulfilled                            | `requester_confirm_delivery` |     |     |     |     |
| Map windows           | Pickup older than 6 h and fulfilled older than 12 h disappear                          | `map_markers`                |     |     |     |     |
| Document privacy      | Anon and non-admin cannot read `volunteer-docs` objects                              | live                           |     |     |     |     |
| Stock concurrency     | Available never below 0 under parallel approvals                                       | `admin_approve_request`      |     |     |     |     |
| Function privileges   | Only `get_tracking`, the 3 `requester_*` functions and `map_markers` are anon-callable (plus `is_admin`, which RLS policies need and which returns false for anon). Every function outside the 25 client RPCs is `service_role` only. Query 1 of `scripts/check_function_privileges.sql` returns zero rows | migration `20261122000011`, `scripts/check_function_privileges.sql` |     |     |     |     |
| Audit chain           | `select * from verify_audit_chain()` returns no broken row                           | live                           |     |     |     |     |
| Short-delivery dispute | Report opens one incident, assignment `disputed`, request `partially_fulfilled`; a second report returns `already_reported` | `requester_confirm_delivery` |     |     |     |     |
| Incident resolution   | Dismiss puts request back to `fulfilled`; resolve keeps `partially_fulfilled`; closed incident cannot change | `admin_resolve_incident`   |     |     |     |     |
| OTP wrong driver      | Another volunteer's `driver_verify_otp` returns `not_found`; a replayed code returns `invalid_state` | `driver_verify_otp`          |     |     |     |     |
| OTP re-issue          | Asking again cancels the old code; the 11th request in an hour returns `too_many_requests`   | `requester_get_otp`          |     |     |     |     |
| Tracking privacy      | Wrong ref or token is `not_found`; response has no phone or last name; location only while `en_route_*` | `get_tracking`               |     |     |     |     |
| Skip OTP              | `update_assignment_state` to `delivered` / `picked_up` returns `otp_required`          | `update_assignment_state`    |     |     |     |     |
| Stock after delivery  | Delivery OTP lowers lot quantity and reserved quantity by the reserved amount; lot becomes `consumed` at 0 | `driver_verify_otp`          |     |     |     |     |
| Lot moves             | Partial move splits the lot; reserved stock cannot be moved; `adjusted` needs a reason | `admin_move_lot`             |     |     |     |     |
| Audit timeline        | Pages by `next_before`; filter by action; non-admin gets `forbidden`                   | `admin_list_audit`           |     |     |     |     |
| Admin-only RPCs       | Volunteer and anon calls to every `admin_*` RPC fail (`forbidden` / permission denied) | all `admin_*`                |     |     |     |     |
| Push: new offer       | Creating assignments queues one push per eligible volunteer device; payload has only `type`, `assignment_id`, `request_id`; ineligible and declining volunteers get nothing | `send-push`, `push_recipients` |     |     |     |     |
| Push: escalation      | Unclaimed tier A offer sends one `escalated` push to volunteers with A plus B or C, within about a minute after `escalate_at`; exactly-{A} volunteers are not pushed twice | `push-escalations` cron      |     |     |     |     |
| Push: privileges      | Anon and volunteer cannot call `push_claim_batch`, `push_recipients` or read `push_outbox`; `send-push` without the right `x-push-secret` returns 401 | revoke/grant migration       |     |     |     |     |
| Push: dead token      | A token FCM reports unregistered is removed from `device_tokens`; the rest still receive the push | `send-push`                  |     |     |     |     |

## Seed smoke checks (live now)

Run in the SQL Editor after seeding. Expected counts are for a clean demo project.

| Check                      | Query                                                                | Expected                                         |
| -------------------------- | -------------------------------------------------------------------- | ------------------------------------------------ |
| Districts                  | `select count(*) from districts`                                   | 77                                               |
| Settings                   | `select key from app_settings order by 1`                          | `central_inventory`, `district`              |
| Demo users                 | `select count(*) from profiles where email like '%@demo.test'`     | 5                                                |
| Requests                   | `select count(*) from requests where requester_name like 'Demo %'` | 16                                               |
| Assignments in every state | `select state, count(*) from assignments group by 1`               | all 10 states present                            |
| Open incidents             | `select status, count(*) from incidents group by 1`                | `open` 1, `resolved` 1                       |
| Reservations               | `select status, count(*) from inventory_reservations group by 1`   | `active`, `dispatched`, `released` present |
| Audit demo rows            | `select count(*) from audit_logs where detail->>'demo' = 'true'`   | 7                                                |
| Map windows (data only)    | requests with `picked_up_at` 2 h ago and 7 h ago both exist        | 1 inside 6 h, 1 outside                          |

Run each RPC as anon, volunteer (A, A+B, A+C) and admin, and confirm the denied cases return `forbidden` or `not_eligible`.

Local check (2026-11-22): migrations `...000001` to `...000007` apply cleanly in order on PostgreSQL 16 with PostGIS and stubbed Supabase roles/auth, and the flows above were exercised by hand (delivery with OTP lock and expiry, donation pickup with a lowered quantity, dispute and dismissal, lot split, audit paging, map markers). That was not the demo project, so the cells stay blank until someone runs them there.
Postman: `postman/sahayogi.postman_collection.json`. Extend it with each new RPC and run the smoke set after every push.
| Sign-up OTP gate | Application without a token, with another email's token, or a reused token returns `403 email_not_verified`; with a valid token returns 201 and `email_verified_at` is set | `send-signup-otp`, `verify-signup-otp`, `submit-volunteer-application` |  |  |  |  |
| OTP wrong code | 4 wrong codes show `attempts_left`; the 5th returns `otp_locked`; the correct code afterwards is still rejected until a new code is requested | `verify-signup-otp`, `verify-reset-otp` |  |  |  |  |
| OTP expiry and resend | Code older than 10 min returns `otp_expired`; a second send within 60 s returns `resend_too_soon`; a new code invalidates the old one | `send-signup-otp` |  |  |  |  |
| Sign-up existing email | Email with a live application or an account returns `409 application_exists` at the send step | `send-signup-otp` |  |  |  |  |
| Forgot password | Code, token, new password works once; login with the old password fails and the new one works; old sessions are signed out; `password_reset` is in the audit log | `request-password-reset`, `verify-reset-otp`, `reset-password` |  |  |  |  |
| Reset does not leak accounts | Unknown, suspended and active emails all get the same 200 body from `request-password-reset`; only the active one receives mail | `request-password-reset` |  |  |  |  |
| Reset token single use | Replaying `reset_token`, or using it after 10 min, returns `invalid_token`; a weak password returns `weak_password` and the token still works | `reset-password` |  |  |  |  |
| Invite fallback | Approved volunteer who never opened the invite sets a first password through the OTP flow and can log in | `reset-password` |  |  |  |  |