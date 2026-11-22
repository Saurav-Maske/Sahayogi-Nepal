import { supabase } from '../supabase';
import type { ActivityItem, DashboardData } from '../types/dashboard';
import { kindLabel, humanize } from '../utils/labels';
import { hasSession } from '../services/session';

const IN_STOCK_PHASES = ['received', 'processing', 'ready_to_ship'];
const APPROVED_STATUSES = ['approved', 'awaiting_assignment'];
const ACTIVE_ASSIGNMENT_STATES = ['accepted', 'en_route_to_pickup', 'picked_up', 'en_route_to_destination'];
const EN_ROUTE_STATES = ['en_route_to_pickup', 'en_route_to_destination'];

const DAY = 864e5;
const since = (days: number) => new Date(Date.now() - days * DAY).toISOString();

const count = async (table: string, filter?: (q: any) => any): Promise<number> => {
  let q: any = supabase.from(table).select('*', { count: 'exact', head: true });
  if (filter) q = filter(q);
  const { count: n, error } = await q;
  if (error) throw error;
  return n ?? 0;
};

const rows = async (table: string, cols: string, filter?: (q: any) => any): Promise<any[]> => {
  let q: any = supabase.from(table).select(cols);
  if (filter) q = filter(q);
  const { data, error } = await q;
  if (error) throw error;
  return data ?? [];
};

const stamp = (iso: string) => {
  const d = new Date(iso);
  return d.toDateString() === new Date().toDateString()
    ? d.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' })
    : d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short' });
};

async function fetchLive(): Promise<DashboardData> {
  const startOfToday = new Date(); startOfToday.setHours(0, 0, 0, 0);

  const [total, lastMonth, prevMonth, pending, pendingToday, approved, fulfilled,
    volunteers, activeAsg, enRoute, openInc, discrepancies] = await Promise.all([
    count('requests'),
    count('requests', (q) => q.gte('created_at', since(30))),
    count('requests', (q) => q.gte('created_at', since(60)).lt('created_at', since(30))),
    count('requests', (q) => q.eq('status', 'pending_admin_review')),
    count('requests', (q) => q.eq('status', 'pending_admin_review').gte('created_at', startOfToday.toISOString())),
    count('requests', (q) => q.in('status', APPROVED_STATUSES)),
    count('requests', (q) => q.eq('status', 'fulfilled')),
    count('profiles', (q) => q.eq('role', 'volunteer')),
    count('assignments', (q) => q.in('state', ACTIVE_ASSIGNMENT_STATES)),
    count('assignments', (q) => q.in('state', EN_ROUTE_STATES)),
    count('incidents', (q) => q.eq('status', 'open')),
    count('incidents', (q) => q.eq('status', 'open').not('reported_shortfall', 'is', null)),
  ]);

  const [vTypes, lots, kinds, fulfilledRows, newReqs, doneReqs, incs, apps] = await Promise.all([
    rows('profiles', 'volunteer_type', (q) => q.eq('role', 'volunteer')),
    rows('inventory_lots', 'item_type, unit, quantity, reserved_qty', (q) => q.in('phase', IN_STOCK_PHASES)),
    rows('requests', 'kind', (q) => q.gte('created_at', since(30))),
    rows('requests', 'fulfilled_at', (q) => q.gte('fulfilled_at', since(7))),
    rows('requests', 'public_ref, kind, created_at', (q) => q.order('created_at', { ascending: false }).limit(5)),
    rows('requests', 'public_ref, fulfilled_at', (q) => q.not('fulfilled_at', 'is', null).order('fulfilled_at', { ascending: false }).limit(5)),
    rows('incidents', 'id, incident_type, created_at', (q) => q.order('created_at', { ascending: false }).limit(5)),
    rows('volunteer_applications', 'id, full_name, review_status, reviewed_at', (q) => q.not('reviewed_at', 'is', null).order('reviewed_at', { ascending: false }).limit(5)),
  ]);

  // inventory: available = quantity - reserved, per item type
  const stock = new Map<string, { available: number; unit: string }>();
  lots.forEach((l) => {
    const cur = stock.get(l.item_type) ?? { available: 0, unit: l.unit };
    cur.available += (Number(l.quantity) || 0) - (Number(l.reserved_qty) || 0);
    stock.set(l.item_type, cur);
  });
  const byKind = new Map<string, number>();
  kinds.forEach((r) => byKind.set(r.kind, (byKind.get(r.kind) ?? 0) + 1));

  const days = Array.from({ length: 7 }, (_, i) => {
    const d = new Date(); d.setHours(0, 0, 0, 0); d.setDate(d.getDate() - (6 - i)); return d;
  });

  const activity: (ActivityItem & { at: string })[] = [
    ...newReqs.map((r) => ({ id: `n-${r.public_ref}`, at: r.created_at, href: '/requests', text: `New request — ${r.public_ref}, ${kindLabel(r.kind).toLowerCase()}` })),
    ...doneReqs.map((r) => ({ id: `f-${r.public_ref}`, at: r.fulfilled_at, href: '/requests', text: `Request fulfilled — ${r.public_ref}` })),
    ...incs.map((i) => ({ id: `i-${i.id}`, at: i.created_at, href: '/incidents', text: `Incident reported — ${humanize(i.incident_type)}` })),
    ...apps.map((a) => ({ id: `a-${a.id}`, at: a.reviewed_at, href: '/volunteers', text: `Volunteer application ${humanize(a.review_status).toLowerCase()} — ${a.full_name}` })),
  ].map((x) => ({ ...x, time: stamp(x.at) }));
  activity.sort((a, b) => +new Date(b.at) - +new Date(a.at));

  return {
    stats: {
      totalRequests: total,
      totalRequestsChangePct: prevMonth ? Math.round(((lastMonth - prevMonth) / prevMonth) * 100) : 0,
      pendingRequests: pending,
      needReviewToday: pendingToday,
      approvedRequests: approved,
      fulfilledRequests: fulfilled,
      fulfilmentRatePct: total ? Math.round((fulfilled / total) * 100) : 0,
      activeVolunteers: volunteers,
      volunteerCategories: new Set(vTypes.map((v) => v.volunteer_type).filter(Boolean)).size,
      availableInventory: Math.round([...stock.values()].reduce((s, v) => s + v.available, 0)),
      inventoryCategories: stock.size,
      activeAssignments: activeAsg,
      driversEnRoute: enRoute,
      openIncidents: openInc,
      urgentIncidents: discrepancies,
    },
    byCategory: [...byKind].map(([k, value]) => ({ label: kindLabel(k), value })),
    fulfilledOverTime: days.map((d) => ({
      label: d.toLocaleDateString('en-GB', { weekday: 'short' }),
      value: fulfilledRows.filter((r) => new Date(r.fulfilled_at).toDateString() === d.toDateString()).length,
    })),
    activity: activity.slice(0, 6),
    attention: {
      quantityDiscrepancies: discrepancies,
    },
    updatedAt: new Date().toISOString(),
    source: 'live',
  };
}

export async function getDashboardData(): Promise<DashboardData> {
  if (!(await hasSession())) throw new Error('Sign in as an administrator to view the operations dashboard.');
  return fetchLive();
}
