import { supabase } from '../supabase';
import { hasSession } from './session';

export type NoticeCategory = 'Requests' | 'Donations' | 'Assignments' | 'Inventory';
export type Notice = {
  id: string;
  title: string;
  detail: string;
  createdAt: string;
  category: NoticeCategory;
  kind: 'alert' | 'success' | 'normal';
  to: string;
};

const LOW_STOCK_THRESHOLD = 100;
const RECENT_ACTIVITY_DAYS = 7;
const PREFERENCES_KEY = 'sahayogi-admin-notification-preferences';
const one = (value: any) => Array.isArray(value) ? value[0] : value;
const notificationsEnabled = () => {
  try {
    const saved = JSON.parse(localStorage.getItem(PREFERENCES_KEY) ?? '{}');
    return { shortage: saved.shortage !== false, requests: saved.requests !== false, volunteers: saved.volunteers !== false, inventory: saved.inventory !== false };
  } catch { return { shortage: true, requests: true, volunteers: true, inventory: true }; }
};

export async function listNotifications(): Promise<Notice[]> {
  if (!(await hasSession())) throw new Error('Sign in as an administrator to view notifications.');
  const preferences = notificationsEnabled();
  const recentSince = new Date(Date.now() - RECENT_ACTIVITY_DAYS * 24 * 60 * 60 * 1000).toISOString();
  const [incidents, requests, assignments, applications, lots] = await Promise.all([
    supabase.from('incidents').select('id, incident_type, status, created_at').in('status', ['open', 'under_review']).order('created_at', { ascending: false }).limit(20),
    supabase.from('requests').select('id, public_ref, kind, status, requester_name, created_at').gte('created_at', recentSince).order('created_at', { ascending: false }).limit(30),
    supabase.from('assignment_events').select('id, event_type, created_at, assignment:assignments!inner(id, request:requests!inner(public_ref), volunteer:profiles!volunteer_id(full_name))').gte('created_at', recentSince).order('created_at', { ascending: false }).limit(40),
    supabase.from('volunteer_applications').select('id, full_name, volunteer_type, review_status, created_at').in('review_status', ['submitted', 'under_review']).gte('created_at', recentSince).order('created_at', { ascending: false }).limit(20),
    supabase.from('inventory_lots').select('item_type, unit, quantity, reserved_qty').in('phase', ['received', 'processing', 'ready_to_ship']),
  ]);
  for (const result of [incidents, requests, assignments, applications, lots]) if (result.error) throw result.error;

  const notices: Notice[] = [];
  preferences.shortage && (incidents.data ?? []).forEach((row: any) => notices.push({
    id: `incident:${row.id}`, title: `Incident needs review: ${row.incident_type.replace(/_/g, ' ')}`,
    detail: `${row.status.replace(/_/g, ' ')} · Incident ${row.id.slice(0, 8)}`,
    createdAt: row.created_at, category: 'Requests', kind: 'alert', to: `/incidents/${row.id}`,
  }));
  preferences.requests && (requests.data ?? []).forEach((row: any) => notices.push({
    id: `request:${row.id}`, title: row.kind === 'donation_offer' ? 'New donation offer' : 'New help request',
    detail: `${row.public_ref} · ${row.requester_name} · ${row.status.replace(/_/g, ' ')}`,
    createdAt: row.created_at, category: row.kind === 'donation_offer' ? 'Donations' : 'Requests', kind: 'normal',
    to: row.kind === 'donation_offer' ? `/donations/${row.id}` : `/requests/${row.id}`,
  }));
  (assignments.data ?? []).forEach((row: any) => {
    const assignment = one(row.assignment);
    const req = one(assignment?.request);
    const volunteer = one(assignment?.volunteer);
    notices.push({
      id: `assignment-event:${row.id}`, title: `Assignment ${row.event_type.replace(/_/g, ' ')}`,
      detail: `${req?.public_ref ?? 'Request'} · ${volunteer?.full_name ?? 'Unassigned'}`,
      createdAt: row.created_at, category: 'Assignments',
      kind: /deliver|complete/i.test(row.event_type) ? 'success' : 'normal', to: `/assignments/${assignment?.id}`,
    });
  });
  preferences.volunteers && (applications.data ?? []).filter((row: any) => ['submitted', 'under_review'].includes(row.review_status)).forEach((row: any) => notices.push({
    id: `application:${row.id}`, title: 'Volunteer application received',
    detail: `${row.full_name} · ${row.volunteer_type.replace(/_/g, ' ')}`,
    createdAt: row.created_at, category: 'Requests', kind: 'normal', to: `/volunteers/${row.id}`,
  }));

  const stock = new Map<string, { quantity: number; unit: string }>();
  (lots.data ?? []).forEach((row: any) => {
    const current = stock.get(row.item_type) ?? { quantity: 0, unit: row.unit };
    current.quantity += Number(row.quantity) - Number(row.reserved_qty);
    stock.set(row.item_type, current);
  });
  preferences.inventory && stock.forEach((value, type) => {
    if (value.quantity < LOW_STOCK_THRESHOLD) notices.push({
      id: `stock:${type}`, title: `Low inventory: ${type.replace(/_/g, ' ')}`,
      detail: `${value.quantity} ${value.unit} currently available · Threshold ${LOW_STOCK_THRESHOLD}`,
      createdAt: new Date().toISOString(), category: 'Inventory', kind: 'alert', to: '/inventory',
    });
  });
  return notices.sort((a, b) => +new Date(b.createdAt) - +new Date(a.createdAt));
}
