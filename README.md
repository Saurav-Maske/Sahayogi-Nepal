# Sahayogi Nepal

Mobile coordination platform for community requests, donations, volunteers and emergency supplies.
**48-hour prototype scaffold** — not production-ready (see `docs/`).

## Monorepo layout
| Path | Owner | What |
|---|---|---|
| `supabase/` | Person 2 | Migrations, seed, RLS, Edge Functions (canonical API) |
| `apps/mobile/` | Person 1 | Flutter app: public forms, volunteer UI, map screen |
| `apps/admin/` | Person 3 | React + Vite admin web panel |
| `docs/`, `scripts/`, `.github/` | Person 4 | API contract copy, QA, seed/reset, CI, demo |

## Prerequisites
- Git, Node 20+, Docker Desktop (for local Supabase)
- Flutter 3.24+ (Dart 3.5+) — https://docs.flutter.dev/get-started/install
- Supabase CLI — https://supabase.com/docs/guides/cli
- Deno — optional locally (Supabase CLI serves functions)

## First-time setup (everyone)
```bash
./scripts/setup.sh                 # checks tools, installs deps, generates Flutter platforms
cp .env.example .env               # fill in values
supabase start                     # local Postgres/Auth/Storage/Studio
supabase db reset                  # applies migrations + seed.sql
node scripts/seed-demo-users.mjs   # fictional demo auth users
```
Run apps:
```bash
cd apps/admin && cp .env.example .env && npm run dev
cd apps/mobile && flutter run \
  --dart-define=SUPABASE_URL=http://10.0.2.2:54321 \
  --dart-define=SUPABASE_ANON_KEY=<anon key from `supabase status`>
supabase functions serve --env-file .env
```
(Android emulator reaches host via `10.0.2.2`; iOS simulator uses `127.0.0.1`.)

## Working independently
Read `CONTRIBUTING.md` and `docs/OWNERSHIP.md`. UIs can build against mock data until
`docs/API-CONTRACT.md` endpoints are live. **Schema changes only via migrations by Person 2.**
