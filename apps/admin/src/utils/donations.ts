import type { Donation, DonationTab } from '../types/donations';
import { humanize } from './labels';
import { fmtDate, itemLabel } from './requests';
import type { HistoryEntry } from './requests';

export const DONATION_TABS: { key: DonationTab; label: string; statuses: string[] | null }[] = [
  { key: 'all', label: 'All', statuses: null },
  { key: 'pending', label: 'Pending approval', statuses: ['pending_admin_review'] },
  { key: 'accepted', label: 'Accepted', statuses: ['approved', 'awaiting_assignment'] },
  { key: 'pickup', label: 'Pickup assigned', statuses: ['assigned'] },
  { key: 'in_progress', label: 'In progress', statuses: ['in_progress'] },
  { key: 'collected', label: 'Collected', statuses: ['fulfilled', 'partially_fulfilled'] },
  { key: 'declined', label: 'Declined', statuses: ['declined'] },
];

export const DONATION_STATUS_LABEL: Record<string, string> = {
  pending_admin_review: 'Pending', approved: 'Accepted', awaiting_assignment: 'Accepted',
  assigned: 'Pickup assigned', in_progress: 'Pickup in progress', fulfilled: 'Collected',
  partially_fulfilled: 'Partly collected', declined: 'Declined', cancelled: 'Cancelled',
};

export const isPendingDonation = (s: string) => s === 'pending_admin_review';
export const isFinalDonation = (s: string) => ['fulfilled', 'partially_fulfilled', 'declined', 'cancelled'].includes(s);
/** Accepted quantity can still be corrected until the driver verifies the pickup. */
export const canAdjustDonation = (s: string) => ['approved', 'awaiting_assignment', 'assigned', 'in_progress'].includes(s);

export const categoryOf = (d: Donation) => (d.items[0] ? humanize(d.items[0].itemType) : '—');
export { itemLabel };

export function buildDonationHistory(d: Donation): HistoryEntry[] {
  const out: HistoryEntry[] = [{ title: 'Donation offered', detail: d.items.map((i) => itemLabel(i, i.offeredQty)).join(', ') || undefined, at: d.createdAt }];
  if (d.status === 'pending_admin_review') out.push({ title: 'Awaiting admin review' });
  if (d.approvedAt) {
    const accepted = d.items.filter((i) => i.acceptedQty != null).map((i) => itemLabel(i, i.acceptedQty!)).join(', ');
    out.push({ title: 'Donation accepted', detail: accepted ? `Admin accepted ${accepted}` : undefined, at: d.approvedAt, done: true });
  }
  if (d.pickedUpAt) out.push({ title: 'Picked up by driver', at: d.pickedUpAt, done: true });
  if (d.fulfilledAt) out.push({ title: 'Collection verified', at: d.fulfilledAt, done: true });
  if (d.status === 'declined') out.push({ title: 'Donation declined', detail: d.declineReason ?? undefined, at: d.updatedAt ?? undefined, done: true });
  return out;
}
export { fmtDate };
