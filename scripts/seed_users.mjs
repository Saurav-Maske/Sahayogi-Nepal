import { client, strongPassword, upsertAuthUser } from "./_util.mjs";

const sb = client();
const password = process.env.DEMO_PASSWORD || strongPassword();

const users = [
  { email: "admin@demo.test",   name: "Demo Admin",    role: "admin",     type: null,       cats: [],            phone: "9800000000" },
  { email: "driver1@demo.test", name: "Demo Driver 1", role: "volunteer", type: "driver",   cats: ["A", "B"],    phone: "9800000001" },
  { email: "driver2@demo.test", name: "Demo Driver 2", role: "volunteer", type: "driver",   cats: ["A", "B"],    phone: "9800000002" },
  { email: "general@demo.test", name: "Demo Helper",   role: "volunteer", type: "manpower", cats: ["A"],         phone: "9800000003" },
  { email: "doctor@demo.test",  name: "Demo Doctor",   role: "volunteer", type: "doctor",   cats: ["A", "C"],    phone: "9800000004" },
];

for (const u of users) {
  try {
    const id = await upsertAuthUser(sb, u.email, password);
    const { error } = await sb.from("profiles").upsert({
      id, full_name: u.name, email: u.email, phone: u.phone, role: u.role,
      volunteer_type: u.type, categories: u.cats, account_status: "active",
    });
    if (error) throw error;
    console.log(`ok  ${u.role.padEnd(9)} ${u.email}`);
  } catch (e) {
    console.error(`ERR ${u.email}: ${e.message}`);
  }
}
console.log(`\nPassword for all demo users: ${password}`);
console.log("Share it only inside the team. Use a different one on the final demo project.");