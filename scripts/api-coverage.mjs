import { readFileSync, readdirSync, existsSync, mkdirSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const fnDir = join(root, "supabase", "functions");
const postmanDir = join(root, "postman");
const ROUTERS = ["admin-api", "volunteer-api", "public-api"];

const AUDIENCE = {
  "admin-api": "admin", "admin-login": "admin", "admin-set-account-status": "admin", "approve-volunteer": "admin",
  "volunteer-api": "mobile", "volunteer-login": "mobile", "submit-volunteer-application": "mobile", "create-upload-urls": "mobile",
  "send-signup-otp": "mobile", "verify-signup-otp": "mobile",
  "public-api": "public", "submit-request": "public",
  "auth-me": "shared", "get-route": "shared",
  "request-password-reset": "shared", "verify-reset-otp": "shared", "reset-password": "shared",
  "send-push": "internal",
};

function routerRoutes(fn) {
  const src = readFileSync(join(fnDir, fn, "index.ts"), "utf8");
  return [...src.matchAll(/^\s*"([a-z0-9/_-]+)":\s*\{\s*rpc:\s*"([a-z0-9_]+)"/gm)].map((m) => ({ action: m[1], rpc: m[2] }));
}

function endpoints() {
  const list = [];
  for (const fn of ROUTERS) for (const r of routerRoutes(fn)) list.push({ key: `${fn}/${r.action}`, fn, rpc: r.rpc });
  for (const d of readdirSync(fnDir, { withFileTypes: true })) {
    if (!d.isDirectory() || d.name === "_shared" || ROUTERS.includes(d.name)) continue;
    if (existsSync(join(fnDir, d.name, "index.ts"))) list.push({ key: d.name, fn: d.name, rpc: "" });
  }
  return list;
}

function collectionCalls() {
  const calls = [];
  const files = existsSync(postmanDir) ? readdirSync(postmanDir).filter((f) => f.endsWith(".postman_collection.json")) : [];
  for (const file of files) {
    const col = JSON.parse(readFileSync(join(postmanDir, file), "utf8"));
    const walk = (items) => items.forEach((it) => {
      if (it.item) return walk(it.item);
      const url = typeof it.request?.url === "string" ? it.request.url : it.request?.url?.raw ?? "";
      const m = url.match(/\/functions\/v1\/([A-Za-z0-9_/-]+)/);
      if (!m) return;
      const parts = m[1].split("/");
      const key = ROUTERS.includes(parts[0]) ? parts.join("/") : parts[0];
      const asserts = (it.event ?? []).some((e) => e.listen === "test" && e.script.exec.join("").includes("pm.test"));
      calls.push({ key, collection: file.replace(".postman_collection.json", ""), asserts });
    });
    walk(col.item);
  }
  return calls;
}

export function coverage() {
  const eps = endpoints();
  const calls = collectionCalls();
  const rows = eps.map((e) => {
    const hit = calls.filter((c) => c.key === e.key);
    return { ...e, audience: AUDIENCE[e.fn] ?? "other", requests: hit.length, asserted: hit.filter((c) => c.asserts).length,
             collections: [...new Set(hit.map((c) => c.collection))], covered: hit.length > 0 };
  });
  const known = new Set(eps.map((e) => e.key));
  const unknown = [...new Set(calls.filter((c) => !known.has(c.key)).map((c) => c.key))];
  return { rows, unknown };
}

export function toMarkdown({ rows, unknown }) {
  const by = (pred) => { const r = rows.filter(pred); return `${r.filter((x) => x.covered).length}/${r.length}`; };
  const out = [
    "## Endpoint coverage",
    "",
    `Edge function endpoints with at least one Postman request: **${by(() => true)}**`,
    `(admin ${by((r) => r.audience === "admin")}, mobile ${by((r) => r.audience === "mobile")}, public ${by((r) => r.audience === "public")}, shared ${by((r) => r.audience === "shared")}, internal ${by((r) => r.audience === "internal")})`,
    "",
    "| Endpoint | Used by | Requests | Collections | Status |",
    "| --- | --- | ---: | --- | --- |",
    ...rows.map((r) => `| \`${r.key}\` | ${r.audience} | ${r.requests} | ${r.collections.join(", ") || "-"} | ${r.covered ? "covered" : "**NOT COVERED**"} |`),
  ];
  if (unknown.length) out.push("", `Requests that point at no known endpoint: ${unknown.map((u) => `\`${u}\``).join(", ")}`);
  out.push("", "Coverage means a request exists, not that every branch of the endpoint is exercised. PostgREST table reads and direct RPC calls from the apps are not counted here.");
  return out.join("\n");
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  const cov = coverage();
  const md = toMarkdown(cov);
  const dir = join(root, "reports");
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, "api-coverage.md"), md + "\n");
  console.log(md);
  if (process.argv.includes("--strict") && (cov.rows.some((r) => !r.covered) || cov.unknown.length)) process.exit(1);
}