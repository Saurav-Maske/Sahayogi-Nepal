import { useEffect, useState } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import QuickAction from '../components/dashboard/QuickAction';
import EmptyState from '../components/feedback/EmptyState';
import DatePicker from '../components/fields/DatePicker';
import Pagination from '../components/requests/Pagination';
import RequestDrawer from '../components/requests/RequestDrawer';
import StatusBadge from '../components/requests/StatusBadge';
import { useRequestList } from '../hooks/useRequests';
import { getDistricts } from '../services/requestsService';
import type { District, RequestFilters, TabKey } from '../types/requests';
import { KIND_LABELS, kindLabel } from '../utils/labels';
import { PAGE_SIZE, TABS, fmtDate, isPending, itemLabel } from '../utils/requests';
import '../styles/requests.css';

export default function RequestsPage() {
  const [params, setParams] = useSearchParams();
  const [districts, setDistricts] = useState<District[]>([]);
  const [drawerId, setDrawerId] = useState<string | null>(null);

  // URL is the source of truth, so dashboard links like /requests?status=pending just work
  const tabParam = params.get('status') ?? (params.get('review') === 'pending' ? 'pending' : 'all');
  const filters: RequestFilters = {
    tab: (TABS.some((t) => t.key === tabParam) ? tabParam : 'all') as TabKey,
    q: params.get('q') ?? '',
    districtId: params.get('district') ? Number(params.get('district')) : null,
    kind: params.get('kind') ?? '',
    from: params.get('from') ?? '',
    to: params.get('to') ?? '',
    page: Math.max(1, Number(params.get('page')) || 1),
  };

  const update = (patch: Record<string, string | null>) => {
    const next = new URLSearchParams(params);
    if (params.get('review') === 'pending' && !params.get('status')) next.set('status', 'pending');
    next.delete('review');
    Object.entries(patch).forEach(([k, v]) => (v ? next.set(k, v) : next.delete(k)));
    if (!('page' in patch)) next.delete('page');
    setParams(next, { replace: true });
  };

  const { data, loading, error, reload } = useRequestList(filters);

  useEffect(() => { getDistricts().then(setDistricts).catch(() => setDistricts([])); }, []);

  // debounced search box, kept in sync with ?q= (the topbar search sets it too)
  const [search, setSearch] = useState(filters.q);
  useEffect(() => setSearch(filters.q), [filters.q]);
  useEffect(() => {
    if (search === filters.q) return;
    const t = setTimeout(() => update({ q: search.trim() || null }), 300);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [search]);

  const hasFilters = !!(filters.q || filters.districtId || filters.kind || filters.from || filters.to);
  const count = (key: TabKey) => (key === 'all' ? data?.allTotal : key === 'pending' ? data?.pendingTotal : undefined);

  return (
    <>
      <div className="page__head">
        <div>
          <h1>Request management</h1>
          <p className="crumbs">Sahayogi Nepal / Requests / All districts</p>
        </div>
        <div className="page__actions">
          <QuickAction />
        </div>
      </div>

      <div className="card tabs" role="tablist">
        {TABS.map((t) => (
          <button key={t.key} role="tab" aria-selected={filters.tab === t.key}
            className={`tabs__tab ${filters.tab === t.key ? 'is-active' : ''}`}
            onClick={() => update({ status: t.key === 'all' ? null : t.key })}>
            {t.label}{count(t.key) != null && <span className="tabs__count"> {count(t.key)!.toLocaleString('en-US')}</span>}
          </button>
        ))}
      </div>

      <div className="filters">
        <input className="filters__field filters__search" placeholder="Search ref, name or phone" aria-label="Search requests"
          value={search} onChange={(e) => setSearch(e.target.value)} />
        <select className="filters__field" aria-label="District" value={filters.districtId ?? ''}
          onChange={(e) => update({ district: e.target.value || null })}>
          <option value="">District: All</option>
          {districts.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
        </select>
        <select className="filters__field" aria-label="Category" value={filters.kind}
          onChange={(e) => update({ kind: e.target.value || null })}>
          <option value="">Category: All</option>
          {Object.entries(KIND_LABELS).map(([k, label]) => <option key={k} value={k}>{label}</option>)}
        </select>
        <div className="filters__dates">
          <DatePicker label="Start date" value={filters.from} max={filters.to || undefined} onChange={(value) => update({ from: value || null })}/>
          <DatePicker label="End date" value={filters.to} min={filters.from || undefined} onChange={(value) => update({ to: value || null })}/>
        </div>
      </div>

      <div className="card table-card" aria-busy={loading}>
        {error ? (
          <div className="table-msg">
            <p className="auth-error" role="alert">Couldn't load requests: {error}</p>
            <button className="btn" onClick={reload}>Try again</button>
          </div>
        ) : (
          <div className="table-scroll">
            <table className="table">
              <thead>
                <tr>
                  <th>Request ID</th><th>Requester / phone</th><th>Category</th><th>District</th>
                  <th>Requested items</th><th>Submitted</th><th>Status</th><th>Action</th>
                </tr>
              </thead>
              <tbody className={loading ? 'is-loading' : ''}>
                {data?.rows.map((r) => (
                  <tr key={r.id}>
                    <td className="table__ref">{r.publicRef}</td>
                    <td>{r.requesterName}<br /><span className="table__sub">{r.requesterPhone}</span></td>
                    <td>{kindLabel(r.kind)}</td>
                    <td>{r.district}</td>
                    <td>
                      {r.items.slice(0, 2).map((i) => <div key={i.id}>{itemLabel(i, i.requestedQty)}</div>)}
                      {r.items.length > 2 && <span className="table__sub">+{r.items.length - 2} more</span>}
                      {r.items.length === 0 && '—'}
                    </td>
                    <td>{fmtDate(r.createdAt)}</td>
                    <td><StatusBadge status={r.status} /></td>
                    <td>
                      {isPending(r.status)
                        ? <Link className="link" to={`/requests/${r.id}`}>Review →</Link>
                        : <button className="link" onClick={() => setDrawerId(r.id)}>View →</button>}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
            {!loading && data?.rows.length === 0 && <EmptyState
              title="No requests found"
              description={hasFilters ? 'No requests match the current filters. Adjust or clear the filters to see more results.' : 'New help requests will appear here when they are submitted.'}
              action={hasFilters && <button className="btn" onClick={() => setParams(filters.tab === 'all' ? {} : { status: filters.tab })}>Clear filters</button>}
            />}
            {loading && !data && <p className="empty table-msg">Loading requests…</p>}
          </div>
        )}
      </div>

      {data && <Pagination page={filters.page} total={data.total} pageSize={PAGE_SIZE} onPage={(p) => update({ page: String(p) })} />}
      {drawerId && <RequestDrawer id={drawerId} onClose={() => setDrawerId(null)} />}
    </>
  );
}
