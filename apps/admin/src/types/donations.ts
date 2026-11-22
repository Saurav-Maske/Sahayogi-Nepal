export type DonationTab = 'all' | 'pending' | 'accepted' | 'pickup' | 'collected' | 'declined';

/** Four separate records per item (request_items): offered, accepted, donor-updated, verified collected. */
export interface DonationItem {
  id: string;
  itemType: string;
  unit: string;
  offeredQty: number;
  acceptedQty: number | null;
  donorQty: number | null;
  collectedQty: number | null;
}

export interface DonationDriver { assignmentId: string; state: string; name: string | null; phone: string | null }

export interface Donation {
  id: string;
  publicRef: string;
  status: string;
  donorName: string;
  donorPhone: string;
  district: string;
  createdAt: string;
  updatedAt: string | null;
  addressNote: string | null;
  notes: string | null;
  declineReason: string | null;
  approvedAt: string | null;
  pickedUpAt: string | null;
  fulfilledAt: string | null;
  items: DonationItem[];
  driver: DonationDriver | null;
}

export interface DonationFilters {
  tab: DonationTab; q: string; districtId: number | null; itemType: string; from: string; to: string; page: number;
}
export interface DonationList { rows: Donation[]; total: number; allTotal: number; pendingTotal: number }
export interface DonationDetail { donation: Donation }
