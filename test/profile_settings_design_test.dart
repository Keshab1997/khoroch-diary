// Design/layout/navigation regression tests for the account area: Profile and
// App Settings share one branded header family, keep every control reachable
// and tappable at the smallest supported viewport, and stay readable in both
// languages.
//
// These tests are additive: they do not relax any assertion in
// profile_settings_test.dart, offline_profile_test.dart,
// settings_language_test.dart or settings_navigation_test.dart.
//
import 'package:drift/native.dart';
// Flutter 3.50 deprecates this import; migrate with the app's dependency update.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khoroch_diary/core/l10n/app_strings.dart';
import 'package:khoroch_diary/core/theme/app_colors.dart';
import 'package:khoroch_diary/core/widgets/ledger_header_background.dart';
import 'package:khoroch_diary/core/theme/app_theme.dart';
import 'package:khoroch_diary/features/ledger/data/local_ledger.dart';
import 'package:khoroch_diary/features/profile/profile_screen.dart';
import 'package:khoroch_diary/features/profile/profile_store.dart';
import 'package:khoroch_diary/features/profile/settings_screen.dart';

/// The smallest supported phone (320 x 568 logical px).
const Size smallPhone = Size(320, 568);

/// A tall viewport so lazily built list children are all mounted.
const Size tallPhone = Size(400, 1600);

/// The largest supported text scale.
const double largeScale = 2.0;

/// Pumps [screen] with the real app theme at [size] and [scale].
///
/// No `FlutterError.onError` override: the binding already fails a test on a
/// framework error such as a `RenderFlex` overflow.
Future<void> pumpScreen(
  WidgetTester tester,
  Widget screen, {
  Size size = tallPhone,
  double scale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      builder: (BuildContext context, Widget? child) {
        final MediaQueryData media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(textScaler: TextScaler.linear(scale)),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: screen,
    ),
  );
  await tester.pumpAndSettle();
}

/// Opens an in-memory ledger and closes it with the test.
///
/// Opening and closing run outside the fake-async zone, as in the other
/// database widget tests here; otherwise the profile card's `store.load()`
/// future can never complete and the card's spinner keeps the test pumping
/// forever, and the next test can stall while opening its database.
Future<LocalLedger> openInMemoryLedger(WidgetTester tester) async {
  final LocalLedger ledger = LocalLedger(NativeDatabase.memory());
  await tester.runAsync(ledger.initialize);
  addTearDown(() => tester.runAsync(ledger.close));
  return ledger;
}

/// A profile store over its own in-memory ledger, cleaned up per test.
Future<ProfileStore> openMemoryStore(WidgetTester tester) async =>
    ProfileStore(await openInMemoryLedger(tester));

/// Opens [SettingsScreen] as a pushed route so its back control exists, the
/// way the app really shows it.
Future<void> openSettingsRoute(
  WidgetTester tester, {
  AppLanguage language = AppLanguage.en,
  Size size = tallPhone,
  double scale = 1.0,
}) async {
  await pumpScreen(
    tester,
    Scaffold(
      body: Builder(
        builder: (BuildContext context) => Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (BuildContext _) => SettingsScreen(language: language),
              ),
            ),
            child: const Text('open-settings'),
          ),
        ),
      ),
    ),
    size: size,
    scale: scale,
  );
  await tester.tap(find.text('open-settings'));
  await tester.pumpAndSettle();
}

/// The scroll view owned by [screen].
Finder scrollableOf(Type screen) =>
    find.descendant(of: find.byType(screen), matching: find.byType(Scrollable));

/// Scrolls [screen] until [finder] is visible.
Future<void> reveal(
  WidgetTester tester,
  Finder finder, {
  required Type screen,
}) async {
  await tester.scrollUntilVisible(
    finder,
    120,
    scrollable: scrollableOf(screen),
  );
  await tester.pumpAndSettle();
}

/// The header banner of [screen], found through the key it puts on it.
Finder headerOf(String key) => find.byKey(Key(key));

/// Asserts [finder] resolves to a target at least 48 dp on both sides.
void expectTapTarget(
  WidgetTester tester,
  Finder finder, {
  required String reason,
}) {
  final Size size = tester.getSize(finder);
  expect(
    size.width >= 48 && size.height >= 48,
    isTrue,
    reason: '$reason (found ${size.width} x ${size.height})',
  );
}

void main() {
  group('account header family', () {
    for (final AppLanguage language in AppLanguage.values) {
      final String title = language == AppLanguage.bn ? 'প্রোফাইল' : 'Profile';
      testWidgets(
        'Profile wears the branded banner header (${language.name})',
        (WidgetTester tester) async {
          await pumpScreen(tester, ProfileScreen(language: language));

          final Finder header = headerOf('profile-header');
          expect(header, findsOneWidget);

          // No AppBar on the account family: the banner is the header.
          expect(find.byType(AppBar), findsNothing);

          expect(
            find.descendant(
              of: header,
              matching: find.byType(LedgerHeaderBackground),
            ),
            findsOneWidget,
          );

          // The title is the localized screen name, inside the header, and it
          // is the strong white-on-green type the family uses.
          final Finder titleFinder = find.descendant(
            of: header,
            matching: find.text(title),
          );
          expect(titleFinder, findsOneWidget);
          final Text titleText = tester.widget<Text>(titleFinder);
          expect(titleText.style?.fontWeight, FontWeight.w800);
          expect(titleText.style?.color, AppColors.onPrimary);

          // The settings gear survives the redesign, at a 48 dp target.
          final Finder gear = find.byKey(
            const Key('profile-app-settings-gear'),
          );
          expect(gear, findsOneWidget);
          expect(
            find.descendant(of: header, matching: gear),
            findsOneWidget,
            reason: 'the gear belongs in the header action slot',
          );
          expectTapTarget(
            tester,
            gear,
            reason: 'the settings gear is a 48 dp target',
          );

          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('App Settings wears the same header and a real back button', (
      WidgetTester tester,
    ) async {
      await openSettingsRoute(tester);

      expect(find.byType(AppBar), findsNothing);
      expect(headerOf('settings-header'), findsOneWidget);

      expect(
        find.descendant(
          of: headerOf('settings-header'),
          matching: find.byType(LedgerHeaderBackground),
        ),
        findsOneWidget,
      );

      // The back control is still a real BackButton, so the existing
      // navigation tests keep working, and it is a 48 dp target.
      final Finder back = find.byType(BackButton);
      expect(back, findsOneWidget);
      expectTapTarget(
        tester,
        back,
        reason: 'the back control is a 48 dp target',
      );
      expect(
        find.descendant(
          of: headerOf('settings-header'),
          matching: find.byType(BackButton),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('both account screens use the same banner geometry', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester, const ProfileScreen());
      final double profileHeight = tester
          .getSize(headerOf('profile-header'))
          .height;

      await pumpScreen(tester, const SettingsScreen());
      final double settingsHeight = tester
          .getSize(headerOf('settings-header'))
          .height;

      expect(settingsHeight, profileHeight);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the settings title is localized in Bengali', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester, const SettingsScreen(language: AppLanguage.bn));

      expect(
        find.descendant(
          of: headerOf('settings-header'),
          matching: find.text('অ্যাপ সেটিংস'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('profile identity area', () {
    testWidgets('the identity card is one unit and keeps its actions', (
      WidgetTester tester,
    ) async {
      final ProfileStore store = await openMemoryStore(tester);
      await pumpScreen(
        tester,
        ProfileScreen(profileStore: store, onPickAvatar: () async => null),
      );

      expect(find.byKey(const Key('profile-identity-card')), findsOneWidget);
      // Editing affordances and the honest local-only state are unchanged.
      expect(find.text('Edit name'), findsOneWidget);
      expect(find.text('Choose photo'), findsOneWidget);
      expect(find.text('Not signed in'), findsOneWidget);
      expect(find.text('Local profile'), findsOneWidget);
      expect(find.text('KHOROCH DIARY'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the editable identity card keeps its real controls', (
      WidgetTester tester,
    ) async {
      final ProfileStore store = await openMemoryStore(tester);
      await pumpScreen(
        tester,
        ProfileScreen(profileStore: store, onPickAvatar: () async => null),
      );

      expect(find.byKey(const Key('profile-identity-card')), findsOneWidget);
      expect(find.text('Edit name'), findsOneWidget);
      expect(find.text('Choose photo'), findsOneWidget);
      final Finder avatar = find.byKey(const Key('profile-avatar'));
      expect(
        tester.getBottomLeft(find.text('KHOROCH DIARY')).dy,
        lessThan(tester.getTopLeft(avatar).dy),
        reason: 'The avatar must not paint over the brand caption',
      );
      // A cancelled picker is not an error state: the card stays usable.
      await tester.tap(find.text('Choose photo'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Edit name'), findsOneWidget);
    });

    testWidgets('identity card copy is translated in Bengali', (
      WidgetTester tester,
    ) async {
      final ProfileStore store = await openMemoryStore(tester);
      await pumpScreen(
        tester,
        ProfileScreen(
          language: AppLanguage.bn,
          profileStore: store,
          onPickAvatar: () async => null,
        ),
      );

      expect(find.text('স্থানীয় প্রোফাইল'), findsOneWidget);
      expect(find.text('নাম পরিবর্তন'), findsOneWidget);
      expect(find.text('ছবি বাছুন'), findsOneWidget);
      // The brand caption is localized too, and no English tagline is left.
      expect(find.text('খরচের ডায়েরি'), findsOneWidget);
      expect(
        find.text('Khoroch Diary · Your ledger, on your phone'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('smallest viewport at 200% text', () {
    testWidgets('Profile scrolls to its last row without overflow (English)', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        const ProfileScreen(),
        size: smallPhone,
        scale: largeScale,
      );
      expect(tester.takeException(), isNull);

      await reveal(
        tester,
        find.byKey(const Key('profile-licences-row')),
        screen: ProfileScreen,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Profile scrolls to its last row without overflow (Bengali)', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        const ProfileScreen(language: AppLanguage.bn),
        size: smallPhone,
        scale: largeScale,
      );
      expect(tester.takeException(), isNull);

      await reveal(
        tester,
        find.byKey(const Key('profile-licences-row')),
        screen: ProfileScreen,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('App Settings scrolls to its last row without overflow', (
      WidgetTester tester,
    ) async {
      await openSettingsRoute(
        tester,
        language: AppLanguage.bn,
        size: smallPhone,
        scale: largeScale,
      );
      expect(tester.takeException(), isNull);

      await reveal(
        tester,
        find.byKey(const Key('settings-offline-backup-row')),
        screen: SettingsScreen,
      );
      expect(tester.takeException(), isNull);

      // Back navigation stays reachable at this scale.
      expectTapTarget(
        tester,
        find.byType(BackButton),
        reason: 'back control at 200% text scale',
      );
    });

    testWidgets('the header title stays inside the banner at 200% text', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        const SettingsScreen(),
        size: smallPhone,
        scale: largeScale,
      );
      // The title is one line on a fixed-height banner: it is scaled down to
      // fit rather than wrapped, so the banner can never overflow.
      final Finder title = find.descendant(
        of: headerOf('settings-header'),
        matching: find.text('App Settings'),
      );
      expect(title, findsOneWidget);
      final Rect banner = tester.getRect(headerOf('settings-header'));
      final Rect text = tester.getRect(title);
      expect(text.top >= banner.top - 0.5, isTrue);
      expect(text.bottom <= banner.bottom + 0.5, isTrue);
      expect(tester.takeException(), isNull);
    });
  });

  group('navigation kept intact', () {
    testWidgets('the gear opens App Settings and back returns to Profile', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester, const ProfileScreen(language: AppLanguage.bn));

      await tester.tap(find.byKey(const Key('profile-app-settings-gear')));
      await tester.pumpAndSettle();

      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(headerOf('settings-header'), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(headerOf('profile-header'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
