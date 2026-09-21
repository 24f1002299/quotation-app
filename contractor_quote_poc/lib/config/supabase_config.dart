/// supabase_config.dart — Day 7
///
/// Loads Supabase configuration from compile-time --dart-define values.
///
/// HOW TO RUN WITH REAL VALUES:
///   flutter run \
///     --dart-define=SUPABASE_URL=https://<project-ref>.supabase.co \
///     --dart-define=SUPABASE_ANON_KEY=<your-anon-key>
///
/// SECURITY RULES:
///   ✅ SUPABASE_ANON_KEY — safe to include in the app. It is a public key.
///      RLS policies protect all data even with the anon key.
///   ❌ SUPABASE_SERVICE_ROLE_KEY — NEVER use this in the Flutter app.
///      It bypasses all RLS and grants full database access.
///      The service-role key must stay on the Spring Boot server only.
///
/// Local dev (using local Supabase Docker):
///   flutter run \
///     --dart-define=SUPABASE_URL=http://10.0.2.2:54321 \
///     --dart-define=SUPABASE_ANON_KEY=<local-anon-key-from-supabase-start>
///
/// The local anon key is printed by `supabase start` or visible at:
///   Supabase Studio → http://localhost:54323 → Settings → API
library;

/// URL of the Supabase project.
/// Dev: http://10.0.2.2:54321 (Android emulator → localhost)
/// Prod: https://<project-ref>.supabase.co
const supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'http://10.0.2.2:54321', // local Docker default
);

/// Supabase anon key (public). Safe to ship in the app.
/// RLS policies ensure each user sees only their own data.
const supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: '', // Must be provided via --dart-define in real builds.
);

/// Validates that required Supabase config is present at startup.
/// Call from main() before initialising Supabase.
void assertSupabaseConfigValid() {
  assert(
    supabaseUrl.isNotEmpty,
    'SUPABASE_URL is not set. Pass --dart-define=SUPABASE_URL=<url>',
  );
  assert(
    supabaseAnonKey.isNotEmpty,
    'SUPABASE_ANON_KEY is not set. Pass --dart-define=SUPABASE_ANON_KEY=<key>',
  );
  assert(
    !supabaseAnonKey.contains('service_role'),
    'SUPABASE_ANON_KEY looks like a service-role key. '
    'Never put the service-role key in the Flutter app.',
  );
}
