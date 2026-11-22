import { useEffect, useMemo, useState } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import QuickAction from '../components/dashboard/QuickAction';
import AdminDialog from '../components/overlay/AdminDialog';
import { availableQty, listLots, moveLot, prettyPhase, type Lot } from '../services/inventoryService';
import '../styles/inventory.css';

const inventoryId = (id: string) => `INV-${id.slice(0, 8).toUpperCase()}`;
const MOVABLE_PHASES = [['processing', 'Move to processing'], ['ready_to_ship', 'Move to ready to ship'], ['adjusted', 'Write off quantity']];

export default function InventoryMovementPage() {
  const [params] = useSearchParams();
  const navigate = useNavigate();
  const [lots, setLots] = useState<Lot[]>([]);
  const [lotId, setLotId] = useState(params.get('lot') ?? '');
  const [phase, setPhase] = useState('processing');
  const [quantity, setQuantity] = useState('');
  const [reason, setReason] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [reviewOpen, setReviewOpen] = useState(false);
  useEffect(() => { void listLots().then((rows) => { setLots(rows); if (!lotId && rows.length) setLotId(rows[0].id); }).catch((e) => setError(e instanceof Error ? e.message : 'Could not load inventory.')); }, []);
  const lot = lots.find((item) => item.id === lotId);
  const amount = Number(quantity);
  const available = lot ? availableQty(lot) : 0;
  const preview = useMemo(() => ({ available: Math.max(0, available - (phase === 'adjusted' ? amount : 0)), quantity: phase === 'adjusted' ? Math.max(0, (lot?.quantity ?? 0) - amount) : lot?.quantity ?? 0 }), [available, amount, phase, lot?.quantity]);

  function reviewMovement() {
    setError('');
    if (!lot) { setError('Choose an inventory lot.'); return; }
    if (!Number.isFinite(amount) || amount <= 0) { setError('Enter a quantity greater than zero.'); return; }
    if (amount > available) { setError('The quantity cannot exceed the available amount.'); return; }
    if (phase === 'adjusted' && reason.trim().length < 2) { setError('Add a reason of at least two characters for a write-off.'); return; }
    setReviewOpen(true);
  }

  async function confirmMovement() {
    if (!lot) return;
    setError('');
    setBusy(true);
    try {
      const result = await moveLot(lotId, phase, amount, reason.trim() || null) as { lot_id?: string };
      navigate(`/inventory/${result?.lot_id ?? lotId}`);
    } catch (e) { setError(e instanceof Error ? e.message : 'Could not record this movement.'); }
    finally { setBusy(false); }
  }

  return <div className="inventory-movement-page"><header className="page__head"><div><h1>Record stock movement</h1><p className="crumbs"><Link to="/">Sahayogi Nepal</Link>&nbsp; / &nbsp;<Link to="/inventory">Central Inventory</Link>&nbsp; / &nbsp;All districts</p></div><div className="page__actions"><QuickAction/></div></header>
    <div className="inventory-detail-grid"><section className="card movement-form-card"><h2 className="card__title">{lot ? `${lot.itemType.replace(/_/g, ' ')} · ${inventoryId(lot.id)}` : 'Inventory lot'}</h2>
      <label className="movement-field"><span>Inventory lot</span><select value={lotId} onChange={(e) => setLotId(e.target.value)}>{lots.map((item) => <option key={item.id} value={item.id}>{item.itemType.replace(/_/g, ' ')} · {inventoryId(item.id)} · {prettyPhase(item.phase)}</option>)}</select></label>
      <label className="movement-field"><span>Movement type</span><select value={phase} onChange={(e) => setPhase(e.target.value)}>{MOVABLE_PHASES.map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select><small>The server checks whether this lot can move into the selected stage.</small></label>
      <label className="movement-field"><span>Quantity</span><input type="number" min="0.01" step="0.01" max={available} value={quantity} onChange={(e) => setQuantity(e.target.value)}/><small>Available to move: {available} {lot?.unit ?? ''}</small></label>
      <label className="movement-field"><span>{phase === 'adjusted' ? 'Write-off reason' : 'Movement note'}</span><textarea maxLength={300} value={reason} onChange={(e) => setReason(e.target.value)}/><small>{phase === 'adjusted' ? 'Required for quantity adjustments.' : 'Optional. Recorded in the audit history.'}</small></label>
      {error && !reviewOpen && <p className="inventory-error" role="alert">{error}</p>}<button className="btn btn--primary" disabled={busy || !lot} onClick={reviewMovement}>Review movement</button>
    </section><section className="card movement-preview"><h2 className="card__title">Balance preview</h2>{lot && <><p>Current lot quantity&nbsp; {lot.quantity} {lot.unit}</p><p>Available&nbsp; {available} {lot.unit}</p><p>Reserved&nbsp; {lot.reserved} {lot.unit}</p><p>Quantity moved&nbsp; {Number.isFinite(amount) && amount > 0 ? amount : '—'} {lot.unit}</p><p>Available after action&nbsp; {Number.isFinite(preview.available) ? preview.available : '—'} {lot.unit}</p></>}
      <div className="inventory-reconciliation"><strong>{prettyPhase(phase)} movement</strong><p>A partial move creates a new lot in the selected stage. The audited movement is saved by Supabase only after confirmation.</p></div><Link to="/inventory/timeline">Open inventory activity timeline</Link>
    </section></div>
    <AdminDialog open={reviewOpen} title={phase === 'adjusted' ? `Write off ${amount} ${lot?.unit ?? 'units'}?` : `Move ${lot?.itemType.replace(/_/g, ' ') ?? 'inventory'} to ${prettyPhase(phase)}?`} description={phase === 'adjusted' ? 'This reduces recorded stock. The reason and quantity will be written to the audit history.' : `Move ${amount} ${lot?.unit ?? ''} to ${prettyPhase(phase)}? A partial move creates a separate lot; total stock remains unchanged.`} onClose={() => !busy && setReviewOpen(false)} actions={[
      { label: busy ? 'Recording…' : phase === 'adjusted' ? 'Write off quantity' : 'Move stage', variant: phase === 'adjusted' ? 'danger' : 'primary', disabled: busy, onClick: () => void confirmMovement() },
      { label: 'Cancel', disabled: busy, onClick: () => setReviewOpen(false) },
    ]}>
      {error && <p className="admin-dialog__error" role="alert">{error}</p>}
    </AdminDialog>
  </div>;
}
