import { useEffect, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import QuickAction from '../components/dashboard/QuickAction';
import StatusBadge from '../components/requests/StatusBadge';
import { useRequest } from '../hooks/useRequests';
import { reviewRequest } from '../services/requestsService';
import type { RequestItem, ServiceRequest } from '../types/requests';
import { humanize, kindLabel } from '../utils/labels';
import { buildHistory, fmtDate, fmtTime, isApproved, isPending } from '../utils/requests';
import '../styles/requests.css';

const maxFor = (i: RequestItem) => (i.available == null ? i.requestedQty : Math.max(0, Math.min(i.requestedQty, i.available)));

function Stepper({ item, value, editable, onChange }: { item: RequestItem; value: number; editable: boolean; onChange: (v: number) => void }) {
  const max = maxFor(item);
  const set = (v: number) => onChange(Math.min(max, Math.max(0, Number.isFinite(v) ? v : 0)));
  return (
    <div className="qty">
      <p className="qty__title">{humanize(item.itemType)} · requested {item.requestedQty} {item.unit}</p>
      <div className="qty__row">
        {editable ? (
          <>
            <input type="number" min={0} max={max} value={value} aria-label={`Approved ${item.itemType} quantity`}
              onChange={(e) => set(Number(e.target.value))} />
            <span>{item.unit}</span>
            <span className="qty__btns">
              <button type="button" aria-label="Decrease" onClick={() => set(value - 1)} disabled={value <= 0}>−</button>
              <button type="button" aria-label="Increase" onClick={() => set(value + 1)} disabled={value >= max}>+</button>
            </span>
          </>
        ) : (
          <span>{item.approvedQty ?? 0} {item.unit} approved</span>
        )}
      </div>
      {item.available != null && (
        <p className={`qty__hint ${item.available < item.requestedQty ? 'qty__hint--warn' : ''}`}>
          Central inventory available: {item.available} {item.unit}
          {item.available < item.requestedQty && ' — less than requested'}
        </p>
      )}
    </div>
  );
}

export default function RequestReviewPage() {
  const { id = '' } = useParams();
  const navigate = useNavigate();
  const { data, loading, error, reload } = useRequest(id);
  const r: ServiceRequest | undefined = data?.request;

  const [qtys, setQtys] = useState<Record<string, number>>({});
  const [notes, setNotes] = useState('');
  const [declining, setDeclining] = useState(false);
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);

  useEffect(() => {
    if (!r) return;
    setQtys(Object.fromEntries(r.items.map((i) => [i.id, i.approvedQty ?? maxFor(i)])));
  }, [r?.id, r?.status]); // eslint-disable-line react-hooks/exhaustive-deps

  if (loading && !r) return <div className="skeleton-wrap" aria-busy="true"><div className="skeleton skeleton--title" /><div className="skeleton" style={{ height: 320 }} /></div>;
  if (error || !r) {
    return (
      <div className="card table-msg">
        <p className="auth-error" role="alert">{error ?? 'Request not found.'}</p>
        <Link className="btn" to="/requests">Back to requests</Link>
      </div>
    );
  }

  const pending = isPending(r.status);
  const approved = isApproved(r.status);
  const total = r.items.reduce((s, i) => s + (qtys[i.id] ?? 0), 0);
  const title = pending ? 'Review request' : approved ? 'Request approved' : r.status === 'declined' ? 'Request declined' : 'Request';

  const run = async (decision: 'approve' | 'decline') => {
    setBusy(true);
    setActionError(null);
    try {
      await reviewRequest(r.id, decision, r.items.map((i) => ({ item_id: i.id, qty: qtys[i.id] ?? 0 })), decision === 'decline' ? reason.trim() : notes.trim());
      setDeclining(false);
      reload();
    } catch (e: any) {
      setActionError(e?.message ?? 'Something went wrong. Please try again.');
    } finally {
      setBusy(false);
    }
  };

  const stamp = pending ? `Submitted ${fmtDate(r.createdAt)} at ${fmtTime(r.createdAt)} · Pending approval`
    : r.approvedAt && approved ? `Approved ${fmtDate(r.approvedAt)} at ${fmtTime(r.approvedAt)} · Stock not yet reserved`
    : `Submitted ${fmtDate(r.createdAt)} at ${fmtTime(r.createdAt)}`;

  return (
    <>
      <div className="page__head">
        <div>
          <h1>{title} · {r.publicRef}</h1>
          <p className="crumbs"><Link to="/requests">Requests</Link> / {r.publicRef} / {r.district} district</p>
        </div>
        <div className="page__actions"><QuickAction /></div>
      </div>

      <div className="review">
        <section className="card">
          <div className="review__name"><h2 className="card__title">{r.requesterName}</h2><StatusBadge status={r.status} /></div>
          <p className="card__sub">{stamp}</p>
          <dl className="review__facts">
            <div><dt>Phone</dt><dd>{r.requesterPhone}</dd></div>
            <div><dt>District</dt><dd>{r.district}{r.addressNote ? ` · ${r.addressNote}` : ''}</dd></div>
            <div><dt>Category</dt><dd>{kindLabel(r.kind)}</dd></div>
            {r.urgency && <div><dt>Urgency</dt><dd>{humanize(r.urgency)}</dd></div>}
          </dl>

          <div className="callout">
            <strong>Restricted location</strong>
            <p>Exact delivery address is visible only to authorised staff and the assigned driver.</p>
          </div>

          <h3 className="review__sub">Request history</h3>
          <ul className="timeline">
            {buildHistory(r).map((h, i) => (
              <li key={i} className={h.done ? 'is-done' : ''}>
                <strong>{h.title}</strong>
                {h.detail && <p>{h.detail}</p>}
                {h.at && <time>{fmtDate(h.at)} · {fmtTime(h.at)}</time>}
              </li>
            ))}
          </ul>
        </section>

        <section className="card">
          <h2 className="card__title">{pending ? 'Review approved quantities' : 'Approved quantities'}</h2>
          <p className="card__sub">Approved quantities cannot exceed available stock.</p>

          {r.items.length === 0 && <p className="empty">This request has no items.</p>}
          {r.items.map((i) => (
            <Stepper key={i.id} item={i} value={qtys[i.id] ?? 0} editable={pending} onChange={(v) => setQtys((q) => ({ ...q, [i.id]: v }))} />
          ))}

          {pending && (
            <label className="qty">
              <span className="qty__title">Approval notes</span>
              <textarea rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="e.g. Prioritise delivery before 16:00 today." />
              <span className="qty__hint">Visible to coordinating administrators</span>
            </label>
          )}

          {r.status === 'declined' && r.declineReason && <div className="callout callout--bad"><strong>Decline reason</strong><p>{r.declineReason}</p></div>}

          <div className="callout">
            <strong>Approval does not dispatch stock</strong>
            <p>Reserve and record an inventory movement when an assignment is confirmed.</p>
          </div>

          {declining && (
            <label className="qty">
              <span className="qty__title">Reason for declining (required)</span>
              <textarea rows={2} value={reason} onChange={(e) => setReason(e.target.value)} autoFocus />
            </label>
          )}
          {actionError && <p className="auth-error" role="alert">{actionError}</p>}

          <div className="review__actions">
            {pending && !declining && (
              <>
                <button className="btn btn--primary" disabled={busy || total <= 0} onClick={() => run('approve')}>{busy ? 'Saving…' : 'Approve request'}</button>
                <button className="btn btn--danger" disabled={busy} onClick={() => setDeclining(true)}>Decline</button>
              </>
            )}
            {pending && declining && (
              <>
                <button className="btn btn--danger" disabled={busy || !reason.trim()} onClick={() => run('decline')}>{busy ? 'Saving…' : 'Confirm decline'}</button>
                <button className="btn" disabled={busy} onClick={() => setDeclining(false)}>Cancel</button>
              </>
            )}
            {approved && <button className="btn btn--primary" onClick={() => navigate(`/assignments?request=${r.id}`)}>Assign volunteer</button>}
            {!pending && <Link className="btn" to="/requests">Back to requests</Link>}
          </div>
        </section>
      </div>
    </>
  );
}
