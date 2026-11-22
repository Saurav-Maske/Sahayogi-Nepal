// Clears operational data on a REMOTE (hosted) Supabase project and reseeds demo data.
// Keeps: auth users, profiles, real volunteer_applications, districts, app_settings, audit_logs (append-only).
// Usage (from repo root):
//   ALLOW_DEMO_SEED=yes CONFIRM_PROJECT_REF=<ref> DEMO_PASSWORD='...' node --env-file=.env scripts/reset_demo_remote.mjs
import { createClient } from '@supabase/supabase-js';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const url = process.env.SUPABASE_URL, key = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!url || !key || key === 'replace-me') { console.error('Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY.'); process.exit(1); }
if (/127\.0\.0\.1|localhost/.test(url)) { console.error('That is a local URL. Use scripts/reset-demo.sh for local.'); process.exit(1); }
if (process.env.ALLOW_DEMO_SEED !== 'yes') { console.error('Set ALLOW_DEMO_SEED=yes.'); process.exit(1); }
const ref = new URL(url).hostname.split('.')[0];
if (process.env.CONFIRM_PROJECT_REF !== ref) {
  console.error(`This WIPES requests, items, assignments, incidents, lots and movements on project "${ref}".\nRe-run with CONFIRM_PROJECT_REF=${ref} if that is the demo project.`);
  process.exit(1);
}
if (!process.env.DEMO_PASSWORD) { console.error('Set DEMO_PASSWORD (needed by seed_demo.mjs).'); process.exit(1); }

const sb = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
const sha256 = (value) => createHash('sha256').update(value).digest('hex');
const demoAuthHashes = [
  sha256('driver1@demo.test'), sha256('driver2@demo.test'), sha256('general@demo.test'),
  sha256('9800000301'), sha256('203.0.113.14'),
];

// Child-first order. request_items, assignments, otp_challenges, assignment_events,
// volunteer_locations and inventory_reservations go away via ON DELETE CASCADE.
const order = ['incidents', 'inventory_reservations', 'inventory_movements', 'inventory_lots', 'requests'];
for (const t of order) {
  const { error } = await sb.from(t).delete().not('id', 'is', null);
  if (error) { console.error(`FAILED clearing ${t}: ${error.message}`); process.exit(1); }
  console.log(`cleared ${t}`);
}
// Demo-only rows in tables we otherwise keep (real applicants/devices/attempts are untouched).
const { data: demoApps, error: demoAppsError } = await sb.from('volunteer_applications')
  .select('citizenship_photo_path,license_photo_path,service_card_photo_path').like('email', '%@demo.test');
if (demoAppsError) { console.error(`FAILED loading demo application paths: ${demoAppsError.message}`); process.exit(1); }
const demoDocPaths = (demoApps ?? []).flatMap((a) => [a.citizenship_photo_path, a.license_photo_path, a.service_card_photo_path]).filter(Boolean);
if (demoDocPaths.length) {
  const { error } = await sb.storage.from('volunteer-docs').remove(demoDocPaths);
  if (error) { console.error(`FAILED clearing demo volunteer documents: ${error.message}`); process.exit(1); }
  console.log(`cleared ${demoDocPaths.length} demo volunteer documents`);
}
for (const [t, col, pat] of [['volunteer_applications', 'email', '%@demo.test'], ['device_tokens', 'token', 'demo-%']]) {
  const { error } = await sb.from(t).delete().like(col, pat);
  if (error) { console.error(`FAILED clearing demo ${t}: ${error.message}`); process.exit(1); }
  console.log(`cleared demo rows in ${t}`);
}
const { error: attemptsError } = await sb.from('auth_attempts').delete().in('identifier', demoAuthHashes);
if (attemptsError) { console.error(`FAILED clearing demo auth_attempts: ${attemptsError.message}`); process.exit(1); }
console.log('cleared demo rows in auth_attempts');

for (const script of ['./seed_demo.mjs', './seed_extra.mjs']) {
  const r = spawnSync(process.execPath, [fileURLToPath(new URL(script, import.meta.url))], { stdio: 'inherit', env: process.env });
  if (r.status !== 0) process.exit(r.status ?? 1);
}
