import type { ChartPoint } from './dashboard';

export interface AnalyticsKpis {
  fulfilledRequests: number;
  districtsCovered: number;
  volunteerHours: number | null; // null = not tracked yet
  volunteerHoursChangePct: number | null;
  deliverySuccessPct: number | null;
  completedJobs: number;
  avgApprovalHours: number | null;
  avgApprovalChangeMin: number | null; // negative = faster
}

export interface AnalyticsData {
  kpis: AnalyticsKpis;
  donationsVsDistribution: ChartPoint[]; // kg, alternating donated / distributed
  volunteerParticipation: ChartPoint[];
  inventoryStock: ChartPoint[];
  requestsByDistrict: ChartPoint[];
  updatedAt: string;
}
