import { supabase } from '../supabase';
import type { AnalyticsData } from '../types/analytics';
import type { ChartPoint } from '../types/dashboard';
import { humanize, volunteerLabel } from '../utils/labels';
import { hasSession } from './session';

const IN_STOCK_PHASES = ['received', 'processing', 'ready_to_ship'];
const OUTGOING_PHASES = ['dispatched', 'consumed'];


export const DEMO: Omit<AnalyticsData, 'updatedAt' | 'demoSections'> = {
  kpis: {
    peopleSupported: 4860, districtsCovered: 12,
    volunteerHours: 2418, volunteerHoursChangePct: 18,
    deliverySuccessPct: 96.4, completedJobs: 412,
    avgApprovalHours: 2.4, avgApprovalChangeMin: -35,
  },
  donationsVsDistribution: [
    { label: 'Don', value: 64, hint: 'Week 1 donated (kg)' }, { label: 'Dist', value: 52, hint: 'Week 1 distributed (kg)' },
    { label: 'Don', value: 86, hint: 'Week 2 donated (kg)' }, { label: 'Dist', value: 70, hint: 'Week 2 distributed (kg)' },
    { label: 'Don', value: 96, hint: 'Week 3 donated (kg)' }, { label: 'Dist', value: 83, hint: 'Week 3 distributed (kg)' },
  ],
  volunteerParticipation: [
    { label: 'Manpower', value: 90 }, { label: 'Drivers', value: 66 }, { label: 'Healthcare', value: 48 },
  ],
  inventoryStock: [
    { label: 'Food', value: 90 }, { label: 'Water', value: 65 }, { label: 'Clothes', value: 40 },
    { label: 'Medical', value: 20 }, { label: 'Shelter', value: 52 },
  ],
  requestsByDistrict: [
    { label: 'KTM', value: 62 }, { label: 'Lalitpur', value: 65 }, { label: 'Bhaktapur', value: 52 },
    { label: 'Kavre', value: 40 }, { label: 'Other', value: 32 },
  ],
};

const DAY = 864e5;
const since = (days: number) => new Date(Date.now() - days * DAY).toISOString();

const tally = (items: any[], keyOf: (r: any) => string | undefined, top?: number): ChartPoint[] => {
  const m = new Map<string, number>();
  items.forEach((r) => { const k = keyOf(r); if (k) m.set(k, (m.get(k) ?? 0) + 1); });
  const sorted = [...m].sort((a, b) => b[1] - a[1]).map(([label, value]) => ({ label, value }));
  if (!top || sorted.length <= top) return sorted;
  const rest = sorted.slice(top).reduce((s, p) => s + p.value, 0);
  return [...sorted.slice(0, top), { label: 'Other', value: rest }];
};

async function rows(table: string, cols: string, filter?: (q: any) => any) {
  let q: any = supabase.from(table).select(cols);
  if (filter) q = filter(q);
  const { data, error } = await q;
  if (error) throw error;
  return (data ?? []) as any[];
}

const one = (v: any) => (Array.isArray(v) ? v[0] : v); // embedded relations can come back as object or array

/** Runs one section; on failure returns the demo value and records it. */
async function section<K extends keyof typeof DEMO>(
  key: K, run: () => Promise<(typeof DEMO)[K]>, demoList: string[],
): Promise<(typeof DEMO)[K]> {
  try {
    return await run();
  } catch (err) {
    console.warn(`[analytics] "${String(key)}" using demo data:`, err);
    demoList.push(String(key));
    return DEMO[key];
  }
}

export async function getAnalyticsData(): Promise<AnalyticsData> {
  if (!(await hasSession())) {
    return { ...DEMO, updatedAt: new Date().toISOString(), demoSections: Object.keys(DEMO) };
  }
  const demoSections: string[] = [];

  const [requestsByDistrict, volunteerParticipation, inventoryStock, donationsVsDistribution, kpis] =
    await Promise.all([
      section('requestsByDistrict', async () => {
        const r = await rows('requests', 'districts(name)', (q) => q.gte('created_at', since(30)));
        const p = tally(r, (x) => one(x.districts)?.name ?? 'Unknown', 4);
        if (!p.length) throw new Error('no rows');
        return p;
      }, demoSections),

      section('volunteerParticipation', async () => {
        const r = await rows('profiles', 'volunteer_type', (q) => q.eq('role', 'volunteer'));
        const p = tally(r, (x) => (x.volunteer_type ? volunteerLabel(x.volunteer_type) : undefined));
        if (!p.length) throw new Error('no rows');
        return p;
      }, demoSections),

      section('inventoryStock', async () => {
        const lots = await rows('inventory_lots', 'item_type, quantity, reserved_qty', (q) => q.in('phase', IN_STOCK_PHASES));
        const m = new Map<string, number>();
        lots.forEach((l) => m.set(l.item_type, (m.get(l.item_type) ?? 0) + (Number(l.quantity) || 0) - (Number(l.reserved_qty) || 0)));
        if (!m.size) throw new Error('no rows');
        return [...m].sort((a, b) => b[1] - a[1]).slice(0, 5).map(([k, v]) => ({ label: humanize(k), value: Math.round(v) }));
      }, demoSections),

      // donated = stock received, distributed = stock dispatched or consumed (kg lots only)
      section('donationsVsDistribution', async () => {
        const mv = (await rows('inventory_movements', 'quantity, to_phase, created_at, inventory_lots(unit)', (q) => q.gte('created_at', since(21))))
          .filter((r) => one(r.inventory_lots)?.unit === 'kg');
        const out: ChartPoint[] = [];
        for (let w = 3; w >= 1; w--) {
          const from = Date.now() - w * 7 * DAY, to = from + 7 * DAY;
          const inWeek = (r: any) => { const t = +new Date(r.created_at); return t >= from && t < to; };
          const total = (phases: string[]) => Math.round(mv.filter((r) => inWeek(r) && phases.includes(r.to_phase)).reduce((s, r) => s + (Number(r.quantity) || 0), 0));
          const n = 4 - w;
          out.push({ label: 'Don', value: total(['received']), hint: `Week ${n} donated (kg)` });
          out.push({ label: 'Dist', value: total(OUTGOING_PHASES), hint: `Week ${n} distributed (kg)` });
        }
        return out;
      }, demoSections),

      section('kpis', async () => {
        const [fulfilled, approvals, asg] = await Promise.all([
          rows('requests', 'district_id', (q) => q.eq('status', 'fulfilled')),
          rows('requests', 'created_at, approved_at', (q) => q.not('approved_at', 'is', null).gte('created_at', since(30))),
          rows('assignments', 'state'),
        ]);
        const delivered = asg.filter((a) => a.state === 'delivered').length;
        const failed = asg.filter((a) => ['disputed', 'cancelled'].includes(a.state)).length;
        const hrs = approvals.map((r) => (+new Date(r.approved_at) - +new Date(r.created_at)) / 36e5);
        return {
          peopleSupported: fulfilled.length, // proxy: no people_count column yet
          districtsCovered: new Set(fulfilled.map((r) => r.district_id).filter((d) => d != null)).size,
          volunteerHours: null as any, // not tracked in the schema yet
          volunteerHoursChangePct: null,
          deliverySuccessPct: delivered + failed ? Math.round((delivered / (delivered + failed)) * 1000) / 10 : 0,
          completedJobs: delivered,
          avgApprovalHours: hrs.length ? Math.round((hrs.reduce((a, b) => a + b, 0) / hrs.length) * 10) / 10 : 0,
          avgApprovalChangeMin: null,
        };
      }, demoSections),
    ]);

  return {
    kpis, donationsVsDistribution, volunteerParticipation, inventoryStock, requestsByDistrict,
    updatedAt: new Date().toISOString(), demoSections,
  };
}