import 'dart:convert';
import 'dart:io';

import 'package:app_pulse_kit/app_pulse_kit.dart';
// Flutter 3.50 deprecates this import; migrate with the app's dependency update.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khoroch_diary/core/config/pulse_config.dart';
import 'package:khoroch_diary/core/l10n/app_strings.dart';
import 'package:khoroch_diary/core/theme/app_theme.dart';
import 'package:khoroch_diary/features/profile/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_review_feedback/smart_review_feedback.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('pulse.json parses cleanly and matches Khoroch Diary metadata', () {
    final File file = File('pulse.json');
    expect(file.existsSync(), isTrue);
    final Map<String, dynamic> decoded =
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final PulseConfig cfg = PulseConfig.fromJson(decoded);
    expect(cfg.update.latestVersion, '1.0.0');
    expect(cfg.update.androidUrl, contains(KhorochPulseConfig.packageId));
    expect(cfg.maintenance.enabled, isFalse);
  });

  testWidgets(
    'SettingsScreen shows Rate & Feedback and Check for Updates in Bangla at 2x scale',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final AppPulseController pulse = AppPulseController(
        source: MemoryPulseSource(KhorochPulseConfig.fallbackConfig),
        fallbackConfig: KhorochPulseConfig.fallbackConfig,
      );
      final SmartReviewController review = SmartReviewController(
        feedbackSink: MemoryFeedbackSink(),
        storage: InMemoryReviewStorage(),
        storeAdapter: FakeStoreReviewAdapter(),
        appName: KhorochPulseConfig.appName,
        appVersion: '1.0.0',
        buildNumber: '1',
      );
      await review.init();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          builder: (BuildContext context, Widget? child) {
            final MediaQueryData media = MediaQuery.of(context);
            return MediaQuery(
              data: media.copyWith(textScaler: const TextScaler.linear(2.0)),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: SettingsScreen(
            language: AppLanguage.bn,
            pulseController: pulse,
            reviewController: review,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final Finder rateRow = find.byKey(
        const Key('settings-rate-feedback-row'),
      );
      await tester.scrollUntilVisible(
        rateRow,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(rateRow, findsOneWidget);
      expect(find.text('রেটিং ও মতামত'), findsOneWidget);
      expect(
        find.byKey(const Key('settings-check-updates-row')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
