import { useCallback, useEffect, useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import QuickAction from '../components/dashboard/QuickAction';
import EmptyState from '../components/feedback/EmptyState';
import FeedbackNotice from '../components/feedback/FeedbackNotice';
import OperationsMapPreview from '../components/map/OperationsMapPreview';
import AdminDialog from '../components/overlay/AdminDialog';
import FeedbackDialog from '../components/overlay/FeedbackDialog';
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
  const [savingAdd, setSavingAdd] = useState(false);
  const [selectedTypes, setSelectedTypes] = useState<string[]>([]);
  const [quantities, setQuantities] = useState<Record<string, string>>({});
  const [units, setUnits] = useState<Record<string, string>>({});
  const [addProvider, setAddProvider] = useState('');
  const [addContact, setAddContact] = useState('');
  const [addNote, setAddNote] = useState('');
  const [feedback, setFeedback] = useState<{ title: string; message: string } | null>(null);

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
    const invalid = selectedTypes.length === 0 || selectedTypes.some((type) => !Number.isFinite(Number(quantities[type])) || Number(quantities[type]) <= 0 || !units[type]?.trim());
    if (invalid) { setError('Choose at least one resource, then enter a valid quantity and unit for each.'); return; }
    setError('');
    setSavingAdd(true);
    try {
      await importStock(selectedTypes.map((type) => ({ item_type: type, qty: Number(quantities[type]), unit: units[type].trim(), provider_name: addProvider || null, provider_contact: addContact || null, condition_note: addNote || null, phase: 'received' })));
      const summary = selectedTypes.map((type) => `${quantities[type]} ${units[type].trim()} of ${itemName(type)}`).join('; ');
      setShowAdd(false); setShowMapPreview(false); setSelectedTypes([]); setQuantities({}); setUnits({}); setAddProvider(''); setAddContact(''); setAddNote(''); setFeedback({ title: 'Inventory receipt added', message: `${summary} recorded in received stock.` }); refresh();
    } catch (e) { setError(e instanceof Error ? e.message : 'Could not add inventory.'); }
    finally { setSavingAdd(false); }
  }

  return <div className="inventory-page"><header className="page__head"><div><h1>Central inventory</h1><p className="crumbs">Sahayogi Nepal&nbsp; / &nbsp;Central Inventory&nbsp; / &nbsp;All districts</p></div><div className="page__actions"><QuickAction/></div></header>
    <div className="inventory-toolbar"><input placeholder="Search inventory" aria-label="Search inventory" value={query} onChange={(e) => setQuery(e.target.value)}/><select aria-label="Filter category" value={category} onChange={(e) => setCategory(e.target.value)}><option>All</option>{categories.map((value) => <option key={value} value={value}>{itemName(value)}</option>)}</select><button className="btn btn--primary" onClick={() => { setShowAdd(true); setError(''); }}>+ Add inventory</button><Link className="btn" to="/inventory/timeline">Activity timeline</Link></div>
    <FeedbackNotice variant="info" title="Workflow stage and stock movement are separate" className="inventory-workflow">Stage changes are audited. Reservations and dispatch quantities are managed by request approval and driver confirmation.</FeedbackNotice>
    {error && !showAdd && <p className="inventory-error" role="alert">{error} <button className="btn btn--ghost" onClick={refresh}>Retry</button></p>}
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
    {!loading && !filtered.length && !error && <EmptyState title="No inventory found" description="No stock matches these filters. Try another category or search term."/>}
    {!loading && <p className="inventory-live-note">Live inventory data · quantity changes require an audited backend action.</p>}
    <AdminDialog
      open={showAdd}
      size={showMapPreview ? 'wide' : 'regular'}
      title="Add inventory receipt"
      description="Record physical goods received. A receipt movement and audit entry are created together."
      onClose={() => { if (!savingAdd) { setShowAdd(false); setShowMapPreview(false); } }}
      actions={[
        { label: savingAdd ? 'Saving…' : 'Save inventory item', variant: 'primary', disabled: savingAdd, onClick: () => void addItem() },
        { label: 'Cancel', disabled: savingAdd, onClick: () => { setShowAdd(false); setShowMapPreview(false); } },
      ]}
    >
      <div className="inventory-dialog-fields">
        <fieldset className="inventory-category-picker"><legend>Select resources</legend>
          <div className="inventory-category-picker__options">{ITEM_TYPES.map(([value, label]) => <label key={value} className={selectedTypes.includes(value) ? 'is-selected' : ''}><input type="checkbox" checked={selectedTypes.includes(value)} onChange={(event) => setSelectedTypes((current) => event.target.checked ? [...current, value] : current.filter((item) => item !== value))}/><span>{label}</span></label>)}</div>
          <small>Select one or more categories. Each selected item has its own quantity and unit.</small>
        </fieldset>
        {selectedTypes.length > 0 && <div className="inventory-quantities-list" aria-label="Selected resource quantities">{selectedTypes.map((type) => <div className="inventory-quantity-row" key={type}>
          <strong>{itemName(type)}</strong>
          <label className="admin-dialog__field"><span>Quantity</span><input type="number" min="0.01" step="0.01" value={quantities[type] ?? ''} onChange={(e) => setQuantities((current) => ({ ...current, [type]: e.target.value }))} placeholder="Enter quantity"/></label>
          <label className="admin-dialog__field"><span>Unit</span><input value={units[type] ?? ''} maxLength={20} onChange={(e) => setUnits((current) => ({ ...current, [type]: e.target.value }))} placeholder="kg, bottles, units"/></label>
        </div>)}</div>}
        <label className="admin-dialog__field"><span>Provider name</span><input value={addProvider} maxLength={120} onChange={(e) => setAddProvider(e.target.value)} placeholder="Supplier or donor"/><small>Optional source for this receipt.</small></label>
        <label className="admin-dialog__field"><span>Provider contact</span><input value={addContact} maxLength={120} onChange={(e) => setAddContact(e.target.value)} placeholder="Phone or email"/><small>Restricted to authorised administrators.</small></label>
        <label className="admin-dialog__field"><span>Condition note</span><input value={addNote} maxLength={300} onChange={(e) => setAddNote(e.target.value)} placeholder="Optional"/></label>
      </div>
      <button className="btn inventory-map-toggle" type="button" aria-expanded={showMapPreview} onClick={() => setShowMapPreview((visible) => !visible)}>{showMapPreview ? 'Hide live map' : 'Check live map'}</button>
      {showMapPreview && <div className="inventory-map-panel"><p>Your live location and current operations are shown for reference. The stock record does not save a map location.</p><OperationsMapPreview followLiveLocation/></div>}
      {error && <FeedbackNotice variant="validation" title="Check the inventory details">{error}</FeedbackNotice>}
    </AdminDialog>
    <FeedbackDialog feedback={feedback} onClose={() => setFeedback(null)} />
  </div>;
}
