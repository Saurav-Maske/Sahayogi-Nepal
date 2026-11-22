import { supabase } from '../supabase';
import type { ApprovedItem, DetailResult, District, ListResult, RequestFilters, ServiceRequest } from '../types/requests';
import { PAGE_SIZE, TABS } from '../utils/requests';
import { hasSession } from './session';

/* ---- backend contract (live): admin_approve_request(p_id, p_items) and admin_decline_request(p_id, p_reason) ---- */
export const DECISION = { approve: 'approve', decline: 'decline' } as const;

/** Approve or decline through the live RPCs. Shared with donationsService. Errors carry the RPC's code as message
 *  (forbidden | not_found | invalid_state | invalid_items | invalid_reason | insufficient_stock ...). */
export async function callReviewRpc(id: string, decision: 'approve' | 'decline', items: ApprovedItem[], reason: string) {
  if (decision === 'decline') {
    const { error } = await supabase.rpc('admin_decline_request', { p_id: id, p_reason: reason });
    if (error) throw error;
    return;
  }
  // null = approve everything as requested; otherwise only the items the admin changed, as { item_id, approved_qty }.
  const p_items = items.length ? items.map((i) => ({ item_id: i.item_id, approved_qty: i.qty })) : null;
  const { error } = await supabase.rpc('admin_approve_request', { p_id: id, p_items });
  if (error) throw error;
}
const IN_STOCK_PHASES = ['received', 'processing', 'ready_to_ship'];

const DAY = 864e5;
const one = (v: any) => (Array.isArray(v) ? v[0] : v);

const LIST_SELECT =
  'id, public_ref, kind, status, requester_name, requester_phone, created_at, updated_at, districts(name), request_items(id, item_type, unit, requested_qty, approved_qty)';
const DETAIL_SELECT = `${LIST_SELECT}, address_note, urgency, notes, decline_reason, approved_at, picked_up_at, fulfilled_at`;

const mapRow = (r: any): ServiceRequest => ({
  id: r.id, publicRef: r.public_ref, kind: r.kind, status: r.status,
  requesterName: r.requester_name, requesterPhone: r.requester_phone,
  district: one(r.districts)?.name ?? '—',
  createdAt: r.created_at, updatedAt: r.updated_at ?? null,
  addressNote: r.address_note ?? null, urgency: r.urgency ?? null, notes: r.notes ?? null,
  declineReason: r.decline_reason ?? null, approvedAt: r.approved_at ?? null,
  pickedUpAt: r.picked_up_at ?? null, fulfilledAt: r.fulfilled_at ?? null,
  items: (r.request_items ?? []).map((i: any) => ({
    id: i.id, itemType: i.item_type, unit: i.unit,
    requestedQty: Number(i.requested_qty) || 0,
    approvedQty: i.approved_qty == null ? null : Number(i.approved_qty),
    available: null,
  })),
});

async function countRequests(statuses?: string[]) {
  let q: any = supabase.from('requests').select('*', { count: 'exact', head: true }).neq('kind', 'donation_offer');
  if (statuses) q = q.in('status', statuses);
  const { count, error } = await q;
  if (error) throw error;
  return count ?? 0;
}

/* ------------------------------------- public API ------------------------------------ */
export async function listRequests(f: RequestFilters): Promise<ListResult> {
  if (!(await hasSession())) throw new Error('Sign in as an administrator to view requests.');

  let q: any = supabase.from('requests').select(LIST_SELECT, { count: 'exact' }).neq('kind', 'donation_offer');
  const statuses = TABS.find((t) => t.key === f.tab)?.statuses;
  if (statuses) q = q.in('status', statuses);
  const s = f.q.trim().replace(/[%,()]/g, '');
  if (s) q = q.or(`public_ref.ilike.%${s}%,requester_name.ilike.%${s}%,requester_phone.ilike.%${s}%`);
  if (f.districtId) q = q.eq('district_id', f.districtId);
  if (f.kind) q = q.eq('kind', f.kind);
  if (f.from) q = q.gte('created_at', new Date(f.from).toISOString());
  if (f.to) q = q.lt('created_at', new Date(+new Date(f.to) + DAY).toISOString());
  const start = (f.page - 1) * PAGE_SIZE;
  q = q.order('created_at', { ascending: false }).range(start, start + PAGE_SIZE - 1);

  const [{ data, count, error }, allTotal, pendingTotal] = await Promise.all([
    q, countRequests(), countRequests(['pending_admin_review']),
  ]);
  if (error) throw error;
  return { rows: (data ?? []).map(mapRow), total: count ?? 0, allTotal, pendingTotal };
}

export async function getRequest(id: string): Promise<DetailResult> {
  if (!(await hasSession())) throw new Error('Sign in as an administrator to view this request.');

  const { data, error } = await supabase.from('requests').select(DETAIL_SELECT).eq('id', id).single();
  if (error) throw error;
  const req = mapRow(data);

  if (req.kind === 'resource_request' && req.items.length) {
    const { data: lots, error: e2 } = await supabase
      .from('inventory_lots').select('item_type, unit, quantity, reserved_qty')
      .in('phase', IN_STOCK_PHASES).in('item_type', req.items.map((i) => i.itemType));
    if (e2) throw e2;
    req.items = req.items.map((i) => ({
      ...i,
      available: (lots ?? []).filter((l: any) => l.item_type === i.itemType && l.unit === i.unit)
        .reduce((sum: number, l: any) => sum + (Number(l.quantity) || 0) - (Number(l.reserved_qty) || 0), 0),
    }));
  }
  return { request: req };
}

export async function getDistricts(): Promise<District[]> {
  if (!(await hasSession())) throw new Error('Sign in as an administrator to load districts.');
  const { data, error } = await supabase.from('districts').select('id, name').order('name');
  if (error) throw error;
  return data ?? [];
}

export async function reviewRequest(id: string, decision: 'approve' | 'decline', items: ApprovedItem[], reason: string) {
  if (!(await hasSession())) throw new Error('Sign in as an administrator to review requests.');
  await callReviewRpc(id, decision, items, reason);
}

/** Make an approved request visible as claimable offers; volunteers choose for themselves. */
export async function offerRequestToVolunteers(id: string) {
  if (!(await hasSession())) throw new Error('Sign in as an administrator to share requests with volunteers.');
  const { count, error: lookupError } = await supabase
    .from('assignments')
    .select('id', { count: 'exact', head: true })
    .eq('request_id', id);
  if (lookupError) throw lookupError;
  if ((count ?? 0) > 0) return;

  const { error } = await supabase.rpc('create_assignments', { p_id: id });
  if (!error) return;

  // Avoid a false failure if two admin clients publish at the same time.
  const { count: retryCount, error: retryLookupError } = await supabase
    .from('assignments')
    .select('id', { count: 'exact', head: true })
    .eq('request_id', id);
  if (!retryLookupError && (retryCount ?? 0) > 0) return;
  throw error;
}
