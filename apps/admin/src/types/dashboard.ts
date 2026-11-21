export interface DashboardStats {
  totalRequests: number;
  totalRequestsChangePct: number; // vs last month
  pendingRequests: number;
  needReviewToday: number;
  approvedRequests: number;
  fulfilledRequests: number;
  fulfilmentRatePct: number;
  activeVolunteers: number;
  volunteerCategories: number;
  availableInventory: number;
  inventoryCategories: number;
  activeAssignments: number;
  driversEnRoute: number;
  openIncidents: number;
  urgentIncidents: number;
}

export interface ChartPoint {
  label: string;
  value: number;
  hint?: string; // longer text for the hover tooltip
}

export interface ActivityItem {
  id: string;
  time: string; // "10:42"
  text: string;
  href: string;
}

export interface LowStockAlert {
  item: string;
  available: number;
  threshold: number;
  unit: string;
}

export interface DashboardData {
  stats: DashboardStats;
  byCategory: ChartPoint[];
  fulfilledOverTime: ChartPoint[];
  activity: ActivityItem[];
  attention: { quantityDiscrepancies: number; lowStock: LowStockAlert | null };
  updatedAt: string; // ISO
  source: 'live' | 'demo';
}