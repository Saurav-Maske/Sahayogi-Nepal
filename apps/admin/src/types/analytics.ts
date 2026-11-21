import type { ChartPoint } from './dashboard';

export interface AnalyticsKpis {
  peopleSupported: number;
  districtsCovered: number;
  volunteerHours: number | null; // null = not tracked yet
  volunteerHoursChangePct: number | null;
  deliverySuccessPct: number;
  completedJobs: number;
  avgApprovalHours: number;
  avgApprovalChangeMin: number | null; // negative = faster
}

export interface AnalyticsData {
  kpis: AnalyticsKpis;
  donationsVsDistribution: ChartPoint[]; // kg, alternating donated / distributed
  volunteerParticipation: ChartPoint[];
  inventoryStock: ChartPoint[];
  requestsByDistrict: ChartPoint[];
  updatedAt: string;
  demoSections: string[]; // sections currently showing demo data
}