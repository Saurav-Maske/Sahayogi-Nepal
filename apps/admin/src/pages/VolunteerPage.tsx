import { useEffect, useState } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import QuickAction from '../components/dashboard/QuickAction';
import Pagination from '../components/requests/Pagination';
import { useVolunteerList } from '../hooks/useVolunteers';
import type { VolunteerFilters, VolunteerTab } from '../types/volunteers';
import { PAGE_SIZE, fmtDate } from '../utils/requests';
import { CATEGORY_OPTIONS, DAY_OPTIONS, VOLUNTEER_TABS, categoryInfo, documentsReady, isSuspended } from '../utils/volunteers';
import '../styles/requests.css';

export default function VolunteersPage() {
  const [params, setParams] = useSearchParams();

  // the tab lives in ?status=; the Quick action link (?tab=applications) simply opens the default Pending tab
  const raw = params.get('status') ?? 'pending';
  const filters: VolunteerFilters = {
    tab: (VOLUNTEER_TABS.some((t) => t.key === raw) ? raw : 'pending') as VolunteerTab,
    q: params.get('q') ?? '',
    category: params.get('category') ?? '',
    days: params.get('days') ?? '',
    page: Math.max(1, Number(params.get('page')) || 1),
  };

  const update = (patch: Record<string, string | null>) => {
    const next = new URLSearchParams(params);
    next.delete('tab');
    Object.entries(patch).forEach(([k, v]) => (v ? next.set(k, v) : next.delete(k)));
    if (!('page' in patch)) next.delete('page');
    if (!next.get('status')) next.set('status', filters.tab); // keep the tab when other filters change
    setParams(next, { replace: true });
  };

  const { data, loading, error, reload } = useVolunteerList(filters);

  const [search, setSearch] = useState(filters.q);
  useEffect(() => setSearch(filters.q), [filters.q]);
  useEffect(() => {
    if (search === filters.q) return;
    const t = setTimeout(() => update({ q: search.trim() || null }), 300);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [search]);

  const hasFilters = !!(filters.q || filters.category || filters.days);
  const count = (k: VolunteerTab) => (k === 'pending' ? data?.pendingTotal : k === 'approved' ? data?.approvedTotal : undefined);

  return (
    <>
      <div className="page__head">
        <div>
          <h1>Volunteer management</h1>
          <p className="crumbs">Sahayogi Nepal / Volunteer Management / All districts</p>
        </div>
        <div className="page__actions">
          <QuickAction />
        </div>
      </div>

      <div className="card tabs" role="tablist">
        {VOLUNTEER_TABS.map((t) => (
          <button key={t.key} role="tab" aria-selected={filters.tab === t.key}
            className={`tabs__tab ${filters.tab === t.key ? 'is-active' : ''}`} onClick={() => update({ status: t.key })}>
            {t.label}{count(t.key) != null && <span className="tabs__count"> {count(t.key)!.toLocaleString('en-US')}</span>}
          </button>
        ))}
      </div>

      <div className="filters">
        <input className="filters__field filters__search" placeholder="Search name, email or phone" aria-label="Search volunteers"
          value={search} onChange={(e) => setSearch(e.target.value)} />
        <select className="filters__field" aria-label="District filter unavailable" disabled title="Volunteer records are not linked to districts in the backend.">
          <option>District: All</option>
        </select>
        <select className="filters__field" aria-label="Category" value={filters.category} onChange={(e) => update({ category: e.target.value || null })}>
          <option value="">Category: All</option>
          {CATEGORY_OPTIONS.map((c) => <option key={c.value} value={c.value}>{c.label}</option>)}
        </select>
        <select className="filters__field" aria-label="Applied" value={filters.days} onChange={(e) => update({ days: e.target.value || null })}>
          {DAY_OPTIONS.map((d) => <option key={d.value} value={d.value}>{d.label}</option>)}
        </select>
      </div>
      <p className="volunteer-district-note">District filtering is unavailable because volunteer records are not linked to districts in the backend.</p>

      <div className="card table-card" aria-busy={loading}>
        {error ? (
          <div className="table-msg">
            <p className="auth-error" role="alert">Couldn't load volunteers: {error}</p>
            <button className="btn" onClick={reload}>Try again</button>
          </div>
        ) : (
          <div className="table-scroll">
            <table className="table">
              <thead>
                <tr><th>Name</th><th>Email</th><th>Phone</th><th>Category</th><th>Applied</th><th>Verification</th><th>Action</th></tr>
              </thead>
              <tbody className={loading ? 'is-loading' : ''}>
                {data?.rows.map((v) => {
                  const c = categoryInfo(v.volunteerType);
                  const ready = documentsReady(v);
                  return (
                    <tr key={v.id}>
                      <td className="table__ref">{v.fullName}</td>
                      <td>{v.email}</td>
                      <td>{v.phone}</td>
                      <td>{c.name} / {c.perms}</td>
                      <td>{fmtDate(v.createdAt)}</td>
                      <td>
                        {isSuspended(v) ? <span className="badge badge--bad">Suspended</span>
                          : <span className={`badge badge--${ready ? 'good' : 'warn'}`}>{ready ? 'Documents ready' : 'Documents missing'}</span>}
                      </td>
                      <td><Link className="link" to={`/volunteers/${v.id}`}>{filters.tab === 'pending' ? 'Review →' : 'View →'}</Link></td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
            {!loading && data?.rows.length === 0 && (
              <div className="table-msg">
                <p className="empty">No volunteers here yet.</p>
                {hasFilters && <button className="btn" onClick={() => setParams({ status: filters.tab })}>Clear filters</button>}
              </div>
            )}
            {loading && !data && <p className="empty table-msg">Loading volunteers…</p>}
          </div>
        )}
      </div>

      {data && <Pagination page={filters.page} total={data.total} pageSize={PAGE_SIZE} noun="volunteers" onPage={(p) => update({ page: String(p) })} />}

      <aside className="note">
        <h2 className="note__title">Permission categories</h2>
        <p>A: Manpower · B: Driver (A + B) · C: Healthcare (A + C). Specialist work is sent only to eligible volunteers.</p>
      </aside>
    </>
  );
}
