import { supabase } from '../supabase';
import type { Volunteer, VolunteerDecision, VolunteerDetail, VolunteerFilters, VolunteerList, VolunteerStats } from '../types/volunteers';
import { PAGE_SIZE } from '../utils/requests';
import { hasSession } from './session';

/* ---- backend contract: confirm with Person 2 ---- */
// UI-level review states. DB enum review_status is ('submitted','under_review','approved','declined'):
// pending = submitted | under_review, rejected = declined. Translated at the DB boundary (mapRow / queries below).
const REVIEW = { pending: 'pending', approved: 'approved', rejected: 'rejected' };
const DB_PENDING = ['submitted', 'under_review'];
const DB_DECLINED = 'declined';
const uiReview = (v: string) => (DB_PENDING.includes(v) ? REVIEW.pending : v === DB_DECLINED ? REVIEW.rejected : v);
const SUSPENDED = 'suspended'; // profiles.account_status check ('active','suspended')
const BUCKET = 'volunteer-docs'; // private bucket from migration 20261121000004_storage_docs.sql
const DAY = 864e5;
const one = (v: any) => (Array.isArray(v) ? v[0] : v);

const SELECT =
  'id, profile_id, full_name, email, phone, volunteer_type, citizenship_no, citizenship_photo_path, license_no, license_photo_path, service_card_no, service_card_photo_path, review_status, review_note, reviewed_at, created_at, profiles!profile_id(account_status)';

const mapRow = (r: any): Volunteer => ({
  id: r.id, profileId: r.profile_id ?? null, fullName: r.full_name, email: r.email, phone: r.phone,
  volunteerType: r.volunteer_type ?? null,
  citizenshipNo: r.citizenship_no ?? null, citizenshipPath: r.citizenship_photo_path ?? null,
  licenseNo: r.license_no ?? null, licensePath: r.license_photo_path ?? null,
  serviceCardNo: r.service_card_no ?? null, serviceCardPath: r.service_card_photo_path ?? null,
  reviewStatus: uiReview(r.review_status), reviewNote: r.review_note ?? null, reviewedAt: r.reviewed_at ?? null,
  createdAt: r.created_at, accountStatus: one(r.profiles)?.account_status ?? null,
});

async function countApps(status: string) {
  let q: any = supabase.from('volunteer_applications').select('*', { count: 'exact', head: true });
  q = status === REVIEW.pending ? q.in('review_status', DB_PENDING) : q.eq('review_status', status);
  const { count, error } = await q;
  if (error) throw error;
  return count ?? 0;
}

/* ------------------------------------- public API ------------------------------------ */
export async function listVolunteers(f: VolunteerFilters): Promise<VolunteerList> {
  if (!(await hasSession())) throw new Error('Sign in as an administrator to view volunteers.');

  const select = f.tab === 'suspended' ? SELECT.replace('profiles!profile_id(', 'profiles!profile_id!inner(') : SELECT;
  let q: any = supabase.from('volunteer_applications').select(select, { count: 'exact' });
  if (f.tab === 'pending') q = q.in('review_status', DB_PENDING);
  else if (f.tab === 'approved') q = q.eq('review_status', REVIEW.approved);
  else if (f.tab === 'declined') q = q.eq('review_status', DB_DECLINED);
  else q = q.eq('profiles.account_status', SUSPENDED);

  const s = f.q.trim().replace(/[%,()]/g, '');
  if (s) q = q.or(`full_name.ilike.%${s}%,email.ilike.%${s}%,phone.ilike.%${s}%`);
  if (f.category) q = q.eq('volunteer_type', f.category);
  if (f.days) q = q.gte('created_at', new Date(Date.now() - Number(f.days) * DAY).toISOString());
  const start = (f.page - 1) * PAGE_SIZE;
  q = q.order('created_at', { ascending: false }).range(start, start + PAGE_SIZE - 1);

  const [{ data, count, error }, pendingTotal, approvedTotal] = await Promise.all([q, countApps(REVIEW.pending), countApps(REVIEW.approved)]);
  if (error) throw error;
  return { rows: (data ?? []).map(mapRow), total: count ?? 0, pendingTotal, approvedTotal };
}

async function loadStats(profileId: string): Promise<VolunteerStats | null> {
  try {
    const { data, error } = await supabase.from('assignments').select('id, state, requests(kind)').eq('volunteer_id', profileId);
    if (error) throw error;
    const rows = data ?? [];
    const delivered = rows.filter((a: any) => a.state === 'delivered');
    const failed = rows.filter((a: any) => ['disputed', 'cancelled'].includes(a.state)).length;
    let kg = 0;
    if (delivered.length) {
      const { data: mv, error: e2 } = await supabase.from('inventory_movements').select('quantity, inventory_lots(unit)')
        .in('assignment_id', delivered.map((a: any) => a.id)).in('to_phase', ['dispatched', 'consumed']);
      if (e2) throw e2;
      kg = Math.round((mv ?? []).filter((m: any) => one(m.inventory_lots)?.unit === 'kg').reduce((s: number, m: any) => s + (Number(m.quantity) || 0), 0));
    }
    return {
      completedJobs: delivered.length, hours: null, kgDelivered: kg,
      donationsCollected: delivered.filter((a: any) => one(a.requests)?.kind === 'donation_offer').length,
      successPct: delivered.length + failed ? Math.round((delivered.length / (delivered.length + failed)) * 100) : null,
    };
  } catch (err) {
    console.warn('[volunteers] could not load contribution stats:', err);
    return null; // non-critical: the profile still opens
  }
}

export async function getVolunteer(id: string): Promise<VolunteerDetail> {
  if (!(await hasSession())) throw new Error('Sign in as an administrator to view this volunteer.');
  const { data, error } = await supabase.from('volunteer_applications').select(SELECT).eq('id', id).single();
  if (error) throw error;
  const volunteer = mapRow(data);
  return { volunteer, stats: volunteer.profileId ? await loadStats(volunteer.profileId) : null };
}

export async function reviewVolunteer(id: string, decision: VolunteerDecision, note: string) {
  if (!(await hasSession())) throw new Error('Sign in as an administrator to review volunteers.');
  if (decision === 'approve' || decision === 'reject') {
    // approve-volunteer (admin only): creates the account, sets categories, sends the invite email.
    await callFunction('approve-volunteer', { application_id: id, decision: decision === 'approve' ? 'approve' : 'decline', note });
    return;
  }
  // suspend / reinstate act on the volunteer's account, not the application.
  const { data, error } = await supabase.from('volunteer_applications').select('profile_id').eq('id', id).single();
  if (error) throw error;
  if (!data?.profile_id) throw new Error('This volunteer has no account yet.');
  await callFunction('admin-set-account-status', {
    user_id: data.profile_id, status: decision === 'suspend' ? 'suspended' : 'active', reason: note || null,
  });
}

/** Call an admin Edge Function with the signed-in admin's session and surface its { error: { code, message } } text. */
async function callFunction(name: string, body: Record<string, unknown>) {
  const { error } = await supabase.functions.invoke(name, { body });
  if (!error) return;
  let msg = error.message;
  try { const j = await (error as any).context?.json?.(); msg = j?.error?.message ?? j?.error?.code ?? msg; } catch { /* keep generic message */ }
  throw new Error(msg);
}

/** Short-lived signed link to a private identity document. */
export async function getDocumentUrl(path: string): Promise<string | null> {
  if (!(await hasSession())) throw new Error('Sign in as an administrator to view identity documents.');
  const { data, error } = await supabase.storage.from(BUCKET).createSignedUrl(path, 60);
  if (error) throw error;
  return data.signedUrl;
}
