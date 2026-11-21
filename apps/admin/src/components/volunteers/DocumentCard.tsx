import { useEffect, useState } from 'react';
import { getDocumentUrl } from '../../services/volunteersService';

interface Props { title: string; path: string | null; demo: boolean }

export default function DocumentCard({ title, path, demo }: Props) {
  const [open, setOpen] = useState(false);
  const [url, setUrl] = useState<string | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  // a fresh 60-second link is requested each time the preview opens
  useEffect(() => {
    if (!open || !path) return;
    let off = false;
    setBusy(true); setErr(null); setUrl(null);
    getDocumentUrl(path)
      .then((u) => !off && setUrl(u))
      .catch((e) => !off && setErr(e?.message ?? 'Could not open the document.'))
      .finally(() => !off && setBusy(false));
    return () => { off = true; };
  }, [open, path]);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && setOpen(false);
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [open]);

  return (
    <div className="doc">
      <h3 className="doc__title">{title}</h3>
      <p className="doc__text">{path ? 'Photo on file. Open secure preview to verify the original.' : 'Not uploaded.'}</p>
      <button className="btn" disabled={!path} onClick={() => setOpen(true)}>Open secure preview</button>

      {open && (
        <>
          <div className="drawer__scrim" onClick={() => setOpen(false)} />
          <div className="modal" role="dialog" aria-modal="true" aria-label={title}>
            <div className="modal__head">
              <strong>{title}</strong>
              <button className="btn" onClick={() => setOpen(false)}>Close</button>
            </div>
            <div className="modal__body" onContextMenu={(e) => e.preventDefault()}>
              {busy && <p className="empty">Requesting secure link…</p>}
              {err && <p className="auth-error" role="alert">{err}</p>}
              {url && <img src={url} alt={title} draggable={false} />}
              {!busy && !err && !url && demo && <p className="doc__demo">REDACTED DEMO DOCUMENT</p>}
            </div>
            <p className="modal__foot">The link expires after 60 seconds. Do not share or save this document.</p>
          </div>
        </>
      )}
    </div>
  );
}