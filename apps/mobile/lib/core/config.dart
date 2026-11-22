// Client-safe Supabase values from the repository environment.
class Config {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://gtehciwxxiovriymogpa.supabase.co',
  );
  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_zF1QFOkQG-kqe-cJld6RGA_gB9TVdAV',
  );
}