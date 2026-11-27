import 'package:app_pulse_kit/app_pulse_kit.dart';
// Flutter 3.50 deprecates this import; migrate with the app's dependency update.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:smart_review_feedback/smart_review_feedback.dart';

/// Central configuration for `app_pulse_kit` remote config and
/// `smart_review_feedback` rating/feedback routing in Khoroch Diary.
class KhorochPulseConfig {
  const KhorochPulseConfig._();

  static const String appName = 'Khoroch Diary';
  static const String packageId = 'com.keshabstudios.khorochdiary';
  static const String supportEmail = 'keshabsarkar2018@gmail.com';
  static const String pulseConfigUrl =
      'https://raw.githubusercontent.com/Keshab1997/khoroch-diary/main/pulse.json';

  static const PulseConfig fallbackConfig = PulseConfig(
    flags: <String, dynamic>{'ads_enabled': false, 'cloud_sync_beta': true},
  );
}

/// Exposes optional [AppPulseController] and [SmartReviewController] down the
/// widget tree without breaking existing screens or unit tests that omit them.
class KhorochServicesScope extends InheritedWidget {
  const KhorochServicesScope({
    super.key,
    this.pulseController,
    this.reviewController,
    required super.child,
  });

  final AppPulseController? pulseController;
  final SmartReviewController? reviewController;

  static KhorochServicesScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<KhorochServicesScope>();
  }

  @override
  bool updateShouldNotify(covariant KhorochServicesScope oldWidget) {
    return pulseController != oldWidget.pulseController ||
        reviewController != oldWidget.reviewController;
  }
}
