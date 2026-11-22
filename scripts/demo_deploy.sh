#!/usr/bin/env bash
# Pushes migrations, deploys every Edge Function and sets the function secrets on the HOSTED DEMO project.
# Does NOT seed (see docs/DEMO-SETUP.md step 6) and never touches a project other than the one named in CONFIRM_PROJECT_REF.
#
# Needs (root .env): SUPABASE_URL, CONFIRM_PROJECT_REF, SUPABASE_DB_PASSWORD
# Needs: supabase CLI logged in (supabase login), supabase/functions/.env.demo filled in.
# Windows: run from Git Bash or WSL.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -f .env ] || { echo "No .env in the repo root."; exit 1; }
set -a; . ./.env; set +a

REF="${CONFIRM_PROJECT_REF:-}"
[ -n "$REF" ] || { echo "Set CONFIRM_PROJECT_REF=<demo project ref> in .env."; exit 1; }
case "${SUPABASE_URL:-}" in
  "https://$REF.supabase.co") ;;
  *) echo "SUPABASE_URL (${SUPABASE_URL:-unset}) does not match CONFIRM_PROJECT_REF ($REF). Stopping."; exit 1 ;;
esac
[ -n "${SUPABASE_DB_PASSWORD:-}" ] || { echo "Set SUPABASE_DB_PASSWORD in .env (the database password chosen when the project was created)."; exit 1; }
[ -f supabase/functions/.env.demo ] || { echo "Create supabase/functions/.env.demo from supabase/functions/.env.demo.example first."; exit 1; }
for v in PUSH_WEBHOOK_SECRET OTP_PEPPER SET_PASSWORD_URL ALLOWED_ORIGIN; do
  grep -Eq "^$v=.+" supabase/functions/.env.demo || { echo "supabase/functions/.env.demo has no value for $v."; exit 1; }
done
if grep -Eq "^(OTP_DEV_LOG|PUSH_DRY_RUN)=" supabase/functions/.env.demo; then
  echo "OTP_DEV_LOG / PUSH_DRY_RUN must not be set on a hosted project. Remove them from supabase/functions/.env.demo."; exit 1
fi

echo "== Project $REF =="
read -r -p "Type the project ref again to continue: " again
[ "$again" = "$REF" ] || { echo "Mismatch, stopping."; exit 1; }

echo "== 1/4 link =="
supabase link --project-ref "$REF" --password "$SUPABASE_DB_PASSWORD"

echo "== 2/4 migrations + district seed =="
supabase db push --include-seed --password "$SUPABASE_DB_PASSWORD"

echo "== 3/4 secrets =="
supabase secrets set --env-file supabase/functions/.env.demo --project-ref "$REF"

echo "== 4/4 functions =="
FUNCS=$(find supabase/functions -mindepth 1 -maxdepth 1 -type d ! -name '_*' -exec basename {} \; | sort)
for f in $FUNCS; do
  echo "-- deploy $f"
  supabase functions deploy "$f" --project-ref "$REF"
done

cat <<NEXT

Done. Still manual (docs/DEMO-SETUP.md):
  - scripts/demo_vault_secrets.sql in the SQL Editor (push_function_url + push_secret)
  - Auth -> URL Configuration (site URL + redirect URL) and Auth -> SMTP Settings
  - seed, privilege check, test matrix
NEXT