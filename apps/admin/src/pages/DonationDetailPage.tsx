import { useEffect, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import QuickAction from '../components/dashboard/QuickAction';
import AdminDialog from '../components/overlay/AdminDialog';
import FeedbackDialog from '../components/overlay/FeedbackDialog';
import StatusBadge from '../components/requests/StatusBadge';
import { useDonation } from '../hooks/useDonations';
import { reviewDonation, saveAcceptedQuantities } from '../services/donationsService';
import { offerRequestToVolunteers } from '../services/requestsService';
import type { Donation, DonationItem } from '../types/donations';
import { humanize } from '../utils/labels';
import { DONATION_STATUS_LABEL, buildDonationHistory, canAdjustDonation, isFinalDonation, isPendingDonation } from '../utils/donations';
import { fmtDate, fmtTime } from '../utils/requests';
import '../styles/requests.css';

function QtyCard({ item, value, editable, onChange }: { item: DonationItem; value: number; editable: boolean; onChange: (v: number) => void }) {
  const set = (v: number) => onChange(Math.max(0, Number.isFinite(v) ? v : 0));
  return (
    <div className="qty">
      <p className="qty__title">{humanize(item.itemType)} · offered {item.offeredQty} {item.unit}</p>
      <div className="qty__row">
        {editable ? (
          <>
            <input type="number" min={0} value={value} aria-label={`Accepted ${item.itemType} quantity`} onChange={(e) => set(Number(e.target.value))} />
            <span>{item.unit} accepted</span>
            <span className="qty__btns">
            </span>
          </>
        ) : (
          <span>{item.acceptedQty ?? 0} {item.unit} accepted</span>
        )}
      </div>
    </div>
  );
}

function Records({ d }: { d: Donation }) {
  const awaiting = canAdjustDonation(d.status);
  return (
    <div className="records">
      {d.items.map((i) => (
        <div key={i.id} className="records__item">
          <strong>{humanize(i.itemType)}</strong>
          <p>Expected {i.offeredQty} {i.unit} · accepted {i.acceptedQty != null ? `${i.acceptedQty} ${i.unit}` : '—'}</p>
          {i.donorQty != null && <p>Donor updated actual: {i.donorQty} {i.unit}</p>}
          <p>Verified collected: {i.collectedQty != null ? `${i.collectedQty} ${i.unit}` : awaiting ? 'Awaiting OTP' : '—'}</p>
        </div>
      ))}
    </div>
  );
}

export default function DonationDetailPage() {
  const { id = '' } = useParams();
  const navigate = useNavigate();
  const { data, loading, error, reload } = useDonation(id);
  const d = data?.donation;

  const [qtys, setQtys] = useState<Record<string, number>>({});
  const [note, setNote] = useState('');
  const [confirming, setConfirming] = useState<'accept' | 'decline' | null>(null);
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);
  const [distributionError, setDistributionError] = useState<string | null>(null);
  const [feedback, setFeedback] = useState<{ title: string; message: string } | null>(null);

  useEffect(() => {
    if (d) setQtys(Object.fromEntries(d.items.map((i) => [i.id, i.acceptedQty ?? i.offeredQty])));
  }, [d?.id, d?.status]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (!d || !canAdjustDonation(d.status)) return;
    let active = true;
    void offerRequestToVolunteers(d.id)
      .then(() => {
        if (active) setDistributionError(null);
        if (active && d.status === 'approved') reload();
      })
      .catch((e) => {
        if (active) setDistributionError(e instanceof Error ? e.message : 'Could not share this donation with volunteers.');
      });
    return () => { active = false; };
  }, [d?.id, d?.status]);

  if (loading && !d) return <div className="skeleton-wrap" aria-busy="true"><div className="skeleton skeleton--title" /><div className="skeleton" style={{ height: 320 }} /></div>;
  if (error || !d) {
    return (
      <div className="card table-msg">
        <p className="auth-error" role="alert">{error ?? 'Donation not found.'}</p>
        <Link className="btn" to="/donations">Back to donations</Link>
      </div>
    );
  }

  const pending = isPendingDonation(d.status);
  const adjustable = canAdjustDonation(d.status);
  const items = d.items.map((i) => ({ item_id: i.id, qty: qtys[i.id] ?? 0 }));
  const total = items.reduce((s, i) => s + i.qty, 0);

  const acceptDonation = async () => {
    await reviewDonation(d.id, 'approve', items, note.trim());
    setDistributionError(null);
    try { await offerRequestToVolunteers(d.id); }
    catch (e) { setDistributionError(e instanceof Error ? e.message : 'Could not share this donation with volunteers.'); }
  };

  const run = async (fn: () => Promise<void>, done: string) => {
    setBusy(true); setActionError(null); setFeedback(null);
    try { await fn(); setConfirming(null); setFeedback({ title: done, message: `${d.publicRef} · ${d.donorName}. The donation record has been updated.` }); reload(); }
    catch (e: any) { setActionError(e?.message ?? 'Something went wrong. Please try again.'); }
    finally { setBusy(false); }
  };

  return (
    <>
      <div className="page__head">
        <div>
          <h1>Donation detail · {d.publicRef}</h1>
          <p className="crumbs"><Link to="/donations">Donations</Link> / {d.publicRef} / {d.district} district</p>
        </div>
        <div className="page__actions"><QuickAction /></div>
      </div>

      <div className="review">
        <section className="card">
          <div className="review__name"><h2 className="card__title">{d.donorName}</h2><StatusBadge status={d.status} labels={DONATION_STATUS_LABEL} /></div>
          <p className="card__sub">{d.donorPhone} · {d.district}</p>

          <dl className="review__facts">
            <div><dt>Pickup</dt><dd>{d.addressNote ?? 'Not provided'}</dd></div>
            {d.notes && <div><dt>Donor note</dt><dd>{d.notes}</dd></div>}
            <div><dt>Offered</dt><dd>{fmtDate(d.createdAt)} at {fmtTime(d.createdAt)}</dd></div>
          </dl>

          <div className="callout">
            <strong>Pickup location · authorised access</strong>
            <p>Exact address is only available to assigned drivers and administrators.</p>
          </div>

          <h3 className="review__sub">Assigned driver</h3>
          {d.driver ? (
            <p className="driver">
              <strong>{d.driver.name ?? 'Driver'}</strong>{d.driver.phone ? ` · ${d.driver.phone}` : ''}<br />
              <span className="table__sub">Assignment {d.driver.assignmentId.slice(0, 8).toUpperCase()} · {humanize(d.driver.state)}</span>
            </p>
          ) : <p className="empty">No driver assigned yet.</p>}

          <ul className="timeline donation-timeline">
            {buildDonationHistory(d).map((h, i) => (
              <li key={i} className={h.done ? 'is-done' : ''}>
                <strong>{h.title}</strong>
                {h.detail && <p>{h.detail}</p>}
                {h.at && <time>{fmtDate(h.at)} · {fmtTime(h.at)}</time>}
              </li>
            ))}
          </ul>
        </section>

        <section className="card">
          <h2 className="card__title">Item and quantity review</h2>
          <p className="card__sub">Expected, accepted and collected are separate records.</p>

          {d.items.length === 0 && <p className="empty">This donation has no items.</p>}
          {d.items.map((i) => (
            <QtyCard key={i.id} item={i} value={qtys[i.id] ?? 0} editable={pending || adjustable} onChange={(v) => setQtys((q) => ({ ...q, [i.id]: v }))} />
          ))}

          <Records d={d} />

          {!pending && !isFinalDonation(d.status) && (
            <div className={distributionError ? 'callout callout--bad' : 'callout'} role={distributionError ? 'alert' : undefined}>
              <strong>{distributionError ? 'Could not share with volunteers' : 'Volunteer distribution'}</strong>
              <p>{distributionError ?? 'Eligible volunteers can claim this pickup offer in the mobile app. Administrators do not choose an individual driver.'}</p>
              {distributionError && <button className="btn" disabled={busy} onClick={() => {
                setBusy(true);
                void offerRequestToVolunteers(d.id).then(() => { setDistributionError(null); reload(); })
                  .catch((e) => setDistributionError(e instanceof Error ? e.message : 'Could not share this donation with volunteers.'))
                  .finally(() => setBusy(false));
              }}>Retry sharing</button>}
            </div>
          )}

          {(pending || adjustable) && (
            <label className="qty">
              <textarea className="qty__textarea" rows={2} value={note} onChange={(e) => setNote(e.target.value)} placeholder="e.g. Confirm the actual pickup quantity with donor." />
            </label>
          )}

          {d.status === 'declined' && d.declineReason && <div className="callout callout--bad"><strong>Decline reason</strong><p>{d.declineReason}</p></div>}

          {actionError && !confirming && <p className="auth-error" role="alert">{actionError}</p>}

          <div className="review__actions">
            {pending && (
              <>
                <button className="btn btn--primary" disabled={busy || total <= 0}
                  onClick={() => { setActionError(null); setConfirming('accept'); }}>Accept donation</button>
                <button className="btn btn--danger" disabled={busy} onClick={() => { setActionError(null); setConfirming('decline'); }}>Decline</button>
              </>
            )}
            {adjustable && (
              <>
                <button className="btn btn--primary" disabled={busy}
                  onClick={() => run(() => saveAcceptedQuantities(d.id, items, note.trim()), 'Accepted quantity saved.')}>{busy ? 'Saving…' : 'Save accepted quantity'}</button>
                <button className="btn" onClick={() => navigate(`/assignments?request=${d.id}`)}>View pickup assignment</button>
              </>
            )}
            {!pending && !adjustable && <Link className="btn" to="/donations">Back to donations</Link>}
          </div>
        </section>
      </div>
      <AdminDialog
        open={confirming !== null}
        title={confirming === 'accept' ? `Accept donation ${d.publicRef}?` : 'Decline this donation?'}
        description={confirming === 'accept'
          ? `${d.donorName} · ${d.items.map((item) => `${qtys[item.id] ?? 0} ${humanize(item.itemType)}`).join(' and ')}. The accepted quantity will be verified again at pickup.`
          : 'A clear reason is required and will be shared with the donor.'}
        onClose={() => !busy && setConfirming(null)}
        actions={confirming === 'accept' ? [
          { label: busy ? 'Accepting…' : 'Accept donation', variant: 'primary', disabled: busy || total <= 0, onClick: () => void run(acceptDonation, 'Donation accepted.') },
          { label: 'Cancel', disabled: busy, onClick: () => setConfirming(null) },
        ] : confirming === 'decline' ? [
          { label: busy ? 'Declining…' : 'Decline donation', variant: 'danger', disabled: busy || reason.trim().length < 2, onClick: () => void run(() => reviewDonation(d.id, 'decline', [], reason.trim()), 'Donation declined.') },
          { label: 'Cancel', disabled: busy, onClick: () => setConfirming(null) },
        ] : []}
      >
        {confirming === 'decline' && <label className="admin-dialog__field"><span>Decline reason</span><textarea rows={3} value={reason} onChange={(event) => setReason(event.target.value)} autoFocus/><small>Required · Keep the reason concise and respectful.</small></label>}
        {actionError && confirming && <p className="admin-dialog__error" role="alert">{actionError}</p>}
      </AdminDialog>
      <FeedbackDialog feedback={feedback} onClose={() => setFeedback(null)} />
    </>
  );
}
