// Design & layout regression gate for the account family: the pushed Sign-in,
// Cloud Backup pages and the embedded Account card (batch account-design-b1).
//
// These tests assert presentation only - the shared branded page header, the
// hierarchy of the action blocks, the warm card surfaces, and that nothing
// overflows or loses its hit area at 320x568 with 200 % text - so the
// behavioural suites (sign_in_screen_test.dart, cloud_backup_screen_test.dart,
// account_card_test.dart) keep owning every callback, route result and state.
//
// Flutter 3.50 deprecates this import; migrate with the app's dependency update.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khoroch_diary/core/l10n/app_strings.dart' show AppLanguage;
import 'package:khoroch_diary/core/theme/app_colors.dart';
import 'package:khoroch_diary/core/widgets/ledger_header_background.dart';
import 'package:khoroch_diary/core/theme/app_theme.dart';
import 'package:khoroch_diary/features/sync/account_card.dart';
import 'package:khoroch_diary/features/sync/cloud_backup_screen.dart';
import 'package:khoroch_diary/features/sync/sign_in_screen.dart';
import 'package:khoroch_diary/features/sync/sync_engine.dart';
import 'package:khoroch_diary/features/sync/sync_status.dart';

import 'support/fake_cloud_backend.dart';

/// The small phone the brief gates on: 320x568 with 200 % text must scroll
/// cleanly, so every layout test that cares about content visibility still
/// gets a viewport tall enough to build the whole page (a ListView never builds
/// what it cannot show, and an off-screen button is not a hierarchy bug).
const Size _smallPhone = Size(320, 568);
const Size _tallPhone = Size(400, 1400);

/// Above this scale the header drops its subtitle; the layout tests use it as
/// the single definition of "large text" so the assertion and the widget agree.
const double _largeText = 2.0;

const Key _headerKey = Key('account-page-header');
const Key _titleKey = Key('account-page-title');
const Key _backKey = Key('account-page-back');

/// The first painted surface under [key]: the [Container] itself when the key
/// sits on one, otherwise the card shell's own [Container] inside it.
BoxDecoration _decorationOf(WidgetTester tester, Key key) {
  final Finder target = find.byKey(key);
  final Widget self = tester.widget(target);
  if (self is Container && self.decoration is BoxDecoration) {
    return self.decoration! as BoxDecoration;
  }
  final Finder inner = find
      .descendant(of: target, matching: find.byType(Container))
      .first;
  return tester.widget<Container>(inner).decoration! as BoxDecoration;
}

/// Pumps [screen] as a normal pushed route: the page is reached by tapping
/// "open", so `Navigator.canPop()` is true and the back action is real.
Future<void> _pumpPushed(
  WidgetTester tester,
  Widget screen, {
  Size size = _tallPhone,
  double textScale = 1,
  bool push = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    // A fresh key per pump: the same test may render the page twice (en, then
    // bn) and must start from the parent screen each time.
    MaterialApp(
      key: UniqueKey(),
      theme: AppTheme.light(),
      builder: (BuildContext context, Widget? child) {
        final MediaQueryData media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: TextScaler.linear(textScale),
            padding: const EdgeInsets.only(top: 24, bottom: 16),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: Builder(
        builder: (BuildContext context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context)
                  .push<void>(MaterialPageRoute<void>(builder: (_) => screen)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (push) {
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }
}

/// Pumps the card on its own, the way Profile embeds it: a scrolling parent,
/// not a full screen.
Future<void> _pumpCard(
  WidgetTester tester,
  Widget card, {
  Size size = _smallPhone,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      key: UniqueKey(),
      theme: AppTheme.light(),
      builder: (BuildContext context, Widget? child) {
        final MediaQueryData media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(textScaler: TextScaler.linear(textScale)),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[card],
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('branded account page header', () {
    testWidgets(
      'SignInScreen: green banner with golden edge, icon, title, back',
      (WidgetTester tester) async {
        final FakeCloudBackend backend = FakeCloudBackend();
        await _pumpPushed(tester, SignInScreen(backend: backend));

        expect(find.byKey(_headerKey), findsOneWidget);
        expect(find.byType(LedgerHeaderBackground), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(_headerKey),
            matching: find.byType(CustomPaint),
          ),
          findsWidgets,
        );

        // Localized title, one line, ellipsized; contextual cloud icon beside it.
        final Text title = tester.widget<Text>(find.byKey(_titleKey));
        expect(title.data, 'Sign in');
        expect(title.maxLines, 1);
        expect(title.overflow, TextOverflow.ellipsis);
        expect(
          find.descendant(
            of: find.byKey(_headerKey),
            matching: find.byIcon(Icons.cloud_outlined),
          ),
          findsOneWidget,
        );

        // Back navigation is real and keeps a >= 48 dp hit area.
        expect(find.byKey(_backKey), findsOneWidget);
        final IconButton back = tester.widget<IconButton>(find.byKey(_backKey));
        expect(back.onPressed, isNotNull);
        expect(tester.getSize(find.byKey(_backKey)), const Size(48, 48));

        // No Material AppBar chrome behind the branded banner.
        expect(find.byType(AppBar), findsNothing);
        expect(tester.takeException(), isNull);

        await backend.dispose();
      },
    );

    testWidgets(
      'CloudBackupScreen: same header family in English and Bengali',
      (WidgetTester tester) async {
        await _pumpPushed(tester, const CloudBackupScreen());
        expect(find.byKey(_headerKey), findsOneWidget);
        expect(tester.widget<Text>(find.byKey(_titleKey)).data, 'Cloud Backup');
        expect(find.byKey(_backKey), findsOneWidget);
        expect(find.byType(AppBar), findsNothing);
        expect(tester.takeException(), isNull);

        await _pumpPushed(
          tester,
          const CloudBackupScreen(language: AppLanguage.bn),
        );
        expect(
          tester.widget<Text>(find.byKey(_titleKey)).data,
          'ক্লাউড ব্যাকআপ',
        );
        final Text bnTitle = tester.widget<Text>(find.byKey(_titleKey));
        expect(bnTitle.maxLines, 1);
        expect(bnTitle.overflow, TextOverflow.ellipsis);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('back action pops the page and leaves the parent intact', (
      WidgetTester tester,
    ) async {
      await _pumpPushed(tester, const CloudBackupScreen());
      expect(find.byKey(const Key('cloud-backup-screen')), findsOneWidget);

      await tester.tap(find.byKey(_backKey));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cloud-backup-screen')), findsNothing);
      expect(find.text('open'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('subtitle yields to the title at 200% text, and the header '
        'still fits the safe area on 320dp', (WidgetTester tester) async {
      final FakeCloudBackend backend = FakeCloudBackend();
      await _pumpPushed(
        tester,
        SignInScreen(backend: backend, language: AppLanguage.bn),
        size: _smallPhone,
        textScale: 1,
      );
      // Normal scale: the subtitle earns its line.
      expect(find.byKey(const Key('account-page-subtitle')), findsOneWidget);

      await _pumpPushed(
        tester,
        SignInScreen(backend: backend, language: AppLanguage.bn),
        size: _smallPhone,
        textScale: _largeText,
      );
      // Large text: the title keeps the whole banner; nothing is clipped away.
      expect(find.byKey(const Key('account-page-subtitle')), findsNothing);
      expect(find.byKey(_titleKey), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(_titleKey)).overflow,
        TextOverflow.ellipsis,
      );

      final Rect header = tester.getRect(find.byKey(_headerKey));
      expect(header.width, _smallPhone.width);
      // The banner starts at the top edge (it paints under the status bar) and
      // stays compact enough to leave the page real room on a 568 dp screen.
      expect(header.top, 0);
      expect(header.bottom, lessThan(_smallPhone.height / 4));
      expect(tester.takeException(), isNull);

      await backend.dispose();
    });
  });

  group('sign-in hierarchy', () {
    testWidgets('one filled CTA, one quiet exit, hero pill still honest', (
      WidgetTester tester,
    ) async {
      final FakeCloudBackend backend = FakeCloudBackend();
      await _pumpPushed(tester, SignInScreen(backend: backend));

      // The Google CTA is the only filled control on the page. (.icon() builds
      // a private FilledButton subclass, so match by predicate, not byType.)
      expect(
        find.byWidgetPredicate((Widget widget) => widget is FilledButton),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('continue-with-google-button')),
        findsOneWidget,
      );
      // ...and the only way out is the quiet outlined one under it.
      expect(
        find.byWidgetPredicate((Widget widget) => widget is OutlinedButton),
        findsOneWidget,
      );
      expect(find.byKey(const Key('sign-in-not-now-button')), findsOneWidget);
      expect(find.byKey(const Key('legal-privacy-link')), findsOneWidget);
      expect(find.byKey(const Key('legal-terms-link')), findsOneWidget);
      expect(find.byKey(const Key('legal-delete-link')), findsOneWidget);

      // The optional-backup promise is still on screen, in the hero.
      expect(find.byKey(const Key('sign-in-hero')), findsOneWidget);
      expect(find.text('Optional Cloud Backup'), findsOneWidget);
      expect(find.text('Local data stays on this phone'), findsOneWidget);
      final BoxDecoration heroDecoration = _decorationOf(
        tester,
        const Key('sign-in-hero'),
      );
      expect(heroDecoration.color, AppColors.lightGreen);
      expect(heroDecoration.borderRadius, BorderRadius.circular(20));
      expect(heroDecoration.boxShadow, hasLength(1));

      // One card system: warm ivory, radius 20, beige hairline, one shadow.
      expect(heroDecoration.border, isNotNull);

      // Both actions keep a real touch target.
      expect(
        tester
            .getSize(find.byKey(const Key('continue-with-google-button')))
            .height,
        greaterThanOrEqualTo(48),
      );
      expect(
        tester.getSize(find.byKey(const Key('sign-in-not-now-button'))).height,
        greaterThanOrEqualTo(48),
      );
      // Primary action above the quiet one: one reading order, one color call.
      expect(
        tester
            .getBottomLeft(find.byKey(const Key('continue-with-google-button')))
            .dy,
        lessThanOrEqualTo(
          tester.getTopLeft(find.byKey(const Key('sign-in-not-now-button'))).dy,
        ),
      );
      expect(tester.takeException(), isNull);

      await backend.dispose();
    });

    testWidgets('inline feedback keeps its own place in the action card', (
      WidgetTester tester,
    ) async {
      final FakeCloudBackend backend = FakeCloudBackend();
      backend.onSignInWithGoogle = () async => null;
      await _pumpPushed(tester, SignInScreen(backend: backend));

      await tester.scrollUntilVisible(
        find.byKey(const Key('continue-with-google-button')),
        120,
      );
      await tester.ensureVisible(
        find.byKey(const Key('continue-with-google-button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('continue-with-google-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sign-in-feedback')), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      // The CTA stays available and the page still scrolls (no overflow).
      expect(
        find.byKey(const Key('continue-with-google-button')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await backend.dispose();
    });
  });

  group('cloud backup & account card surfaces', () {
    testWidgets('the local-first note sits under the state card with the same '
        'warm surface', (WidgetTester tester) async {
      await _pumpPushed(tester, const CloudBackupScreen());

      final BoxDecoration decoration = _decorationOf(
        tester,
        const Key('cloud-backup-local-note'),
      );
      // The same geometry as the state card, but quiet: cream, no shadow, so it
      // supports the account card instead of competing with it.
      expect(decoration.color, AppColors.creamBackground);
      expect(decoration.borderRadius, BorderRadius.circular(20));
      expect((decoration.border! as Border).top.color, AppColors.outline);
      expect(decoration.boxShadow, isNull);

      expect(
        tester.getTopLeft(find.byKey(const Key('cloud-backup-local-note'))).dy,
        greaterThan(
          tester
              .getBottomLeft(
                find.byKey(const Key('cloud-backup-unconfigured-card')),
              )
              .dy,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('signed-in card names the account block and groups its facts', (
      WidgetTester tester,
    ) async {
      await _pumpCard(
        tester,
        AccountCard(
          status: SyncStatus.idle(
            userEmail: 'keshab@example.com',
            lastSyncedAt: DateTime.utc(2026, 11, 19, 15, 0),
            pendingCount: 3,
          ),
          onBackupNow: () async => SyncOutcome.synced,
          onSignOut: () async {},
        ),
        size: const Size(400, 900),
      );

      expect(find.text('CLOUD ACCOUNT'), findsOneWidget);
      expect(find.byKey(const Key('account-card-sync-facts')), findsOneWidget);
      // The facts panel groups the two read-only lines inside one surface.
      expect(
        find.descendant(
          of: find.byKey(const Key('account-card-sync-facts')),
          matching: find.byKey(const Key('account-card-last-synced')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('account-card-sync-facts')),
          matching: find.byKey(const Key('account-card-pending-chip')),
        ),
        findsOneWidget,
      );
      // Status pill and account identity are above the facts panel.
      expect(
        tester.getTopLeft(find.byKey(const Key('account-card-status-pill'))).dy,
        lessThan(
          tester
              .getTopLeft(find.byKey(const Key('account-card-sync-facts')))
              .dy,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('every state carries the same label and one card surface', (
      WidgetTester tester,
    ) async {
      final List<Widget> states = <Widget>[
        AccountCard(status: const SyncStatus.signedOut(), onSignIn: () {}),
        AccountCard(
          status: SyncStatus.syncing(
            userEmail: 'keshab@example.com',
            pendingCount: 1,
          ),
        ),
        AccountCard(
          status: SyncStatus.error(
            reason: 'Temporary gateway error',
            userEmail: 'keshab@example.com',
            pendingCount: 2,
          ),
          onRetry: () async => SyncOutcome.synced,
          onSignOut: () async {},
        ),
        AccountCard(
          status: SyncStatus.idle(
            userEmail: 'keshab@example.com',
            pendingCount: 0,
          ),
          onBackupNow: () async => SyncOutcome.synced,
          onSignOut: () async {},
        ),
      ];

      for (final Widget state in states) {
        await _pumpCard(tester, state, size: const Size(400, 900));
        expect(
          find.byKey(const Key('account-card-label')),
          findsOneWidget,
          reason: 'every state names the block it belongs to',
        );
        final BoxDecoration decoration = _decorationOf(
          tester,
          const Key('account-card'),
        );
        expect(decoration.color, AppColors.surface);
        expect(decoration.borderRadius, BorderRadius.circular(20));
        expect((decoration.border! as Border).top.color, AppColors.outline);
        expect(decoration.boxShadow, hasLength(1));
        // The destructive action is separated from the primary one by a rule.
        if (find
            .byKey(const Key('account-card-logout-button'))
            .evaluate()
            .isNotEmpty) {
          final Finder primary =
              find
                  .byKey(const Key('account-card-backup-button'))
                  .evaluate()
                  .isNotEmpty
              ? find.byKey(const Key('account-card-backup-button'))
              : find.byKey(const Key('account-card-retry-button'));
          expect(
            tester
                .getTopLeft(find.byKey(const Key('account-card-logout-button')))
                .dy,
            greaterThan(tester.getBottomLeft(primary).dy),
          );
        }
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('320x568 at 200% text scrolls without overflow', () {
    Future<void> expectScrollsClean(
      WidgetTester tester,
      Finder scrollable,
    ) async {
      // Drag the body a few times: an unbounded child (an IntrinsicHeight row,
      // a fixed-height banner, a Row that cannot shrink) throws here.
      for (int i = 0; i < 6; i++) {
        await tester.drag(scrollable, const Offset(0, -260));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await tester.drag(scrollable, const Offset(0, 2000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    testWidgets('SignInScreen (en + bn)', (WidgetTester tester) async {
      for (final AppLanguage language in AppLanguage.values) {
        final FakeCloudBackend backend = FakeCloudBackend();
        await _pumpPushed(
          tester,
          SignInScreen(backend: backend, language: language),
          size: _smallPhone,
          textScale: _largeText,
        );
        expect(tester.takeException(), isNull);
        await expectScrollsClean(tester, find.byType(Scrollable).last);
        // Both actions survive the trip to the bottom of the page.
        await tester.scrollUntilVisible(
          find.byKey(const Key('continue-with-google-button')),
          160,
        );
        expect(
          tester
              .getSize(find.byKey(const Key('continue-with-google-button')))
              .height,
          greaterThanOrEqualTo(48),
        );
        expect(
          tester
              .getSize(find.byKey(const Key('sign-in-not-now-button')))
              .height,
          greaterThanOrEqualTo(48),
        );
        await backend.dispose();
      }
    });

    testWidgets('CloudBackupScreen unconfigured (en + bn)', (
      WidgetTester tester,
    ) async {
      for (final AppLanguage language in AppLanguage.values) {
        await _pumpPushed(
          tester,
          CloudBackupScreen(language: language),
          size: _smallPhone,
          textScale: _largeText,
        );
        expect(find.byKey(_headerKey), findsOneWidget);
        expect(tester.takeException(), isNull);
        await expectScrollsClean(tester, find.byType(Scrollable).last);
      }
    });

    testWidgets('AccountCard in all four states (en + bn)', (
      WidgetTester tester,
    ) async {
      for (final AppLanguage language in AppLanguage.values) {
        final List<Widget> states = <Widget>[
          AccountCard(
            language: language,
            status: const SyncStatus.signedOut(),
            onSignIn: () {},
          ),
          AccountCard(
            language: language,
            status: SyncStatus.idle(
              userEmail: 'long.account.name@example.com',
              lastSyncedAt: DateTime.utc(2026, 11, 19, 15, 0),
              pendingCount: 42,
            ),
            onBackupNow: () async => SyncOutcome.synced,
            onSignOut: () async {},
          ),
          AccountCard(
            language: language,
            status: SyncStatus.syncing(
              userEmail: 'long.account.name@example.com',
              pendingCount: 7,
            ),
          ),
          AccountCard(
            language: language,
            status: SyncStatus.error(
              reason: 'Temporary gateway error while backing up',
              userEmail: 'long.account.name@example.com',
              pendingCount: 2,
            ),
            onRetry: () async => SyncOutcome.synced,
            onSignOut: () async {},
          ),
        ];
        for (final Widget state in states) {
          await _pumpCard(
            tester,
            state,
            size: _smallPhone,
            textScale: _largeText,
          );
          expect(tester.takeException(), isNull);
          await expectScrollsClean(tester, find.byType(Scrollable).last);
        }
      }
    });
  });
}
