import { client, strongPassword, upsertAuthUser } from "./_util.mjs";

const email = (process.env.ADMIN_EMAIL || "").trim().toLowerCase();
const name = (process.env.ADMIN_NAME || "").trim();
if (!email || !name) { console.error("Set ADMIN_EMAIL and ADMIN_NAME"); process.exit(1); }

const sb = client();
const password = process.env.ADMIN_PASSWORD || strongPassword();
const id = await upsertAuthUser(sb, email, password);
const { error } = await sb.from("profiles").upsert({
  id, full_name: name, email, role: "admin", volunteer_type: null, categories: [], account_status: "active",
});
if (error) { console.error(error.message); process.exit(1); }
console.log(`Admin ready: ${email}\nPassword: ${password}`);