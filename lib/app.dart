import 'package:app_pulse_kit/app_pulse_kit.dart';
// Flutter 3.50 deprecates this import; migrate to material_ui in a dedicated dependency update.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:smart_review_feedback/smart_review_feedback.dart';

import 'core/config/pulse_config.dart';
import 'core/l10n/app_strings.dart';
import 'core/l10n/language_preference.dart';
import 'core/l10n/onboarding_preference.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/app_colors.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/shell/main_shell.dart';
import 'features/ledger/data/local_ledger.dart';
import 'features/sync/cloud_sync.dart';

class KhorochDiaryApp extends StatefulWidget {
  const KhorochDiaryApp({
    super.key,
    this.ledger,
    this.cloudSync,
    this.initialLanguage = AppLanguage.en,
    this.showOnboarding = false,
    this.pulseController,
    this.reviewController,
  });

  final LocalLedger? ledger;

  /// The live cloud sync service started in `main`. `null` (tests, web
  /// preview, or an unconfigured build) means the app stays purely local.
  final CloudSync? cloudSync;

  /// The language saved on this device, read before the first frame.
  final AppLanguage initialLanguage;

  /// First-run gate supplied by `main`; defaults off for embedded/widget tests.
  final bool showOnboarding;

  /// Optional remote update/maintenance/notices controller from `app_pulse_kit`.
  final AppPulseController? pulseController;

  /// Optional smart rating gate & private feedback controller.
  final SmartReviewController? reviewController;

  @override
  State<KhorochDiaryApp> createState() => _KhorochDiaryAppState();
}

class _KhorochDiaryAppState extends State<KhorochDiaryApp> {
  late bool _showOnboarding = widget.showOnboarding;
  late AppLanguage _language = widget.initialLanguage;

  Future<void> _changeOnboardingLanguage(AppLanguage language) async {
    final bool saved = await saveLanguagePreference(language);
    if (!mounted) return;
    if (saved) setState(() => _language = language);
  }

  Future<void> _finishOnboarding() async {
    // Let the user into the app even if preferences are temporarily unavailable;
    // the first-run prompt may return next time if storage still cannot be read.
    await saveOnboardingCompleted();
    if (mounted) setState(() => _showOnboarding = false);
  }

  @override
  void didUpdateWidget(covariant KhorochDiaryApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showOnboarding != widget.showOnboarding) {
      _showOnboarding = widget.showOnboarding;
    }
    if (oldWidget.initialLanguage != widget.initialLanguage) {
      _language = widget.initialLanguage;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget rootHome = _showOnboarding
        ? OnboardingScreen(
            language: _language,
            onLanguageChanged: _changeOnboardingLanguage,
            onComplete: _finishOnboarding,
          )
        : MainShell(
            ledger: widget.ledger,
            cloudSync: widget.cloudSync,
            initialLanguage: _language,
          );

    final AppPulseController? pulse = widget.pulseController;
    final Widget gatedHome = pulse == null
        ? rootHome
        : AppPulseGate(
            controller: pulse,
            strings: _language == AppLanguage.bn
                ? const PulseStrings.bn()
                : const PulseStrings.en(),
            child: rootHome,
          );

    return KhorochServicesScope(
      pulseController: widget.pulseController,
      reviewController: widget.reviewController,
      child: MaterialApp(
        title: 'Khoroch Diary',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        builder: (context, child) => Container(
          color: AppColors.navigationGrey.withAlpha(51),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: child!,
            ),
          ),
        ),
        home: gatedHome,
      ),
    );
  }
}
