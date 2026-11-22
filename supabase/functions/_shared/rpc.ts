// Thin HTTP layer over the SQL RPCs. One function per audience (admin-api, volunteer-api, public-api); each one
// is a table of routes. A route names the RPC and the body fields it takes (the RPC parameter name without `p_`).
// The caller's own JWT is forwarded to Postgres, so auth.uid(), is_admin() and the function grants apply exactly
// as they do when the SDK calls the RPC directly. No service role is used here.
import { createClient } from "@supabase/supabase-js";
import { corsHeaders, fail, ok } from "./cors.ts";
import { anonClient, bearer, readJson, requireAdmin, requireUser } from "./auth.ts";

declare const Deno: {
  env: { get(name: string): string | undefined };
  serve(handler: (req: Request) => Response | Promise<Response>): void;
};

type FieldType = "uuid" | "text" | "int" | "num" | "bool" | "array";
export type Spec = Record<string, FieldType | `${FieldType}?`>; // trailing ? = optional (left out so the SQL default applies)
export type Route = { rpc: string; auth: "none" | "user" | "admin"; spec?: Spec };

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MAX_TEXT = 4096;

function check(t: FieldType, x: unknown): boolean {
  switch (t) {
    case "uuid": return typeof x === "string" && UUID_RE.test(x);
    case "text": return typeof x === "string" && x.length <= MAX_TEXT;
    case "int": return typeof x === "number" && Number.isInteger(x);
    case "num": return typeof x === "number" && Number.isFinite(x);
    case "bool": return typeof x === "boolean";
    case "array": return Array.isArray(x) && x.length <= 200;
  }
}

// Returns the RPC args (p_ prefixed) or an error message naming the bad field.
function buildArgs(spec: Spec, b: Record<string, any>): { args: Record<string, unknown> } | { problem: string } {
  const args: Record<string, unknown> = {};
  for (const [key, raw] of Object.entries(spec)) {
    const optional = raw.endsWith("?");
    const type = (optional ? raw.slice(0, -1) : raw) as FieldType;
    const val = b[key];
    if (val === undefined || val === null) {
      if (optional) continue;
      return { problem: `Field '${key}' is required.` };
    }
    if (!check(type, val)) return { problem: `Field '${key}' is not a valid ${type}.` };
    args[`p_${key}`] = val;
  }
  return { args };
}

// Codes the SQL raises that are not a plain 400.
const STATUS: Record<string, number> = {
  unauthorized: 401, forbidden: 403, not_found: 404,
  already_claimed: 409, already_on_request: 409, already_assigned: 409, already_reported: 409, not_available: 409,
  invalid_state: 409, invalid_transition: 409, otp_required: 409, otp_not_available: 409,
  lot_reserved: 409, insufficient_stock: 409, already_received: 409, not_received: 409,
  too_many_requests: 429, hub_not_configured: 500,
};

const MESSAGES: Record<string, string> = {
  unauthorized: "Sign in required.",
  forbidden: "You are not allowed to do this.",
  not_found: "Not found.",
  already_claimed: "Someone else already took this.",
  already_on_request: "You already have an assignment on this request.",
  not_available: "This is no longer available.",
  not_eligible: "You are not eligible for this assignment.",
  invalid_state: "This cannot be done in the current state.",
  invalid_transition: "That move is not allowed from the current state.",
  otp_required: "This step needs the OTP.",
  already_received: "This donation has already been counted at the hub.",
  not_received: "Count the donation at the hub before issuing the code.",
  invalid_items: "The items are not valid. List each item with a whole-number quantity.",
  otp_not_available: "No code can be issued right now.",
  too_many_requests: "Too many tries. Please wait and retry.",
  insufficient_stock: "Not enough stock to reserve.",
  invalid_quantity: "Quantity must be a whole number of kits.",
  invalid_type: "type must be pickup_refused or items_mismatch.",
  invalid_note: "Write a short note (2 to 500 characters).",
  hub_not_configured: "The central hub is not configured.",
};

// A Postgres `raise exception 'code'` arrives as error.message === 'code'. Anything else (permission denied,
// syntax, connection) is a server problem and is logged, not shown.
const CODE_RE = /^[a-z][a-z0-9_]{2,60}$/;

function mapError(rpc: string, e: { message?: string; details?: string | null }): Response {
  const code = e.message ?? "";
  if (!CODE_RE.test(code)) {
    console.error(`${rpc} failed:`, code, e.details ?? "");
    return fail("db_error", "Something went wrong.", 500);
  }
  const status = STATUS[code] ?? 400;
  const extra = code === "insufficient_stock" && e.details ? { details: e.details } : {};
  if (status >= 500) console.error(`${rpc} failed:`, code);
  return fail(code, MESSAGES[code] ?? "Request could not be completed.", status, extra);
}

function userClient(token: string) {
  return createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
}

// Path is /functions/v1/<name>/<action...>. Locally and hosted both keep <name> in the path.
function actionOf(req: Request, name: string): string {
  const seg = new URL(req.url).pathname.split("/").filter(Boolean);
  const i = seg.indexOf(name);
  return (i >= 0 ? seg.slice(i + 1) : seg).join("/");
}

export function serveApi(name: string, routes: Record<string, Route>) {
  Deno.serve(async (req) => {
    if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

    const action = actionOf(req, name);
    const route = routes[action];
    if (!route) return fail("unknown_action", `No such action. Try: ${Object.keys(routes).join(", ")}`, 404);

    const spec = route.spec ?? {};
    const takesBody = Object.keys(spec).length > 0;
    if (req.method !== "POST" && !(req.method === "GET" && !takesBody)) {
      return fail("method_not_allowed", takesBody ? "POST only" : "POST or GET", 405);
    }

    let body: Record<string, any> = {};
    if (takesBody) {
      const b = await readJson(req);
      if (!b) return fail("bad_json", "Invalid JSON.");
      body = b;
    }
    const built = buildArgs(spec, body);
    if ("problem" in built) return fail("invalid_input", built.problem);

    let sb;
    if (route.auth === "none") {
      sb = anonClient();
    } else {
      // No / invalid / expired token is always 401, so clients know to refresh or sign in again.
      // A valid user who is not an admin is 403.
      const user = await requireUser(req);
      if (!user) return fail("unauthenticated", "Sign in required.", 401);
      if (route.auth === "admin" && !(await requireAdmin(req))) return fail("forbidden", "Admin only.", 403);
      sb = userClient(bearer(req));
    }

    const { data, error } = await sb.rpc(route.rpc, built.args);
    if (error) return mapError(route.rpc, error);
    return ok(data);
  });
}