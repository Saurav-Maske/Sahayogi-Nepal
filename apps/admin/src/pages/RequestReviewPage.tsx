import { useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import QuickAction from '../components/dashboard/QuickAction';
import AdminDialog from '../components/overlay/AdminDialog';
import FeedbackDialog from '../components/overlay/FeedbackDialog';
import StatusBadge from '../components/requests/StatusBadge';
import { useRequest } from '../hooks/useRequests';
import { offerRequestToVolunteers, reviewRequest } from '../services/requestsService';
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
  const { data, loading, error, reload } = useRequest(id);
  const r: ServiceRequest | undefined = data?.request;

  const [qtys, setQtys] = useState<Record<string, number>>({});
  const [notes, setNotes] = useState('');
  const [confirming, setConfirming] = useState<'approve' | 'decline' | null>(null);
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);
  const [distributionError, setDistributionError] = useState<string | null>(null);
  const [feedback, setFeedback] = useState<{ title: string; message: string } | null>(null);

  useEffect(() => {
    if (!r) return;
    setQtys(Object.fromEntries(r.items.map((i) => [i.id, i.approvedQty ?? maxFor(i)])));
  }, [r?.id, r?.status]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (!r || !isApproved(r.status)) return;
    let active = true;
    void offerRequestToVolunteers(r.id)
      .then(() => {
        if (active) setDistributionError(null);
        if (active && r.status === 'approved') reload();
      })
      .catch((e) => {
        if (active) setDistributionError(e instanceof Error ? e.message : 'Could not share this request with volunteers.');
      });
    return () => { active = false; };
  }, [r?.id, r?.status]);

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
  const needsItemQuantities = r.kind === 'resource_request' || r.kind === 'donation_offer';
  const canApprove = !busy && (!needsItemQuantities || total > 0);
  const title = pending ? 'Review request' : approved ? 'Request approved' : r.status === 'declined' ? 'Request declined' : 'Request';
  const itemSummary = r.items.map((item) => `${qtys[item.id] ?? 0} ${humanize(item.itemType)}`).join(' and ');

  const run = async (decision: 'approve' | 'decline') => {
    setBusy(true);
    setActionError(null);
    try {
      await reviewRequest(r.id, decision, r.items.map((i) => ({ item_id: i.id, qty: qtys[i.id] ?? 0 })), decision === 'decline' ? reason.trim() : notes.trim());
      setDistributionError(null);
      if (decision === 'approve') {
        try { await offerRequestToVolunteers(r.id); }
        catch (e) { setDistributionError(e instanceof Error ? e.message : 'Could not share this request with volunteers.'); }
      }
      setConfirming(null);
      setFeedback({ title: decision === 'approve' ? 'Request approved' : 'Request declined', message: decision === 'approve'
        ? `${r.publicRef} · ${r.requesterName}. Eligible volunteers can claim the request in the mobile app.`
        : `${r.publicRef} · ${r.requesterName}. The request status has been updated.` });
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
          <p className="card__sub">{needsItemQuantities ? 'Approved quantities cannot exceed available stock.' : 'This request does not require inventory quantities.'}</p>

          {r.items.length === 0 && <p className="empty">{needsItemQuantities ? 'This request has no item quantities to review.' : 'No item quantities are required for this request.'}</p>}
          {r.items.map((i) => (
            <Stepper key={i.id} item={i} value={qtys[i.id] ?? 0} editable={pending} onChange={(v) => setQtys((q) => ({ ...q, [i.id]: v }))} />
          ))}

          {pending && (
            <label className="qty review__notes">
            <textarea rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="e.g. Prioritise delivery before 16:00 today." />
            </label>
          )}

          {r.status === 'declined' && r.declineReason && <div className="callout callout--bad"><strong>Decline reason</strong><p>{r.declineReason}</p></div>}

          <div className="callout">
            <strong>Approval does not dispatch stock</strong>
            <p>Approved quantities are reserved when applicable. Eligible volunteers receive the request and claim it themselves; dispatch is recorded through the audited inventory workflow.</p>
          </div>

          {approved && (
            <div className={distributionError ? 'callout callout--bad' : 'callout'} role={distributionError ? 'alert' : undefined}>
              <strong>{distributionError ? 'Could not share with volunteers' : 'Volunteer distribution'}</strong>
              <p>{distributionError ?? 'Volunteers choose and accept their own offers; administrators do not select an individual volunteer.'}</p>
              {distributionError && <button className="btn" disabled={busy} onClick={() => {
                setBusy(true);
                void offerRequestToVolunteers(r.id).then(() => { setDistributionError(null); reload(); })
                  .catch((e) => setDistributionError(e instanceof Error ? e.message : 'Could not share this request with volunteers.'))
                  .finally(() => setBusy(false));
              }}>Retry sharing</button>}
            </div>
          )}

          <div className="review__actions">
            {pending && (
              <>
                <button className="btn btn--primary" disabled={!canApprove} onClick={() => { setActionError(null); setConfirming('approve'); }}>Approve request</button>
                <button className="btn btn--danger" disabled={busy} onClick={() => { setActionError(null); setConfirming('decline'); }}>Decline</button>
              </>
            )}
            {!pending && <Link className="btn" to="/requests">Back to requests</Link>}
          </div>
        </section>
      </div>
      <AdminDialog
        open={confirming !== null}
        title={confirming === 'approve' ? `Approve request ${r.publicRef}?` : 'Decline this request?'}
        description={confirming === 'approve'
          ? `${r.requesterName}${itemSummary ? ` · ${itemSummary}` : ''}. Approval does not reserve or dispatch stock.`
          : 'A clear reason is required and will be shared with the requester.'}
        onClose={() => !busy && setConfirming(null)}
        actions={confirming === 'approve' ? [
          { label: busy ? 'Approving…' : 'Approve request', variant: 'primary', disabled: !canApprove, onClick: () => void run('approve') },
          { label: 'Cancel', onClick: () => setConfirming(null), disabled: busy },
        ] : confirming === 'decline' ? [
          { label: busy ? 'Declining…' : 'Decline request', variant: 'danger', disabled: busy || reason.trim().length < 2, onClick: () => void run('decline') },
          { label: 'Cancel', onClick: () => setConfirming(null), disabled: busy },
        ] : []}
      >
        {confirming === 'decline' && <label className="admin-dialog__field"><span>Decline reason</span><textarea rows={3} value={reason} onChange={(event) => setReason(event.target.value)} autoFocus/><small>Required · Keep the reason concise and respectful.</small></label>}
        {actionError && <p className="admin-dialog__error" role="alert">{actionError}</p>}
      </AdminDialog>
      <FeedbackDialog feedback={feedback} onClose={() => setFeedback(null)} />
    </>
  );
}
