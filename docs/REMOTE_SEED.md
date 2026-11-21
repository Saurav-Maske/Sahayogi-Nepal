
# Seeding the hosted Supabase project

Owner: Person 4 (Rujan Dhamala, Aakash Thakur), who are also Person 2. Run on the **demo** project first. For production, apply only step 1.

## Prerequisites

- Supabase CLI logged in (`supabase login`) and the project linked: `supabase link --project-ref <ref>`
- Root `.env` (git-ignored) containing:
  ```
  SUPABASE_URL=https://<ref>.supabase.co
  SUPABASE_SERVICE_ROLE_KEY=<service role key: Project Settings > API>
  DEMO_PASSWORD=<10+ chars, upper, lower, digit, symbol>
  ALLOW_DEMO_SEED=yes
  CONFIRM_PROJECT_REF=<ref>
  ```

  Use the **service role** key, not the anon key. Put flags in `.env`: `VAR=value command` does not work in Windows PowerShell.

## Steps

```bash
# 1. Schema, districts seed, settings (hub + district config)
supabase db push --include-seed

# 2. Demo data
cd scripts && npm install && cd ..
node --env-file=.env scripts/seed_demo.mjs     # users, base inventory, 8 requests
node --env-file=.env scripts/seed_extra.mjs    # fills every other table (needs step above first)
# or both at once: cd scripts && npm run seed

# 3. Rehearsal reset: wipes operational data, reseeds both scripts
node --env-file=.env scripts/reset_demo_remote.mjs
```

Run `npm install` inside `scripts/` (not the repo root): the scripts load packages from there.

## What each step creates

| Step                       | Tables filled                                                                                                                                                                                                                                                                                                                                                                                                               |
| -------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `db push --include-seed` | `districts` (77, idempotent), `app_settings` (`district`, `central_inventory`)                                                                                                                                                                                                                                                                                                                                      |
| `seed_demo.mjs`          | auth users + `profiles` (5), `inventory_lots` + `inventory_movements` (5), `requests` + `request_items` (8), 2 open `assignments`                                                                                                                                                                                                                                                                               |
| `seed_extra.mjs`         | `volunteer_applications` (7, with placeholder images in `volunteer-docs`), `device_tokens`, `auth_attempts`, 8 more `requests`, `assignments` in all 10 states, `assignment_events`, `otp_challenges`, `volunteer_locations`, `incidents` (1 open, 1 resolved), `inventory_reservations` (active, dispatched, released), extra lots in every phase, `audit_logs` (7) and `audit_hash_checkpoints` |

Demo logins: `admin@demo.test`, `driver1@demo.test`, `driver2@demo.test`, `general@demo.test`, `doctor@demo.test` with `DEMO_PASSWORD`.
The active delivery OTP for "Demo Requester I" is `123456` (stored hashed; usable once the OTP RPCs exist).

## Safety rules built into the scripts

- Refuse to touch a non-local project unless `ALLOW_DEMO_SEED=yes`.
- `reset_demo_remote.mjs` also needs `CONFIRM_PROJECT_REF` to match the URL.
- `audit_logs` is append-only and is never cleared, so old demo audit rows stay after a reset. `seed_extra.mjs` skips adding more when demo rows exist.
- Reset deletes all `requests`, `inventory_*`, `incidents` and their children, plus demo-only applications, device tokens and auth attempts. Real users, profiles and real applications are kept.
- `seed_demo.mjs` and `seed_extra.mjs` can be re-run: each section skips itself if its demo rows exist. To rebuild from scratch use the reset script.

## Verify

Rows counts in Studio's table list are estimates and often show 0 right after inserting. Count in the SQL Editor instead (see the seed smoke checks in [`TEST-MATRIX.md`](TEST-MATRIX.md)).

## Troubleshooting

| Symptom                                   | Cause / fix                                                                                                                          |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `Refusing to touch remote project`      | Set `ALLOW_DEMO_SEED=yes` in `.env`.                                                                                             |
| `Cannot find package 'bcryptjs'`        | Run `npm install` in `scripts/`.                                                                                                 |
| `Demo user ... missing`                 | Run `seed_demo.mjs` before `seed_extra.mjs`.                                                                                     |
| `app_settings` count is 0               | Migration `20261122000001` not pushed: run `supabase db push` and check it appears in the list.                                  |
| Unique `name` conflict on `districts` | The hosted project already has districts under different ids. Clear that table once in Studio, then re-push with `--include-seed`. |
| `FAILED: ...` from a script             | The message is the database error. Send the full output to Person 2.                                                                 |

Replace the placeholder `central_inventory` coordinates once the hub is confirmed, via a new migration.
