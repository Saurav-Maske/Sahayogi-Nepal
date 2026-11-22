import { useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import QuickAction from '../components/dashboard/QuickAction';
import DocumentCard from '../components/volunteers/DocumentCard';
import AdminDialog from '../components/overlay/AdminDialog';
import FeedbackDialog from '../components/overlay/FeedbackDialog';
import { useVolunteer } from '../hooks/useVolunteers';
import { reviewVolunteer } from '../services/volunteersService';
import type { VolunteerDecision } from '../types/volunteers';
import { categoryInfo, isSuspended, maskId } from '../utils/volunteers';
import '../styles/requests.css';

export default function VolunteerProfilePage() {
  const { id = '' } = useParams();
  const { data, loading, error, reload } = useVolunteer(id);
  const v = data?.volunteer;
  const stats = data?.stats;

  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);
  const [feedback, setFeedback] = useState<{ title: string; message: string } | null>(null);
  const [confirming, setConfirming] = useState<VolunteerDecision | null>(null);

  useEffect(() => { if (v) setNote(v.reviewNote ?? ''); }, [v?.id, v?.reviewStatus, v?.accountStatus]); // eslint-disable-line react-hooks/exhaustive-deps

  if (loading && !v) return <div className="skeleton-wrap" aria-busy="true"><div className="skeleton skeleton--title" /><div className="skeleton" style={{ height: 320 }} /></div>;
  if (error || !v) {
    return (
      <div className="card table-msg">
        <p className="auth-error" role="alert">{error ?? 'Volunteer not found.'}</p>
        <Link className="btn" to="/volunteers">Back to volunteers</Link>
      </div>
    );
  }

  const c = categoryInfo(v.volunteerType);
  const pending = v.reviewStatus === 'pending';
  const rejected = v.reviewStatus === 'rejected';
  const suspended = isSuspended(v);
  const approved = v.reviewStatus === 'approved' && !suspended;
  const needsNote = (d: VolunteerDecision) => d === 'reject' || d === 'suspend';

  const title = pending ? 'Volunteer profile' : approved ? 'Volunteer approved' : suspended ? 'Volunteer suspended' : 'Application rejected';
  const sub = pending ? `${c.name} · Permissions ${c.perms}` : approved ? `Approved · ${c.perms}` : suspended ? `Suspended · ${c.perms}` : `Rejected · ${c.name}`;

  const run = async (decision: VolunteerDecision, done: string) => {
    setBusy(true); setActionError(null); setFeedback(null);
    try { await reviewVolunteer(v.id, decision, note.trim()); setFeedback({ title: done.replace(/\.$/, ''), message: `${v.fullName}'s volunteer record has been updated.` }); setConfirming(null); reload(); }
    catch (e: any) { setActionError(e?.message ?? 'Something went wrong. Please try again.'); }
    finally { setBusy(false); }
  };

  const noteBlocked = (d: VolunteerDecision) => needsNote(d) && !note.trim();

  return (
    <>
      <div className="page__head">
        <div>
          <h1>{title} · {v.fullName}</h1>
          <p className="crumbs"><Link to="/volunteers">Volunteer Management</Link> / {v.fullName} / All districts</p>
        </div>
        <div className="page__actions"><QuickAction /></div>
      </div>

      <div className="review">
        <section className="card">
          <h2 className="card__title">{v.fullName}</h2>
          <p className="card__sub">{sub}</p>

          <p className="contact">
            {v.email}<br />
            {v.phone}<br />
            NID / citizenship: {maskId(v.citizenshipNo)}<br />
            {v.licenseNo && <>Driving licence: {maskId(v.licenseNo)}<br /></>}
            {v.serviceCardNo && <>Service card: {maskId(v.serviceCardNo)}</>}
          </p>

          <h3 className="review__sub">Contribution statistics</h3>
          {stats && (stats.completedJobs > 0 || stats.successPct != null) ? (
            <div className="stats-lines">
              <p>{stats.completedJobs} completed jobs · {stats.hours != null ? `${stats.hours} volunteer hours` : 'hours not tracked yet'}</p>
              <p>{stats.kgDelivered} kg delivered · {stats.donationsCollected} donations collected</p>
              <p>{stats.successPct != null ? `${stats.successPct}% successful assignments` : 'No finished assignments yet'}</p>
            </div>
          ) : <p className="empty">No assignments yet.</p>}

          <label className="qty">
            <span className="qty__title">Internal admin note</span>
            {rejected ? <span className="note-readonly">{v.reviewNote ?? '—'}</span> : (
              <textarea className="qty__textarea" rows={2} value={note} onChange={(e) => setNote(e.target.value)} placeholder="e.g. Identity and driving licence reviewed." />
            )}
            <span className="qty__hint">Restricted to volunteer administrators{!rejected && ' · A note is required to reject or suspend'}</span>
          </label>

          {actionError && !confirming && <p className="auth-error" role="alert">{actionError}</p>}

          <div className="review__actions">
            {pending && (
              <>
                <button className="btn btn--primary" disabled={busy} onClick={() => { setActionError(null); setConfirming('approve'); }}>Approve application</button>
                <button className="btn btn--danger" disabled={busy} onClick={() => { setActionError(null); setConfirming('reject'); }}>Reject</button>
              </>
            )}
            {approved && <button className="btn btn--danger" disabled={busy} onClick={() => { setActionError(null); setConfirming('suspend'); }}>Suspend volunteer</button>}
            {suspended && <button className="btn btn--primary" disabled={busy} onClick={() => { setActionError(null); setConfirming('reinstate'); }}>Reinstate volunteer</button>}
            {!pending && <Link className="btn" to="/volunteers">Back to volunteers</Link>}
          </div>
        </section>

        <section className="card">
          <h2 className="card__title">Secure document preview</h2>
          <p className="card__sub">Restricted access · Short-lived link · No public download</p>
          <DocumentCard title="Citizenship photograph" path={v.citizenshipPath} />
          {(v.licenseNo || v.licensePath) && <DocumentCard title="Driving licence photograph" path={v.licensePath} />}
          {(v.serviceCardNo || v.serviceCardPath) && <DocumentCard title="Service card photograph" path={v.serviceCardPath} />}
        </section>
      </div>
      <AdminDialog
        open={confirming !== null}
        title={confirming === 'approve' ? `Approve ${v.fullName}?` : confirming === 'reject' ? 'Reject this application?' : confirming === 'suspend' ? 'Suspend volunteer access?' : 'Reinstate volunteer access?'}
        description={confirming === 'approve'
          ? `An account activation and password setup email will be sent to ${v.email}. No plaintext password is displayed or emailed.`
          : confirming === 'reject'
            ? 'The applicant will receive a message explaining the next steps.'
            : confirming === 'suspend'
              ? 'Complete an investigation first. Active assignments must be safely reassigned before suspension.'
              : `Restore active volunteer access for ${v.fullName}?`}
        onClose={() => !busy && setConfirming(null)}
        actions={confirming ? [
          { label: busy ? 'Saving…' : confirming === 'approve' ? 'Approve & send email' : confirming === 'reject' ? 'Reject application' : confirming === 'suspend' ? 'Suspend volunteer' : 'Reinstate volunteer', variant: confirming === 'reject' || confirming === 'suspend' ? 'danger' : 'primary', disabled: busy || noteBlocked(confirming), onClick: () => void run(confirming, confirming === 'approve' ? 'Application approved.' : confirming === 'reject' ? 'Application rejected.' : confirming === 'suspend' ? 'Volunteer suspended.' : 'Volunteer reinstated.') },
          { label: 'Cancel', onClick: () => setConfirming(null), disabled: busy },
        ] : []}
      >
        {(confirming === 'reject' || confirming === 'suspend') && <label className="admin-dialog__field"><span>{confirming === 'reject' ? 'Rejection reason' : 'Investigation reason'}</span><textarea rows={3} value={note} onChange={(event) => setNote(event.target.value)} autoFocus/><small>{confirming === 'reject' ? 'Required · The applicant can reapply with a clearer document.' : 'Required · Restricted internal audit record.'}</small></label>}
        {actionError && confirming && <p className="admin-dialog__error" role="alert">{actionError}</p>}
      </AdminDialog>
      <FeedbackDialog feedback={feedback} onClose={() => setFeedback(null)} />
    </>
  );
}
