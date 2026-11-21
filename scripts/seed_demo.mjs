import { createClient } from '@supabase/supabase-js';
import { createHash, randomBytes } from 'node:crypto';

const { SUPABASE_URL, SERVICE_KEY } = process.env;
if (!SUPABASE_URL || !SERVICE_KEY) {
  console.error('Set SUPABASE_URL and SERVICE_KEY (service-role key) first.');
  process.exit(1);
}
const RESET = process.argv.includes('--reset');
const PASSWORD = process.env.DEMO_PASSWORD ?? 'ChangeMe-Demo-123!';
const sb = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });

const must = (res, what) => {
  if (res.error) { console.error(`FAILED: ${what}\n  ${res.error.message}`); process.exit(1); }
  return res.data;
};
const sha256 = (s) => createHash('sha256').update(s).digest('hex');
const hoursAgo = (h) => new Date(Date.now() - h * 3600_000).toISOString();

const { data: cfgRows, error: cfgErr } = await sb.from('app_settings').select('key,value');
if (cfgErr) { console.error('Cannot read app_settings. Are the migrations pushed?\n ', cfgErr.message); process.exit(1); }
const cfg = Object.fromEntries(cfgRows.map((r) => [r.key, r.value]));
if (!cfg.district || !cfg.central_inventory) {
  console.error('app_settings is missing "district" or "central_inventory". Apply supabase/seed.sql first.');
  process.exit(1);
}
const { south, west, north, east } = cfg.district.bounds;
const { lat: cLat, lng: cLng } = cfg.district.center;
const { data: dist } = await sb.from('districts').select('id').order('id').limit(1).single();
const districtId = dist?.id ?? null;

const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));
const pin = (dLat, dLng) => ({
  lat: +clamp(cLat + dLat, south + 0.001, north - 0.001).toFixed(5),
  lng: +clamp(cLng + dLng, west + 0.001, east - 0.001).toFixed(5),
});

if (RESET) {
  console.log('--reset: removing earlier demo rows');
  const { data: lots } = await sb.from('inventory_lots').select('id').like('provider_name', 'Demo%');
  const lotIds = (lots ?? []).map((l) => l.id);
  if (lotIds.length) {
    must(await sb.from('inventory_movements').delete().in('lot_id', lotIds), 'delete demo movements');
    must(await sb.from('inventory_lots').delete().in('id', lotIds), 'delete demo lots');
  }
  must(await sb.from('requests').delete().like('requester_name', 'Demo %'), 'delete demo requests');  
}

const users = [
  { email: 'admin@demo.test',   name: 'Demo Admin',    role: 'admin',     type: null,       cats: [],            phone: '9800000100' },
  { email: 'driver1@demo.test', name: 'Demo Driver 1', role: 'volunteer', type: 'driver',   cats: ['A', 'B'],    phone: '9800000101' },
  { email: 'driver2@demo.test', name: 'Demo Driver 2', role: 'volunteer', type: 'driver',   cats: ['A', 'B'],    phone: '9800000102' },
  { email: 'general@demo.test', name: 'Demo Helper',   role: 'volunteer', type: 'manpower', cats: ['A'],         phone: '9800000103' },
  { email: 'doctor@demo.test',  name: 'Demo Doctor',   role: 'volunteer', type: 'doctor',   cats: ['A', 'C'],    phone: '9800000104' },
];

async function findUserByEmail(email) {
  for (let page = 1; page <= 10; page++) {
    const { data, error } = await sb.auth.admin.listUsers({ page, perPage: 200 });
    if (error) throw error;
    const hit = data.users.find((u) => u.email?.toLowerCase() === email);
    if (hit) return hit;
    if (data.users.length < 200) break;
  }
  return null;
}

console.log('Users:');
for (const u of users) {
  let id;
  const { data, error } = await sb.auth.admin.createUser({ email: u.email, password: PASSWORD, email_confirm: true });
  if (error) {
    const existing = await findUserByEmail(u.email);
    if (!existing) { console.error(`  FAILED ${u.email}: ${error.message}`); process.exit(1); }
    id = existing.id;
    console.log(`  exists   ${u.email}`);
  } else {
    id = data.user.id;
    console.log(`  created  ${u.email}`);
  }
  must(await sb.from('profiles').upsert({
    id, full_name: u.name, email: u.email, phone: u.phone,
    role: u.role, volunteer_type: u.type, categories: u.cats, account_status: 'active',
  }), `upsert profile ${u.email}`);
}

const { count: lotCount } = await sb.from('inventory_lots').select('id', { count: 'exact', head: true }).like('provider_name', 'Demo%');
if (lotCount > 0) {
  console.log(`Inventory: ${lotCount} demo lots already there, skipped (use --reset to redo)`);
} else {
  const lots = [
    { item_type: 'drinking_water',  unit: 'litre', quantity: 1000, phase: 'ready_to_ship', provider_name: 'Demo Water Supplier', provider_contact: '9800000201', condition_note: 'sealed' },
    { item_type: 'food',            unit: 'pack',  quantity: 500,  phase: 'ready_to_ship', provider_name: 'Demo Food Donor',     provider_contact: '9800000202', condition_note: 'good' },
    { item_type: 'medical_supplies',unit: 'box',   quantity: 200,  phase: 'ready_to_ship', provider_name: 'Demo Pharma Supplier',provider_contact: '9800000203', condition_note: 'sealed' },
    { item_type: 'cloth',           unit: 'piece', quantity: 300,  phase: 'received',      provider_name: 'Demo Clothes Donor',  provider_contact: '9800000204', condition_note: 'sorted soon' },
    { item_type: 'temp_shelter',    unit: 'tent',  quantity: 40,   phase: 'processing',    provider_name: 'Demo Shelter Supplier',provider_contact: '9800000205', condition_note: 'new' },
  ];
  const inserted = must(await sb.from('inventory_lots').insert(lots).select('id, phase, quantity'), 'insert lots');
  must(await sb.from('inventory_movements').insert(inserted.map((l) => ({
    lot_id: l.id, from_phase: null, to_phase: l.phase, quantity: l.quantity, reason: 'demo seed',
  }))), 'insert movements');
  console.log(`Inventory: ${inserted.length} lots created`);
}

const { count: reqCount } = await sb.from('requests').select('id', { count: 'exact', head: true }).like('requester_name', 'Demo %');
if (reqCount > 0) {
  console.log(`Requests: ${reqCount} demo requests already there, skipped (use --reset to redo)`);
} else {
  const demo = [
    { key: 'pending resource', kind: 'resource_request', status: 'pending_admin_review', name: 'Demo Requester A', phone: '9800000001',
      at: pin(0.010, 0.012), urgency: 'high', notes: 'DEMO: flooded ward, water and food needed',
      items: [['drinking_water', 200, 'litre'], ['food', 50, 'pack']] },
    { key: 'pending donation', kind: 'donation_offer', status: 'pending_admin_review', name: 'Demo Donor B', phone: '9800000002',
      at: pin(-0.015, 0.008), urgency: 'normal', notes: 'DEMO: donating food packs',
      items: [['food', 20, 'pack']] },
    { key: 'pending manpower', kind: 'manpower_request', status: 'pending_admin_review', name: 'Demo Requester C', phone: '9800000003',
      at: pin(0.020, -0.010), urgency: 'critical', notes: 'DEMO: 3 volunteers to clear debris', volunteers_needed: 3, items: [] },

    { key: 'open manpower (approved)', kind: 'manpower_request', status: 'awaiting_assignment', name: 'Demo Requester D', phone: '9800000004',
      at: pin(-0.008, -0.015), urgency: 'high', notes: 'DEMO: 2 helpers, already approved', volunteers_needed: 2, items: [],
      approved_at: hoursAgo(0.1), assignments: 2 },
    { key: 'pickup 2h ago', kind: 'donation_offer', status: 'in_progress', name: 'Demo Donor E', phone: '9800000005',
      at: pin(0.004, 0.025), urgency: 'normal', notes: 'DEMO: picked up 2 h ago (shows on 6 h layer)',
      items: [['food', 30, 'pack', 30]], approved_at: hoursAgo(4), picked_up_at: hoursAgo(2) },
    { key: 'pickup 7h ago (hidden)', kind: 'donation_offer', status: 'in_progress', name: 'Demo Donor F', phone: '9800000006',
      at: pin(0.030, 0.020), urgency: 'low', notes: 'DEMO: picked up 7 h ago (must NOT show)',
      items: [['cloth', 40, 'piece', 40]], approved_at: hoursAgo(9), picked_up_at: hoursAgo(7) },
    { key: 'fulfilled 3h ago', kind: 'resource_request', status: 'fulfilled', name: 'Demo Requester G', phone: '9800000007',
      at: pin(-0.022, 0.004), urgency: 'high', notes: 'DEMO: delivered 3 h ago (shows on 12 h layer)',
      items: [['drinking_water', 100, 'litre', 100]], approved_at: hoursAgo(6), fulfilled_at: hoursAgo(3) },
    { key: 'fulfilled 13h ago (hidden)', kind: 'resource_request', status: 'fulfilled', name: 'Demo Requester H', phone: '9800000008',
      at: pin(0.016, -0.028), urgency: 'normal', notes: 'DEMO: delivered 13 h ago (must NOT show)',
      items: [['food', 60, 'pack', 60]], approved_at: hoursAgo(16), fulfilled_at: hoursAgo(13) },
  ];

  const tokens = [];
  console.log('Requests:');
  for (const d of demo) {
    const token = randomBytes(16).toString('hex');
    const row = must(await sb.from('requests').insert({
      kind: d.kind, status: d.status, requester_name: d.name, requester_phone: d.phone,
      district_id: districtId,
      location: `SRID=4326;POINT(${d.at.lng} ${d.at.lat})`,              // longitude first
      urgency: d.urgency, notes: d.notes, volunteers_needed: d.volunteers_needed ?? null,
      tracking_token_hash: sha256(token),
      approved_at: d.approved_at ?? null, picked_up_at: d.picked_up_at ?? null, fulfilled_at: d.fulfilled_at ?? null,
    }).select('id, public_ref').single(), `insert request "${d.key}"`);

    if (d.items.length) {
      must(await sb.from('request_items').insert(d.items.map(([item_type, qty, unit, done]) => ({
        request_id: row.id, item_type, unit, requested_qty: qty,
        approved_qty: d.status === 'pending_admin_review' ? null : qty,
        confirmed_qty: done ?? null,
      }))), `insert items "${d.key}"`);
    }

    if (d.assignments) {                                             
      must(await sb.from('assignments').insert(Array.from({ length: d.assignments }, () => ({
        request_id: row.id, assignment_type: 'manpower', required_tier: 'A',
        escalate_at: new Date(Date.now() + 60_000).toISOString(),
        route_snapshot: [{ label: 'requester', lat: d.at.lat, lng: d.at.lng }],
      }))), `insert assignments "${d.key}"`);
    }

    console.log(`  ${row.public_ref}  ${d.key}`);
    if (d.status === 'pending_admin_review') tokens.push({ ref: row.public_ref, token, kind: d.kind });
  }

  console.log('\nTracking tokens for the pending demo requests (for testing get_tracking later):');
  for (const t of tokens) console.log(`  ${t.ref}  ${t.kind.padEnd(17)}  ${t.token}`);
}

console.log(`\nDone. Demo logins: admin@demo.test, driver1@demo.test, driver2@demo.test, general@demo.test, doctor@demo.test`);
console.log(`Password: ${PASSWORD}   (demo project only: use a different one for the final demo)`);