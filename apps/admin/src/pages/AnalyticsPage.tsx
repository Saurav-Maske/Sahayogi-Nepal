import BarChart from '../components/dashboard/BarChart';
import QuickAction from '../components/dashboard/QuickAction';
import StatCard from '../components/dashboard/StatCard';
import { useAnalytics } from '../hooks/useAnalytics';
import type { AnalyticsData } from '../types/analytics';

const time = (iso: string) =>
  new Date(iso).toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' });

const trend = (value: number | null, suffix: string, goodWhenUp = true) => {
  if (value === null) return { note: '', tone: 'good' as const };
  const up = value >= 0;
  return {
    note: `${up ? '↑' : '↓'} ${Math.abs(value)}${suffix}`,
    tone: (up === goodWhenUp ? 'good' : 'bad') as 'good' | 'bad',
  };
};

function exportCsv(d: AnalyticsData) {
  const rows: (string | number)[][] = [['section', 'label', 'value']];
  const add = (name: string, pts: { label: string; hint?: string; value: number }[]) =>
    pts.forEach((p) => rows.push([name, p.hint ?? p.label, p.value]));
  add('Donations vs distribution (kg)', d.donationsVsDistribution);
  add('Volunteer participation', d.volunteerParticipation);
  add('Inventory stock distribution', d.inventoryStock);
  add('Requests by district', d.requestsByDistrict);
  const csv = rows.map((r) => r.map((c) => `"${String(c).replace(/"/g, '""')}"`).join(',')).join('\n');
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob([csv], { type: 'text/csv' }));
  a.download = `sahayogi-analytics-${new Date().toISOString().slice(0, 10)}.csv`;
  a.click();
  URL.revokeObjectURL(a.href);
}

export default function AnalyticsPage() {
  const { data, loading, error, reload } = useAnalytics();

  if (error && !data) return <div className="table-msg"><p className="auth-error" role="alert">Couldn’t load analytics: {error}</p><button className="btn" onClick={reload}>Try again</button></div>;

  if (loading || !data) {
    return (
      <div className="skeleton-wrap" aria-busy="true" aria-live="polite">
        <div className="skeleton skeleton--title" />
        <div className="grid-stats">
          {Array.from({ length: 4 }, (_, i) => <div key={i} className="skeleton skeleton--card" />)}
        </div>
      </div>
    );
  }

  const { kpis: k } = data;
  const caption = (range: string) => `${range} · Updated ${time(data.updatedAt)} NPT`;
  const vh = trend(k.volunteerHoursChangePct, '% this month');
  const ap = trend(k.avgApprovalChangeMin, ' min this month', false);

  return (
    <>
      <div className="page__head">
        <div>
          <h1>Analytics &amp; impact</h1>
          <p className="crumbs">Sahayogi Nepal / Analytics / All districts</p>
        </div>
        <div className="page__actions">
          <button className="btn btn--ghost" onClick={() => exportCsv(data)}>Export CSV</button>
          <QuickAction />
        </div>
      </div>

      <div className="grid-stats">
        <StatCard to="/requests?status=fulfilled" label="Fulfilled requests" value={k.fulfilledRequests}
          note={`Across ${k.districtsCovered} districts`} />
        <StatCard to="/volunteers" label="Volunteer hours" value={k.volunteerHours ?? '—'}
          note={vh.note || (k.volunteerHours === null ? 'Not tracked yet' : 'All time')} tone={vh.tone} />
        <StatCard to="/assignments" label="Delivery success" value={k.deliverySuccessPct === null ? '—' : `${k.deliverySuccessPct}%`}
          note={k.deliverySuccessPct === null ? 'No delivery outcomes in backend data' : `Across ${k.completedJobs} completed or failed jobs`} />
        <StatCard to="/requests" label="Average approval" value={k.avgApprovalHours === null ? '—' : `${k.avgApprovalHours} hrs`}
          note={k.avgApprovalHours === null ? 'No approved requests in backend data' : ap.note || 'Request to approval'} tone={ap.tone} />
      </div>

      <div className="grid-charts">
        <BarChart title="Stock receipts and distribution · kg" points={data.donationsVsDistribution}
          caption={caption('Last 3 weeks')} />
        <BarChart title="Volunteers by category" points={data.volunteerParticipation}
          caption={caption('Current volunteer profiles')} />
        <BarChart title="Inventory stock distribution" points={data.inventoryStock}
          caption={caption('Current stock')} />
        <BarChart title="Requests by district" points={data.requestsByDistrict}
          caption={caption('Last 30 days')} />
      </div>

      <aside className="note">
        <h2 className="note__title">Reporting definitions</h2>
        <p>Only verified deliveries count as fulfilled. Quantity adjustments remain in the audit trail.</p>
      </aside>
    </>
  );
}
