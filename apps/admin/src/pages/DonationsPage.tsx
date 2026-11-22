import { useEffect, useState } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import QuickAction from '../components/dashboard/QuickAction';
import DatePicker from '../components/fields/DatePicker';
import Pagination from '../components/requests/Pagination';
import StatusBadge from '../components/requests/StatusBadge';
import { useDonationList } from '../hooks/useDonations';
import { getDonationDistricts, getDonationItemTypes } from '../services/donationsService';
import type { DonationFilters, DonationTab } from '../types/donations';
import type { District } from '../types/requests';
import { humanize } from '../utils/labels';
import { DONATION_STATUS_LABEL, DONATION_TABS, categoryOf, isFinalDonation, itemLabel } from '../utils/donations';
import { PAGE_SIZE, fmtDate } from '../utils/requests';
import '../styles/requests.css';

export default function DonationsPage() {
  const [params, setParams] = useSearchParams();
  const [districts, setDistricts] = useState<District[]>([]);
  const [itemTypes, setItemTypes] = useState<string[]>([]);

  const tabParam = params.get('status') ?? 'all';
  const filters: DonationFilters = {
    tab: (DONATION_TABS.some((t) => t.key === tabParam) ? tabParam : 'all') as DonationTab,
    q: params.get('q') ?? '',
    districtId: params.get('district') ? Number(params.get('district')) : null,
    itemType: params.get('item') ?? '',
    from: params.get('from') ?? '',
    to: params.get('to') ?? '',
    page: Math.max(1, Number(params.get('page')) || 1),
  };

  const update = (patch: Record<string, string | null>) => {
    const next = new URLSearchParams(params);
    Object.entries(patch).forEach(([k, v]) => (v ? next.set(k, v) : next.delete(k)));
    if (!('page' in patch)) next.delete('page');
    setParams(next, { replace: true });
  };

  const { data, loading, error, reload } = useDonationList(filters);

  useEffect(() => {
    getDonationDistricts().then(setDistricts).catch(() => setDistricts([]));
    getDonationItemTypes().then(setItemTypes).catch(() => setItemTypes([]));
  }, []);

  const [search, setSearch] = useState(filters.q);
  useEffect(() => setSearch(filters.q), [filters.q]);
  useEffect(() => {
    if (search === filters.q) return;
    const t = setTimeout(() => update({ q: search.trim() || null }), 300);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [search]);

  const hasFilters = !!(filters.q || filters.districtId || filters.itemType || filters.from || filters.to);
  const count = (key: DonationTab) =>
    key === 'all' ? data?.allTotal
      : key === 'pending' ? data?.pendingTotal
        : key === 'in_progress' ? data?.inProgressTotal
          : undefined;

  return (
    <>
      <div className="page__head">
        <div>
          <h1>Donation management</h1>
          <p className="crumbs">Sahayogi Nepal / Donations / All districts</p>
        </div>
        <div className="page__actions">
          <QuickAction />
        </div>
      </div>

      <div className="card tabs" role="tablist">
        {DONATION_TABS.map((t) => (
          <button key={t.key} role="tab" aria-selected={filters.tab === t.key}
            className={`tabs__tab ${filters.tab === t.key ? 'is-active' : ''}`}
            onClick={() => update({ status: t.key === 'all' ? null : t.key })}>
            {t.label}{count(t.key) != null && <span className="tabs__count"> {count(t.key)!.toLocaleString('en-US')}</span>}
          </button>
        ))}
      </div>

      <div className="filters">
        <input className="filters__field filters__search" placeholder="Search ref, donor or phone" aria-label="Search donations"
          value={search} onChange={(e) => setSearch(e.target.value)} />
        <select className="filters__field" aria-label="District" value={filters.districtId ?? ''} onChange={(e) => update({ district: e.target.value || null })}>
          <option value="">District: All</option>
          {districts.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
        </select>
        <select className="filters__field" aria-label="Category" value={filters.itemType} onChange={(e) => update({ item: e.target.value || null })}>
          <option value="">Category: All</option>
          {itemTypes.map((t) => <option key={t} value={t}>{humanize(t)}</option>)}
        </select>
        <div className="filters__dates">
          <DatePicker label="Start date" value={filters.from} max={filters.to || undefined} onChange={(value) => update({ from: value || null })}/>
          <DatePicker label="End date" value={filters.to} min={filters.from || undefined} onChange={(value) => update({ to: value || null })}/>
        </div>
      </div>

      <div className="card table-card" aria-busy={loading}>
        {error ? (
          <div className="table-msg">
            <p className="auth-error" role="alert">Couldn't load donations: {error}</p>
            <button className="btn" onClick={reload}>Try again</button>
          </div>
        ) : (
          <div className="table-scroll">
            <table className="table">
              <thead>
                <tr>
                  <th>Donation ID</th><th>Donor / contact</th><th>Category</th><th>Item / quantity</th>
                  <th>Pickup district</th><th>Submitted</th><th>Status</th><th>Action</th>
                </tr>
              </thead>
              <tbody className={loading ? 'is-loading' : ''}>
                {data?.rows.map((d) => (
                  <tr key={d.id}>
                    <td className="table__ref">{d.publicRef}</td>
                    <td>{d.donorName}<br /><span className="table__sub">{d.donorPhone}</span></td>
                    <td>{categoryOf(d)}</td>
                    <td>
                      {d.items.slice(0, 2).map((i) => <div key={i.id}>{itemLabel(i, i.offeredQty)}</div>)}
                      {d.items.length > 2 && <span className="table__sub">+{d.items.length - 2} more</span>}
                      {d.items.length === 0 && '—'}
                    </td>
                    <td>{d.district}</td>
                    <td>{fmtDate(d.createdAt)}</td>
                    <td><StatusBadge status={d.status} labels={DONATION_STATUS_LABEL} /></td>
                    <td><Link className="link" to={`/donations/${d.id}`}>{isFinalDonation(d.status) ? 'View →' : 'Review →'}</Link></td>
                  </tr>
                ))}
              </tbody>
            </table>
            {!loading && data?.rows.length === 0 && (
              <div className="table-msg">
                <p className="empty">No donations match these filters.</p>
                {hasFilters && <button className="btn" onClick={() => setParams(filters.tab === 'all' ? {} : { status: filters.tab })}>Clear filters</button>}
              </div>
            )}
            {loading && !data && <p className="empty table-msg">Loading donations…</p>}
          </div>
        )}
      </div>

      {data && <Pagination page={filters.page} total={data.total} pageSize={PAGE_SIZE} noun="donations" onPage={(p) => update({ page: String(p) })} />}

      <aside className="note">
        <h2 className="note__title">Accepted and collected quantities are separate</h2>
        <p>Donors may update actual quantities before the driver verifies the pickup OTP.</p>
      </aside>
    </>
  );
}
