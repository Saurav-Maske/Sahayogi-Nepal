import { corsHeaders, fail, ok } from "../_shared/cors.ts";
import { adminClient, clientIp, readJson, recordAttempt, sha256, tooMany } from "../_shared/auth.ts";

declare const Deno: {
  env: { get(name: string): string | undefined };
  serve(handler: (req: Request) => Response | Promise<Response>): void;
};

const BUCKET = "volunteer-docs";
const EXT: Record<string, string> = { "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp" };
const ALLOWED_KINDS: Record<string, string[]> = {
  manpower: ["citizenship"],
  driver: ["citizenship", "license"],
  doctor: ["citizenship", "service_card"],
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return fail("method_not_allowed", "POST only", 405);

  const b = await readJson(req);
  const allowed = ALLOWED_KINDS[String(b?.volunteer_type)];
  if (!allowed) return fail("invalid_type", "volunteer_type must be manpower, driver or doctor.");
  const files = Array.isArray(b?.files) ? b!.files : [];
  const kinds = files.map((f: any) => f?.kind);
  if (files.length < 1 || files.length > 3 || new Set(kinds).size !== kinds.length ||
      kinds.some((k: string) => !allowed.includes(k)) || !kinds.includes("citizenship") ||
      files.some((f: any) => !EXT[String(f?.content_type)])) {
    return fail("invalid_files", "Send one entry per document kind with content_type image/jpeg, image/png or image/webp.");
  }

  const sb = adminClient();
  const ip = clientIp(req);
  if (await tooMany(sb, { kind: "upload", identHash: await sha256(ip), ip, identMax: 10, ipMax: 10, windowMin: 60 })) {
    return fail("too_many_attempts", "Too many upload requests. Try again later.", 429);
  }
  await recordAttempt(sb, "upload", await sha256(ip), ip, false);

  const out = [];
  for (const f of files) {
    const path = `docs/${crypto.randomUUID()}.${EXT[f.content_type]}`;
    const { data, error } = await sb.storage.from(BUCKET).createSignedUploadUrl(path);
    if (error || !data) return fail("upload_url_failed", "Could not create an upload URL.", 500);
    out.push({ kind: f.kind, path: data.path, token: data.token, signed_url: data.signedUrl, content_type: f.content_type });
  }
  return ok({ uploads: out, max_bytes: 5 * 1024 * 1024 });
});