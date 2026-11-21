import { createClient } from "@supabase/supabase-js";
import { randomBytes } from "node:crypto";

export function client() {
  const url = process.env.SUPABASE_URL, key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key || key === "replace-me") { console.error("Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY (node --env-file=.env ...)"); process.exit(1); }
  const local = /127\.0\.0\.1|localhost/.test(url);
  if (!local && process.env.ALLOW_DEMO_SEED !== "yes") {
    console.error(`Refusing to touch remote project ${url}. Set ALLOW_DEMO_SEED=yes if that is really what you want.`); process.exit(1);
  }
  return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
}

export function strongPassword() {
  const b = randomBytes(12).toString("base64url").replace(/[-_]/g, "x");
  return `${b}Aa1!`;
}

export async function upsertAuthUser(sb, email, password) {
  const { data, error } = await sb.auth.admin.createUser({ email, password, email_confirm: true });
  if (!error) return data.user.id;
  if (!/already|registered|exists/i.test(error.message)) throw error;
  for (let page = 1; page < 20; page++) {
    const { data: list, error: e2 } = await sb.auth.admin.listUsers({ page, perPage: 200 });
    if (e2) throw e2;
    const u = list.users.find((x) => x.email?.toLowerCase() === email.toLowerCase());
    if (u) {
      const { error: e3 } = await sb.auth.admin.updateUserById(u.id, { password, email_confirm: true, ban_duration: "none" });
      if (e3) throw e3;
      return u.id;
    }
    if (list.users.length < 200) break;
  }
  throw new Error(`Could not find existing user ${email}`);
}