// Volunteer types and what they mean. One volunteer can hold several types (for example driver AND doctor).
// Categories: A = general (every volunteer), B = driver, C = healthcare.
// The category list stored on profiles.categories is the union over all of the volunteer's types.

export const VOLUNTEER_TYPES = ["manpower", "driver", "doctor"] as const;
export type VolunteerType = typeof VOLUNTEER_TYPES[number];

const CATEGORIES: Record<VolunteerType, string[]> = {
  manpower: ["A"],
  driver: ["A", "B"],
  doctor: ["A", "C"],
};

// Upload kinds each type needs or may send. Every applicant uploads a citizenship photo.
const DOC_KINDS: Record<VolunteerType, string[]> = {
  manpower: ["citizenship"],
  driver: ["citizenship", "license"],
  doctor: ["citizenship", "service_card"],
};

// Which single type is stored in the legacy `volunteer_type` column when there are several.
const PRIMARY_ORDER: VolunteerType[] = ["doctor", "driver", "manpower"];

const isType = (t: string): t is VolunteerType => (VOLUNTEER_TYPES as readonly string[]).includes(t);

/**
 * Reads the types from a request body. `volunteer_types` (array) wins; the older single
 * `volunteer_type` (string) is still accepted. Returns null if missing, empty or invalid.
 */
export function parseVolunteerTypes(body: any): VolunteerType[] | null {
  let raw: unknown[];
  if (body?.volunteer_types !== undefined) {
    if (!Array.isArray(body.volunteer_types)) return null;
    raw = body.volunteer_types;
  } else if (body?.volunteer_type !== undefined) {
    raw = [body.volunteer_type];
  } else {
    return null;
  }
  const types = [...new Set(raw.map((t) => String(t)))];
  if (types.length < 1 || !types.every(isType)) return null;
  return types as VolunteerType[];
}

export const primaryType = (types: VolunteerType[]): VolunteerType =>
  PRIMARY_ORDER.find((t) => types.includes(t)) ?? types[0];

export const categoriesFor = (types: VolunteerType[]): string[] =>
  [...new Set(types.flatMap((t) => CATEGORIES[t]))].sort();

export const docKindsFor = (types: VolunteerType[]): string[] =>
  [...new Set(types.flatMap((t) => DOC_KINDS[t]))];