// Fills EVERY remaining table with demo rows so each admin/volunteer screen has something to show.
// Run AFTER seed_demo.mjs (it needs the demo users, lots and requests that script creates):
//   node --env-file=.env scripts/seed_extra.mjs
// Safe to re-run: each section checks for its own marker rows first.
import { createClient } from '@supabase/supabase-js';
import { createHash, randomBytes } from 'node:crypto';
import bcrypt from 'bcryptjs';

const URL_ = process.env.SUPABASE_URL;
const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.SERVICE_KEY;
if (!URL_ || !KEY || KEY === 'replace-me') { console.error('Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY.'); process.exit(1); }
if (!/127\.0\.0\.1|localhost/.test(URL_) && process.env.ALLOW_DEMO_SEED !== 'yes') {
  console.error(`Refusing to touch remote project ${URL_}. Set ALLOW_DEMO_SEED=yes.`); process.exit(1);
}
const sb = createClient(URL_, KEY, { auth: { persistSession: false, autoRefreshToken: false } });
const must = (res, what) => { if (res.error) { console.error(`FAILED: ${what}\n  ${res.error.message}`); process.exit(1); } return res.data; };
const sha256 = (s) => createHash('sha256').update(s).digest('hex');
const ago = (h) => new Date(Date.now() - h * 3600_000).toISOString();
const inMin = (m) => new Date(Date.now() + m * 60_000).toISOString();
const DEMO_OTP = '123456';

// ---- who / where -------------------------------------------------------------
const emails = ['admin@demo.test', 'driver1@demo.test', 'driver2@demo.test', 'general@demo.test', 'doctor@demo.test'];
const profs = must(await sb.from('profiles').select('id,email,full_name').in('email', emails), 'load demo profiles');
const P = Object.fromEntries(profs.map((p) => [p.email.split('@')[0], p.id]));
for (const k of ['admin', 'driver1', 'driver2', 'general', 'doctor']) {
  if (!P[k]) { console.error(`Demo user ${k}@demo.test missing. Run seed_demo.mjs first.`); process.exit(1); }
}
const { data: cfgRows } = await sb.from('app_settings').select('key,value');
const cfg = Object.fromEntries((cfgRows ?? []).map((r) => [r.key, r.value]));
const d = cfg.district ?? { center: { lat: 27.7172, lng: 85.324 }, bounds: { south: 27.62, west: 85.22, north: 27.82, east: 85.44 } };
const hub = cfg.central_inventory ?? { name: 'Central Inventory Hub', lat: 27.705, lng: 85.32 };
const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));
const pin = (a, b) => ({
  lat: +clamp(d.center.lat + a, d.bounds.south + 0.001, d.bounds.north - 0.001).toFixed(5),
  lng: +clamp(d.center.lng + b, d.bounds.west + 0.001, d.bounds.east - 0.001).toFixed(5),
});

// ---- 1. volunteer_applications (+ placeholder images in the private bucket) --------------------
const PNG = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==', 'base64');
const apps = [
  { who: 'driver1', type: 'driver',   status: 'approved', cit: '27-01-71-00101', lic: 'BA-01-0001234' },
  { who: 'driver2', type: 'driver',   status: 'approved', cit: '27-01-72-00102', lic: 'BA-01-0005678' },
  { who: 'general', type: 'manpower', status: 'approved', cit: '27-01-73-00103' },
  { who: 'doctor',  type: 'doctor',   status: 'approved', cit: '27-01-74-00104', card: 'NMC-12345' },
  { email: 'applicant.pending@demo.test', name: 'Demo Applicant Pending', phone: '9800000301', type: 'manpower', status: 'submitted', cit: '27-01-80-00201' },
  { email: 'applicant.review@demo.test',  name: 'Demo Applicant Review',  phone: '9800000302', type: 'driver',   status: 'under_review', cit: '27-01-81-00202', lic: 'BA-02-0009999' },
  { email: 'applicant.declined@demo.test',name: 'Demo Applicant Declined',phone: '9800000303', type: 'doctor',   status: 'declined', cit: '27-01-82-00203', card: 'NMC-00000', note: 'Service card image unreadable' },
];
const { count: appCount } = await sb.from('volunteer_applications').select('id', { count: 'exact', head: true }).like('email', '%@demo.test');
if (appCount > 0) console.log(`volunteer_applications: ${appCount} demo rows already there, skipped`);
else {
  const rows = [];
  for (const a of apps) {
    const email = a.email ?? `${a.who}@demo.test`;
    const slug = email.split('@')[0];
    const paths = { cit: `demo/${slug}/citizenship.png`, lic: a.lic ? `demo/${slug}/license.png` : null, card: a.card ? `demo/${slug}/service_card.png` : null };
    for (const p of Object.values(paths).filter(Boolean)) {
      const { error } = await sb.storage.from('volunteer-docs').upload(p, PNG, { contentType: 'image/png', upsert: true });
      if (error) console.warn(`  (storage upload ${p}: ${error.message})`);
    }
    const prof = a.who ? profs.find((p) => p.email === email) : null;
    rows.push({
      profile_id: prof?.id ?? null, full_name: a.name ?? prof?.full_name ?? slug, email, phone: a.phone ?? '9800000300',
      volunteer_type: a.type, citizenship_no: a.cit, citizenship_photo_path: paths.cit,
      license_no: a.lic ?? null, license_photo_path: paths.lic, service_card_no: a.card ?? null, service_card_photo_path: paths.card,
      review_status: a.status, review_note: a.note ?? null,
      reviewed_by: ['approved', 'declined'].includes(a.status) ? P.admin : null,
      reviewed_at: ['approved', 'declined'].includes(a.status) ? ago(30) : null,
    });
  }
  must(await sb.from('volunteer_applications').insert(rows), 'insert volunteer_applications');
  console.log(`volunteer_applications: ${rows.length} created (+ placeholder images in volunteer-docs)`);
}

// ---- 2. device_tokens ------------------------------------------------------------------------
must(await sb.from('device_tokens').upsert([
  { profile_id: P.driver1, token: 'demo-fcm-driver1-android', platform: 'android' },
  { profile_id: P.driver2, token: 'demo-fcm-driver2-ios',     platform: 'ios' },
  { profile_id: P.doctor,  token: 'demo-fcm-doctor-android',  platform: 'android' },
  { profile_id: P.admin,   token: 'demo-fcm-admin-web',       platform: 'web' },
], { onConflict: 'token' }), 'upsert device_tokens');
console.log('device_tokens: 4 upserted');

// ---- 3. auth_attempts ------------------------------------------------------------------------
const { count: attCount } = await sb.from('auth_attempts').select('id', { count: 'exact', head: true }).like('identifier', '%@demo.test');
if (attCount > 0) console.log(`auth_attempts: ${attCount} demo rows already there, skipped`);
else {
  must(await sb.from('auth_attempts').insert([
    { kind: 'login', identifier: 'driver1@demo.test', ip: '203.0.113.10', success: true },
    { kind: 'login', identifier: 'driver2@demo.test', ip: '203.0.113.11', success: false },
    { kind: 'login', identifier: 'driver2@demo.test', ip: '203.0.113.11', success: true },
    { kind: 'reset', identifier: 'general@demo.test', ip: '203.0.113.12', success: true },
    { kind: 'apply', identifier: 'applicant.pending@demo.test', ip: '203.0.113.13', success: true },
    { kind: 'upload', identifier: 'applicant.review@demo.test', ip: '203.0.113.14', success: true },
  ]), 'insert auth_attempts');
  console.log('auth_attempts: 6 created');
}

// ---- 4. requests, items, lots, reservations, assignments, events, OTPs, incidents, locations ----
const { count: marker } = await sb.from('requests').select('id', { count: 'exact', head: true }).eq('requester_name', 'Demo Requester I');
if (marker > 0) console.log('operations scenario: already seeded, skipped');
else {
  const byName = async (name) => must(await sb.from('requests').select('id').eq('requester_name', name).single(), `find ${name}`).id;
  const itemsOf = async (rid) => must(await sb.from('request_items').select('id,item_type,approved_qty').eq('request_id', rid), 'items');
  const mkReq = async (r) => {
    const row = must(await sb.from('requests').insert({
      kind: r.kind, status: r.status, requester_name: r.name, requester_phone: r.phone,
      location: `SRID=4326;POINT(${r.at.lng} ${r.at.lat})`, urgency: r.urgency ?? 'normal', notes: r.notes,
      volunteers_needed: r.needed ?? null, decline_reason: r.decline ?? null, tracking_token_hash: sha256(randomBytes(16).toString('hex')),
      approved_at: r.approved_at ?? null, picked_up_at: r.picked_up_at ?? null, fulfilled_at: r.fulfilled_at ?? null,
    }).select('id').single(), `insert request ${r.name}`);
    let items = [];
    if (r.items?.length) items = must(await sb.from('request_items').insert(r.items.map(([t, q, u, aq, cq]) => ({
      request_id: row.id, item_type: t, unit: u, requested_qty: q, approved_qty: aq ?? null, confirmed_qty: cq ?? null,
    }))).select('id,item_type'), `items ${r.name}`);
    return { id: row.id, items };
  };
  const mkLot = async (l, chain, request_id = null) => {
    const lot = must(await sb.from('inventory_lots').insert({
      item_type: l.item_type, unit: l.unit, quantity: l.quantity, reserved_qty: l.reserved ?? 0, phase: l.phase,
      provider_name: l.provider, provider_contact: l.contact ?? '9800000299', condition_note: l.note, source_request_id: l.source ?? null,
      created_by: P.admin,
    }).select('id').single(), `lot ${l.provider}`);
    let prev = null, t = chain.length * 2;
    must(await sb.from('inventory_movements').insert(chain.map((phase) => {
      const m = { lot_id: lot.id, from_phase: prev, to_phase: phase, quantity: l.quantity, reason: `demo: ${phase}`,
        actor_id: P.admin, request_id, created_at: ago(t) };
      prev = phase; t -= 2; return m;
    })), `movements ${l.provider}`);
    return lot.id;
  };
  const mkAsg = async (a) => must(await sb.from('assignments').insert({
    request_id: a.req, assignment_type: a.type, required_tier: a.tier, state: a.state, volunteer_id: a.vol ?? null,
    declined_by: a.declined ?? [], offered_at: ago(a.offeredH ?? 1), accepted_at: a.acceptedH != null ? ago(a.acceptedH) : null,
    completed_at: a.doneH != null ? ago(a.doneH) : null, route_snapshot: a.route ?? [], items_snapshot: a.snap ?? [],
  }).select('id').single(), `assignment ${a.type}/${a.state}`).id;
  const events = async (aid, list) => must(await sb.from('assignment_events').insert(list.map(([event_type, actor_id, payload, h]) => ({
    assignment_id: aid, event_type, actor_id, payload: payload ?? null, created_at: ago(h) }))), `events ${aid}`);
  const otp = async (aid, purpose, { consumed = false, attempts = 0 } = {}) => must(await sb.from('otp_challenges').insert({
    assignment_id: aid, purpose, code_hash: bcrypt.hashSync(DEMO_OTP, 10), attempts,
    expires_at: consumed ? ago(0.5) : inMin(15), consumed_at: consumed ? ago(1) : null,
  }), `otp ${purpose}`);
  const reserve = async (item, lot, qty, status) => must(await sb.from('inventory_reservations').insert({
    request_item_id: item, lot_id: lot, quantity: qty, status }), 'reservation');
  const hubPt = { label: 'central inventory', lat: hub.lat, lng: hub.lng };
  const drv = (lat, lng) => ({ label: 'driver', lat, lng });

  // S1: Donor E (existing, picked up 2h ago) -> pickup assignment picked_up + OTP used + received lot
  const reqE = await byName('Demo Donor E'); const E = pin(0.004, 0.025);
  const aE = await mkAsg({ req: reqE, type: 'pickup', tier: 'B', state: 'picked_up', vol: P.driver1, offeredH: 4, acceptedH: 3.8,
    route: [drv(hub.lat, hub.lng), { label: 'donor', ...E }, hubPt], snap: [{ item_type: 'food', qty: 30, unit: 'pack' }] });
  await events(aE, [['offered', null, null, 4], ['accepted', P.driver1, null, 3.8], ['en_route_to_pickup', P.driver1, null, 3.2],
    ['otp_verified', P.driver1, { purpose: 'pickup', quantity_changed: false }, 2], ['picked_up', P.driver1, { qty: 30 }, 2]]);
  await otp(aE, 'pickup', { consumed: true, attempts: 1 });
  await mkLot({ item_type: "food", unit: "pack", quantity: 30, phase: "received", provider: "Demo Food Donor E", note: "from pickup", source: reqE }, ["received"], reqE);

  // S2: Requester G (fulfilled 3h ago) -> delivery delivered + consumed lot + dispatched reservation
  const reqG = await byName('Demo Requester G'); const [itG] = await itemsOf(reqG); const G = pin(-0.022, 0.004);
  const aG = await mkAsg({ req: reqG, type: 'delivery', tier: 'B', state: 'delivered', vol: P.driver2, offeredH: 6, acceptedH: 5.5, doneH: 3,
    route: [drv(hub.lat, hub.lng), hubPt, { label: 'requester', ...G }], snap: [{ item_type: 'drinking_water', qty: 100, unit: 'litre' }] });
  await events(aG, [['offered', null, null, 6], ['accepted', P.driver2, null, 5.5], ['picked_up', P.driver2, null, 4.5],
    ['en_route_to_destination', P.driver2, null, 4.2], ['otp_verified', P.driver2, { purpose: 'delivery' }, 3], ['delivered', P.driver2, { requester_full: true }, 3]]);
  await otp(aG, 'delivery', { consumed: true, attempts: 1 });
  const lotG = await mkLot({ item_type: 'drinking_water', unit: 'litre', quantity: 100, reserved: 100, phase: 'consumed', provider: 'Demo Water Supplier (batch 2)', note: 'delivered' },
    ['received', 'processing', 'ready_to_ship', 'dispatched', 'consumed'], reqG);
  await reserve(itG.id, lotG, 100, 'dispatched');

  // S3: Requester H (fulfilled 13h ago) -> delivered + RESOLVED incident
  const reqH = await byName('Demo Requester H'); const H = pin(0.016, -0.028);
  const aH = await mkAsg({ req: reqH, type: 'delivery', tier: 'B', state: 'delivered', vol: P.driver1, offeredH: 17, acceptedH: 16.5, doneH: 13,
    route: [drv(hub.lat, hub.lng), hubPt, { label: 'requester', ...H }], snap: [{ item_type: 'food', qty: 60, unit: 'pack' }] });
  await events(aH, [['offered', null, null, 17], ['accepted', P.driver1, null, 16.5], ['delivered', P.driver1, null, 13], ['incident_opened', null, { type: 'short_delivery' }, 12.5], ['incident_resolved', P.admin, null, 10]]);
  await otp(aH, 'delivery', { consumed: true, attempts: 2 });
  must(await sb.from('incidents').insert({ assignment_id: aH, request_id: reqH, incident_type: 'short_delivery', status: 'resolved',
    reporter_note: 'Two packs missing from the box', reported_shortfall: { food: 2 }, resolution: 'Recount showed all 60 packs delivered; requester miscounted.',
    admin_notes: 'Called requester and driver. No action against volunteer.', created_at: ago(12.5) }), 'incident resolved');

  // S4: Requester I -> delivery en route, live location, ACTIVE unused delivery OTP, dispatched lot
  const I = pin(0.012, -0.020);
  const rI = await mkReq({ name: 'Demo Requester I', phone: '9800000009', kind: 'resource_request', status: 'in_progress', at: I, urgency: 'high',
    notes: 'DEMO: delivery on the way', items: [['drinking_water', 50, 'litre', 50, null]], approved_at: ago(2) });
  const aI = await mkAsg({ req: rI.id, type: 'delivery', tier: 'B', state: 'en_route_to_destination', vol: P.driver2, offeredH: 1.8, acceptedH: 1.5,
    route: [drv(hub.lat, hub.lng), hubPt, { label: 'requester', ...I }], snap: [{ item_type: 'drinking_water', qty: 50, unit: 'litre' }] });
  await events(aI, [['offered', null, null, 1.8], ['accepted', P.driver2, null, 1.5], ['picked_up', P.driver2, null, 1], ['en_route_to_destination', P.driver2, null, 0.9]]);
  await otp(aI, 'delivery');
  must(await sb.from('volunteer_locations').insert({ assignment_id: aI, lat: +((hub.lat + I.lat) / 2).toFixed(5), lng: +((hub.lng + I.lng) / 2).toFixed(5) }), 'volunteer_locations');
  const lotI = await mkLot({ item_type: 'drinking_water', unit: 'litre', quantity: 50, reserved: 50, phase: 'dispatched', provider: 'Demo Water Supplier (batch 3)', note: 'in transit' },
    ['received', 'processing', 'ready_to_ship', 'dispatched'], rI.id);
  await reserve(rI.items[0].id, lotI, 50, 'dispatched');

  // S5: Requester J -> DISPUTED delivery + OPEN incident
  const J = pin(-0.012, 0.022);
  const rJ = await mkReq({ name: 'Demo Requester J', phone: '9800000010', kind: 'resource_request', status: 'partially_fulfilled', at: J, urgency: 'critical',
    notes: 'DEMO: requester says food was short', items: [['food', 40, 'pack', 40, 25]], approved_at: ago(5), fulfilled_at: ago(1) });
  const aJ = await mkAsg({ req: rJ.id, type: 'delivery', tier: 'B', state: 'disputed', vol: P.driver1, offeredH: 5, acceptedH: 4.5, doneH: 1,
    route: [drv(hub.lat, hub.lng), hubPt, { label: 'requester', ...J }], snap: [{ item_type: 'food', qty: 40, unit: 'pack' }] });
  await events(aJ, [['offered', null, null, 5], ['accepted', P.driver1, null, 4.5], ['otp_verified', P.driver1, { purpose: 'delivery' }, 1], ['requester_reported_short', null, { food: 15 }, 1]]);
  await otp(aJ, 'delivery', { consumed: true, attempts: 1 });
  must(await sb.from('incidents').insert({ assignment_id: aJ, request_id: rJ.id, incident_type: 'short_delivery', status: 'open',
    reporter_note: 'Only 25 of 40 packs arrived', reported_shortfall: { food: 15 }, created_at: ago(1) }), 'incident open');
  const lotJ = await mkLot({ item_type: 'food', unit: 'pack', quantity: 40, reserved: 40, phase: 'dispatched', provider: 'Demo Food Donor (batch 2)', note: 'dispatched' },
    ['received', 'processing', 'ready_to_ship', 'dispatched'], rJ.id);
  await reserve(rJ.items[0].id, lotJ, 40, 'dispatched');

  // S6: healthcare request accepted by the doctor
  const K = pin(0.006, 0.006);
  const rK = await mkReq({ name: 'Demo Requester K', phone: '9800000011', kind: 'healthcare_request', status: 'assigned', at: K, urgency: 'critical', notes: 'DEMO: injured person, needs a doctor', approved_at: ago(0.5) });
  const aK = await mkAsg({ req: rK.id, type: 'healthcare', tier: 'C', state: 'accepted', vol: P.doctor, offeredH: 0.4, acceptedH: 0.3, route: [{ label: 'requester', ...K }] });
  await events(aK, [['offered', null, null, 0.4], ['accepted', P.doctor, null, 0.3]]);

  // S7: transport request: one expired offer + one open offer someone already declined
  const L = pin(0.025, 0.015);
  const rL = await mkReq({ name: 'Demo Requester L', phone: '9800000012', kind: 'transport_request', status: 'awaiting_assignment', at: L, notes: 'DEMO: needs a vehicle to move a family', approved_at: ago(1) });
  await mkAsg({ req: rL.id, type: 'transport', tier: 'B', state: 'expired', offeredH: 1, route: [{ label: 'requester', ...L }] });
  const aL = await mkAsg({ req: rL.id, type: 'transport', tier: 'B', state: 'offered', declined: [P.driver1], offeredH: 0.2, route: [{ label: 'requester', ...L }] });
  await events(aL, [['offered', null, null, 0.2], ['declined', P.driver1, null, 0.1]]);

  await mkAsg({ req: rL.id, type: 'transport', tier: 'B', state: 'declined', declined: [P.driver2], offeredH: 0.8, route: [{ label: 'requester', ...L }] });

  // S7b: donation pickup, driver is on the way (state en_route_to_pickup)
  const Q = pin(0.018, 0.030);
  const rQ = await mkReq({ name: 'Demo Donor Q', phone: '9800000016', kind: 'donation_offer', status: 'assigned', at: Q, notes: 'DEMO: driver heading to the donor',
    items: [['cloth', 25, 'piece', 25, null]], approved_at: ago(0.7) });
  const aQ = await mkAsg({ req: rQ.id, type: 'pickup', tier: 'B', state: 'en_route_to_pickup', vol: P.driver1, offeredH: 0.6, acceptedH: 0.5,
    route: [drv(hub.lat, hub.lng), { label: 'donor', ...Q }, hubPt], snap: [{ item_type: 'cloth', qty: 25, unit: 'piece' }] });
  await events(aQ, [['offered', null, null, 0.6], ['accepted', P.driver1, null, 0.5], ['en_route_to_pickup', P.driver1, null, 0.4]]);
  await otp(aQ, 'pickup');

  // S8: approved resource request awaiting a driver, ACTIVE reservation against the main water lot
  const N = pin(-0.028, -0.012);
  const rN = await mkReq({ name: 'Demo Requester N', phone: '9800000013', kind: 'resource_request', status: 'awaiting_assignment', at: N, urgency: 'high',
    notes: 'DEMO: approved, waiting for a driver', items: [['drinking_water', 80, 'litre', 80, null]], approved_at: ago(0.3) });
  const mainWater = must(await sb.from('inventory_lots').select('id,reserved_qty').eq('provider_name', 'Demo Water Supplier').single(), 'main water lot');
  must(await sb.from('inventory_lots').update({ reserved_qty: Number(mainWater.reserved_qty) + 80 }).eq('id', mainWater.id), 'reserve on main lot');
  await reserve(rN.items[0].id, mainWater.id, 80, 'active');
  await mkAsg({ req: rN.id, type: 'delivery', tier: 'B', state: 'offered', offeredH: 0.2,
    route: [drv(hub.lat, hub.lng), hubPt, { label: 'requester', ...N }], snap: [{ item_type: 'drinking_water', qty: 80, unit: 'litre' }] });

  // S9: cancelled request: RELEASED reservation + cancelled assignment.  S10: declined request.
  const O = pin(0.002, -0.030);
  const rO = await mkReq({ name: 'Demo Requester O', phone: '9800000014', kind: 'resource_request', status: 'cancelled', at: O, notes: 'DEMO: requester cancelled', items: [['cloth', 30, 'piece', 30, null]], approved_at: ago(8) });
  await reserve(rO.items[0].id, (await sb.from('inventory_lots').select('id').eq('provider_name', 'Demo Clothes Donor').single()).data.id, 30, 'released');
  await mkAsg({ req: rO.id, type: 'delivery', tier: 'B', state: 'cancelled', offeredH: 7, route: [] });
  await mkReq({ name: 'Demo Requester P', phone: '9800000015', kind: 'manpower_request', status: 'declined', at: pin(-0.030, 0.030), needed: 5,
    notes: 'DEMO: declined example', decline: 'Duplicate of an earlier request in the same ward' });

  // inventory: one lot each in 'adjusted' and 'returned'
  await mkLot({ item_type: 'food', unit: 'pack', quantity: 10, phase: 'adjusted', provider: 'Demo Count Correction', note: 'stock count correction' }, ['received', 'adjusted']);
  await mkLot({ item_type: 'medical_supplies', unit: 'box', quantity: 5, phase: 'returned', provider: 'Demo Returned Goods', note: 'returned unopened' }, ['received', 'ready_to_ship', 'dispatched', 'returned']);
  console.log('operations scenario: 8 new requests + assignments in all 10 states, events, OTPs, 2 incidents, reservations, extra lots created');
  console.log(`  Active delivery OTP (assignment for "Demo Requester I") is ${DEMO_OTP} (stored hashed).`);
}

// ---- 5. audit_logs (through the hash-chain function) + checkpoint ---------------------------------
const { count: auditCount } = await sb.from('audit_logs').select('id', { count: 'exact', head: true }).filter('detail->>demo', 'eq', 'true');
if (auditCount > 0) console.log(`audit_logs: ${auditCount} demo rows already there, skipped`);
else {
  const reqId = (await sb.from('requests').select('id').eq('requester_name', 'Demo Requester I').single()).data?.id ?? null;
  const entries = [
    ['volunteer.approve', P.admin, 'volunteer_application', null], ['request.submit', null, 'request', reqId], ['request.approve', P.admin, 'request', reqId],
    ['assignment.claim', P.driver2, 'assignment', null], ['inventory.move', P.admin, 'inventory_lot', null],
    ['otp.verify', P.driver2, 'assignment', null], ['incident.open', null, 'incident', null],
  ];
  for (const [action, actor, entity, id] of entries) {
    must(await sb.rpc('append_audit_log', { p_action: action, p_actor_id: actor, p_entity: entity, p_entity_id: id, p_detail: { demo: true } }), `audit ${action}`);
  }
  console.log(`audit_logs: ${entries.length} created via append_audit_log (hash chain intact)`);
}
const cp = await sb.rpc('fn_export_latest_audit_hash');
console.log(cp.error ? `audit_hash_checkpoints: skipped (${cp.error.message})` : `audit_hash_checkpoints: checkpoint #${cp.data} written`);
console.log('\nDone. districts and app_settings come from the migration/seed; everything else is filled.');