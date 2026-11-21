import { getDonation, listDonations } from '../services/donationsService';
import type { DonationDetail, DonationFilters, DonationList } from '../types/donations';
import { useAsync } from './useRequests';

export const useDonationList = (f: DonationFilters) => useAsync<DonationList>(() => listDonations(f), [JSON.stringify(f)]);
export const useDonation = (id: string) => useAsync<DonationDetail>(() => getDonation(id), [id]);