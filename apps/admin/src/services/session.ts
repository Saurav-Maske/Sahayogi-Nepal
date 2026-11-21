import { supabase } from '../supabase';

/** RLS returns empty results (not errors) with no session, so check first and show demo data instead of zeros. */
export async function hasSession(): Promise<boolean> {
  const { data } = await supabase.auth.getSession();
  return !!data.session;
}