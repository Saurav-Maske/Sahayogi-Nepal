import { supabase } from '../supabase';
import type { ApprovedItem, District } from '../types/requests';
import type { Donation, DonationDetail, DonationFilters, DonationList } from '../types/donations';
import { DONATION_TABS } from '../utils/donations';
import { PAGE_SIZE } from '../utils/requests';
import { DECISION, REVIEW_RPC, RPC_PARAMS } from './requestsService';
import { hasSession } from './session';

/**
 * PROPOSED RPC, not in API-CONTRACT.md yet. Ask Person 2 to add it (and to log every change,
 * since the Figma says "All quantity changes are recorded"). Names live here only.
 */
const ADJUST_RPC = 'admin_set_accepted_qty';
const ADJUST_PARAMS = (itemId: string, qty: number, note: string) => ({ p_request_item_id: itemId, p_qty: qty, p_note: note });

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

/* ------------------------------ demo data (no session) ------------------------------ */
type Seed = [string, number, string, number | null, number | null, number | null]; // type, offered, unit, accepted, donor, collected
const mk = (n: number, name: string, phone: string, district: string, items: Seed[], status: string, date: string, extra: Partial<Donation> = {}): Donation => ({
  id: `demo-don-${n}`, publicRef: `DON-${String(n).padStart(4, '0')}`, status, donorName: name, donorPhone: phone, district,
  createdAt: date, updatedAt: date, addressNote: 'Ward 3, Maharajgunj', notes: null, declineReason: null,
  approvedAt: null, pickedUpAt: null, fulfilledAt: null, driver: null,
  items: items.map(([t, o, u, a, d, c], i) => ({ id: `demo-don-${n}-${i}`, itemType: t, unit: u, offeredQty: o, acceptedQty: a, donorQty: d, collectedQty: c })),
  ...extra,
});

const DEMO_DISTRICTS: District[] = [{ id: 1, name: 'Kathmandu' }, { id: 2, name: 'Lalitpur' }, { id: 3, name: 'Bhaktapur' }];

let demo: Donation[] = [
  mk(284, 'Maya Shrestha', '9851 234 789', 'Kathmandu', [['rice', 50, 'kg', 50, 45, null], ['water', 24, 'bottles', 24, 24, null]], 'in_progress', '2026-06-18T08:10:00Z',
    { approvedAt: '2026-06-18T09:30:00Z', notes: 'Preferred pickup: today, 11:00–13:00',
      driver: { assignmentId: 'demo-asg-0301', state: 'en_route_to_pickup', name: 'Ramesh Gurung', phone: null } }),
  mk(283, 'Kiran Joshi', '9841 555 031', 'Lalitpur', [['water', 120, 'bottles', null, null, null]], 'pending_admin_review', '2026-06-18T07:20:00Z'),
  mk(282, 'Asha Basnet', '9841 555 032', 'Bhaktapur', [['blankets', 30, 'units', 30, 30, 30]], 'fulfilled', '2026-06-17T10:00:00Z',
    { approvedAt: '2026-06-17T10:30:00Z', pickedUpAt: '2026-06-17T13:00:00Z', fulfilledAt: '2026-06-17T13:20:00Z' }),
  mk(281, 'Nepal Food Bank', '01 555 0140', 'Kathmandu', [['rice', 300, 'kg', 300, 300, 300]], 'fulfilled', '2026-06-17T08:00:00Z',
    { approvedAt: '2026-06-17T08:30:00Z', pickedUpAt: '2026-06-17T11:00:00Z', fulfilledAt: '2026-06-17T11:20:00Z' }),
];

function listDemo(f: DonationFilters): DonationList {
  const statuses = DONATION_TABS.find((t) => t.key === f.tab)?.statuses;
  const q = f.q.trim().toLowerCase();
  const dName = f.districtId ? DEMO_DISTRICTS.find((d) => d.id === f.districtId)?.name : null;
  const filtered = [...demo].sort((a, b) => +new Date(b.createdAt) - +new Date(a.createdAt)).filter((d) =>
    (!statuses || statuses.includes(d.status)) &&
    (!q || [d.publicRef, d.donorName, d.donorPhone].some((s) => s.toLowerCase().includes(q))) &&
    (!dName || d.district === dName) && (!f.itemType || d.items.some((i) => i.itemType === f.itemType)) &&
    (!f.from || d.createdAt.slice(0, 10) >= f.from) && (!f.to || d.createdAt.slice(0, 10) <= f.to));
  const start = (f.page - 1) * PAGE_SIZE;
  return { rows: filtered.slice(start, start + PAGE_SIZE), total: filtered.length, allTotal: demo.length, pendingTotal: demo.filter((d) => d.status === 'pending_admin_review').length, demo: true };
}

/* ------------------------------------- public API ------------------------------------ */
export async function listDonations(f: DonationFilters): Promise<DonationList> {
  if (!(await hasSession())) return listDemo(f);

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

  const [{ data, count, error }, allTotal, pendingTotal] = await Promise.all([q, countDonations(), countDonations(['pending_admin_review'])]);
  if (error) throw error;
  return { rows: (data ?? []).map(mapDonation), total: count ?? 0, allTotal, pendingTotal, demo: false };
}

export async function getDonation(id: string): Promise<DonationDetail> {
  if (!(await hasSession())) {
    const d = demo.find((x) => x.id === id);
    if (!d) throw new Error('Donation not found');
    return { donation: structuredClone(d), demo: true };
  }
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
  return { donation, demo: false };
}

export async function getDonationItemTypes(): Promise<string[]> {
  if (!(await hasSession())) return [...new Set(demo.flatMap((d) => d.items.map((i) => i.itemType)))].sort();
  const { data, error } = await supabase.from('request_items').select('item_type, requests!inner(kind)').eq('requests.kind', 'donation_offer');
  if (error) throw error;
  return [...new Set((data ?? []).map((r: any) => r.item_type as string))].sort();
}

export async function getDonationDistricts(): Promise<District[]> {
  if (!(await hasSession())) return DEMO_DISTRICTS;
  const { data, error } = await supabase.from('districts').select('id, name').order('name');
  if (error) throw error;
  return data ?? [];
}

/** Accept or decline a pending donation. Reuses the contract's admin_review_request. */
export async function reviewDonation(id: string, decision: 'approve' | 'decline', items: ApprovedItem[], reason: string) {
  if (!(await hasSession())) {
    const d = demo.find((x) => x.id === id);
    if (!d) throw new Error('Donation not found');
    const now = new Date().toISOString();
    d.updatedAt = now;
    if (decision === 'decline') { d.status = 'declined'; d.declineReason = reason; return; }
    d.status = 'approved'; d.approvedAt = now;
    d.items.forEach((i) => { i.acceptedQty = items.find((a) => a.item_id === i.id)?.qty ?? 0; });
    return;
  }
  const { error } = await supabase.rpc(REVIEW_RPC, RPC_PARAMS(id, DECISION[decision], items, reason));
  if (error) throw error;
}

/** Correct accepted quantities on an already-accepted donation. */
export async function saveAcceptedQuantities(id: string, items: ApprovedItem[], note: string) {
  if (!(await hasSession())) {
    const d = demo.find((x) => x.id === id);
    if (!d) throw new Error('Donation not found');
    d.items.forEach((i) => { const m = items.find((a) => a.item_id === i.id); if (m) i.acceptedQty = m.qty; });
    return;
  }
  for (const it of items) {
    const { error } = await supabase.rpc(ADJUST_RPC, ADJUST_PARAMS(it.item_id, it.qty, note));
    if (error) throw error;
  }
}