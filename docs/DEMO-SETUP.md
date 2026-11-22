# Demo project: setup, test run, reset

Owner: Person 4 (with Person 2). Goal: a hosted `sahayogi-demo` project where every matrix row can be run and the presentation screenshots taken. Nothing here has been run yet: the first full run will find problems, and each one is a fix to a migration or function in Git, not in the dashboard.

Use a **separate** Supabase project. Never point the scripts below at anything you cannot wipe.

## 0. Before you start

- [ ] Confirm the real hub coordinates with Person 4 (issue 8). `create_assignments` fails with `hub_not_configured` without them, and routes use whatever is there.
- [ ] Tools: Supabase CLI logged in (`supabase login`), Node 20+. On Windows use `scripts\demo_deploy.ps1`; the `.sh` version needs Git Bash or WSL.
- [ ] `cd scripts && npm install` (the seed and test scripts load packages from there).

## 1. Create the project

Supabase dashboard: New project, name `sahayogi-demo`, a region near the demo audience, a strong database password (keep it; the CLI needs it). Note the project ref (the `xxxx` in `https://xxxx.supabase.co`).

Project Settings > API: copy the URL, the `anon` key and the `service_role` key.

Database > Extensions: nothing to switch on by hand. The migrations create `postgis`, `pgcrypto`, `pg_cron` and `pg_net`; `vault` is on by default. If `db push` complains about an extension, enable it here and push again.

## 2. Root `.env`

Copy `.env.example` to `.env` and set (never commit):

```
SUPABASE_URL=https://<ref>.supabase.co
SUPABASE_ANON_KEY=<anon key>
SUPABASE_SERVICE_ROLE_KEY=<service role key>
SUPABASE_DB_PASSWORD=<database password>
CONFIRM_PROJECT_REF=<ref>
ALLOW_DEMO_SEED=yes
DEMO_PASSWORD=<10+ chars, upper, lower, digit, symbol; NOT the one in the scripts' defaults>
```

## 3. Function secrets

```bash
cp supabase/functions/.env.demo.example supabase/functions/.env.demo
# fill it in: SET_PASSWORD_URL, ALLOWED_ORIGIN, OTP_PEPPER, PUSH_WEBHOOK_SECRET (openssl rand -hex 32), RESEND_API_KEY, MAIL_FROM_ADDRESS, VALHALLA_URL, FCM_SERVICE_ACCOUNT
```

Do not add `OTP_DEV_LOG` or `PUSH_DRY_RUN`; `demo_deploy.sh` / `demo_deploy.ps1` refuse if they are present.

## 4. Push migrations, set secrets, deploy functions

```bash
./scripts/demo_deploy.sh                                                  # macOS, Linux, Git Bash, WSL
```

```powershell
powershell -ExecutionPolicy Bypass -File scripts\demo_deploy.ps1          # Windows PowerShell
```

Both scripts check that `SUPABASE_URL` matches `CONFIRM_PROJECT_REF`, asks you to retype the ref, then runs: link, `db push --include-seed` (migrations `000001` to `000011` in order, plus the 77 districts), `secrets set`, and `functions deploy` for every folder in `supabase/functions` except `_shared`.

If a migration fails, nothing after it is applied. Fix it in Git as a new migration (do not edit one that already ran on the project) and push again. `20261122000011_function_privileges.sql` rolls itself back and names the function if `anon` or `authenticated` could still run something outside their lists.

## 5. Manual settings (the CLI does not do these)

1. **SQL Editor:** run `scripts/demo_vault_secrets.sql` with the real ref and the same `PUSH_WEBHOOK_SECRET` as in `.env.demo`. Without it the database cannot wake `send-push`; the cron tick still queues rows.
2. **Auth > URL Configuration:** site URL and `SET_PASSWORD_URL` in the redirect list.
3. **Auth > SMTP Settings:** custom SMTP: host `smtp.resend.com`, port `465`, username `resend`, password = your Resend API key, sender = `MAIL_FROM_ADDRESS` (the default sender allows only a couple of mails per hour, which breaks invites and OTP emails during a rehearsal).
4. **Auth > Providers / Sign In:** email sign-ups off, anonymous sign-ins off, minimum password length 10 with lower, upper, digits and symbols (what `config.toml` says locally; the hosted project does not read it).
5. **Hub coordinates:** set by migration `20261122140000_hub_to_fwu_soe.sql` (FWU-SOE, Kanchanpur), so `supabase db push` is enough. To move the hub later, add a new migration that upserts `app_settings` key `central_inventory`.

## 6. Seed

```bash
node --env-file=.env scripts/reset_demo_remote.mjs
```

It wipes operational data, then runs `seed_demo.mjs` and `seed_extra.mjs`. It never deletes `audit_logs`. For a first run on an empty project you can run the two seed scripts directly instead (`cd scripts && npm run seed`).

Run the seed smoke checks in `docs/TEST-MATRIX.md` in the SQL Editor (77 districts, 5 demo users, 16 demo requests, all 10 assignment states, and so on).

## 7. Database checks (SQL Editor)

```sql
-- every scheduled job exists and is active (expect 5 rows)
select jobname, schedule, active from cron.job order by 1;
--   export-latest-audit-hash   0 */2 * * *
--   purge-auth-attempts        29 3 * * *
--   purge-email-otps           23 3 * * *
--   purge-push-outbox          17 3 * * *
--   push-escalations           * * * * *

-- the cron jobs actually ran (look after a minute; status should be 'succeeded')
select jobname, status, start_time, return_message
  from cron.job_run_details d join cron.job j using (jobid)
 order by start_time desc limit 10;

-- vault entries exist (names only)
select name from vault.secrets where name in ('push_function_url', 'push_secret');   -- 2 rows

-- audit chain
select * from verify_audit_chain();                                                  -- 0 rows
```

Then `scripts/check_function_privileges.sql`: query 1 must return zero rows. Keep the output of query 2 for the screenshots.

## 8. Run the tests

```bash
cd scripts
npm run test:matrix:fast      # about 30 s: RLS, roles, double accept, stock concurrency, document privacy, rate limit, Edge API roles
npm run test:matrix           # adds the 60 s timer and the push-escalation cron check, about 4 minutes
```

Then Postman: import `postman/sahayogi-edge-api.postman_collection.json` and `postman/demo.postman_environment.json`, set `base_url`, `anon_key`, `password`, run folders 0 to 4 in order. Do the by-hand rows listed in `docs/TEST-MATRIX.md` ("Not automated").

Record results in the H-column of `docs/TEST-MATRIX.md`. A failing row is a bug in Git: fix, push, rerun that row (`--only=<name>`).

Runs add `Matrix Test` requests, a `cloth` lot and a few Postman rows. Reset before a rehearsal (step 9). The tests change stock quantities, so the stock figures in the seed smoke checks only hold on a freshly reset project.

## 9. Reset between rehearsals

```bash
node --env-file=.env scripts/reset_demo_remote.mjs
```

Needs `ALLOW_DEMO_SEED=yes` and `CONFIRM_PROJECT_REF`. Check afterwards that the seed smoke checks match and that `select count(*) from audit_logs` did not drop.

## 10. Screenshots for the presentation

- Studio > Table Editor: `requests`, `assignments`, `inventory_lots`, `audit_logs`.
- Authentication > Policies (RLS on every table) and Storage > `volunteer-docs` (private).
- Output of `scripts/check_function_privileges.sql` query 2.
- `select * from cron.job` and the run history.
- The terminal output of `npm run test:matrix`.

## Known gaps after this run

- Real FCM delivery needs a Firebase project and a device or emulator with a registered token; the runner only proves the outbox row is created once.
- `public-api/tracking*` has no throttle on wrong ref or token guesses (needs a new `auth_attempts.kind`, so a migration).
- Requester notifications and pushes after a claim are not built; in-app polling is the fallback.