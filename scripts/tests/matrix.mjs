// Automated run of the concurrency / RLS / role rows of docs/TEST-MATRIX.md, as real roles, over HTTP.
//
//   node --env-file=.env scripts/tests/matrix.mjs                 # everything (about 3 minutes, most of it the 60 s timer)
//   node --env-file=.env scripts/tests/matrix.mjs --skip=timer    # no 60 s / cron waiting
//   node --env-file=.env scripts/tests/matrix.mjs --only=Double   # rows whose name contains "Double"
//
// Needs the seeded demo users (scripts/seed_demo.mjs) and the service role key (setup, storage and the audit-chain check only;
// every assertion about access runs as anon, volunteer or admin). On a hosted project it refuses to run without
// ALLOW_DEMO_SEED=yes and CONFIRM_PROJECT_REF. It ADDS requests, one cloth lot and one storage object: reset with
// scripts/reset_demo_remote.mjs afterwards. audit_logs is append-only and keeps its rows.
import { writeFileSync } from "node:fs";
import { guard, ENV, signIn, rpc, readTable, edge, storage, submit, freshPhone, sleep, sum } from "./lib.mjs";

guard();
const args = process.argv.slice(2);
const only = args.find((a) => a.startsWith("--only="))?.slice(7).toLowerCase();
const skipTimer = args.includes("--skip=timer");

// ---- tiny runner ----------------------------------------------------------------------------------------
const results = [];
class Skip extends Error {}
const skip = (why) => { throw new Skip(why); };
const assert = (cond, msg) => { if (!cond) throw new Error(msg); };
const eq = (a, b, msg) => assert(a === b, `${msg} (got ${JSON.stringify(a)}, wanted ${JSON.stringify(b)})`);
async function test(row, fn) {
  if (only && !row.toLowerCase().includes(only)) return;
  const t0 = Date.now();
  try { await fn(); results.push({ row, status: "pass", ms: Date.now() - t0 }); console.log(`✅ ${row}`); }
  catch (e) {
    if (e instanceof Skip) { results.push({ row, status: "skip", note: e.message }); console.log(`⏳ ${row}  (skipped: ${e.message})`); }
    else { results.push({ row, status: "fail", note: e.message }); console.log(`❌ ${row}\n     ${e.message}`); }
  }
}

// ---- sessions and builders ------------------------------------------------------------------------------
console.log(`Target: ${ENV.url}\n`);
const admin = await signIn("admin@demo.test");
const d1 = await signIn("driver1@demo.test");       // A, B
const d2 = await signIn("driver2@demo.test");       // A, B
const general = await signIn("general@demo.test");  // A only
const doctor = await signIn("doctor@demo.test");    // A, C

const uuid0 = "00000000-0000-0000-0000-000000000000";
const ctx = {};

async function approved(kind, extra = {}) {
  const s = await submit(kind, extra);
  assert(s.status === 201, `submit ${kind} -> ${s.status} ${JSON.stringify(s.error)}`);
  const a = await rpc(admin, "admin_approve_request", { p_id: s.data.request_id });
  assert(a.ok, `approve ${kind} -> ${a.code}`);
  return s.data;
}
async function offered(kind, extra = {}) {
  const r = await approved(kind, extra);
  const c = await rpc(admin, "create_assignments", { p_id: r.request_id });
  assert(c.ok, `create_assignments ${kind} -> ${c.code}`);
  return { ...r, assignments: c.data.assignments };
}
const offerIds = async (who) => { const r = await rpc(who, "my_offers"); assert(r.ok, `my_offers -> ${r.code}`); return r.data; };

// =====================================================================================================
// RLS and role rows
// =====================================================================================================
const DENIED_TO_ANON = ["profiles", "volunteer_applications", "requests", "request_items", "inventory_lots", "inventory_movements",
  "inventory_reservations", "assignments", "assignment_events", "otp_challenges", "incidents", "volunteer_locations",
  "device_tokens", "audit_logs", "push_outbox", "email_otps", "auth_attempts"];
const ADMIN_ONLY_FOR_VOLUNTEER = ["requests", "request_items", "inventory_lots", "inventory_movements", "inventory_reservations",
  "assignment_events", "incidents", "audit_logs", "volunteer_applications", "volunteer_locations", "otp_challenges", "push_outbox", "email_otps", "auth_attempts"];

await test("Anonymous submit", async () => {
  const s = await submit("resource_request", { items: [{ item_type: "drinking_water", qty: 3, unit: "litre" }] });
  eq(s.status, 201, "submit status");
  eq(s.data.status, "pending_admin_review", "status");
  assert(s.data.tracking_token?.length >= 64, "tracking_token missing");
  for (const t of ["requests", "request_items", "assignments"]) {
    const r = await readTable(null, t);
    eq(r.rows.length, 0, `anon can read ${t}`);
  }
});

await test("RLS: anon reads nothing private", async () => {
  const pos = await readTable(admin, "requests", "select=id&limit=1");
  assert(pos.rows.length > 0, "positive control failed: admin sees no requests, so the zero checks below would prove nothing");
  const leaks = [];
  for (const t of DENIED_TO_ANON) { const r = await readTable(null, t); if (r.rows.length) leaks.push(`${t}(${r.rows.length})`); }
  assert(!leaks.length, `anon can read rows in: ${leaks.join(", ")}`);
  const d = await readTable(null, "districts", "select=id&limit=1");
  assert(d.rows.length === 1, "districts should be public");
});

await test("RLS: volunteer sees only own rows", async () => {
  const leaks = [];
  for (const t of ADMIN_ONLY_FOR_VOLUNTEER) { const r = await readTable(d1, t); if (r.rows.length) leaks.push(`${t}(${r.rows.length})`); }
  assert(!leaks.length, `volunteer can read rows in: ${leaks.join(", ")}`);
  const p = await readTable(d1, "profiles");
  assert(p.rows.length >= 1 && p.rows.every((x) => x.id === d1.id), "volunteer sees profiles other than their own");
  const a = await readTable(d1, "assignments");
  assert(a.rows.every((x) => x.volunteer_id === d1.id), "volunteer sees assignments that are not theirs");
  const t = await readTable(d1, "device_tokens");
  assert(t.rows.every((x) => x.profile_id === d1.id), "volunteer sees other people's device tokens");
});

await test("RLS: volunteer cannot write", async () => {
  const r1 = await fetch(`${ENV.url}/rest/v1/profiles?id=eq.${d1.id}`, { method: "PATCH", headers: { apikey: ENV.anon, Authorization: `Bearer ${d1.token}`, "Content-Type": "application/json", Prefer: "return=representation" }, body: JSON.stringify({ role: "admin", categories: ["A", "B", "C"] }) });
  const j = await r1.json().catch(() => null);
  assert(!(r1.status === 200 && Array.isArray(j) && j.length), `volunteer could update own profile: ${JSON.stringify(j)}`);
  const me = await readTable(d1, "profiles", `select=role,categories&id=eq.${d1.id}`);
  eq(me.rows[0]?.role, "volunteer", "profile role changed");
  const ins = await fetch(`${ENV.url}/rest/v1/requests`, { method: "POST", headers: { apikey: ENV.anon, Authorization: `Bearer ${d1.token}`, "Content-Type": "application/json" }, body: JSON.stringify({ kind: "manpower_request", requester_name: "x", requester_phone: "9800000000" }) });
  assert(ins.status >= 400, `volunteer inserted into requests directly (${ins.status})`);
  const insA = await fetch(`${ENV.url}/rest/v1/requests`, { method: "POST", headers: { apikey: ENV.anon, "Content-Type": "application/json" }, body: JSON.stringify({ kind: "manpower_request", requester_name: "x", requester_phone: "9800000000" }) });
  assert(insA.status >= 400, `anon inserted into requests directly (${insA.status})`);
});

await test("Settings exposure", async () => {
  for (const [name, who] of [["anon", null], ["volunteer", d1]]) {
    const r = await readTable(who, "app_settings", "select=key");
    const keys = r.rows.map((x) => x.key);
    assert(!keys.includes("central_inventory"), `${name} can read central_inventory`);
    assert(keys.every((k) => k === "district"), `${name} can read settings other than district: ${keys}`);
  }
  const a = await readTable(admin, "app_settings", "select=key");
  assert(a.rows.some((x) => x.key === "central_inventory"), "admin cannot read central_inventory (positive control)");
});

await test("Admin-only RPCs", async () => {
  const calls = [
    ["admin_list_requests", {}], ["admin_approve_request", { p_id: uuid0 }], ["admin_decline_request", { p_id: uuid0, p_reason: "test" }],
    ["admin_dashboard_counts", {}], ["create_assignments", { p_id: uuid0 }], ["admin_map_markers", {}],
    ["admin_import_stock", { p_items: [{ item_type: "food", qty: 1 }] }], ["admin_move_lot", { p_id: uuid0, p_phase: "processing" }],
    ["admin_list_incidents", {}], ["admin_resolve_incident", { p_id: uuid0, p_status: "resolved" }], ["admin_list_audit", {}],
  ];
  const ok = await rpc(admin, "admin_dashboard_counts");
  assert(ok.ok, `positive control: admin_dashboard_counts failed (${ok.code})`);
  const bad = [];
  for (const [name, a] of calls) for (const [who, w] of [["anon", null], ["driver", d1], ["helper", general]]) {
    const r = await rpc(w, name, a);
    if (r.ok) bad.push(`${name} as ${who} SUCCEEDED`);
    else if (!["forbidden", "unauthorized", "42501"].includes(r.code)) bad.push(`${name} as ${who} -> ${r.code} (wanted forbidden/unauthorized/42501)`);
  }
  assert(!bad.length, bad.join("; "));
});

await test("Function privileges", async () => {
  const bad = [];
  const mustDeny = [["submit_request", { p: {} }], ["push_claim_batch", { p_limit: 1 }], ["push_recipients", { p_assignment: uuid0, p_kind: "new_offer" }],
    ["purge_email_otps", {}], ["purge_auth_attempts", {}], ["revoke_user_sessions", { p_user_id: uuid0 }], ["verify_audit_chain", {}], ["fn_export_latest_audit_hash", {}]];
  for (const [name, a] of mustDeny) for (const [who, w] of [["anon", null], ["volunteer", d1], ["admin", admin]]) {
    const r = await rpc(w, name, a);
    if (r.ok || r.code !== "42501") bad.push(`${name} as ${who}: ${r.ok ? "ALLOWED" : r.code} (wanted 42501)`);
  }
  const m = await rpc(null, "map_markers"); if (!m.ok) bad.push(`anon map_markers failed: ${m.code}`);
  const g = await rpc(null, "get_tracking", { p_ref: "ZZZZZZZZ", p_token: "x" }); if (g.ok || g.code !== "not_found") bad.push(`anon get_tracking bad token -> ${g.ok ? "ok" : g.code} (wanted not_found)`);
  const ia = await rpc(null, "is_admin"); if (!ia.ok || ia.data !== false) bad.push(`anon is_admin -> ${JSON.stringify(ia.data ?? ia.code)} (wanted false)`);
  const sv = await rpc("service", "verify_audit_chain"); if (!sv.ok) bad.push(`service_role cannot call verify_audit_chain: ${sv.code}`);
  assert(!bad.length, bad.join("; "));
});

// =====================================================================================================
// Concurrency rows
// =====================================================================================================
await test("Double accept", async () => {
  const rounds = 6, report = [];
  for (let i = 0; i < rounds; i++) {
    const r = await offered("transport_request", { volunteers_needed: 1 });         // tier B: driver1 and driver2 both eligible
    const id = r.assignments[0].id;
    // rounds alternate between the RPC and the Edge API so both paths are covered
    const results2 = i % 2 === 0
      ? await Promise.all([rpc(d1, "claim_assignment", { p_id: id }), rpc(d2, "claim_assignment", { p_id: id })])
      : (await Promise.all([edge(d1, "volunteer-api", "assignments/claim", { id }), edge(d2, "volunteer-api", "assignments/claim", { id })]))
          .map((x) => ({ ok: x.status === 200, code: x.error?.code, status: x.status }));
    const wins = results2.filter((x) => x.ok).length;
    const losers = results2.filter((x) => !x.ok);
    if (wins !== 1) report.push(`round ${i}: ${wins} winners`);
    else if (!losers.every((x) => ["already_claimed", "not_available"].includes(x.code) && (x.status === undefined || x.status === 409 || x.status === 400))) report.push(`round ${i}: loser got ${losers.map((x) => x.code)}`);
    const rows = await readTable(admin, "assignments", `select=id,volunteer_id,state&id=eq.${id}`);
    if (rows.rows[0]?.state !== "accepted" || ![d1.id, d2.id].includes(rows.rows[0]?.volunteer_id)) report.push(`round ${i}: row is ${JSON.stringify(rows.rows[0])}`);
  }
  assert(!report.length, report.join("; "));
});

await test("Stock concurrency", async () => {
  const imp = await rpc(admin, "admin_import_stock", { p_items: [{ item_type: "cloth", qty: 100, unit: "piece", phase: "ready_to_ship", provider_name: "Matrix Test Supplier" }] });
  assert(imp.ok, `import stock -> ${imp.code}`);
  const lots = async () => (await readTable(admin, "inventory_lots", "select=id,quantity,reserved_qty&item_type=eq.cloth&phase=eq.ready_to_ship")).rows;
  const before = await lots();
  const avail = sum(before.map((l) => Number(l.quantity) - Number(l.reserved_qty)));
  const q = Math.ceil(avail * 0.4);
  const expected = Math.min(4, Math.floor(avail / q));
  const reqs = [];
  for (let i = 0; i < 4; i++) {
    const s = await submit("resource_request", { items: [{ item_type: "cloth", qty: q, unit: "piece" }] });
    assert(s.status === 201, `submit -> ${s.status} ${JSON.stringify(s.error)}`);
    reqs.push(s.data.request_id);
  }
  const out = await Promise.all(reqs.map((id) => rpc(admin, "admin_approve_request", { p_id: id })));
  const wins = out.filter((x) => x.ok).length;
  const odd = out.filter((x) => !x.ok && x.code !== "insufficient_stock").map((x) => x.code);
  const after = await lots();
  const reservedDelta = sum(after.map((l) => Number(l.reserved_qty))) - sum(before.map((l) => Number(l.reserved_qty)));
  const over = after.filter((l) => Number(l.reserved_qty) > Number(l.quantity) || Number(l.reserved_qty) < 0);
  assert(!odd.length, `unexpected errors under contention: ${odd} (deadlock or lock timeout?)`);
  assert(!over.length, `lot reserved above quantity or below 0: ${JSON.stringify(over)}`);
  eq(wins, expected, `parallel approvals that fit (available ${avail}, each wants ${q})`);
  eq(reservedDelta, expected * q, "reserved quantity change must equal exactly what the winners asked for (losers must roll back fully)");
});

await test("Audit chain", async () => {
  const r = await rpc("service", "verify_audit_chain");
  assert(r.ok, `verify_audit_chain -> ${r.code}`);
  eq((r.data ?? []).length, 0, `broken audit rows after the concurrency tests: ${JSON.stringify(r.data)}`);
});

// =====================================================================================================
// Eligibility, 60 s timer, push escalation
// =====================================================================================================
await test("Volunteer eligibility", async () => {
  const tierB = await offered("transport_request", { volunteers_needed: 1 });
  const tierC = await offered("healthcare_request", { volunteers_needed: 1 });
  const idB = tierB.assignments[0].id, idC = tierC.assignments[0].id;
  const has = async (w, id) => (await offerIds(w)).some((o) => o.id === id);
  eq(await has(d1, idB), true, "A+B driver should see tier B");
  eq(await has(general, idB), false, "A-only helper must not see tier B");
  eq(await has(doctor, idB), false, "A+C doctor must not see tier B");
  eq(await has(doctor, idC), true, "A+C doctor should see tier C");
  eq(await has(d1, idC), false, "A+B driver must not see tier C");
  const bad = await rpc(general, "claim_assignment", { p_id: idB });
  eq(bad.code, "not_eligible", "helper claiming tier B");
  const o = (await offerIds(d1)).find((x) => x.id === idB);
  assert(o && !("requester_name" in o) && !("requester_phone" in o), "offer leaks requester contact before claim");
});

await test("60 s escalation", async () => {
  if (skipTimer) skip("--skip=timer");
  const r = await offered("manpower_request", { volunteers_needed: 2 });          // tier A, exactly-{A} for 60 s
  const [s1, s2] = r.assignments.map((a) => a.id);
  ctx.escal = { slots: [s1, s2], reqId: r.request_id };
  const g0 = await offerIds(general), d0 = await offerIds(d1), c0 = await offerIds(doctor);
  eq(g0.some((o) => o.id === s1), true, "exactly-{A} helper should see the offer at once");
  eq(d0.some((o) => o.id === s1) || c0.some((o) => o.id === s1), false, "A+B / A+C must not see it in the first 60 s");
  const early = await edge(d1, "volunteer-api", "assignments/claim", { id: s1 });
  assert(early.status === 400 && early.error?.code === "not_eligible", `early claim by driver -> ${early.status} ${early.error?.code} (wanted 400 not_eligible)`);
  const esc = new Date(g0.find((o) => o.id === s1).escalate_at).getTime();
  ctx.escal.at = esc;
  const wait = esc - Date.now() + 2000;
  if (wait > 0) { console.log(`   waiting ${Math.ceil(wait / 1000)} s for escalate_at ...`); await sleep(wait); }
  assert((await offerIds(d1)).some((o) => o.id === s1), "driver should see the offer after escalate_at");
  assert((await offerIds(doctor)).some((o) => o.id === s1), "doctor should see the offer after escalate_at");
  // slot 1 is claimed by whoever wins; slot 2 stays open so the escalation push row can be checked
  const race = await Promise.all([rpc(d1, "claim_assignment", { p_id: s1 }), rpc(doctor, "claim_assignment", { p_id: s1 })]);
  eq(race.filter((x) => x.ok).length, 1, "winners of the post-escalation race");
});

await test("Push: escalation", async () => {
  if (skipTimer) skip("--skip=timer");
  if (!ctx.escal) skip("60 s escalation did not run");
  const slot = ctx.escal.slots[1];
  const deadline = Date.now() + 120_000;
  let rows = [];
  while (Date.now() < deadline) {
    const r = await readTable("service", "push_outbox", `select=id,kind,processed_at,last_error&assignment_id=eq.${slot}&kind=eq.escalated`);
    rows = r.rows;
    if (rows.length) break;
    await sleep(5000);
  }
  assert(rows.length > 0, "no 'escalated' row in push_outbox within 120 s of escalate_at: is the push-escalations cron job scheduled (select * from cron.job)?");
  eq(rows.length, 1, "escalated rows for one assignment (the unique index should allow exactly one)");
  // a second look a minute later must not add another row
  await sleep(65_000);
  const again = await readTable("service", "push_outbox", `select=id&assignment_id=eq.${slot}&kind=eq.escalated`);
  eq(again.rows.length, 1, "escalated rows after another cron tick");
  console.log(`   outbox row processed_at=${rows[0].processed_at ?? "null (no FCM configured or nobody to tell)"} last_error=${rows[0].last_error ?? "null"}`);
});

// =====================================================================================================
// Delivery OTP, wrong driver, skip OTP, tracking privacy, short-delivery
// =====================================================================================================
await test("Delivery OTP, wrong driver, skip OTP", async () => {
  const r = await offered("resource_request", { items: [{ item_type: "drinking_water", qty: 2, unit: "litre" }] });
  const id = r.assignments[0].id;
  eq((await rpc(d1, "claim_assignment", { p_id: id })).ok, true, "claim");
  for (const st of ["en_route_to_pickup", "picked_up", "en_route_to_destination"]) {
    const u = await rpc(d1, "update_assignment_state", { p_id: id, p_state: st });
    assert(u.ok, `state ${st} -> ${u.code}`);
  }
  eq((await rpc(d1, "update_assignment_state", { p_id: id, p_state: "delivered" })).code, "otp_required", "skipping the OTP");
  const other = await rpc(d2, "update_assignment_state", { p_id: id, p_state: "delivered" });
  assert(!other.ok, "another driver moved someone else's assignment");

  const issue = async () => { const o = await rpc(null, "requester_get_otp", { p_ref: r.public_ref, p_token: r.tracking_token, p_purpose: "delivery" }); assert(o.ok, `requester_get_otp -> ${o.code}`); return o.data.code; };
  const code1 = await issue();
  const wrongDriver = await rpc(d2, "driver_verify_otp", { p_id: id, p_purpose: "delivery", p_code: code1 });
  eq(wrongDriver.code, "not_found", "another driver verifying the OTP");
  const wrong = code1 === "000000" ? "111111" : "000000";
  const reasons = [];
  for (let i = 0; i < 5; i++) { const v = await rpc(d1, "driver_verify_otp", { p_id: id, p_purpose: "delivery", p_code: wrong }); reasons.push(v.data?.reason ?? v.code); }
  eq(reasons.slice(0, 4).every((x) => x === "invalid_otp"), true, `first four wrong codes: ${reasons}`);
  eq(reasons[4], "otp_locked", "fifth wrong code");
  const afterLock = await rpc(d1, "driver_verify_otp", { p_id: id, p_purpose: "delivery", p_code: code1 });
  eq(afterLock.data?.reason, "otp_locked", "right code after lock");
  const code2 = await issue();
  const stale = await rpc(d1, "driver_verify_otp", { p_id: id, p_purpose: "delivery", p_code: code1 === code2 ? wrong : code1 });
  assert(stale.data?.ok !== true, "old code accepted after re-issue");
  const code3 = await issue();                                                  // the stale attempt may have used attempts of code2; issue a clean one
  const good = await rpc(d1, "driver_verify_otp", { p_id: id, p_purpose: "delivery", p_code: code3 });
  eq(good.data?.ok, true, `correct code -> ${JSON.stringify(good.data ?? good.code)}`);
  const replay = await rpc(d1, "driver_verify_otp", { p_id: id, p_purpose: "delivery", p_code: code3 });
  assert(replay.data?.ok !== true, "OTP accepted twice");
  const done = await rpc(null, "requester_confirm_delivery", { p_ref: r.public_ref, p_token: r.tracking_token, p_full: true });
  assert(done.ok, `requester_confirm_delivery -> ${done.code}`);
  ctx.delivered = r;
});

await test("Tracking privacy", async () => {
  const r = ctx.delivered ?? skip("delivery flow did not run");
  const t = await rpc(null, "get_tracking", { p_ref: r.public_ref, p_token: r.tracking_token });
  assert(t.ok, `get_tracking -> ${t.code}`);
  const text = JSON.stringify(t.data);
  assert(!/"phone"|requester_phone|"last_name"/i.test(text), "tracking response has a phone or last-name field");
  assert(!/9[6-8]\d{8}/.test(text), "tracking response contains a phone number");
  eq((await rpc(null, "get_tracking", { p_ref: r.public_ref, p_token: r.tracking_token + "x" })).code, "not_found", "wrong token");
  eq((await rpc(null, "get_tracking", { p_ref: "ZZZZZZZZ", p_token: r.tracking_token })).code, "not_found", "wrong ref");
});

await test("Admin approval", async () => {
  const s = await submit("resource_request", { items: [{ item_type: "temp_shelter", qty: 900000, unit: "tent" }] });
  eq(s.status, 201, "submit");
  eq((await rpc(admin, "admin_approve_request", { p_id: s.data.request_id })).code, "insufficient_stock", "approving more than the stock");
  const after = await readTable(admin, "requests", `select=status&id=eq.${s.data.request_id}`);
  eq(after.rows[0]?.status, "pending_admin_review", "request must stay pending after a failed approval");
  const items = await readTable(admin, "request_items", `select=id,requested_qty&request_id=eq.${s.data.request_id}`);
  const over = await rpc(admin, "admin_approve_request", { p_id: s.data.request_id, p_items: [{ item_id: items.rows[0].id, approved_qty: 900001 }] });
  eq(over.code, "invalid_items", "approving more than requested");
});

// =====================================================================================================
// Edge API as real roles
// =====================================================================================================
await test("Edge API roles", async () => {
  const bad = [];
  const expect = (label, got, want) => { if (got !== want) bad.push(`${label}: ${got} (wanted ${want})`); };
  expect("admin-api no token", (await edge(null, "admin-api", "dashboard")).status, 401);
  expect("volunteer-api no token", (await edge(null, "volunteer-api", "offers")).status, 401);
  expect("admin-api as volunteer", (await edge(d1, "admin-api", "dashboard")).status, 403);
  const adminOnVol = (await edge(admin, "volunteer-api", "offers")).status;
  if (![401, 403].includes(adminOnVol)) bad.push(`volunteer-api as admin: ${adminOnVol} (wanted 401 or 403)`);
  expect("admin-api as admin", (await edge(admin, "admin-api", "dashboard")).status, 200);
  expect("volunteer-api as driver", (await edge(d1, "volunteer-api", "offers")).status, 200);
  expect("public-api map, no token", (await edge(null, "public-api", "map")).status, 200);
  const mal = await edge(d1, "volunteer-api", "assignments/claim", { id: "not-a-uuid" });
  expect("malformed uuid", mal.status, 400); expect("malformed uuid code", mal.error?.code, "invalid_input");
  const trk = await edge(null, "public-api", "tracking", { ref: "ZZZZZZZZ", token: "nope" });
  expect("wrong tracking token", trk.status, 404);
  const tb = await offered("transport_request", { volunteers_needed: 1 });
  const nel = await edge(general, "volunteer-api", "assignments/claim", { id: tb.assignments[0].id });
  expect("helper claims tier B", nel.status, 400); expect("helper claims tier B code", nel.error?.code, "not_eligible");
  const unk = await edge(admin, "admin-api", "no-such-action");
  if (![400, 404].includes(unk.status)) bad.push(`unknown action: ${unk.status} (wanted 400 or 404)`);
  assert(!bad.length, bad.join("; "));
});

// =====================================================================================================
// Storage and submit limits
// =====================================================================================================
await test("Document privacy", async () => {
  const png = Uint8Array.from(Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==", "base64"));
  const path = `matrix-test/${Date.now()}.png`;
  const up = await storage.upload(path, png);
  assert(up.status === 200, `service-role upload failed: ${up.status} ${up.text.slice(0, 120)}`);
  try {
    const bad = [];
    const check = async (label, res, wantOk) => { const okc = res.status === 200; if (okc !== wantOk) bad.push(`${label}: ${res.status}`); };
    await check("anon authenticated-URL", await storage.get(null, path), false);
    await check("anon public-URL (bucket must be private)", await storage.get(null, path, "public"), false);
    await check("volunteer authenticated-URL", await storage.get(d1, path), false);
    await check("volunteer public-URL", await storage.get(d1, path, "public"), false);
    await check("admin authenticated-URL (positive control)", await storage.get(admin, path), true);
    const lv = await storage.list(d1, "matrix-test"); if ((lv.json ?? []).length) bad.push(`volunteer can list ${lv.json.length} objects`);
    const la = await storage.list(null, "matrix-test"); if (Array.isArray(la.json) && la.json.length) bad.push(`anon can list ${la.json.length} objects`);
    const ld = await storage.list(admin, "matrix-test"); if (!(ld.json ?? []).length) bad.push("admin cannot list (positive control)");
    assert(!bad.length, bad.join("; "));
  } finally { await storage.remove(path); }
});

await test("Submit rate limit", async () => {
  const phone = freshPhone(), bad = [];
  const one = (p = phone) => submit("manpower_request", { volunteers_needed: 1 }, p);
  for (let i = 0; i < 5; i++) { const r = await one(); if (r.status !== 201) bad.push(`submission ${i + 1}: ${r.status} ${r.error?.code}`); }
  const sixth = await one(); if (sixth.status !== 429 || sixth.error?.code !== "too_many_requests") bad.push(`6th: ${sixth.status} ${sixth.error?.code} (wanted 429 too_many_requests)`);
  const intl = await one(`+977${phone}`); if (intl.status !== 429) bad.push(`+977 form of the same phone: ${intl.status} (wanted 429)`);
  const fresh = await one(freshPhone()); if (fresh.status !== 201) bad.push(`different phone: ${fresh.status}`);
  const outside = await submit("manpower_request", { volunteers_needed: 1, lat: 28.4, lng: 85.3 }); if (outside.status !== 400 || outside.error?.code !== "outside_service_area") bad.push(`outside pilot bounds: ${outside.status} ${outside.error?.code}`);
  const badPhone = await submit("manpower_request", { volunteers_needed: 1 }, "12345"); if (badPhone.status !== 400 || badPhone.error?.code !== "invalid_phone") bad.push(`bad phone: ${badPhone.status} ${badPhone.error?.code}`);
  assert(!bad.length, bad.join("; "));
});

await test("Audit chain (final)", async () => {
  const r = await rpc("service", "verify_audit_chain");
  assert(r.ok, `verify_audit_chain -> ${r.code}`);
  eq((r.data ?? []).length, 0, `broken audit rows at the end of the run: ${JSON.stringify(r.data)}`);
});

// ---- report ---------------------------------------------------------------------------------------------
const icon = { pass: "✅", fail: "❌", skip: "⏳" };
console.log("\n| Test | Result |\n| --- | --- |");
for (const r of results) console.log(`| ${r.row} | ${icon[r.status]}${r.note ? " " + r.note.replace(/\|/g, "/").slice(0, 140) : ""} |`);
const failed = results.filter((r) => r.status === "fail").length;
console.log(`\n${results.filter((r) => r.status === "pass").length} passed, ${failed} failed, ${results.filter((r) => r.status === "skip").length} skipped`);
writeFileSync(new URL("./last-run.json", import.meta.url), JSON.stringify({ at: new Date().toISOString(), target: ENV.url, results }, null, 2));
process.exit(failed ? 1 : 0);