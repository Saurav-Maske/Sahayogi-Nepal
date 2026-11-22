import { useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import QuickAction from '../components/dashboard/QuickAction';
import { availableQty, getLot, listMovements, prettyPhase, type Lot, type Movement } from '../services/inventoryService';
import '../styles/inventory.css';

const inventoryId = (id: string) => `INV-${id.slice(0, 8).toUpperCase()}`;
const dateTime = (value: string) => new Date(value).toLocaleString('en-GB', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' });

export default function InventoryDetailPage() {
  const { id = '' } = useParams();
  const [lot, setLot] = useState<Lot | null>(null);
  const [moves, setMoves] = useState<Movement[]>([]);
  const [error, setError] = useState('');
  useEffect(() => {
    let active = true;
    void Promise.all([getLot(id), listMovements(id)]).then(([currentLot, history]) => {
      if (active) { setLot(currentLot); setMoves(history); setError(''); }
    }).catch((e) => { if (active) setError(e instanceof Error ? e.message : 'Could not load inventory item.'); });
    return () => { active = false; };
  }, [id]);
  if (!lot) return <div className="card table-msg"><p className={error ? 'auth-error' : 'empty'} role={error ? 'alert' : undefined}>{error || 'Loading inventory item…'}</p><Link className="btn" to="/inventory">Back to inventory</Link></div>;
  const ready = availableQty(lot);
  return <div className="inventory-detail-page"><header className="page__head"><div><h1>Inventory detail · {lot.itemType.replace(/_/g, ' ')}</h1><p className="crumbs"><Link to="/">Sahayogi Nepal</Link>&nbsp; / &nbsp;<Link to="/inventory">Central Inventory</Link>&nbsp; / &nbsp;{inventoryId(lot.id)}</p></div><div className="page__actions"><QuickAction/></div></header>
    <div className="inventory-detail-grid"><section className="card inventory-detail-summary"><h2 className="card__title">{lot.itemType.replace(/_/g, ' ')} · {inventoryId(lot.id)}</h2><p className="card__sub">{prettyPhase(lot.phase)}{lot.note ? ` · ${lot.note}` : ''}</p>
      <dl className="inventory-quantities"><div><dt>Current lot quantity</dt><dd>{lot.quantity} {lot.unit}</dd></div><div><dt>Available</dt><dd>{ready} {lot.unit}</dd></div><div><dt>Reserved</dt><dd>{lot.reserved} {lot.unit}</dd></div></dl>
      <p className="inventory-provider">Provider: {lot.provider ?? 'Not recorded'}<br/>Contact: {lot.contact ?? 'Not recorded'}<br/>Added: {new Date(lot.createdAt).toLocaleDateString('en-GB')}<br/>Added by: {lot.createdBy ?? 'Not recorded'}{lot.sourceRequest && <><br/>Related request: {lot.sourceRequest}</>}</p>
      <Link className="btn btn--primary" to={`/inventory/movement/new?lot=${lot.id}`}>Record stock movement</Link>
    </section><section className="card inventory-history"><div className="inventory-card-heading"><h2 className="card__title">Movement history</h2><Link to="/inventory/timeline">View full timeline</Link></div>
      <ol className="inventory-event-list">{moves.map((movement) => <li key={movement.id}><Link to={`/inventory/movements/${movement.id}`}><strong>{prettyPhase(movement.fromPhase)} → {prettyPhase(movement.toPhase)} · {movement.quantity} {movement.unit}</strong></Link><p>{movement.reason ?? 'No note recorded'}{movement.requestId ? ` · Request ${movement.requestId}` : ''}</p><time>{dateTime(movement.createdAt)}</time></li>)}</ol>{!moves.length && <p className="empty">No stock movements recorded yet.</p>}
    </section></div>
  </div>;
}
