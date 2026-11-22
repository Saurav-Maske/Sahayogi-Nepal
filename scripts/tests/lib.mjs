// Plain-fetch helpers for the matrix runner. No dependencies beyond Node 20+.
// Everything goes through the same HTTP surface the apps use (Auth, PostgREST, Edge Functions, Storage),
// so the tests see exactly what a real role sees.
import { randomInt } from "node:crypto";

export const ENV = {
  url: (process.env.SUPABASE_URL ?? "").replace(/\/$/, ""),
  anon: process.env.SUPABASE_ANON_KEY ?? "",
  service: process.env.SUPABASE_SERVICE_ROLE_KEY ?? "",
  password: process.env.DEMO_PASSWORD ?? "ChangeMe-Demo-123!",
};

export function guard() {
  const miss = [];
  if (!ENV.url) miss.push("SUPABASE_URL");
  if (!ENV.anon || ENV.anon === "replace-me") miss.push("SUPABASE_ANON_KEY");
  if (!ENV.service || ENV.service === "replace-me") miss.push("SUPABASE_SERVICE_ROLE_KEY");
  if (miss.length) { console.error(`Set ${miss.join(", ")} in .env (run: node --env-file=.env scripts/tests/matrix.mjs)`); process.exit(1); }
  const local = /127\.0\.0\.1|localhost/.test(ENV.url);
  if (!local) {
    if (process.env.ALLOW_DEMO_SEED !== "yes") { console.error(`Refusing to run against remote project ${ENV.url}. Set ALLOW_DEMO_SEED=yes (demo project only).`); process.exit(1); }
    const ref = new URL(ENV.url).hostname.split(".")[0];
    if (process.env.CONFIRM_PROJECT_REF !== ref) { console.error(`Set CONFIRM_PROJECT_REF=${ref} to confirm "${ref}" is the demo project. The tests create requests, lots and uploads there.`); process.exit(1); }
  }
  return local;
}

async function call(method, path, { token, key, body, headers = {}, raw = false } = {}) {
  const h = { apikey: key ?? ENV.anon, ...headers };
  if (token) h.Authorization = `Bearer ${token}`;
  if (body !== undefined && !(body instanceof Uint8Array)) h["Content-Type"] = "application/json";
  const res = await fetch(`${ENV.url}${path}`, {
    method, headers: h,
    body: body === undefined ? undefined : body instanceof Uint8Array ? body : JSON.stringify(body),
  });
  if (raw) return res;
  const text = await res.text();
  let json = null;
  try { json = text ? JSON.parse(text) : null; } catch { /* not JSON */ }
  return { status: res.status, json, text };
}

// ---- sessions -------------------------------------------------------------------------------------------
export async function signIn(email) {
  const r = await call("POST", "/auth/v1/token?grant_type=password", { body: { email, password: ENV.password } });
  if (r.status !== 200 || !r.json?.access_token) throw new Error(`sign-in failed for ${email}: ${r.status} ${r.text.slice(0, 200)}`);
  return { email, token: r.json.access_token, id: r.json.user.id };
}

// ---- RPC ------------------------------------------------------------------------------------------------
// who: null (anon) | { token } | "service"
// Returns { ok, data, code } where code is the raised exception text ("forbidden", "already_claimed", ...)
// or the Postgres error code when the failure is not a raised code (e.g. 42501 permission denied).
export async function rpc(who, name, args = {}) {
  const asService = who === "service";
  const r = await call("POST", `/rest/v1/rpc/${name}`, {
    key: asService ? ENV.service : ENV.anon,
    token: asService ? ENV.service : who?.token,
    body: args,
  });
  if (r.status >= 200 && r.status < 300) return { ok: true, data: r.json, status: r.status };
  const msg = r.json?.message ?? "";
  const code = /^[a-z_]+$/.test(msg) ? msg : (r.json?.code ?? String(r.status));
  return { ok: false, code, message: msg, status: r.status };
}

// Table read through PostgREST (RLS applies). Returns { rows, denied }.
export async function readTable(who, table, query = "select=*&limit=50") {
  const asService = who === "service";
  const r = await call("GET", `/rest/v1/${table}?${query}`, {
    key: asService ? ENV.service : ENV.anon,
    token: asService ? ENV.service : who?.token,
  });
  if (r.status === 200 && Array.isArray(r.json)) return { rows: r.json, denied: false, status: r.status };
  return { rows: [], denied: true, status: r.status, message: r.json?.message ?? r.text.slice(0, 120) };
}

// ---- Edge Functions -------------------------------------------------------------------------------------
export async function edge(who, fn, action, body = {}) {
  const path = `/functions/v1/${fn}${action ? `/${action}` : ""}`;
  const r = await call("POST", path, { token: who?.token, body });
  return { status: r.status, data: r.json?.data ?? null, error: r.json?.error ?? null, json: r.json };
}

// ---- Storage --------------------------------------------------------------------------------------------
export const storage = {
  upload: (path, bytes, contentType = "image/png") =>
    call("POST", `/storage/v1/object/volunteer-docs/${path}`, { key: ENV.service, token: ENV.service, body: bytes, headers: { "Content-Type": contentType, "x-upsert": "true" } }),
  get: (who, path, mode = "authenticated") =>
    call("GET", `/storage/v1/object/${mode}/volunteer-docs/${path}`, { token: who === "service" ? ENV.service : who?.token, key: who === "service" ? ENV.service : ENV.anon, raw: true }),
  list: (who, prefix) =>
    call("POST", `/storage/v1/object/list/volunteer-docs`, { token: who?.token, body: { prefix, limit: 100 } }),
  remove: (path) =>
    call("DELETE", `/storage/v1/object/volunteer-docs/${path}`, { key: ENV.service, token: ENV.service }),
};

// ---- test data ------------------------------------------------------------------------------------------
// Each run uses fresh phone numbers (the submit limit is 5 per phone per hour).
export const freshPhone = () => `98${String(randomInt(0, 100_000_000)).padStart(8, "0")}`;
// Inside the Kathmandu pilot bounds (27.62..27.82, 85.22..85.44).
export const kathmandu = () => ({ lat: +(27.69 + Math.random() * 0.06).toFixed(5), lng: +(85.30 + Math.random() * 0.06).toFixed(5) });

export async function submit(kind, extra = {}, phone = freshPhone()) {
  const base = { kind, requester_name: "Matrix Test", requester_phone: phone, urgency: "normal", notes: "AUTOMATED TEST", ...kathmandu() };
  const r = await edge(null, "submit-request", "", { ...base, ...extra });
  return { ...r, phone };
}

export const sleep = (ms) => new Promise((res) => setTimeout(res, ms));
export const sum = (a) => a.reduce((x, y) => x + y, 0);