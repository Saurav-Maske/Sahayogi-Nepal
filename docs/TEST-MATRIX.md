# Test matrix (owner: Person 4, Rujan Dhamala and Aakash Thakur)

Mark each cell: ✅ pass, ❌ fail, ⏳ blocked (RPC not built yet), blank = not run.
Run against the demo project after `seed_demo.mjs` and `seed_extra.mjs`. Reset with `reset_demo_remote.mjs` between rehearsals.

| Test                  | Expected                                                                               | Needs                          | H24 | H30 | H36 | H42 |
| --------------------- | -------------------------------------------------------------------------------------- | ------------------------------ | --- | --- | --- | --- |
| Anonymous submit      | Created `pending_admin_review`; no PII or other requests readable                    | `submit-request` (live)      |     |     |     |     |
| Admin approval        | Admin only; approved qty ≤ available stock                                            | `admin_approve_request`      |     |     |     |     |
| Volunteer eligibility | A: general; B: +transport; C: +healthcare                                              | `my_offers`                  |     |     |     |     |
| 60 s escalation       | A-only offer opens to B and C after `escalate_at`                                    | `my_offers`                  |     |     |     |     |
| Double accept         | Only one claim succeeds                                                                | `claim_assignment`           |     |     |     |     |
| Donation pickup       | Donor can lower qty before OTP; confirmed qty lands in inventory as `received`       | `driver_verify_otp`          | ⏳  |     |     |     |
| Delivery OTP          | Single-use, expires in 15 min, locks after 5 attempts, bound to assignment and purpose | `driver_verify_otp`          | ⏳  |     |     |     |
| Short delivery        | Incident in admin queue; request not marked fully fulfilled                            | `requester_confirm_delivery` | ⏳  |     |     |     |
| Map windows           | Pickup older than 6 h and fulfilled older than 12 h disappear                          | `map_markers`                | ⏳  |     |     |     |
| Document privacy      | Anon and non-admin cannot read `volunteer-docs` objects                              | live                           |     |     |     |     |
| Stock concurrency     | Available never below 0 under parallel approvals                                       | `admin_approve_request`      |     |     |     |     |
| Function privileges   | Only tracking, requester-OTP and map functions are anon-callable                       | revoke/grant migration         | ⏳  |     |     |     |
| Audit chain           | `select * from verify_audit_chain()` returns no broken row                           | live                           |     |     |     |     |

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

Role tests to add once RPCs land: run each RPC as anon, volunteer (A, A+B, A+C) and admin, and confirm the denied cases return `forbidden` or `not_eligible`.
Postman: `postman/sahayogi.postman_collection.json`. Extend it with each new RPC and run the smoke set after every push.