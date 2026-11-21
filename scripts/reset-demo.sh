#!/usr/bin/env bash
# Resets LOCAL db to migrations + seed, then recreates demo users, inventory and requests. Run before every rehearsal.
# Needs a root .env (see supabase/functions/.env.example) and: cd scripts && npm install
set -e; cd "$(dirname "$0")/.."
supabase db reset
node --env-file=.env scripts/seed_demo.mjs