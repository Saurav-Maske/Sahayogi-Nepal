import { supabase } from '../supabase';
import type { ApprovedItem, District } from '../types/requests';
import type { Donation, DonationDetail, DonationFilters, DonationList } from '../types/donations';
import { DONATION_TABS } from '../utils/donations';
import { PAGE_SIZE } from '../utils/requests';
import { callReviewRpc } from './requestsService';
import { hasSession } from './session';

const DAY = 864e5;
const one = (v: any) => (Array.isArray(v) ? v[0] : v);
const nn = (v: any) => (v == null ? null : Number(v));

const ITEMS = 'request_items(id, item_type, unit, requested_qty, approved_qty, donor_qty, confirmed_qty)';
const LIST_SELECT = `id, public_ref, status, requester_name, requester_phone, created_at, updated_at, districts(name), ${ITEMS}`;
const DETAIL_SELECT = `${LIST_SELECT}, address_note, notes, decline_reason, approved_at, picked_up_at, fulfilled_at`;

const mapDonation = (r: any): Donation => ({
  id: r.id, publicRef: r.public_ref, status: r.status,
  donorName: r.requester_name, donorPhone: r.requester_phone, district: one(r.districts)?.name ?? '—',
  createdAt: r.created_at, updatedAt: r.updated_at ?? null,
  addressNote: r.address_note ?? null, notes: r.notes ?? null, declineReason: r.decline_reason ?? null,
  approvedAt: r.approved_at ?? null, pickedUpAt: r.picked_up_at ?? null, fulfilledAt: r.fulfilled_at ?? null,
  driver: null,
  items: (r.request_items ?? []).map((i: any) => ({
    id: i.id, itemType: i.item_type, unit: i.unit, offeredQty: Number(i.requested_qty) || 0,
    acceptedQty: nn(i.approved_qty), donorQty: nn(i.donor_qty), collectedQty: nn(i.confirmed_qty),
  })),
});

async function countDonations(statuses?: string[]) {
  let q: any = supabase.from('requests').select('*', { count: 'exact', head: true }).eq('kind', 'donation_offer');
  if (statuses) q = q.in('status', statuses);
  const { count, error } = await q;
  if (error) throw error;
  return count ?? 0;
}

/* ------------------------------------- public API ------------------------------------ */
export async function listDonations(f: DonationFilters): Promise<DonationList> {
  if (!(await hasSession())) throw new Error('Sign in as an administrator to view donations.');

  const select = f.itemType ? LIST_SELECT.replace('request_items(', 'request_items!inner(') : LIST_SELECT;
  let q: any = supabase.from('requests').select(select, { count: 'exact' }).eq('kind', 'donation_offer');
  const statuses = DONATION_TABS.find((t) => t.key === f.tab)?.statuses;
  if (statuses) q = q.in('status', statuses);
  const s = f.q.trim().replace(/[%,()]/g, '');
  if (s) q = q.or(`public_ref.ilike.%${s}%,requester_name.ilike.%${s}%,requester_phone.ilike.%${s}%`);
  if (f.districtId) q = q.eq('district_id', f.districtId);
  if (f.itemType) q = q.eq('request_items.item_type', f.itemType);
  if (f.from) q = q.gte('created_at', new Date(f.from).toISOString());
  if (f.to) q = q.lt('created_at', new Date(+new Date(f.to) + DAY).toISOString());
  const start = (f.page - 1) * PAGE_SIZE;
  q = q.order('created_at', { ascending: false }).range(start, start + PAGE_SIZE - 1);

  const [{ data, count, error }, allTotal, pendingTotal, inProgressTotal] = await Promise.all([
    q,
    countDonations(),
    countDonations(['pending_admin_review']),
    countDonations(['in_progress']),
  ]);
  if (error) throw error;
  return { rows: (data ?? []).map(mapDonation), total: count ?? 0, allTotal, pendingTotal, inProgressTotal };
}

export async function getDonation(id: string): Promise<DonationDetail> {
  if (!(await hasSession())) throw new Error('Sign in as an administrator to view this donation.');
  const { data, error } = await supabase.from('requests').select(DETAIL_SELECT).eq('id', id).eq('kind', 'donation_offer').single();
  if (error) throw error;
  const donation = mapDonation(data);

  // the driver card is non-critical: if this lookup fails the page still works
  try {
    const { data: asg, error: e2 } = await supabase
      .from('assignments')
      .select('id, state, volunteer:profiles!volunteer_id(full_name, phone)')
      .eq('request_id', id).not('state', 'in', '(declined,expired,cancelled)')
      .order('offered_at', { ascending: false }).limit(1);
    if (e2) throw e2;
    const a: any = asg?.[0];
    if (a) donation.driver = { assignmentId: a.id, state: a.state, name: one(a.volunteer)?.full_name ?? null, phone: one(a.volunteer)?.phone ?? null };
  } catch (err) {
    console.warn('[donations] could not load assigned driver:', err);
  }
  return { donation };
}

export async function getDonationItemTypes(): Promise<string[]> {
  if (!(await hasSession())) throw new Error('Sign in as an administrator to load donation categories.');
  const { data, error } = await supabase.from('request_items').select('item_type, requests!inner(kind)').eq('requests.kind', 'donation_offer');
  if (error) throw error;
  return [...new Set((data ?? []).map((r: any) => r.item_type as string))].sort();
}

export async function getDonationDistricts(): Promise<District[]> {
  if (!(await hasSession())) throw new Error('Sign in as an administrator to load districts.');
  const { data, error } = await supabase.from('districts').select('id, name').order('name');
  if (error) throw error;
  return data ?? [];
}

/** Accept or decline a pending donation. Uses admin_approve_request / admin_decline_request. */
export async function reviewDonation(id: string, decision: 'approve' | 'decline', items: ApprovedItem[], reason: string) {
  if (!(await hasSession())) throw new Error('Sign in as an administrator to review donations.');
  await callReviewRpc(id, decision, items, reason);
}

/** Correct accepted quantities on an already-accepted donation. */
export async function saveAcceptedQuantities(id: string, items: ApprovedItem[], note: string) {
  if (!(await hasSession())) throw new Error('Sign in as an administrator to update donation quantities.');
  // No backend RPC exists for this: after approval the donor changes quantities through requester_update_pickup_qty
  // and the driver confirms at pickup. Fail loudly instead of calling a function that does not exist.
  // TODO (Person 2 / 3): either add an admin RPC for it or remove the "edit accepted quantities" action from the UI.
  void note;
  throw new Error('Changing accepted quantities after approval is not supported by the backend yet.');
}
