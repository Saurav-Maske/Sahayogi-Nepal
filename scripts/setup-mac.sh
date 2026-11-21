#!/usr/bin/env bash
# Sahayogi Nepal - macOS setup. Installs missing tools with Homebrew, then sets up the project.
# Put this file in the repo's scripts/ folder (or the repo root), then run:
#   chmod +x setup-mac.sh && ./setup-mac.sh
set -e

# Find repo root
HERE="$(cd "$(dirname "$0")" && pwd)"
if [ -d "$HERE/apps/admin" ]; then ROOT="$HERE"; else ROOT="$HERE/.."; fi
cd "$ROOT"
[ -d apps/admin ] || { echo "Run this from inside the sahayogi-nepal repo."; exit 1; }

have(){ command -v "$1" >/dev/null 2>&1; }

# Homebrew
if ! have brew; then
  echo "-> Installing Homebrew"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  [ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
fi

have git      || brew install git
have node     || brew install node
have supabase || brew install supabase/tap/supabase
have flutter  || brew install --cask flutter
have docker   || { echo "-> Installing Docker Desktop"; brew install --cask docker; }

if ! docker info >/dev/null 2>&1; then
  echo "! Docker Desktop is installed but not running. Open it from Applications, wait until it says 'running', then re-run this script."
  open -a Docker 2>/dev/null || true
  exit 1
fi

echo "-> Admin web dependencies"
(cd apps/admin && npm install && { [ -f .env ] || cp .env.example .env; })

echo "-> Script dependencies"
(cd scripts && npm install)

echo "-> Flutter platforms + packages"
(cd apps/mobile && { [ -d android ] || flutter create --platforms=android,ios . --org np.sahayogi --project-name sahayogi_mobile; } && flutter pub get)

[ -f .env ] || cp .env.example .env
echo
echo "Done. Next:  supabase start && supabase db reset && node scripts/seed-demo-users.mjs"
echo "For iOS builds you also need Xcode from the App Store (then: sudo xcodebuild -license accept)."