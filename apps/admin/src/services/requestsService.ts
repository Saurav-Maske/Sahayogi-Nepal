import { supabase } from '../supabase';
import type { ApprovedItem, DetailResult, District, ListResult, RequestFilters, ServiceRequest } from '../types/requests';
import { PAGE_SIZE, TABS } from '../utils/requests';
import { hasSession } from './session';

/* ---- backend contract: confirm with Person 2 (admin_review_request is still a TODO in API-CONTRACT.md) ---- */
export const REVIEW_RPC = 'admin_review_request';
export const DECISION = { approve: 'approve', decline: 'decline' } as const;
export const RPC_PARAMS = (id: string, decision: string, items: ApprovedItem[], reason: string) => ({
  p_request_id: id, p_decision: decision, p_approved_items: items, p_reason: reason,
});
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
  let q: any = supabase.from('requests').select('*', { count: 'exact', head: true });
  if (statuses) q = q.in('status', statuses);
  const { count, error } = await q;
  if (error) throw error;
  return count ?? 0;
}

/* ------------------------------ demo data (no session) ------------------------------ */
const mk = (n: number, ref: string, name: string, phone: string, kind: string, district: string,
  items: [string, number, string][], status: string, date: string, extra: Partial<ServiceRequest> = {}): ServiceRequest => ({
  id: `demo-${n}`, publicRef: ref, kind, status, requesterName: name, requesterPhone: phone, district,
  createdAt: date, updatedAt: date, addressNote: 'Ward 6, Kirtipur', urgency: 'high',
  notes: 'Food support for a household of five.', declineReason: null, approvedAt: null, pickedUpAt: null, fulfilledAt: null,
  items: items.map(([t, q, u], i) => ({ id: `demo-${n}-${i}`, itemType: t, unit: u, requestedQty: q, approvedQty: null, available: null })),
  ...extra,
});

const DEMO_DISTRICTS: District[] = [
  { id: 1, name: 'Kathmandu' }, { id: 2, name: 'Lalitpur' }, { id: 3, name: 'Bhaktapur' }, { id: 4, name: 'Kavre' }, { id: 5, name: 'Kirtipur' },
];
const DEMO_STOCK: Record<string, number> = { rice: 240, water: 84 };

let demo: ServiceRequest[] = [
  mk(1042, 'REQ-1042', 'Sita Tamang', '9841 234 567', 'resource_request', 'Kathmandu', [['rice', 20, 'kg'], ['water', 12, 'bottles']], 'pending_admin_review', '2026-06-18T09:12:00Z'),
  mk(1041, 'REQ-1041', 'Hari Thapa', '9841 555 014', 'resource_request', 'Lalitpur', [['water', 24, 'bottles']], 'approved', '2026-06-18T08:40:00Z',
    { approvedAt: '2026-06-18T09:05:00Z' }),
  mk(1040, 'REQ-1040', 'Mina Rai', '9841 555 016', 'healthcare_request', 'Bhaktapur', [['nurse', 2, 'hours']], 'assigned', '2026-06-18T07:55:00Z',
    { approvedAt: '2026-06-18T08:10:00Z' }),
  mk(1039, 'REQ-1039', 'Ram Gurung', '9841 555 018', 'resource_request', 'Kavre', [['tents', 4, 'units']], 'in_progress', '2026-06-17T15:20:00Z',
    { approvedAt: '2026-06-17T16:00:00Z', pickedUpAt: '2026-06-17T17:30:00Z' }),
  mk(1038, 'REQ-1038', 'Rita Lama', '9841 555 020', 'resource_request', 'Kirtipur', [['rice', 10, 'kg']], 'fulfilled', '2026-06-17T11:00:00Z',
    { approvedAt: '2026-06-17T11:30:00Z', pickedUpAt: '2026-06-17T12:30:00Z', fulfilledAt: '2026-06-17T14:00:00Z' }),
  mk(1037, 'REQ-1037', 'Bina Shah', '9841 555 022', 'resource_request', 'Kathmandu', [['blankets', 8, 'units']], 'declined', '2026-06-17T09:00:00Z',
    { declineReason: 'Duplicate of REQ-1031.' }),
];

function listDemo(f: RequestFilters): ListResult {
  const statuses = TABS.find((t) => t.key === f.tab)?.statuses;
  const q = f.q.trim().toLowerCase();
  const dName = f.districtId ? DEMO_DISTRICTS.find((d) => d.id === f.districtId)?.name : null;
  const filtered = [...demo].sort((a, b) => +new Date(b.createdAt) - +new Date(a.createdAt)).filter((r) =>
    (!statuses || statuses.includes(r.status)) &&
    (!q || [r.publicRef, r.requesterName, r.requesterPhone].some((s) => s.toLowerCase().includes(q))) &&
    (!dName || r.district === dName) && (!f.kind || r.kind === f.kind) &&
    (!f.from || r.createdAt.slice(0, 10) >= f.from) && (!f.to || r.createdAt.slice(0, 10) <= f.to));
  const start = (f.page - 1) * PAGE_SIZE;
  return {
    rows: filtered.slice(start, start + PAGE_SIZE), total: filtered.length, allTotal: demo.length,
    pendingTotal: demo.filter((r) => r.status === 'pending_admin_review').length, demo: true,
  };
}

/* ------------------------------------- public API ------------------------------------ */
export async function listRequests(f: RequestFilters): Promise<ListResult> {
  if (!(await hasSession())) return listDemo(f);

  let q: any = supabase.from('requests').select(LIST_SELECT, { count: 'exact' });
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
  return { rows: (data ?? []).map(mapRow), total: count ?? 0, allTotal, pendingTotal, demo: false };
}

export async function getRequest(id: string): Promise<DetailResult> {
  if (!(await hasSession())) {
    const r = demo.find((x) => x.id === id);
    if (!r) throw new Error('Request not found');
    const copy = structuredClone(r);
    if (copy.kind === 'resource_request') copy.items.forEach((i) => { i.available = DEMO_STOCK[i.itemType] ?? 500; });
    return { request: copy, demo: true };
  }

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
  return { request: req, demo: false };
}

export async function getDistricts(): Promise<District[]> {
  if (!(await hasSession())) return DEMO_DISTRICTS;
  const { data, error } = await supabase.from('districts').select('id, name').order('name');
  if (error) throw error;
  return data ?? [];
}

export async function reviewRequest(id: string, decision: 'approve' | 'decline', items: ApprovedItem[], reason: string) {
  if (!(await hasSession())) {
    const r = demo.find((x) => x.id === id);
    if (!r) throw new Error('Request not found');
    const now = new Date().toISOString();
    r.updatedAt = now;
    if (decision === 'decline') { r.status = 'declined'; r.declineReason = reason; return; }
    r.status = 'approved'; r.approvedAt = now;
    r.items.forEach((i) => { i.approvedQty = items.find((a) => a.item_id === i.id)?.qty ?? 0; });
    return;
  }
  const { error } = await supabase.rpc(REVIEW_RPC, RPC_PARAMS(id, DECISION[decision], items, reason));
  if (error) throw error;
}