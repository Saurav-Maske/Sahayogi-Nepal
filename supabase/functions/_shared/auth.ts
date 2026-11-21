import { createClient } from "@supabase/supabase-js";

const URL_ = Deno.env.get("SUPABASE_URL")!;

declare const Deno: {
  env: { get(name: string): string | undefined };
  serve(handler: (req: Request) => Response | Promise<Response>): void;
};

export const adminClient = () =>
  createClient(URL_, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

export const anonClient = () =>
  createClient(URL_, Deno.env.get("SUPABASE_ANON_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false, flowType: "implicit" },
  });

export const EMAIL_RE = /^[^\s@]{1,64}@[^\s@]+\.[^\s@]{2,}$/;
export const NEPAL_PHONE_RE = /^(\+977)?9[6-8][0-9]{8}$/; // same rule as submit_request in the playbook

export async function sha256(s: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

export const clientIp = (req: Request) =>
  (req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim() || req.headers.get("cf-connecting-ip") || "unknown";

export async function readJson(req: Request): Promise<Record<string, any> | null> {
  try {
    const b = await req.json();
    return b && typeof b === "object" && !Array.isArray(b) ? b : null;
  } catch {
    return null;
  }
}

export const bearer = (req: Request) => (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "").trim();

export async function requireUser(req: Request) {
  const token = bearer(req);
  if (!token) return null;
  const { data, error } = await adminClient().auth.getUser(token);
  return error || !data.user ? null : { user: data.user, token };
}

export async function requireDriver(req: Request) {
  const u = await requireUser(req);
  if (!u) return null;
  const { data: p } = await adminClient().from("profiles")
    .select("id, role, account_status").eq("id", u.user.id).maybeSingle();
  return p && p.role.includes("B") && p.account_status === "active" ? { id: u.user.id } : null;
}

export async function requireDoctor(req: Request) {
  const u = await requireUser(req);
  if (!u) return null;
  const { data: p } = await adminClient().from("profiles")
    .select("id, role, account_status").eq("id", u.user.id).maybeSingle();
  return p && p.role.includes("C") && p.account_status === "active" ? { id: u.user.id } : null;
}

export async function requireAdmin(req: Request) {
  const u = await requireUser(req);
  if (!u) return null;
  const { data: p } = await adminClient().from("profiles")
    .select("id, role, account_status").eq("id", u.user.id).maybeSingle();
  return p && p.role === "admin" && p.account_status === "active" ? { id: u.user.id } : null;
}

export type ThrottleKind = "login" | "reset" | "apply" | "upload";

export async function tooMany(
  sb: ReturnType<typeof adminClient>,
  o: { kind: ThrottleKind; identHash?: string; ip: string; identMax: number; ipMax: number; windowMin: number; failuresOnly?: boolean },
): Promise<boolean> {
  const since = new Date(Date.now() - o.windowMin * 60_000).toISOString();
  const count = async (col: "identifier" | "ip", val: string) => {
    let q = sb.from("auth_attempts").select("id", { count: "exact", head: true })
      .eq("kind", o.kind).eq(col, val).gte("created_at", since);
    if (o.failuresOnly) q = q.eq("success", false);
    const { count: c } = await q;
    return c ?? 0;
  };
  if (o.identHash && (await count("identifier", o.identHash)) >= o.identMax) return true;
  if (o.ip !== "unknown" && (await count("ip", o.ip)) >= o.ipMax) return true;
  return false;
}

export const recordAttempt = (sb: ReturnType<typeof adminClient>, kind: ThrottleKind, identHash: string, ip: string, success = false) =>
  sb.from("auth_attempts").insert({ kind, identifier: identHash, ip, success });