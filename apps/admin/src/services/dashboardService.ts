import { supabase } from '../supabase';
import type { DashboardData } from '../types/dashboard';

/**
 * Table / column names used for the live query.
 * Person 2: if the schema differs, change them here only.
 */
const T = {
  requests: 'requests', // status: pending | approved | fulfilled, category, created_at, fulfilled_at
  volunteers: 'volunteers', // status: approved
  assignments: 'assignments', // status: active
  incidents: 'incidents', // status: open, severity: urgent
  inventory: 'central_inventory', // quantity, category, low_stock_threshold, item_name, unit
  activity: 'activity_log', // created_at, message, link
};

export const DEMO_DATA: DashboardData = {
  stats: {
    totalRequests: 1284, totalRequestsChangePct: 12,
    pendingRequests: 48, needReviewToday: 12,
    approvedRequests: 186, fulfilledRequests: 1050, fulfilmentRatePct: 82,
    activeVolunteers: 124, volunteerCategories: 3,
    availableInventory: 2840, inventoryCategories: 5,
    activeAssignments: 32, driversEnRoute: 8,
    openIncidents: 6, urgentIncidents: 2,
  },
  byCategory: [
    { label: 'Food', value: 88 }, { label: 'Water', value: 62 },
    { label: 'Shelter', value: 45 }, { label: 'Health', value: 30 },
    { label: 'Other', value: 52 },
  ],
  fulfilledOverTime: [
    { label: 'Mon', value: 40 }, { label: 'Tue', value: 52 }, { label: 'Wed', value: 46 },
    { label: 'Thu', value: 68 }, { label: 'Fri', value: 78 }, { label: 'Sat', value: 89 },
  ],
  activity: [
    { id: '1', time: '10:42', text: 'Delivery completed — REQ-1038, Kirtipur', href: '/requests' },
    { id: '2', time: '10:35', text: 'Donation picked up — DON-0284, 45 kg rice', href: '/donations' },
    { id: '3', time: '10:21', text: 'Volunteer approved — Nisha Rai, Healthcare', href: '/volunteers' },
    { id: '4', time: '10:14', text: 'Inventory updated — 240 kg rice ready to ship', href: '/inventory' },
    { id: '5', time: '09:58', text: 'New request — REQ-1042, food assistance', href: '/requests' },
    { id: '6', time: '09:50', text: 'Incident reported — INC-0061, shortage of 2 kg', href: '/incidents' },
  ],
  attention: {
    quantityDiscrepancies: 2,
    lowStock: { item: 'Drinking water', available: 84, threshold: 100, unit: 'bottles' },
  },
  updatedAt: new Date().toISOString(),
  source: 'demo',
};

const count = async (table: string, filter?: (q: any) => any): Promise<number> => {
  let q: any = supabase.from(table).select('*', { count: 'exact', head: true });
  if (filter) q = filter(q);
  const { count: n, error } = await q;
  if (error) throw error;
  return n ?? 0;
};

const hhmm = (iso: string) =>
  new Date(iso).toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' });

async function fetchLive(): Promise<DashboardData> {
  const monthAgo = new Date(Date.now() - 30 * 864e5).toISOString();
  const twoMonthsAgo = new Date(Date.now() - 60 * 864e5).toISOString();

  const [total, lastMonth, prevMonth, pending, approved, fulfilled, volunteers, assignments, openInc, urgentInc] =
    await Promise.all([
      count(T.requests),
      count(T.requests, (q) => q.gte('created_at', monthAgo)),
      count(T.requests, (q) => q.gte('created_at', twoMonthsAgo).lt('created_at', monthAgo)),
      count(T.requests, (q) => q.eq('status', 'pending')),
      count(T.requests, (q) => q.eq('status', 'approved')),
      count(T.requests, (q) => q.eq('status', 'fulfilled')),
      count(T.volunteers, (q) => q.eq('status', 'approved')),
      count(T.assignments, (q) => q.eq('status', 'active')),
      count(T.incidents, (q) => q.eq('status', 'open')),
      count(T.incidents, (q) => q.eq('status', 'open').eq('severity', 'urgent')),
    ]);

  const [inv, reqs, log] = await Promise.all([
    supabase.from(T.inventory).select('item_name, category, quantity, unit, low_stock_threshold'),
    supabase.from(T.requests).select('category, status, fulfilled_at').gte('created_at', monthAgo),
    supabase.from(T.activity).select('id, created_at, message, link').order('created_at', { ascending: false }).limit(6),
  ]);
  if (inv.error) throw inv.error;
  if (reqs.error) throw reqs.error;
  if (log.error) throw log.error;

  const invRows = inv.data ?? [];
  const low = invRows
    .filter((r: any) => r.low_stock_threshold != null && r.quantity < r.low_stock_threshold)
    .sort((a: any, b: any) => a.quantity / a.low_stock_threshold - b.quantity / b.low_stock_threshold)[0];

  const cat = new Map<string, number>();
  (reqs.data ?? []).forEach((r: any) => cat.set(r.category, (cat.get(r.category) ?? 0) + 1));

  const days = Array.from({ length: 7 }, (_, i) => {
    const d = new Date(); d.setHours(0, 0, 0, 0); d.setDate(d.getDate() - (6 - i));
    return d;
  });
  const fulfilledOverTime = days.map((d) => ({
    label: d.toLocaleDateString('en-GB', { weekday: 'short' }),
    value: (reqs.data ?? []).filter(
      (r: any) => r.fulfilled_at && new Date(r.fulfilled_at).toDateString() === d.toDateString(),
    ).length,
  }));

  return {
    stats: {
      totalRequests: total,
      totalRequestsChangePct: prevMonth ? Math.round(((lastMonth - prevMonth) / prevMonth) * 100) : 0,
      pendingRequests: pending,
      needReviewToday: pending,
      approvedRequests: approved,
      fulfilledRequests: fulfilled,
      fulfilmentRatePct: total ? Math.round((fulfilled / total) * 100) : 0,
      activeVolunteers: volunteers,
      volunteerCategories: 3,
      availableInventory: invRows.reduce((s: number, r: any) => s + (r.quantity ?? 0), 0),
      inventoryCategories: new Set(invRows.map((r: any) => r.category)).size,
      activeAssignments: assignments,
      driversEnRoute: assignments,
      openIncidents: openInc,
      urgentIncidents: urgentInc,
    },
    byCategory: [...cat].map(([label, value]) => ({ label, value })),
    fulfilledOverTime,
    activity: (log.data ?? []).map((r: any) => ({
      id: String(r.id), time: hhmm(r.created_at), text: r.message, href: r.link ?? '/requests',
    })),
    attention: {
      quantityDiscrepancies: urgentInc,
      lowStock: low
        ? { item: low.item_name, available: low.quantity, threshold: low.low_stock_threshold, unit: low.unit ?? 'units' }
        : null,
    },
    updatedAt: new Date().toISOString(),
    source: 'live',
  };
}

/** Live data when Supabase answers; demo data otherwise so the UI is always usable. */
export async function getDashboardData(): Promise<DashboardData> {
  try {
    return await fetchLive();
  } catch (err) {
    console.warn('[dashboard] Supabase query failed, showing demo data:', err);
    return { ...DEMO_DATA, updatedAt: new Date().toISOString() };
  }
}