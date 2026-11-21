#!/usr/bin/env bash
# Resets LOCAL db to migrations + seed, then recreates demo users. Run before every rehearsal.
set -e; cd "$(dirname "$0")/.."
supabase db reset
node scripts/seed-demo-users.mjs
