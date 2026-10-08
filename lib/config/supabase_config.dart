/// ─────────────────────────────────────────────────────────────────────
///  PUT YOUR SUPABASE DETAILS HERE — this is the only file you need to edit.
///
///  1. Supabase dashboard → Project Settings → API
///  2. Copy "Project URL"            → paste it into [url]
///  3. Copy "anon" / "publishable" key → paste it into [anonKey]
///
///  The anon/publishable key is designed to be public. It is safe inside the
///  app because the SQL in supabase/setup.sql blocks direct table access.
///  NEVER paste the "service_role" / "secret" key here.
/// ─────────────────────────────────────────────────────────────────────
class SupabaseConfig {
  static const String url = 'PASTE_YOUR_SUPABASE_URL_HERE'; // https://xxxxxxxx.supabase.co
  static const String anonKey = 'PASTE_YOUR_ANON_OR_PUBLISHABLE_KEY_HERE';

  /// False until both values above have been replaced.
  static bool get isConfigured =>
      url.startsWith('https://') &&
      !url.contains('PASTE_') &&
      anonKey.length > 20 &&
      !anonKey.contains('PASTE_');

  static String get baseUrl => url.trim().replaceAll(RegExp(r'/+$'), '');
}
