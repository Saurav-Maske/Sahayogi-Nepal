import type { Volunteer, VolunteerTab } from '../types/volunteers';
import { humanize, volunteerLabel } from './labels';

export const VOLUNTEER_TABS: { key: VolunteerTab; label: string }[] = [
  { key: 'pending', label: 'Pending Applications' },
  { key: 'approved', label: 'Approved Volunteers' },
  { key: 'declined', label: 'Declined' },
  { key: 'suspended', label: 'Suspended' },
];

/** Raw volunteer_type enum values. Check the enum in the migration; the contract says A=general, B=driver, C=healthcare. */
export const CATEGORY_OPTIONS = [
  { value: 'general', label: 'Manpower' },
  { value: 'driver', label: 'Driver' },
  { value: 'doctor', label: 'Healthcare' },
];

export const DAY_OPTIONS = [
  { value: '', label: 'Applied: any time' },
  { value: '7', label: 'Last 7 days' },
  { value: '30', label: 'Last 30 days' },
  { value: '90', label: 'Last 90 days' },
];

const CATEGORY: Record<string, { name: string; perms: string }> = {
  Manpower: { name: 'Manpower', perms: 'A' },
  Drivers: { name: 'Driver', perms: 'A + B' },
  Healthcare: { name: 'Healthcare', perms: 'A + C' },
};

export function categoryInfo(type: string | null) {
  if (!type) return { name: '—', perms: '—' };
  return CATEGORY[volunteerLabel(type)] ?? { name: humanize(type), perms: '—' };
}

export const isSuspended = (v: Volunteer) => v.accountStatus === 'suspended';

/** Citizenship is always required; a driver also needs a licence, healthcare a service card. */
export function documentsReady(v: Volunteer): boolean {
  const { perms } = categoryInfo(v.volunteerType);
  const ok = !!(v.citizenshipNo && v.citizenshipPath);
  const licence = !perms.includes('B') || !!(v.licenseNo && v.licensePath);
  const card = !perms.includes('C') || !!(v.serviceCardNo && v.serviceCardPath);
  return ok && licence && card;
}

/** Shows the start and end of an ID number only. */
export function maskId(s: string | null) {
  if (!s) return 'Not provided';
  return s.length <= 6 ? '••••••' : `${s.slice(0, 5)}••••••${s.slice(-2)}`;
}