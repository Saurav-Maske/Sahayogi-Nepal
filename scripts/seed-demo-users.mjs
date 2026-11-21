// Creates FICTIONAL demo auth users + profiles. Uses service role: run locally / demo project only.
import 'dotenv/config';
import { createClient } from '@supabase/supabase-js';
const sb = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });
const PW = 'Demo#12345'; // demo only
const users = [
  { email: 'admin@demo.sahayogi.test',   name: 'Demo Admin',    role: 'admin',     cats: [] },
  { email: 'driver1@demo.sahayogi.test', name: 'Demo Driver 1', role: 'volunteer', cats: ['A','B'] },
  { email: 'driver2@demo.sahayogi.test', name: 'Demo Driver 2', role: 'volunteer', cats: ['A','B'] },
  { email: 'general@demo.sahayogi.test', name: 'Demo General',  role: 'volunteer', cats: ['A'] },
  { email: 'doctor@demo.sahayogi.test',  name: 'Demo Doctor',   role: 'volunteer', cats: ['A','C'] },
];
for (const u of users) {
  const { data, error } = await sb.auth.admin.createUser({ email: u.email, password: PW, email_confirm: true });
  let id = data?.user?.id;
  if (!id) { const l = await sb.auth.admin.listUsers({ perPage: 200 }); id = l.data?.users.find(x => x.email === u.email)?.id; }
  if (!id) { console.error('✗', u.email, error?.message); continue; }
  const { error: pe } = await sb.from('profiles').upsert({ id, name: u.name, email: u.email, role: u.role, account_status: 'active', categories: u.cats });
  console.log(pe ? `✗ profile ${u.email}: ${pe.message}` : `✓ ${u.email} (${u.role} ${u.cats.join('+')})`);
}
console.log('Demo password for all:', PW);
