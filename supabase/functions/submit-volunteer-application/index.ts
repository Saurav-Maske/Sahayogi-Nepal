import { corsHeaders, fail, ok } from "../_shared/cors.ts";
import { adminClient, clientIp, EMAIL_RE, NEPAL_PHONE_RE, readJson, recordAttempt, sha256, tooMany } from "../_shared/auth.ts";
import { claimToken, releaseToken } from "../_shared/otp.ts";
import { parseVolunteerTypes, primaryType } from "../_shared/volunteer_types.ts";

declare const Deno: {
  env: { get(name: string): string | undefined };
  serve(handler: (req: Request) => Response | Promise<Response>): void;
};

const BUCKET = "volunteer-docs";
const PATH_RE = /^docs\/[0-9a-f-]{36}\.(jpg|png|webp)$/;

async function objectExists(sb: ReturnType<typeof adminClient>, path: string) {
  const name = path.split("/")[1];
  const { data } = await sb.storage.from(BUCKET).list("docs", { search: name, limit: 5 });
  return !!data?.some((f) => f.name === name);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return fail("method_not_allowed", "POST only", 405);

  const b = await readJson(req);
  if (!b) return fail("bad_json", "Invalid JSON.");

  const full_name = String(b.full_name ?? "").trim();
  const email = String(b.email ?? "").trim().toLowerCase();
  const phone = String(b.phone ?? "").replace(/[\s-]/g, "");
  // `volunteer_types` is a list (a person can be driver AND doctor). The old single `volunteer_type` still works.
  const types = parseVolunteerTypes(b);
  const citizenship_no = String(b.citizenship_no ?? "").trim();
  const license_no = b.license_no ? String(b.license_no).trim() : null;
  const service_card_no = b.service_card_no ? String(b.service_card_no).trim() : null;

  if (full_name.length < 2 || full_name.length > 120) return fail("invalid_name", "Full name required (2-120 chars).");
  if (!EMAIL_RE.test(email) || email.length > 254) return fail("invalid_email", "A valid email is required.");
  if (!NEPAL_PHONE_RE.test(phone)) return fail("invalid_phone", "Enter a valid Nepal mobile number.");
  if (!types) return fail("invalid_type", "volunteer_types must be a list of manpower, driver and/or doctor.");
  const isDriver = types.includes("driver");
  const isDoctor = types.includes("doctor");
  if (citizenship_no.length < 4 || citizenship_no.length > 30) return fail("invalid_citizenship_no", "Citizenship number required.");
  const verifyToken = String(b.email_verification_token ?? "");
  if (!verifyToken) return fail("email_not_verified", "Verify your email with the 6-digit code first.", 403);
  if (isDriver && (!license_no || !b.license_photo_path)) return fail("license_required", "Drivers need licence number and photo.");
  if (isDoctor && (!service_card_no || !b.service_card_photo_path)) return fail("service_card_required", "Healthcare volunteers need service-card number and photo.");

  const paths: Record<string, string | null> = {
    citizenship_photo_path: String(b.citizenship_photo_path ?? ""),
    license_photo_path: isDriver ? String(b.license_photo_path) : null,
    service_card_photo_path: isDoctor ? String(b.service_card_photo_path) : null,
  };
  for (const p of Object.values(paths)) if (p !== null && !PATH_RE.test(p)) return fail("invalid_path", "Invalid document path.");

  const sb = adminClient();
  const ip = clientIp(req);
  const phoneHash = await sha256(phone);
  if (await tooMany(sb, { kind: "apply", identHash: phoneHash, ip, identMax: 3, ipMax: 500, windowMin: 1440 })) {
    return fail("too_many_attempts", "Too many applications. Try again later.", 429);
  }
  await recordAttempt(sb, "apply", phoneHash, ip, false);

  for (const p of Object.values(paths)) {
    if (p !== null && !(await objectExists(sb, p))) return fail("document_missing", "An uploaded document was not found. Upload again.");
  }

  const { data: existing } = await sb.from("profiles").select("id").eq("email", email).maybeSingle();
  if (existing) return fail("application_exists", "An application or account with this email already exists.", 409);

  // Spend the proof-of-email token only now, after every other check passed, so a typo does not burn it.
  if (!(await claimToken(sb, email, "signup", verifyToken))) {
    return fail("email_not_verified", "Your email verification is missing or expired. Verify your email again.", 403);
  }

  const { data, error } = await sb.from("volunteer_applications").insert({
    full_name, email, phone, volunteer_type: primaryType(types), volunteer_types: types, citizenship_no, email_verified_at: new Date().toISOString(),
    citizenship_photo_path: paths.citizenship_photo_path,
    license_no: isDriver ? license_no : null, license_photo_path: paths.license_photo_path,
    service_card_no: isDoctor ? service_card_no : null, service_card_photo_path: paths.service_card_photo_path,
  }).select("id, review_status").single();

  if (error) {
    await releaseToken(sb, email, "signup"); // the application was not saved, so the verification stays usable
    if (error.code === "23505") return fail("application_exists", "An application or account with this email already exists.", 409);
    console.error("application insert failed:", error.message);
    return fail("submit_failed", "Could not save your application.", 500);
  }
  return ok({ application_id: data.id, status: data.review_status }, 201);
});
