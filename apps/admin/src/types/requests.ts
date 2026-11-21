export type TabKey = 'all' | 'pending' | 'approved' | 'assigned' | 'in_progress' | 'fulfilled' | 'declined';

export interface RequestItem {
  id: string;
  itemType: string;
  unit: string;
  requestedQty: number;
  approvedQty: number | null;
  available: number | null; // central stock; only loaded on the detail view, null = not stock-limited
}

export interface ServiceRequest {
  id: string;
  publicRef: string;
  kind: string;
  status: string;
  requesterName: string;
  requesterPhone: string;
  district: string;
  createdAt: string;
  updatedAt: string | null;
  addressNote: string | null;
  urgency: string | null;
  notes: string | null;
  declineReason: string | null;
  approvedAt: string | null;
  pickedUpAt: string | null;
  fulfilledAt: string | null;
  items: RequestItem[];
}

export interface RequestFilters {
  tab: TabKey;
  q: string;
  districtId: number | null;
  kind: string;
  from: string; // yyyy-mm-dd
  to: string;
  page: number;
}

export interface ListResult { rows: ServiceRequest[]; total: number; allTotal: number; pendingTotal: number; demo: boolean }
export interface DetailResult { request: ServiceRequest; demo: boolean }
export interface District { id: number; name: string }
export interface ApprovedItem { item_id: string; qty: number }