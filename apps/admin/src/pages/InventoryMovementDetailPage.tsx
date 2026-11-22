import { useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import QuickAction from '../components/dashboard/QuickAction';
import { getLot, getMovement, listMovements, prettyPhase, type Lot, type Movement } from '../services/inventoryService';
import '../styles/inventory.css';

const shortId = (prefix: string, id: string) => `${prefix}-${id.slice(0, 8).toUpperCase()}`;
const dateTime = (value: string) => new Date(value).toLocaleString('en-GB', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' });

export default function InventoryMovementDetailPage() {
  const { movementId = '' } = useParams();
  const [movement, setMovement] = useState<Movement | null>(null);
  const [lot, setLot] = useState<Lot | null>(null);
  const [history, setHistory] = useState<Movement[]>([]);
  const [error, setError] = useState('');
  useEffect(() => {
    let active = true;
    void Promise.all([getMovement(movementId), listMovements()]).then(async ([record, all]) => {
      const inventoryLot = await getLot(record.lotId);
      if (active) { setMovement(record); setLot(inventoryLot); setHistory(all.filter((entry) => entry.lotId === record.lotId)); setError(''); }
    }).catch((e) => { if (active) setError(e instanceof Error ? e.message : 'Could not load movement.'); });
    return () => { active = false; };
  }, [movementId]);
  if (!movement || !lot) return <div className="card table-msg"><p className={error ? 'auth-error' : 'empty'} role={error ? 'alert' : undefined}>{error || 'Loading stock movement…'}</p><Link className="btn" to="/inventory">Back to inventory</Link></div>;

  return <div className="inventory-detail-page"><header className="page__head"><div><h1>Stock movement · {shortId('MOV', movement.id)}</h1><p className="crumbs"><Link to="/">Sahayogi Nepal</Link>&nbsp; / &nbsp;<Link to="/inventory">Central Inventory</Link>&nbsp; / &nbsp;{shortId('INV', lot.id)}</p></div><div className="page__actions"><QuickAction/></div></header>
    <div className="inventory-detail-grid"><section className="card inventory-detail-summary"><h2 className="card__title">{lot.itemType.replace(/_/g, ' ')} · {shortId('INV', lot.id)}</h2><p className="card__sub">{prettyPhase(movement.fromPhase)} → {prettyPhase(movement.toPhase)}</p>
      <dl className="inventory-quantities"><div><dt>Quantity moved</dt><dd>{movement.quantity} {movement.unit}</dd></div><div><dt>Current lot quantity</dt><dd>{lot.quantity} {lot.unit}</dd></div><div><dt>Reserved in lot</dt><dd>{lot.reserved} {lot.unit}</dd></div></dl>
      <p className="inventory-provider">Recorded: {dateTime(movement.createdAt)}<br/>Reason: {movement.reason ?? 'No note recorded'}{movement.requestId && <><br/>Request ID: {movement.requestId}</>}{movement.actorId && <><br/>Admin ID: {movement.actorId}</>}</p>
      <Link className="btn btn--primary" to={`/inventory/movement/new?lot=${lot.id}`}>Record another movement</Link>
    </section><section className="card inventory-history"><h2 className="card__title">Lot movement history</h2><ol className="inventory-event-list">{history.map((entry) => <li key={entry.id}><Link to={`/inventory/movements/${entry.id}`}><strong>{prettyPhase(entry.fromPhase)} → {prettyPhase(entry.toPhase)} · {entry.quantity} {entry.unit}</strong></Link><p>{entry.reason ?? 'No note recorded'}</p><time>{dateTime(entry.createdAt)}</time></li>)}</ol></section></div>
  </div>;
}
