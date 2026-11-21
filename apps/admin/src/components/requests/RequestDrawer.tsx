import { useEffect, useRef } from 'react';
import { useNavigate } from 'react-router-dom';
import { useRequest } from '../../hooks/useRequests';
import { buildHistory, fmtTime, isPending, itemLabel } from '../../utils/requests';
import { fmtDate } from '../../utils/requests';

interface Props { id: string; onClose: () => void }

export default function RequestDrawer({ id, onClose }: Props) {
  const { data, loading, error } = useRequest(id);
  const navigate = useNavigate();
  const closeRef = useRef<HTMLButtonElement>(null);
  const r = data?.request;

  useEffect(() => {
    closeRef.current?.focus();
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && onClose();
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [onClose]);

  return (
    <>
      <div className="drawer__scrim" onClick={onClose} />
      <aside className="drawer" role="dialog" aria-modal="true" aria-label="Request details">
        {loading && !r && <p className="empty">Loading…</p>}
        {error && <p className="auth-error" role="alert">{error}</p>}
        {r && (
          <>
            <h2 className="drawer__title">{r.publicRef} · {r.requesterName}</h2>
            <p className="drawer__auth">Authorised operations view</p>

            <p className="drawer__line">{r.requesterPhone} · {r.district}</p>
            <p className="drawer__line">Requested: {r.items.map((i) => itemLabel(i, i.requestedQty)).join(' · ')}</p>
            {r.items.some((i) => i.available != null) && (
              <p className="drawer__line">
                Available: {r.items.filter((i) => i.available != null).map((i) => itemLabel(i, i.available!)).join(' · ')}
              </p>
            )}
            {r.notes && <p className="drawer__line">Notes: {r.notes}</p>}

            <h3 className="drawer__sub">Request history</h3>
            <ul className="drawer__history">
              {buildHistory(r).map((h, i) => (
                <li key={i}>
                  {h.at ? `${fmtDate(h.at)} ${fmtTime(h.at)}` : '—'} · {h.title}
                </li>
              ))}
            </ul>

            <div className="drawer__actions">
              <button className="btn btn--primary" onClick={() => navigate(`/requests/${r.id}`)}>
                {isPending(r.status) ? 'Review approved quantities' : 'Open full request'}
              </button>
              <button className="btn btn--primary" ref={closeRef} onClick={onClose}>Close drawer</button>
            </div>
          </>
        )}
      </aside>
    </>
  );
}