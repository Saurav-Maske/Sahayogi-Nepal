import AttentionPanel from '../components/dashboard/AttentionPanel';
import QuickAction from '../components/dashboard/QuickAction';
import RecentActivity from '../components/dashboard/RecentActivity';
import StatCard from '../components/dashboard/StatCard';
import { useDashboard } from '../hooks/useDashboard';

export default function DashboardPage() {
  const { data, loading, error, reload } = useDashboard();

  if (error && !data) return <div className="table-msg"><p className="auth-error" role="alert">Couldn’t load the operations overview: {error}</p><button className="btn" onClick={reload}>Try again</button></div>;

  if (loading || !data) {
    return (
      <div className="skeleton-wrap" aria-busy="true" aria-live="polite">
        <div className="skeleton skeleton--title" />
        <div className="grid-stats">
          {Array.from({ length: 8 }, (_, i) => <div key={i} className="skeleton skeleton--card" />)}
        </div>
      </div>
    );
  }

  const { stats: s } = data;
  const change = s.totalRequestsChangePct;

  return (
    <>
      <div className="page__head">
        <div>
          <h1>Operations overview</h1>
          <p className="crumbs">Sahayogi Nepal / Overview / All districts</p>
        </div>
        <div className="page__actions">
          <QuickAction />
        </div>
      </div>

      <div className="grid-stats">
        <StatCard to="/requests" label="Total requests" value={s.totalRequests}
          note={`${change >= 0 ? '↑' : '↓'} ${Math.abs(change)}% from last month`} tone={change >= 0 ? 'good' : 'bad'} />
        <StatCard to="/requests?status=pending" label="Pending requests" value={s.pendingRequests}
          note={`${s.needReviewToday} require review today`} />
        <StatCard to="/requests?status=approved" label="Approved requests" value={s.approvedRequests}
          note="Ready for assignment" />
        <StatCard to="/requests?status=fulfilled" label="Fulfilled requests" value={s.fulfilledRequests}
          note={`${s.fulfilmentRatePct}% fulfilment rate`} />
        <StatCard to="/volunteers" label="Active volunteers" value={s.activeVolunteers}
          note={`Across ${s.volunteerCategories} categories`} />
        <StatCard to="/inventory" label="Available inventory" value={s.availableInventory}
          note={`Units across ${s.inventoryCategories} categories`} />
        <StatCard to="/assignments" label="Active assignments" value={s.activeAssignments}
          note={`${s.driversEnRoute} drivers en route`} />
        <StatCard to="/incidents" label="Open incidents" value={s.openIncidents}
          note={`${s.urgentIncidents} need urgent review`} tone={s.urgentIncidents > 0 ? 'bad' : 'good'} />
      </div>

      <div className="grid-bottom">
        <RecentActivity items={data.activity} />
        <AttentionPanel attention={data.attention} />
      </div>
    </>
  );
}
