import type { ServiceRequest, TabKey } from '../types/requests';
import { humanize, kindLabel } from './labels';

export const PAGE_SIZE = 10;

export type Tone = 'warn' | 'info' | 'good' | 'bad' | 'muted';

export const STATUS_LABEL: Record<string, string> = {
  pending_admin_review: 'Pending', approved: 'Approved', awaiting_assignment: 'Awaiting assignment',
  assigned: 'Assigned', in_progress: 'In progress', fulfilled: 'Fulfilled',
  partially_fulfilled: 'Partly fulfilled', declined: 'Declined', cancelled: 'Cancelled',
};

export const STATUS_TONE: Record<string, Tone> = {
  pending_admin_review: 'warn', approved: 'info', awaiting_assignment: 'info', assigned: 'info',
  in_progress: 'info', fulfilled: 'good', partially_fulfilled: 'good', declined: 'bad', cancelled: 'muted',
};

export const TABS: { key: TabKey; label: string; statuses: string[] | null }[] = [
  { key: 'all', label: 'All', statuses: null },
  { key: 'pending', label: 'Pending Approval', statuses: ['pending_admin_review'] },
  { key: 'approved', label: 'Approved', statuses: ['approved', 'awaiting_assignment'] },
  { key: 'assigned', label: 'Assigned', statuses: ['assigned'] },
  { key: 'in_progress', label: 'In Progress', statuses: ['in_progress'] },
  { key: 'fulfilled', label: 'Fulfilled', statuses: ['fulfilled', 'partially_fulfilled'] },
  { key: 'declined', label: 'Declined', statuses: ['declined'] },
];

export const isPending = (s: string) => s === 'pending_admin_review';
export const isApproved = (s: string) => s === 'approved' || s === 'awaiting_assignment';

export const fmtDate = (iso: string) =>
  new Date(iso).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' });
export const fmtTime = (iso: string) =>
  new Date(iso).toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' });

export const itemLabel = (i: { itemType: string; unit: string }, qty: number) =>
  `${humanize(i.itemType)} · ${qty} ${i.unit}`;

export interface HistoryEntry { title: string; detail?: string; at?: string; done?: boolean }

/** No history table exists, so the timeline is derived from the request's own timestamps. */
export function buildHistory(r: ServiceRequest): HistoryEntry[] {
  const out: HistoryEntry[] = [{ title: 'Request submitted', detail: r.notes ?? `${kindLabel(r.kind)} request`, at: r.createdAt }];
  if (isPending(r.status)) out.push({ title: 'Awaiting admin review' });
  if (r.approvedAt) {
    const approved = r.items.filter((i) => i.approvedQty != null).map((i) => itemLabel(i, i.approvedQty!)).join(', ');
    out.push({ title: 'Request approved', detail: approved || undefined, at: r.approvedAt, done: true });
  }
  if (r.pickedUpAt) out.push({ title: 'Picked up', at: r.pickedUpAt, done: true });
  if (r.fulfilledAt) out.push({ title: 'Request fulfilled', at: r.fulfilledAt, done: true });
  if (r.status === 'declined') out.push({ title: 'Request declined', detail: r.declineReason ?? undefined, at: r.updatedAt ?? undefined, done: true });
  return out;
}