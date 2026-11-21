export const humanize = (s: string) => {
  const t = (s ?? '').replace(/_/g, ' ').trim();
  return t.charAt(0).toUpperCase() + t.slice(1);
};

export const KIND_LABELS: Record<string, string> = {
  resource_request: 'Resources',
  manpower_request: 'Manpower',
  donation_offer: 'Donations',
  healthcare_request: 'Healthcare',
  transport_request: 'Transport',
};
export const kindLabel = (k: string) => KIND_LABELS[k] ?? humanize(k);

// volunteer_type enum: A=general, B=driver, C=healthcare (check exact enum values in the migration)
export const VOLUNTEER_LABELS: Record<string, string> = {
  general: 'Manpower', A: 'Manpower',
  driver: 'Drivers', B: 'Drivers',
  healthcare: 'Healthcare', doctor: 'Healthcare', C: 'Healthcare',
};
export const volunteerLabel = (t: string) => VOLUNTEER_LABELS[t] ?? humanize(t);