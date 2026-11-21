
# Contract and backend changelog

Newest first. Anything that changes a payload, table, function or seed behaviour gets a line here.

## 2026-11-22

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
