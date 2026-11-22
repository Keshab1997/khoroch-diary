// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khoroch_diary/core/l10n/app_strings.dart';
import 'package:khoroch_diary/core/theme/app_theme.dart';
import 'package:khoroch_diary/features/counter/note_counter_screen.dart';
import 'package:khoroch_diary/features/profile/profile_screen.dart';
import 'package:khoroch_diary/features/profile/settings_screen.dart';

const Size _smallViewport = Size(320, 568);
const Size _tallViewport = Size(400, 1600);

Future<void> _pumpWithScale(
  WidgetTester tester,
  Widget child, {
  Size size = _tallViewport,
  double scale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      builder: (BuildContext context, Widget? navigator) {
        final MediaQueryData media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(textScaler: TextScaler.linear(scale)),
          child: navigator ?? const SizedBox.shrink(),
        );
      },
      home: child,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _revealOn(
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
  testWidgets('the full-screen counter has no settings app bar', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: NoteCounterScreen()));
    expect(find.byType(AppBar), findsNothing);
    expect(find.byTooltip('Settings'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'profile action list follows S5 row order before and after settings nav',
    (WidgetTester tester) async {
      await _pumpWithScale(tester, const ProfileScreen());
      expect(tester.takeException(), isNull);

      const List<String> expectedOrder = <String>[
        'profile-wallet-row',
        'profile-backup-row',
        'profile-sign-in-row',
        'profile-app-settings-row',
        'profile-about-row',
        'profile-logout-row',
      ];

      double lastDy = -1;
      for (final String key in expectedOrder) {
        final double dy = tester.getTopLeft(find.byKey(Key(key))).dy;
        expect(dy, greaterThan(lastDy), reason: '$key out of order');
        lastDy = dy;
      }

      await tester.tap(find.byKey(const Key('profile-app-settings-row')));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final AppLanguage language in AppLanguage.values) {
    testWidgets(
      '320x568 at 200% text navigates Profile <-> Settings without overflow (${language.name})',
      (WidgetTester tester) async {
        await _pumpWithScale(
          tester,
          ProfileScreen(language: language),
          size: _smallViewport,
          scale: 2.0,
        );
        expect(tester.takeException(), isNull);

        final Finder settingsRow = find.byKey(
          const Key('profile-app-settings-row'),
        );
        await _revealOn(tester, settingsRow, screen: ProfileScreen);
        expect(tester.takeException(), isNull);

        await tester.tap(settingsRow.hitTestable());
        await tester.pumpAndSettle();
        expect(find.byType(SettingsScreen), findsOneWidget);
        expect(tester.takeException(), isNull);

        await _revealOn(
          tester,
          find.byKey(const Key('settings-offline-backup-row')),
          screen: SettingsScreen,
        );
        expect(tester.takeException(), isNull);

        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.byType(ProfileScreen), findsOneWidget);
        expect(tester.takeException(), isNull);

        await _revealOn(
          tester,
          find.byKey(const Key('profile-logout-row')),
          screen: ProfileScreen,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
