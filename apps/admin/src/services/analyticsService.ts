import { supabase } from '../supabase';
import type { AnalyticsData } from '../types/analytics';
import type { ChartPoint } from '../types/dashboard';

/**
 * Names used for live queries. Only requests.district/status/created_at are
 * confirmed from the migration; the rest are guesses. Fix them here only.
 */
const T = {
  requests: 'requests', // district, status, created_at, approved_at?, people_count?
  donations: 'donations', // quantity_kg, status, created_at
  distributions: 'distributions', // quantity_kg, created_at
  volunteers: 'volunteers', // category, hours_logged, status
  assignments: 'assignments', // status
  inventory: 'central_inventory', // category, quantity
};

const DEMO: Omit<AnalyticsData, 'updatedAt' | 'demoSections'> = {
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

const tally = (rows: any[], key: string, top?: number): ChartPoint[] => {
  const m = new Map<string, number>();
  rows.forEach((r) => r[key] && m.set(r[key], (m.get(r[key]) ?? 0) + 1));
  const sorted = [...m].sort((a, b) => b[1] - a[1]).map(([label, value]) => ({ label, value }));
  if (!top || sorted.length <= top) return sorted;
  const rest = sorted.slice(top).reduce((s, p) => s + p.value, 0);
  return [...sorted.slice(0, top), { label: 'Other', value: rest }];
};

const sum = (rows: any[], key: string) => rows.reduce((s, r) => s + (Number(r[key]) || 0), 0);

async function rows(table: string, cols: string, days?: number) {
  let q: any = supabase.from(table).select(cols);
  if (days) q = q.gte('created_at', since(days));
  const { data, error } = await q;
  if (error) throw error;
  return (data ?? []) as any[];
}

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
  const demoSections: string[] = [];

  const [requestsByDistrict, volunteerParticipation, inventoryStock, donationsVsDistribution, kpis] =
    await Promise.all([
      section('requestsByDistrict', async () => {
        const p = tally(await rows(T.requests, 'district', 30), 'district', 4);
        if (!p.length) throw new Error('no rows');
        return p;
      }, demoSections),

      section('volunteerParticipation', async () => {
        const p = tally(await rows(T.volunteers, 'category'), 'category');
        if (!p.length) throw new Error('no rows');
        return p;
      }, demoSections),

      section('inventoryStock', async () => {
        const inv = await rows(T.inventory, 'category, quantity');
        const m = new Map<string, number>();
        inv.forEach((r) => m.set(r.category, (m.get(r.category) ?? 0) + (Number(r.quantity) || 0)));
        if (!m.size) throw new Error('no rows');
        return [...m].map(([label, value]) => ({ label, value }));
      }, demoSections),

      section('donationsVsDistribution', async () => {
        const [don, dist] = await Promise.all([rows(T.donations, 'quantity_kg, created_at', 21), rows(T.distributions, 'quantity_kg, created_at', 21)]);
        const out: ChartPoint[] = [];
        for (let w = 3; w >= 1; w--) {
          const from = Date.now() - w * 7 * DAY, to = from + 7 * DAY;
          const inWeek = (r: any) => { const t = +new Date(r.created_at); return t >= from && t < to; };
          const n = 4 - w;
          out.push({ label: 'Don', value: sum(don.filter(inWeek), 'quantity_kg'), hint: `Week ${n} donated (kg)` });
          out.push({ label: 'Dist', value: sum(dist.filter(inWeek), 'quantity_kg'), hint: `Week ${n} distributed (kg)` });
        }
        return out;
      }, demoSections),

      section('kpis', async () => {
        const [req, vol, asg] = await Promise.all([
          rows(T.requests, 'district, status, created_at, approved_at, people_count'),
          rows(T.volunteers, 'hours_logged'),
          rows(T.assignments, 'status'),
        ]);
        const fulfilled = req.filter((r) => r.status === 'fulfilled');
        const done = asg.filter((a) => a.status === 'completed').length;
        const failed = asg.filter((a) => a.status === 'failed').length;
        const approvals = req.filter((r) => r.approved_at).map((r) => (+new Date(r.approved_at) - +new Date(r.created_at)) / 36e5);
        return {
          peopleSupported: sum(fulfilled, 'people_count'),
          districtsCovered: new Set(fulfilled.map((r) => r.district)).size,
          volunteerHours: sum(vol, 'hours_logged'),
          volunteerHoursChangePct: null,
          deliverySuccessPct: done + failed ? Math.round((done / (done + failed)) * 1000) / 10 : 0,
          completedJobs: done,
          avgApprovalHours: approvals.length ? Math.round((approvals.reduce((a, b) => a + b, 0) / approvals.length) * 10) / 10 : 0,
          avgApprovalChangeMin: null,
        };
      }, demoSections),
    ]);

  return {
    kpis, donationsVsDistribution, volunteerParticipation, inventoryStock, requestsByDistrict,
    updatedAt: new Date().toISOString(), demoSections,
  };
}