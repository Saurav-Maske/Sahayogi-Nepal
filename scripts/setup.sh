#!/usr/bin/env bash
set -e
cd "$(dirname "$0")/.."
MISSING=0
need(){ command -v "$1" >/dev/null 2>&1 || { echo "✗ missing: $1 — $2"; MISSING=1; }; }
need git "install git"; need node "install Node 20+"; need npm "comes with Node"
need docker "needed for local Supabase"; need supabase "https://supabase.com/docs/guides/cli"; need flutter "https://docs.flutter.dev/get-started/install"
[ "$MISSING" = 1 ] && { echo "Install the missing tools above, then re-run."; exit 1; }

echo "→ admin web deps"; (cd apps/admin && npm install && { [ -f .env ] || cp .env.example .env; })
echo "→ scripts deps";   (cd scripts && npm install)
echo "→ flutter platforms + deps"
(cd apps/mobile && { [ -d android ] || flutter create --platforms=android,ios . --org np.sahayogi --project-name sahayogi_mobile; } && flutter pub get)
[ -f .env ] || cp .env.example .env
echo "✓ Done. Next: supabase start && supabase db reset"