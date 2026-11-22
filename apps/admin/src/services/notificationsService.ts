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

const RECENT_ACTIVITY_DAYS = 7;
const one = (value: any) => Array.isArray(value) ? value[0] : value;

export async function listNotifications(): Promise<Notice[]> {
  if (!(await hasSession())) throw new Error('Sign in as an administrator to view notifications.');
  const recentSince = new Date(Date.now() - RECENT_ACTIVITY_DAYS * 24 * 60 * 60 * 1000).toISOString();
  const [incidents, requests, assignments, applications, movements] = await Promise.all([
    supabase.from('incidents').select('id, incident_type, status, created_at').in('status', ['open', 'under_review']).order('created_at', { ascending: false }).limit(20),
    supabase.from('requests').select('id, public_ref, kind, status, requester_name, created_at').gte('created_at', recentSince).order('created_at', { ascending: false }).limit(30),
    supabase.from('assignment_events').select('id, event_type, created_at, assignment:assignments!inner(id, request:requests!inner(public_ref), volunteer:profiles!volunteer_id(full_name))').gte('created_at', recentSince).order('created_at', { ascending: false }).limit(40),
    supabase.from('volunteer_applications').select('id, full_name, volunteer_type, review_status, created_at').in('review_status', ['submitted', 'under_review']).gte('created_at', recentSince).order('created_at', { ascending: false }).limit(20),
    supabase.from('inventory_movements').select('id, from_phase, to_phase, quantity, reason, request_id, created_at, inventory_lots!inner(item_type, unit)').gte('created_at', recentSince).order('created_at', { ascending: false }).limit(30),
  ]);
  for (const result of [incidents, requests, assignments, applications, movements]) if (result.error) throw result.error;

  const notices: Notice[] = [];
  (incidents.data ?? []).forEach((row: any) => notices.push({
    id: `incident:${row.id}`, title: `Incident needs review: ${row.incident_type.replace(/_/g, ' ')}`,
    detail: `${row.status.replace(/_/g, ' ')} · Incident ${row.id.slice(0, 8)}`,
    createdAt: row.created_at, category: 'Requests', kind: 'alert', to: `/incidents/${row.id}`,
  }));
  (requests.data ?? []).forEach((row: any) => notices.push({
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
  (applications.data ?? []).filter((row: any) => ['submitted', 'under_review'].includes(row.review_status)).forEach((row: any) => notices.push({
    id: `application:${row.id}`, title: 'Volunteer application received',
    detail: `${row.full_name} · ${row.volunteer_type.replace(/_/g, ' ')}`,
    createdAt: row.created_at, category: 'Requests', kind: 'normal', to: `/volunteers/${row.id}`,
  }));

  (movements.data ?? []).forEach((row: any) => {
    const lot = one(row.inventory_lots);
    const phase = row.to_phase.replace(/_/g, ' ');
    notices.push({
      id: `inventory-movement:${row.id}`,
      title: row.from_phase ? `Stock moved to ${phase}` : 'Stock received',
      detail: `${row.quantity} ${lot?.unit ?? ''} ${lot?.item_type?.replace(/_/g, ' ') ?? 'inventory'}${row.reason ? ` · ${row.reason}` : ''}`.trim(),
      createdAt: row.created_at, category: 'Inventory', kind: 'normal', to: `/inventory/movements/${row.id}`,
    });
  });

  return notices.sort((a, b) => +new Date(b.createdAt) - +new Date(a.createdAt));
}
