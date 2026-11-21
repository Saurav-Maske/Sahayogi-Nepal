import { createClient } from "@supabase/supabase-js";
// Anon key only. NEVER put the service-role key in this app.
export const supabase = createClient(import.meta.env.VITE_SUPABASE_URL, import.meta.env.VITE_SUPABASE_ANON_KEY);
