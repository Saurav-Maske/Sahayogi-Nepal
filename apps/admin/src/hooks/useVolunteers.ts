import { getVolunteer, listVolunteers } from '../services/volunteersService';
import type { VolunteerDetail, VolunteerFilters, VolunteerList } from '../types/volunteers';
import { useAsync } from './useRequests';

export const useVolunteerList = (f: VolunteerFilters) => useAsync<VolunteerList>(() => listVolunteers(f), [JSON.stringify(f)]);
export const useVolunteer = (id: string) => useAsync<VolunteerDetail>(() => getVolunteer(id), [id]);