// Focused coverage for the simplified Profile and App Settings screens.
// Flutter 3.50 deprecates these compatibility imports; migrate with the app's dependency update.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khoroch_diary/core/l10n/app_strings.dart';
import 'package:khoroch_diary/core/theme/app_theme.dart';
import 'package:khoroch_diary/features/profile/profile_screen.dart';
import 'package:khoroch_diary/features/profile/settings_screen.dart';

const Size _smallPhone = Size(320, 568);
const Size _tallPhone = Size(400, 1600);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Size size = _tallPhone,
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      builder: (context, child) {
        final MediaQueryData data = MediaQuery.of(context);
        return MediaQuery(
          data: data.copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        );
      },
      home: child,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _reveal(
  WidgetTester tester,
  Finder target, {
  required Type screen,
}) async {
  await tester.scrollUntilVisible(
    target,
    120,
    scrollable: find.descendant(
      of: find.byType(screen),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('Profile', () {
    testWidgets('shows a short local profile and no invented account', (
      tester,
    ) async {
      await _pump(tester, const ProfileScreen());

      expect(find.byKey(const Key('profile-identity-card')), findsOneWidget);
      expect(find.text('Local profile'), findsOneWidget);
      expect(find.text('Saved on this device'), findsOneWidget);
      expect(find.textContaining('@'), findsNothing);
      expect(find.textContaining('Last synced'), findsNothing);
      expect(find.textContaining('Keshab'), findsNothing);
      expect(find.byKey(const Key('profile-offline-status')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps only useful account actions and a compact About list', (
      tester,
    ) async {
      await _pump(tester, const ProfileScreen());

      const List<String> usefulRows = <String>[
        'profile-wallet-row',
        'profile-backup-row',
        'profile-sign-in-row',
        'profile-app-settings-row',
      ];
      double previousTop = -1;
      for (final String key in usefulRows) {
        final Finder row = find.byKey(Key(key));
        expect(row, findsOneWidget);
        final double top = tester.getTopLeft(row).dy;
        expect(top, greaterThan(previousTop));
        previousTop = top;
      }
      expect(find.byKey(const Key('profile-about-row')), findsNothing);
      expect(find.byKey(const Key('profile-logout-row')), findsNothing);
      expect(find.text(ProfileScreen.versionLabel), findsOneWidget);
      expect(find.byKey(const Key('profile-licences-row')), findsOneWidget);
      expect(find.text('Where your data lives'), findsNothing);
      expect(
        find.text('Indian rupees (INR), Indian digit grouping'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('wired actions work and App Settings returns to Profile', (
      tester,
    ) async {
      int walletCalls = 0;
      int backupCalls = 0;
      int cloudCalls = 0;
      await _pump(
        tester,
        ProfileScreen(
          onWalletSummary: () => walletCalls++,
          onBackup: () => backupCalls++,
          onCloudBackup: () => cloudCalls++,
        ),
      );

      for (final (String key, VoidCallback _) in <(String, VoidCallback)>[
        ('profile-wallet-row', () => walletCalls++),
        ('profile-backup-row', () => backupCalls++),
        ('profile-sign-in-row', () => cloudCalls++),
      ]) {
        final Finder row = find.byKey(Key(key));
        await _reveal(tester, row, screen: ProfileScreen);
        await tester.tap(row.hitTestable());
        await tester.pumpAndSettle();
      }
      expect(walletCalls, 1);
      expect(backupCalls, 1);
      expect(cloudCalls, 1);

      final Finder settings = find.byKey(const Key('profile-app-settings-row'));
      await _reveal(tester, settings, screen: ProfileScreen);
      await tester.tap(settings.hitTestable());
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.text('INR (₹)'), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('gear opens the same App Settings page', (tester) async {
      await _pump(tester, const ProfileScreen());
      await tester.tap(find.byKey(const Key('profile-app-settings-gear')));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
    });
  });

  group('App Settings', () {
    testWidgets('shows only preferences and a short data/backup note', (
      tester,
    ) async {
      await _pump(tester, const SettingsScreen());

      expect(find.byKey(const Key('settings-currency-row')), findsOneWidget);
      expect(find.byKey(const Key('settings-theme-row')), findsOneWidget);
      expect(find.byKey(const Key('settings-language-row')), findsOneWidget);
      expect(find.byKey(const Key('settings-storage-row')), findsOneWidget);
      expect(find.text('INR (₹)'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
      expect(find.text('Your data'), findsOneWidget);
      expect(find.text('Back up or restore from Profile.'), findsOneWidget);
      expect(find.text('Fixed in v1'), findsNothing);
      expect(find.text('Cloud backup'), findsNothing);
      expect(find.text('Internet required'), findsNothing);
      expect(find.byKey(const Key('settings-readonly-notice')), findsNothing);
      expect(find.byKey(const Key('settings-change-language')), findsNothing);
      expect(find.text('Khoroch Diary 1.0.0 (build 1)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('language control appears only when it can save', (
      tester,
    ) async {
      await _pump(tester, SettingsScreen(onLanguageChanged: (_) async => true));
      expect(find.byKey(const Key('settings-change-language')), findsOneWidget);
      expect(find.text('Not available yet'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('uses concise Bengali labels and backup guidance', (
      tester,
    ) async {
      const AppStrings bn = AppStrings(AppLanguage.bn);
      await _pump(tester, const SettingsScreen(language: AppLanguage.bn));
      expect(find.text(bn.text(AppString.appSettings)), findsOneWidget);
      expect(find.text(bn.text(AppString.preferences)), findsOneWidget);
      expect(find.text(bn.text(AppString.storage)), findsOneWidget);
      expect(find.text(bn.text(AppString.currencyInr)), findsOneWidget);
      expect(find.text(bn.text(AppString.settingsBackupHint)), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('both pages stay usable at 320 dp and 200% text', (
      tester,
    ) async {
      for (final AppLanguage language in AppLanguage.values) {
        await _pump(
          tester,
          ProfileScreen(language: language),
          size: _smallPhone,
          scale: 2,
        );
        expect(tester.takeException(), isNull);

        expect(find.byType(Scrollable), findsWidgets);
        expect(tester.takeException(), isNull);

        // The title gear is always reachable; navigation stays clear at large
        // text without requiring a long profile list.
        await tester.tap(find.byKey(const Key('profile-app-settings-gear')));
        await tester.pumpAndSettle();
        expect(find.byType(SettingsScreen), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.byType(ProfileScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  });
}
