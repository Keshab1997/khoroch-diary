// Flutter 3.50 deprecates this import; migrate with the app's dependency update.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khoroch_diary/core/l10n/app_strings.dart';
import 'package:khoroch_diary/core/theme/app_theme.dart';
import 'package:khoroch_diary/features/onboarding/onboarding_screen.dart';

Future<void> _pumpOnboarding(
  WidgetTester tester, {
  AppLanguage language = AppLanguage.en,
  Future<void> Function(AppLanguage language)? onLanguageChanged,
  Future<void> Function()? onComplete,
  Size size = const Size(400, 800),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      builder: (BuildContext context, Widget? child) {
        final MediaQueryData media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(textScaler: TextScaler.linear(textScale)),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: OnboardingScreen(
        language: language,
        onLanguageChanged: onLanguageChanged ?? (_) async {},
        onComplete: onComplete ?? () async {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('first-run onboarding', () {
    testWidgets('explains real benefits and advances through all four pages', (
      WidgetTester tester,
    ) async {
      await _pumpOnboarding(tester);
      expect(find.text('Your everyday khata, made simple'), findsOneWidget);
      expect(find.textContaining('income and expenses'), findsOneWidget);

      await tester.tap(find.byKey(const Key('onboarding-next-button')));
      await tester.pumpAndSettle();
      expect(find.text('Works offline. No account needed.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('onboarding-next-button')));
      await tester.pumpAndSettle();
      expect(find.text('Keep different khatas organized'), findsOneWidget);

      await tester.tap(find.byKey(const Key('onboarding-next-button')));
      await tester.pumpAndSettle();
      expect(find.text('Useful tools. Backup on your terms.'), findsOneWidget);
      expect(find.byKey(const Key('onboarding-start-button')), findsOneWidget);
    });

    testWidgets('Start finishes onboarding once', (WidgetTester tester) async {
      int completeCalls = 0;
      await _pumpOnboarding(tester, onComplete: () async => completeCalls++);
      for (int i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const Key('onboarding-next-button')));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const Key('onboarding-start-button')));
      await tester.pumpAndSettle();
      expect(completeCalls, 1);
    });

    testWidgets('Skip completes immediately', (WidgetTester tester) async {
      int completeCalls = 0;
      await _pumpOnboarding(tester, onComplete: () async => completeCalls++);
      await tester.tap(find.byKey(const Key('onboarding-skip-button')));
      await tester.pumpAndSettle();
      expect(completeCalls, 1);
    });

    testWidgets('language button requests Bengali without losing page', (
      WidgetTester tester,
    ) async {
      AppLanguage? requested;
      await _pumpOnboarding(
        tester,
        onLanguageChanged: (AppLanguage language) async => requested = language,
      );
      await tester.tap(find.byKey(const Key('onboarding-language-button')));
      await tester.pumpAndSettle();
      expect(requested, AppLanguage.bn);
      expect(find.byKey(const Key('onboarding-screen')), findsOneWidget);
    });

    testWidgets('Bengali layout remains usable at 320dp and 200% text', (
      WidgetTester tester,
    ) async {
      await _pumpOnboarding(
        tester,
        language: AppLanguage.bn,
        size: const Size(320, 568),
        textScale: 2,
      );
      expect(find.text('প্রতিদিনের হিসাব, সহজে'), findsOneWidget);
      expect(find.byKey(const Key('onboarding-next-button')), findsOneWidget);
      expect(tester.takeException(), isNull);
      for (int i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const Key('onboarding-next-button')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      expect(find.byKey(const Key('onboarding-start-button')), findsOneWidget);
    });
  });
}
