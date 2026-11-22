/// The Supabase project behind Khoroch Diary's optional cloud backup.
///
/// Both values are public by design: every installed copy of the app carries
/// them, so they live in code rather than in build secrets (Keshab's decision,
/// 2026-11-20). They only let the app reach the project. What a signed-in
/// person may read or write is decided on the server by row-level security,
/// which limits every request to that person's own khatas and entries; the
/// anonymous role has no table access at all (see `supabase/migrations/`).
///
/// Never put a secret key or the service-role key here, or anywhere in `lib/`;
/// `test/cloud_project_test.dart` fails if one appears.
library;

/// URL of Supabase project `kajgkcevlhhcsnyvjxvy`.
const String kSupabaseUrl = 'https://kajgkcevlhhcsnyvjxvy.supabase.co';

/// Publishable (client) API key of the same project.
const String kSupabasePublishableKey =
    'sb_publishable_tApn4SeiNtt5XAWR-GMIBA_NpHul93m';
