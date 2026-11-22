import { supabase } from '../supabase';

/** RLS may return empty results without a session; admin services check first to explain the missing access. */
export async function hasSession(): Promise<boolean> {
  const { data } = await supabase.auth.getSession();
  return !!data.session;
}
