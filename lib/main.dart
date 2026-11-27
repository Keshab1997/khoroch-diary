// Flutter 3.50 deprecates this import; migrate to material_ui in a dedicated dependency update.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import 'dart:async' show runZonedGuarded, unawaited;

import 'package:app_pulse_kit/app_pulse_kit.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:smart_review_feedback/smart_review_feedback.dart';

import 'app.dart';
import 'core/config/pulse_config.dart';
import 'core/l10n/app_strings.dart';
import 'core/l10n/language_preference.dart';
import 'core/l10n/onboarding_preference.dart';
import 'features/ledger/data/local_ledger.dart';
import 'features/ledger/data/web_ledger_stub.dart'
    if (dart.library.js_interop) 'features/ledger/data/web_ledger.dart'
    if (dart.library.html) 'features/ledger/data/web_ledger.dart';
import 'features/sync/cloud_sync.dart';

Future<void> main() async {
  // Last-resort hook so an uncaught async error in the field at least reaches
  // the device log instead of dying silently. (No crash reporter is wired up;
  // this is deliberately the cheapest observable sink.)
  await runZonedGuarded<Future<void>>(_run, (Object error, StackTrace stack) {
    debugPrint('Khoroch Diary uncaught error: $error\n$stack');
  });
}

Future<void> _run() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Read the saved language before the first frame, so a Bengali user never
  // sees an English flash.
  final AppLanguage language = await loadLanguagePreference();
  final bool onboardingCompleted = await loadOnboardingCompleted();

  // Web opens the real WASM/IndexedDB ledger; native uses the on-device DB.
  // Passing a live ledger makes MainShell leave its read-only preview mode.
  final LocalLedger ledger = kIsWeb
      ? await openWebLedger()
      : LocalLedger.device();
  await ledger.initialize();

  CloudSync? cloudSync;
  try {
    cloudSync = await CloudSync.start(ledger: ledger);
  } catch (error) {
    // Sync must never block startup: a bad config or an unreachable project
    // leaves the app purely local-only. But the failure must not vanish
    // either — persist it to sync_metadata.last_error so the Diagnostics
    // screen (Cloud Backup → Diagnostics) can show it, and log it.
    cloudSync = null;
    final String reason = _startupSyncFailure(error);
    debugPrint(reason);
    unawaited(
      ledger
          .writeSyncMetadata(lastError: reason)
          .catchError(
            (Object e) => debugPrint('Could not record startup sync error: $e'),
          ),
    );
  }
  AppPulseController? pulseController;
  try {
    pulseController = await AppPulse.init(
      configUrl: KhorochPulseConfig.pulseConfigUrl,
      fallbackConfig: KhorochPulseConfig.fallbackConfig,
    );
  } catch (error) {
    debugPrint('AppPulse init skipped: $error');
  }

  SmartReviewController? reviewController;
  try {
    reviewController = await SmartReview.init(
      feedbackSink: const EmailFeedbackSink(
        toEmail: KhorochPulseConfig.supportEmail,
      ),
      appName: KhorochPulseConfig.appName,
      androidPackageName: KhorochPulseConfig.packageId,
    );
  } catch (error) {
    debugPrint('SmartReview init skipped: $error');
  }

  runApp(
    KhorochDiaryApp(
      ledger: ledger,
      cloudSync: cloudSync,
      initialLanguage: language,
      showOnboarding: !onboardingCompleted,
      pulseController: pulseController,
      reviewController: reviewController,
    ),
  );
}

/// One-line, length-capped description of a `CloudSync.start` failure, safe
/// to persist in `sync_metadata.last_error` and show on the Diagnostics
/// screen.
String _startupSyncFailure(Object error) {
  const int maxLength = 300;
  final String detail = error.toString().replaceAll('\n', ' ');
  final String reason = 'Cloud sync failed to start: $detail';
  return reason.length <= maxLength
      ? reason
      : '${reason.substring(0, maxLength - 1)}…';
}
