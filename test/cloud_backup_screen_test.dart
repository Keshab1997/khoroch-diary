// Flutter 3.50 deprecates this import; migrate with the app's dependency update.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khoroch_diary/core/l10n/app_strings.dart' show AppLanguage;
import 'package:khoroch_diary/core/theme/app_theme.dart';
import 'package:khoroch_diary/features/entry/add_entry_screen.dart';
import 'package:khoroch_diary/features/ledger/data/local_ledger.dart';
import 'package:khoroch_diary/features/sync/cloud_backend.dart';
import 'package:khoroch_diary/features/sync/cloud_backup_screen.dart';
import 'package:khoroch_diary/features/sync/cloud_sync.dart';

import 'support/fake_cloud_backend.dart';

Future<void> _pumpScreen(
  WidgetTester tester,
  CloudBackupScreen screen, {
  Size size = const Size(400, 840),
  double textScale = 1.0,
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
          data: media.copyWith(textScaler: TextScaler.linear(textScale)),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: screen,
    ),
  );
  await tester.pump();
}

Future<LocalLedger> _openLedger(WidgetTester tester) async {
  late LocalLedger ledger;
  await tester.runAsync(() async {
    ledger = LocalLedger(NativeDatabase.memory());
    await ledger.initialize();
  });
  return ledger;
}

Future<void> _tearDownService(
  WidgetTester tester, {
  required CloudSync sync,
  required FakeCloudBackend backend,
  required LocalLedger ledger,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.runAsync(() async {
    await sync.dispose();
    await backend.dispose();
    await ledger.close();
  });
}

void main() {
  group('CloudBackupScreen', () {
    testWidgets(
      'unconfigured state (cloudSync == null) explains build has no cloud backup and data stays on phone',
      (WidgetTester tester) async {
        await _pumpScreen(tester, const CloudBackupScreen());

        expect(
          find.byKey(const Key('cloud-backup-unconfigured-card')),
          findsOneWidget,
        );
        expect(
          find.text('Cloud backup is not set up in this build'),
          findsOneWidget,
        );
        expect(find.text('Saved on this phone'), findsOneWidget);
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'local-only state pushes SignInScreen and syncs entries to signed-in state without blocking dialogs',
      (WidgetTester tester) async {
        final LocalLedger ledger = await _openLedger(tester);
        await tester.runAsync(() async {
          await ledger.addEntry(
            EntryFormResult(
              kind: EntryFormKind.expense,
              amountPaise: 32000,
              category: 'Food',
              description: 'Biryani',
              occurredAt: DateTime.utc(2026, 11, 20, 12, 0),
            ),
          );
        });

        final CloudUser alice = CloudUser(
          id: 'u-alice',
          email: 'alice@example.com',
        );
        final FakeCloudBackend backend = FakeCloudBackend();
        backend.nextSignInUser = alice;

        // CloudSync must subscribe to backend.userChanges in the widget-test
        // zone; a runAsync zone swallows stream callbacks.
        final CloudSync sync = CloudSync(
          ledger: ledger,
          backend: backend,
          observeAppLifecycle: false,
        );
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });

        await _pumpScreen(tester, CloudBackupScreen(cloudSync: sync));
        await tester.pump();

        expect(find.text('Sign in to enable cloud backup'), findsOneWidget);
        expect(
          find.byKey(const Key('account-card-signin-button')),
          findsOneWidget,
        );

        // Tap Sign in -> navigates to SignInScreen (S11).
        await tester.tap(find.byKey(const Key('account-card-signin-button')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('sign-in-screen')), findsOneWidget);
        expect(find.text('Continue with Google'), findsOneWidget);

        // Tap Continue with Google -> signs in, pops back to CloudBackupScreen,
        // and syncs local ledger rows into FakeCloudBackend!
        await tester.ensureVisible(
          find.byKey(const Key('continue-with-google-button')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('continue-with-google-button')));
        await tester.pump();
        await tester.runAsync(() async {
          // The sign-in stream event and the first sync run on the real event
          // loop with real database work; give them room to finish.
          await Future<void>.delayed(const Duration(milliseconds: 300));
        });
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('cloud-backup-screen')), findsOneWidget);
        expect(find.text('alice@example.com'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('account-card')),
            matching: find.text('0 pending'),
          ),
          findsOneWidget,
        );
        expect(find.byType(AlertDialog), findsNothing);
        expect(backend.storedTransactionsFor(alice.id), hasLength(1));

        await _tearDownService(
          tester,
          sync: sync,
          backend: backend,
          ledger: ledger,
        );
      },
    );

    testWidgets(
      'error state renders failure reason and Retry recovers to signed-in idle',
      (WidgetTester tester) async {
        final LocalLedger ledger = await _openLedger(tester);
        final CloudUser alice = CloudUser(
          id: 'u-alice',
          email: 'alice@example.com',
        );
        final FakeCloudBackend backend = FakeCloudBackend(initialUser: alice);
        backend.nextError = Exception('Temporary gateway error');

        late CloudSync sync;
        await tester.runAsync(() async {
          sync = CloudSync(
            ledger: ledger,
            backend: backend,
            observeAppLifecycle: false,
          );
          await Future<void>.delayed(const Duration(milliseconds: 40));
        });

        await _pumpScreen(tester, CloudBackupScreen(cloudSync: sync));
        await tester.pump();

        expect(find.text('Temporary gateway error'), findsOneWidget);
        expect(
          find.byKey(const Key('account-card-retry-button')),
          findsOneWidget,
        );
        expect(find.byType(AlertDialog), findsNothing);

        // Tap Retry -> succeeds and clears error.
        await tester.tap(find.byKey(const Key('account-card-retry-button')));
        await tester.pump();
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 60));
        });
        await tester.pumpAndSettle();

        expect(find.text('Temporary gateway error'), findsNothing);
        expect(find.text('Back up now'), findsOneWidget);

        await _tearDownService(
          tester,
          sync: sync,
          backend: backend,
          ledger: ledger,
        );
      },
    );

    testWidgets(
      'the unconfigured layout stacks the state card above the local note',
      (WidgetTester tester) async {
        // Unconfigured: the note sits under the "not set up" card.
        await _pumpScreen(tester, const CloudBackupScreen());
        expect(
          find.byKey(const Key('cloud-backup-local-note')),
          findsOneWidget,
        );
        expect(find.text('Your phone is the primary copy'), findsOneWidget);
        // The note is below the state card, not beside it.
        final double stateBottom = tester
            .getBottomLeft(
              find.byKey(const Key('cloud-backup-unconfigured-card')),
            )
            .dy;
        final double noteTop = tester
            .getTopLeft(find.byKey(const Key('cloud-backup-local-note')))
            .dy;
        expect(noteTop, greaterThan(stateBottom));
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'renders Bengali copy cleanly across unconfigured and configured states at 320dp / 200%',
      (WidgetTester tester) async {
        // 1. Unconfigured Bengali at 320dp / 200%.
        await _pumpScreen(
          tester,
          const CloudBackupScreen(language: AppLanguage.bn),
          size: const Size(320, 640),
          textScale: 2.0,
        );
        expect(
          find.text('এই সংস্করণে ক্লাউড ব্যাকআপ সেট আপ করা নেই'),
          findsOneWidget,
        );
        expect(find.text('এই ফোনে সংরক্ষিত'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // 2. Configured signed-in Bengali at 320dp / 200%.
        final LocalLedger ledger = await _openLedger(tester);
        final FakeCloudBackend backend = FakeCloudBackend(
          initialUser: CloudUser(id: 'u-bn', email: 'bn@example.com'),
        );
        late CloudSync sync;
        await tester.runAsync(() async {
          sync = CloudSync(
            ledger: ledger,
            backend: backend,
            observeAppLifecycle: false,
          );
          await Future<void>.delayed(const Duration(milliseconds: 40));
        });

        await _pumpScreen(
          tester,
          CloudBackupScreen(language: AppLanguage.bn, cloudSync: sync),
          size: const Size(320, 640),
          textScale: 2.0,
        );
        await tester.pump();

        expect(find.text('ক্লাউড ব্যাকআপ'), findsOneWidget);
        expect(find.text('bn@example.com'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('account-card')),
            matching: find.text('০টি অপেক্ষমাণ'),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);

        await _tearDownService(
          tester,
          sync: sync,
          backend: backend,
          ledger: ledger,
        );
      },
    );
  });
}
