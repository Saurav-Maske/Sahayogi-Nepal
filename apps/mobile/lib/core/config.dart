// Pass at run time: flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
class Config {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: 'http://10.0.2.2:54321');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
}
