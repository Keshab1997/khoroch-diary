/// Build-time configuration for Khoroch Diary cloud backup & sync (B5).
///
/// Defaults to the baked-in project constants from
/// `core/config/cloud_project.dart`; `--dart-define=SUPABASE_URL=...` and
/// `--dart-define=SUPABASE_PUBLISHABLE_KEY=...` can override them at compile
/// time. Only publishable keys are ever used — no secrets in source.
library;

import 'package:flutter/foundation.dart' show kIsWeb;

import '../../core/config/cloud_project.dart';

final class CloudConfig {
  const CloudConfig({
    required this.url,
    required this.publishableKey,
    this.redirectTo = defaultRedirectTo,
  });

  /// Builds from the baked-in project constants in
  /// `core/config/cloud_project.dart` unless `--dart-define` overrides are
  /// provided, so a plain `flutter run` is cloud-enabled out of the box.
  const CloudConfig.fromEnvironment()
    : url = const String.fromEnvironment(
        'SUPABASE_URL',
        defaultValue: kSupabaseUrl,
      ),
      publishableKey = const String.fromEnvironment(
        'SUPABASE_PUBLISHABLE_KEY',
        defaultValue: kSupabasePublishableKey,
      ),
      redirectTo = defaultRedirectTo;

  /// Native OAuth callback registered in Supabase (`null` on web so the
  /// browser redirects back to the current page).
  static const String? defaultRedirectTo = kIsWeb
      ? null
      : 'com.keshabstudios.khorochdiary://login-callback';

  final String url;
  final String publishableKey;
  final String? redirectTo;

  /// `true` only when both [url] and [publishableKey] are non-blank and [url]
  /// parses as an `http` or `https` URI with a host.
  bool get isConfigured {
    final String trimmedUrl = url.trim();
    final String trimmedKey = publishableKey.trim();
    if (trimmedUrl.isEmpty || trimmedKey.isEmpty) return false;
    final Uri? parsed = Uri.tryParse(trimmedUrl);
    if (parsed == null || !parsed.hasAuthority || parsed.host.isEmpty) {
      return false;
    }
    return parsed.scheme == 'https' || parsed.scheme == 'http';
  }
}
