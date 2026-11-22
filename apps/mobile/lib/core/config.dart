// Client-safe Supabase values from the repository environment.
class Config {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://zttpmbxktwyriwtjlenm.supabase.co',
  );
  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_VxqApoHCGmu7VDmE9akq4Q_AZw_MWjl',
  );
}
