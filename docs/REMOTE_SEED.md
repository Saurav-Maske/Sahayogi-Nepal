# Seeding the hosted Supabase project

Run once per project (demo, then prod without the demo users).

```bash
supabase login
supabase link --project-ref <ref>

# 1. Schema + districts seed + settings (hub, district config)
supabase db push --include-seed

# 2. Fill .env (SUPABASE_URL=https://<ref>.supabase.co, SUPABASE_SERVICE_ROLE_KEY, DEMO_PASSWORD,
#    ALLOW_DEMO_SEED=yes, CONFIRM_PROJECT_REF=<ref>), then:
cd scripts && npm install && cd ..
node --env-file=.env scripts/seed_demo.mjs
node --env-file=.env scripts/seed_extra.mjs   # fills every other table

# 3. Rehearsal reset (wipes requests/items/assignments/incidents/lots/movements, then reseeds)
node --env-file=.env scripts/reset_demo_remote.mjs
```

Notes

- `--include-seed` runs `supabase/seeds/nepal_districts.sql` (~1 MB, idempotent upserts).
- `audit_logs` is never cleared (append-only triggers forbid it).
- Replace the placeholder `central_inventory` coordinates once the hub is confirme

# Seeding the hosted Supabase project

Run once per project (demo, then prod without the demo users).

```bash
supabase login
supabase link --project-ref <ref>

# 1. Schema + districts seed + settings (hub, district config)
supabase db push --include-seed

# 2. Fill .env (SUPABASE_URL=https://<ref>.supabase.co, SUPABASE_SERVICE_ROLE_KEY, DEMO_PASSWORD,
#    ALLOW_DEMO_SEED=yes, CONFIRM_PROJECT_REF=<ref>), then:
cd scripts && npm install && cd ..
node --env-file=.env scripts/seed_demo.mjs

# 3. Rehearsal reset (wipes requests/items/assignments/incidents/lots/movements, then reseeds)
node --env-file=.env scripts/reset_demo_remote.mjs
```

Notes

- `--include-seed` runs `supabase/seeds/nepal_districts.sql` (~1 MB, idempotent upserts).
- `audit_logs` is never cleared (append-only triggers forbid it).
- Replace the placeholder `central_inventory` coordinates once the hub is confirmed.
