import { corsHeaders, fail, ok } from "../_shared/cors.ts";
import { adminClient, sha256 } from "../_shared/auth.ts";
import { loadServiceAccount, sendFcm } from "../_shared/fcm.ts";

declare const Deno: {
  env: { get(name: string): string | undefined };
  serve(handler: (req: Request) => Response | Promise<Response>): void;
};

// Not called by apps. It is called by the database (pg_net, see migration 20261122000009) and by hand for tests,
// always with the shared secret in `x-push-secret`. It drains push_outbox:
//   push_claim_batch -> push_recipients -> FCM -> mark processed.
// Payloads carry IDs only. Never an OTP, name, phone or location.

type OutboxRow = { id: number; kind: "new_offer" | "escalated"; assignment_id: string; request_id: string; assignment_type: string; attempts: number };
type Recipient = { profile_id: string; token: string; platform: string };

const TITLES: Record<string, string> = {
  delivery: "Delivery needs a driver",
  pickup: "Donation pickup needs a driver",
  transport: "Transport needs a driver",
  healthcare: "Healthcare request needs a doctor",
  manpower: "Volunteers needed",
};

const BATCH = 50;
const CHUNK = 20; // parallel FCM calls
const BUDGET_MS = 20_000;

function messageFor(row: OutboxRow, assignmentId: string) {
  const escalated = row.kind === "escalated";
  return {
    title: TITLES[row.assignment_type] ?? "New request",
    body: escalated ? "Nobody has taken this yet. Open the app to claim it." : "A new request is open. Open the app to view and claim it.",
    data: { type: row.kind, assignment_id: assignmentId, request_id: row.request_id },
    collapseKey: row.request_id,
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return fail("method_not_allowed", "POST only", 405);

  const secret = Deno.env.get("PUSH_WEBHOOK_SECRET");
  if (!secret) return fail("misconfigured", "PUSH_WEBHOOK_SECRET is not set.", 500);
  const given = req.headers.get("x-push-secret") ?? "";
  if ((await sha256(given)) !== (await sha256(secret))) return fail("unauthorized", "Not allowed.", 401);

  const sa = loadServiceAccount();
  const dryRun = Deno.env.get("PUSH_DRY_RUN") === "true"; // LOCAL ONLY: log instead of sending, never set on the hosted project
  if (!sa && !dryRun) return fail("fcm_not_configured", "FCM_SERVICE_ACCOUNT is not set.", 503);

  const sb = adminClient();
  const totals = { claimed: 0, groups: 0, sent: 0, failed: 0, invalid_tokens_removed: 0, dry_run: dryRun && !sa };
  const started = Date.now();

  while (Date.now() - started < BUDGET_MS) {
    const { data, error } = await sb.rpc("push_claim_batch", { p_limit: BATCH });
    if (error) {
      console.error("push_claim_batch failed:", error.message);
      return fail("claim_failed", "Could not read the push queue.", 500);
    }
    const rows = (data ?? []) as OutboxRow[];
    if (!rows.length) break;
    totals.claimed += rows.length;

    // One push per volunteer per request and kind, however many assignments (manpower needs several).
    const groups = new Map<string, OutboxRow[]>();
    for (const r of rows) {
      const k = `${r.kind}:${r.request_id}`;
      groups.set(k, [...(groups.get(k) ?? []), r]);
    }

    for (const group of groups.values()) {
      totals.groups++;
      const ids = group.map((r) => r.id);
      const head = group[0];

      // First assignment in the group that still has someone to tell (others may have been claimed already).
      let recipients: Recipient[] = [];
      let useAssignment = head.assignment_id;
      let lookupError: string | null = null;
      for (const r of group) {
        const { data: rec, error: recErr } = await sb.rpc("push_recipients", { p_assignment: r.assignment_id, p_kind: r.kind });
        if (recErr) {
          lookupError = recErr.message;
          break;
        }
        if ((rec ?? []).length) {
          recipients = rec as Recipient[];
          useAssignment = r.assignment_id;
          break;
        }
      }

      if (lookupError) {
        console.error("push_recipients failed:", lookupError);
        await sb.from("push_outbox").update({ locked_at: null, last_error: "recipients_lookup_failed" }).in("id", ids);
        totals.failed += group.length;
        continue;
      }

      // Same phone can hold one token under two accounts only briefly; send each token once.
      const tokens = [...new Set(recipients.map((r) => r.token))];
      const msg = messageFor(head, useAssignment);

      let sent = 0;
      let retryable = 0;
      let lastError = "";
      const invalid: string[] = [];

      if (!tokens.length) {
        // Nobody to tell (claimed already, or no registered devices). Done.
      } else if (!sa) {
        console.log(`[push dry-run] ${head.kind} request=${head.request_id} recipients=${tokens.length}`);
        sent = tokens.length;
      } else {
        for (let i = 0; i < tokens.length; i += CHUNK) {
          const results = await Promise.all(tokens.slice(i, i + CHUNK).map((t) => sendFcm(sa, t, msg)));
          results.forEach((res, j) => {
            if (res.ok) sent++;
            else if (res.invalidToken) invalid.push(tokens[i + j]);
            else {
              lastError = res.error;
              if (res.retry) retryable++;
            }
          });
        }
      }

      if (invalid.length) {
        await sb.from("device_tokens").delete().in("token", invalid);
        totals.invalid_tokens_removed += invalid.length;
      }

      totals.sent += sent;
      const allFailedRetryable = tokens.length > 0 && sent === 0 && retryable > 0 && retryable + invalid.length === tokens.length;
      if (allFailedRetryable) {
        // Nothing got through: release the rows so the next kick (cron, every minute) tries again.
        console.error(`push group failed (${head.kind}, request ${head.request_id}): ${lastError}`);
        await sb.from("push_outbox").update({ locked_at: null, last_error: lastError.slice(0, 300) }).in("id", ids);
        totals.failed += tokens.length;
      } else {
        totals.failed += retryable;
        await sb.from("push_outbox").update({ processed_at: new Date().toISOString(), locked_at: null, last_error: retryable ? lastError.slice(0, 300) : null }).in("id", ids);
      }
    }

    if (rows.length < BATCH) break;
  }

  return ok(totals);
});