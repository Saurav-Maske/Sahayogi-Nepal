import { supabase } from '../supabase';
import { hasSession } from './session';

export type Lot = { id: string; itemType: string; unit: string; quantity: number; reserved: number; phase: string; provider: string | null; contact: string | null; note: string | null; createdAt: string; createdBy: string | null; sourceRequest: string | null };
export type Movement = { id: string; lotId: string; itemType: string; unit: string; quantity: number; fromPhase: string | null; toPhase: string; reason: string | null; requestId: string | null; createdAt: string; actorId: string | null };
const one = (value: any) => Array.isArray(value) ? value[0] : value;
const requireAdmin = async (message: string) => { if (!(await hasSession())) throw new Error(message); };
const mapLot = (row: any): Lot => ({
  id: row.id, itemType: row.item_type, unit: row.unit, quantity: Number(row.quantity), reserved: Number(row.reserved_qty), phase: row.phase,
  provider: row.provider_name, contact: row.provider_contact, note: row.condition_note, createdAt: row.created_at,
  createdBy: one(row.profiles)?.full_name ?? null, sourceRequest: one(row.requests)?.public_ref ?? null,
});

export async function listLots(): Promise<Lot[]> {
  await requireAdmin('Sign in as an administrator to view inventory.');
  const { data, error } = await supabase.from('inventory_lots')
    .select('id,item_type,unit,quantity,reserved_qty,phase,provider_name,provider_contact,condition_note,created_at,created_by,source_request_id,requests(public_ref),profiles!created_by(full_name)')
    .order('created_at', { ascending: false });
  if (error) throw error;
  return (data ?? []).map(mapLot);
}

export async function getLot(id: string): Promise<Lot> {
  const lot = (await listLots()).find((item) => item.id === id);
  if (!lot) throw new Error('Inventory item not found.');
  return lot;
}

export async function listMovements(lotId?: string): Promise<Movement[]> {
  await requireAdmin('Sign in as an administrator to view inventory history.');
  let query: any = supabase.from('inventory_movements')
    .select('id,lot_id,from_phase,to_phase,quantity,reason,request_id,actor_id,created_at,inventory_lots!inner(item_type,unit)')
    .order('created_at', { ascending: false });
  if (lotId) query = query.eq('lot_id', lotId);
  const { data, error } = await query;
  if (error) throw error;
  return (data ?? []).map((row: any) => ({
    id: row.id, lotId: row.lot_id, itemType: one(row.inventory_lots)?.item_type ?? '', unit: one(row.inventory_lots)?.unit ?? '',
    quantity: Number(row.quantity), fromPhase: row.from_phase, toPhase: row.to_phase, reason: row.reason,
    requestId: row.request_id, createdAt: row.created_at, actorId: row.actor_id,
  }));
}

export async function getMovement(id: string): Promise<Movement> {
  const movement = (await listMovements()).find((item) => item.id === id);
  if (!movement) throw new Error('Inventory movement not found.');
  return movement;
}

export const prettyPhase = (phase: string | null) => phase ? phase.replace(/_/g, ' ').replace(/^./, (letter) => letter.toUpperCase()) : 'Received';
export const availableQty = (lot: Lot) => Math.max(0, lot.quantity - lot.reserved);

export async function importStock(items: Array<Record<string, unknown>>) {
  await requireAdmin('Sign in as an administrator to add inventory.');
  const { data, error } = await supabase.rpc('admin_import_stock', { p_items: items });
  if (error) throw error;
  return data;
}

export async function moveLot(id: string, phase: string, quantity: number, reason: string | null) {
  await requireAdmin('Sign in as an administrator to move inventory.');
  const { data, error } = await supabase.rpc('admin_move_lot', { p_id: id, p_phase: phase, p_qty: quantity, p_reason: reason });
  if (error) throw error;
  return data;
}
