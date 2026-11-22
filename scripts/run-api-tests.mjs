import newman from "newman";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { coverage, toMarkdown } from "./api-coverage.mjs";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const postman = join(root, "postman");
const ALL = ["sahayogi-edge-api", "sahayogi-flows"];

const arg = process.argv.slice(2).find((a) => a.startsWith("--collections="));
const names = arg ? arg.slice(14).split(",").filter(Boolean) : ALL;
const bad = names.filter((n) => !ALL.includes(n));
if (bad.length) { console.error(`Unknown collection ${bad.join(", ")}. Choose from: ${ALL.join(", ")}`); process.exit(1); }

const url = (process.env.SUPABASE_URL ?? "").replace(/\/$/, "");
const anon = process.env.SUPABASE_ANON_KEY ?? "";
const password = process.env.DEMO_PASSWORD ?? "";
const missing = [["SUPABASE_URL", url], ["SUPABASE_ANON_KEY", anon], ["DEMO_PASSWORD", password]].filter(([, v]) => !v || v === "replace-me").map(([k]) => k);
if (missing.length) { console.error(`Set ${missing.join(", ")} in .env (run: npm run test:api inside scripts/)`); process.exit(1); }

const host = new URL(url).hostname;
if (!/127\.0\.0\.1|localhost/.test(host)) {
  if (process.env.ALLOW_DEMO_SEED !== "yes") { console.error(`Refusing to run against remote project ${host}. Set ALLOW_DEMO_SEED=yes (demo project only).`); process.exit(1); }
  if (process.env.CONFIRM_PROJECT_REF !== host.split(".")[0]) { console.error(`Set CONFIRM_PROJECT_REF=${host.split(".")[0]} to confirm this is the demo project. The flows add requests and stock there.`); process.exit(1); }
}

const stamp = new Date().toISOString().replace(/[:.]/g, "-");
const out = join(root, "reports", stamp);
mkdirSync(out, { recursive: true });
console.log(`Target: ${host}\nReports: ${out}\n`);

const run = (name) => new Promise((res, rej) => newman.run({
  collection: join(postman, `${name}.postman_collection.json`),
  environment: join(postman, "demo.postman_environment.json"),
  envVar: [{ key: "base_url", value: url }, { key: "anon_key", value: anon }, { key: "password", value: password }],
  reporters: ["cli", "htmlextra", "junit", "json"],
  reporter: {
    htmlextra: { export: join(out, `${name}.html`), title: `Sahayogi Nepal - ${name}` },
    junit: { export: join(out, `${name}.xml`) },
    json: { export: join(out, `${name}.json`) },
  },
  delayRequest: 100,
  timeoutRequest: 30000,
}, (err, summary) => (err ? rej(err) : res(summary))));

const results = [];
for (const name of names) {
  const s = await run(name);
  const st = s.run.stats;
  results.push({
    name,
    requests: st.requests.total, requestsFailed: st.requests.failed,
    asserts: st.assertions.total, assertsFailed: st.assertions.failed,
    seconds: ((s.run.timings.completed - s.run.timings.started) / 1000).toFixed(1),
    failures: s.run.failures.map((f) => `${f.source?.name ?? "?"}: ${f.error?.test ?? f.error?.name ?? "error"} - ${String(f.error?.message ?? "").split("\n")[0]}`),
  });
}

const failed = results.reduce((n, r) => n + r.assertsFailed + r.requestsFailed, 0);
const md = [
  "# Sahayogi Nepal backend API test report",
  "",
  `Run: ${new Date().toISOString()}  `,
  `Target: ${host}  `,
  `Result: **${failed ? "FAILED" : "PASSED"}**`,
  "",
  "| Collection | Requests | Request errors | Assertions | Failed assertions | Seconds |",
  "| --- | ---: | ---: | ---: | ---: | ---: |",
  ...results.map((r) => `| ${r.name} | ${r.requests} | ${r.requestsFailed} | ${r.asserts} | ${r.assertsFailed} | ${r.seconds} |`),
  "",
  ...results.flatMap((r) => (r.failures.length ? [`### Failures in ${r.name}`, "", ...r.failures.map((f) => `- ${f}`), ""] : [])),
  toMarkdown(coverage()),
  "",
  "Detail per request is in the .html files next to this report; the .xml files are JUnit for CI.",
].join("\n");
writeFileSync(join(out, "summary.md"), md + "\n");
console.log(`\nSummary: ${join(out, "summary.md")}`);
process.exit(failed ? 1 : 0);