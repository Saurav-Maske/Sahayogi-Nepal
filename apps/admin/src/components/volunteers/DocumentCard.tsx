import { useEffect, useState } from 'react';
import AdminDialog from '../overlay/AdminDialog';
import { getDocumentUrl } from '../../services/volunteersService';

interface Props { title: string; path: string | null }

export default function DocumentCard({ title, path }: Props) {
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

  return (
    <div className="doc">
      <h3 className="doc__title">{title}</h3>
      <p className="doc__text">{path ? 'Photo on file. Open secure preview to verify the original.' : 'Not uploaded.'}</p>
      <button className="btn" disabled={!path} onClick={() => setOpen(true)}>Open secure preview</button>

      <AdminDialog open={open} title={title} description="Restricted access · A fresh, short-lived link is used for each preview." size="wide" onClose={() => setOpen(false)} actions={[{ label: 'Close preview', onClick: () => setOpen(false) }]}>
        <div className="doc-preview" onContextMenu={(e) => e.preventDefault()}>
          {busy && <p className="empty">Requesting secure link…</p>}
          {err && <p className="auth-error" role="alert">{err}</p>}
          {url && <img src={url} alt={title} draggable={false} />}
        </div>
        <p className="admin-dialog__note">The link expires after 60 seconds. Do not share or save this document.</p>
      </AdminDialog>
    </div>
  );
}
