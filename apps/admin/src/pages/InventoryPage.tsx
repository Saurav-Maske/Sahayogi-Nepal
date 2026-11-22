import { useCallback, useEffect, useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import QuickAction from '../components/dashboard/QuickAction';
import OperationsMapPreview from '../components/map/OperationsMapPreview';
import { importStock, availableQty, listLots, prettyPhase, type Lot } from '../services/inventoryService';
import '../styles/inventory.css';

const PHASES = ['received', 'processing', 'ready_to_ship', 'reserved', 'dispatched', 'adjusted'];
const ITEM_TYPES = [['food', 'Food'], ['cloth', 'Clothing'], ['temp_shelter', 'Temporary shelter'], ['medical_supplies', 'Medical supplies'], ['drinking_water', 'Drinking water']];
const itemName = (item: string) => ITEM_TYPES.find(([value]) => value === item)?.[1] ?? item.replace(/_/g, ' ');
const inventoryId = (id: string) => `INV-${id.slice(0, 8).toUpperCase()}`;

export default function InventoryPage() {
  const [lots, setLots] = useState<Lot[]>([]);
  const [query, setQuery] = useState('');
  const [category, setCategory] = useState('All');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [showAdd, setShowAdd] = useState(false);
  const [showMapPreview, setShowMapPreview] = useState(false);
  const [addName, setAddName] = useState('');
  const [addQty, setAddQty] = useState('');
  const [addUnit, setAddUnit] = useState('');
  const [addNote, setAddNote] = useState('');
  const [toast, setToast] = useState('');

  const refresh = useCallback(() => {
    setLoading(true);
    void listLots().then((rows) => { setLots(rows); setError(''); })
      .catch((e) => setError(e instanceof Error ? e.message : 'Could not load inventory.'))
      .finally(() => setLoading(false));
  }, []);
  useEffect(refresh, [refresh]);
  const categories = [...new Set(lots.map((lot) => lot.itemType))].sort();
  const filtered = useMemo(() => lots.filter((lot) => (category === 'All' || lot.itemType === category)
    && (!query || `${itemName(lot.itemType)} ${lot.provider ?? ''} ${lot.sourceRequest ?? ''} ${inventoryId(lot.id)}`.toLowerCase().includes(query.toLowerCase()))), [lots, category, query]);

  async function addItem() {
    const quantity = Number(addQty);
    if (!addName || !Number.isFinite(quantity) || quantity <= 0) { setError('Choose an item type and enter a quantity greater than zero.'); return; }
    setError('');
    try {
      await importStock([{ item_type: addName, qty: quantity, unit: addUnit, condition_note: addNote || null, phase: 'received' }]);
      setShowAdd(false); setShowMapPreview(false); setAddName(''); setAddQty(''); setAddUnit(''); setAddNote(''); setToast('Inventory lot added.'); refresh();
    } catch (e) { setError(e instanceof Error ? e.message : 'Could not add inventory.'); }
  }

  return <div className="inventory-page"><header className="page__head"><div><h1>Central inventory</h1><p className="crumbs">Sahayogi Nepal&nbsp; / &nbsp;Central Inventory&nbsp; / &nbsp;All districts</p></div><div className="page__actions"><QuickAction/></div></header>
    <div className="inventory-toolbar"><input placeholder="Search inventory" aria-label="Search inventory" value={query} onChange={(e) => setQuery(e.target.value)}/><select aria-label="Filter category" value={category} onChange={(e) => setCategory(e.target.value)}><option>All</option>{categories.map((value) => <option key={value} value={value}>{itemName(value)}</option>)}</select><button className="btn btn--primary" onClick={() => { setShowAdd(true); setError(''); }}>+ Add inventory</button><Link className="btn" to="/inventory/timeline">Activity timeline</Link></div>
    <div className="inventory-workflow"><strong>Workflow stage ≠ stock movement</strong><p>Stage changes are audited. Reservations and dispatch quantities are managed by request approval and driver confirmation.</p></div>
    {error && <p className="inventory-error" role="alert">{error} <button className="btn btn--ghost" onClick={refresh}>Retry</button></p>}{toast && <p className="inventory-toast" role="status">{toast}</p>}
    {loading ? <p className="empty">Loading inventory…</p> : <div className="inventory-board">{PHASES.map((phase) => {
      const phaseLots = filtered.filter((lot) => lot.phase === phase);
      return <section className="inventory-column" key={phase}><h2>{prettyPhase(phase).toUpperCase()} <span>{phaseLots.length}</span></h2><div className="inventory-column-list">
        {phaseLots.map((lot) => <Link to={`/inventory/${lot.id}`} className="inventory-lot-card" key={lot.id}>
          <strong>{itemName(lot.itemType)} · {inventoryId(lot.id)}</strong><span className="lot-meta">{prettyPhase(lot.phase)}{lot.note ? ` · ${lot.note}` : ''}</span>
          <b>{availableQty(lot)} {lot.unit} available{lot.reserved > 0 ? ` · ${lot.reserved} reserved` : ''}</b>
          <small>{lot.provider ?? 'Provider not recorded'} · {new Date(lot.createdAt).toLocaleDateString('en-GB', { day: '2-digit', month: 'short' })}</small>
          <small>{lot.createdBy ? `Added by ${lot.createdBy}` : 'Admin not recorded'}</small>
        </Link>)}
        {phase === 'received' && <button className="btn inventory-add-item" onClick={() => { setShowAdd(true); setError(''); }}>+ Add item</button>}
      </div></section>;
    })}</div>}
    {!loading && !filtered.length && !error && <p className="empty">No inventory matches this search.</p>}
    {!loading && <p className="inventory-live-note">Live inventory data · quantity changes require an audited backend action.</p>}
    {showAdd && <div className="inventory-modal-backdrop" onMouseDown={(e) => { if (e.target === e.currentTarget) { setShowAdd(false); setShowMapPreview(false); } }}><section className={`inventory-modal${showMapPreview ? ' inventory-modal--map' : ''}`} role="dialog" aria-modal="true" aria-labelledby="add-inventory-title"><button className="inventory-modal-close" onClick={() => { setShowAdd(false); setShowMapPreview(false); }} aria-label="Close">×</button><h2 id="add-inventory-title">Add inventory item</h2>
      <label>Item type<select value={addName} onChange={(e) => setAddName(e.target.value)}><option value="">Choose item type</option>{ITEM_TYPES.map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></label>
      <div className="inventory-modal-row"><label>Quantity<input type="number" min="0.01" step="0.01" value={addQty} onChange={(e) => setAddQty(e.target.value)}/></label><label>Unit<input value={addUnit} maxLength={20} onChange={(e) => setAddUnit(e.target.value)} placeholder="kg, bottles, units"/></label></div>
      <label>Condition note<input value={addNote} maxLength={300} onChange={(e) => setAddNote(e.target.value)} placeholder="Optional"/></label>
      <button className="btn inventory-map-toggle" type="button" aria-expanded={showMapPreview} onClick={() => setShowMapPreview((visible) => !visible)}>{showMapPreview ? 'Hide live map' : 'Check live map'}</button>
      {showMapPreview && <div className="inventory-map-panel"><p>Your live location and current operations are shown for reference. The stock record does not save a map location.</p><OperationsMapPreview followLiveLocation/></div>}
      {error && <p className="inventory-error">{error}</p>}<button className="btn btn--primary" onClick={() => void addItem()}>Save inventory item</button>
    </section></div>}
  </div>;
}
