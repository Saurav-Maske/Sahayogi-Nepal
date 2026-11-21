export type VolunteerTab = 'pending' | 'approved' | 'declined' | 'suspended';

/** One row of volunteer_applications, plus the linked profile's account_status. */
export interface Volunteer {
  id: string; // application id
  profileId: string | null;
  fullName: string;
  email: string;
  phone: string;
  volunteerType: string | null;
  citizenshipNo: string | null;
  citizenshipPath: string | null;
  licenseNo: string | null;
  licensePath: string | null;
  serviceCardNo: string | null;
  serviceCardPath: string | null;
  reviewStatus: string;
  reviewNote: string | null;
  reviewedAt: string | null;
  createdAt: string;
  accountStatus: string | null;
}

export interface VolunteerStats {
  completedJobs: number;
  hours: number | null; // not tracked in the schema yet
  kgDelivered: number;
  donationsCollected: number;
  successPct: number | null;
}

export interface VolunteerFilters { tab: VolunteerTab; q: string; category: string; days: string; page: number }
export interface VolunteerList { rows: Volunteer[]; total: number; pendingTotal: number; approvedTotal: number; demo: boolean }
export interface VolunteerDetail { volunteer: Volunteer; stats: VolunteerStats | null; demo: boolean }
export type VolunteerDecision = 'approve' | 'reject' | 'suspend' | 'reinstate';