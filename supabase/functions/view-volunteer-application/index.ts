import { corsHeaders, fail, ok } from "../_shared/cors.ts";
import { adminClient, clientIp, readJson, recordAttempt, sha256, tooMany } from "../_shared/auth.ts";

declare const Deno: {
  env: { get(name: string): string | undefined };
  serve(handler: (req: Request) => Response | Promise<Response>): void;
};

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// POST { "application_id": "<uuid>" }  ->  { application_id, status, volunteer_type }
// Public endpoint: the id works like a secret link, and only non-personal fields are returned.
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return fail("method_not_allowed", "POST only", 405);

  const body = await readJson(req);
  const id = String(body?.application_id ?? "").trim().toLowerCase();
  if (!UUID_RE.test(id)) return fail("invalid_id", "A valid application id is required.");

  const sb = adminClient();
  const ip = clientIp(req);
  const idHash = await sha256(id);
  if (await tooMany(sb, { kind: "status_check", identHash: idHash, ip, identMax: 30, ipMax: 60, windowMin: 60 })) {
    return fail("too_many_attempts", "Too many lookups. Try again later.", 429);
  }
  await recordAttempt(sb, "status_check", idHash, ip, false);

  const { data, error } = await sb.from("volunteer_applications")
    .select("id, review_status, volunteer_type")
    .eq("id", id)
    .maybeSingle();

  if (error) {
    console.error("application status lookup failed:", error.message);
    return fail("lookup_failed", "Could not check the status. Try again.", 500);
  }
  if (!data) return fail("not_found", "No application found with that id.", 404);

  return ok({ application_id: data.id, status: data.review_status, volunteer_type: data.volunteer_type });
});