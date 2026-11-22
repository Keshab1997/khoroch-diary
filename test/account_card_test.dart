// Flutter 3.50 deprecates this import; migrate with the app's dependency update.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khoroch_diary/core/l10n/app_strings.dart' show AppLanguage;
import 'package:khoroch_diary/core/theme/app_colors.dart';
import 'package:khoroch_diary/core/theme/app_theme.dart';
import 'package:khoroch_diary/features/entry/add_entry_screen.dart';
import 'package:khoroch_diary/features/ledger/data/local_ledger.dart';
import 'package:khoroch_diary/features/sync/account_card.dart';
import 'package:khoroch_diary/features/sync/cloud_backend.dart';
import 'package:khoroch_diary/features/sync/sync_engine.dart';
import 'package:khoroch_diary/features/sync/sync_status.dart';

import 'support/fake_cloud_backend.dart';

Future<void> _pumpCard(
  WidgetTester tester,
  Widget card, {
  Size size = const Size(400, 900),
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
  group('AccountCard states (S5)', () {
    testWidgets('local-only state shows hint and Sign in button', (
      WidgetTester tester,
    ) async {
      int signInTaps = 0;
      await _pumpCard(
        tester,
        AccountCard(
          status: const SyncStatus.signedOut(pendingCount: 2),
          onSignIn: () => signInTaps++,
        ),
      );

      expect(find.text('Sign in to enable cloud backup'), findsOneWidget);
      expect(
        find.byKey(const Key('account-card-signin-button')),
        findsOneWidget,
      );
      expect(find.text('Back up now'), findsNothing);
      expect(find.text('Log out'), findsNothing);

      await tester.tap(find.byKey(const Key('account-card-signin-button')));
      await tester.pump();
      expect(signInTaps, 1);
    });

    testWidgets(
      'signed-in idle state shows email, Last synced, N pending, Back up now, and Log out in expenseRed',
      (WidgetTester tester) async {
        int backupCalls = 0;
        await _pumpCard(
          tester,
          AccountCard(
            status: SyncStatus.idle(
              userEmail: 'keshab@example.com',
              lastSyncedAt: DateTime.utc(2026, 11, 19, 15, 0),
              pendingCount: 3,
            ),
            onBackupNow: () async {
              backupCalls++;
              return SyncOutcome.synced;
            },
            onSignOut: () async {},
          ),
        );

        expect(find.text('keshab@example.com'), findsOneWidget);
        expect(find.textContaining('Last synced'), findsOneWidget);
        expect(find.text('3 pending'), findsOneWidget);
        expect(find.text('Back up now'), findsOneWidget);
        expect(find.text('Log out'), findsOneWidget);

        // Verify Log out label uses AppColors.expenseRed.
        final Text logoutText = tester.widget<Text>(find.text('Log out'));
        expect(logoutText.style?.color, AppColors.expenseRed);

        await tester.tap(find.byKey(const Key('account-card-backup-button')));
        await tester.pumpAndSettle();
        expect(backupCalls, 1);
      },
    );

    testWidgets(
      'syncing state shows inline progress text only, never a blocking modal dialog',
      (WidgetTester tester) async {
        await _pumpCard(
          tester,
          AccountCard(
            status: SyncStatus.syncing(
              userEmail: 'keshab@example.com',
              pendingCount: 4,
            ),
          ),
        );

        expect(find.text('Syncing with cloud backup…'), findsOneWidget);
        expect(find.text('4 pending'), findsOneWidget);
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byType(Dialog), findsNothing);
        expect(
          find.byKey(const Key('account-card-backup-button')),
          findsNothing,
        );
      },
    );

    testWidgets('error state shows failure reason and Retry button', (
      WidgetTester tester,
    ) async {
      int retries = 0;
      await _pumpCard(
        tester,
        AccountCard(
          status: SyncStatus.error(
            reason: 'Server temporarily unavailable',
            userEmail: 'keshab@example.com',
            pendingCount: 2,
          ),
          onRetry: () async {
            retries++;
            return SyncOutcome.synced;
          },
          onSignOut: () async {},
        ),
      );

      expect(find.text('Server temporarily unavailable'), findsOneWidget);
      expect(find.text('2 pending'), findsOneWidget);
      expect(
        find.byKey(const Key('account-card-retry-button')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('account-card-retry-button')));
      await tester.pumpAndSettle();
      expect(retries, 1);
    });

    testWidgets(
      'backing up while offline shows clear message and does nothing',
      (WidgetTester tester) async {
        int backupCalls = 0;
        await _pumpCard(
          tester,
          AccountCard(
            status: SyncStatus.idle(
              userEmail: 'keshab@example.com',
              pendingCount: 1,
            ),
            isOnline: () async => false,
            onBackupNow: () async {
              backupCalls++;
              return SyncOutcome.synced;
            },
            onSignOut: () async {},
          ),
        );

        await tester.tap(find.byKey(const Key('account-card-backup-button')));
        await tester.pumpAndSettle();

        expect(backupCalls, 0);
        expect(
          find.byKey(const Key('account-card-offline-message')),
          findsOneWidget,
        );
        expect(find.textContaining('offline'), findsOneWidget);
      },
    );

    testWidgets(
      'log-out confirm dialog cancels safely and never deletes local data on confirm',
      (WidgetTester tester) async {
        final LocalLedger ledger = LocalLedger(NativeDatabase.memory());
        await ledger.initialize();
        await ledger.addEntry(
          EntryFormResult(
            kind: EntryFormKind.expense,
            amountPaise: 58000,
            category: 'Food',
            description: 'Lunch',
            occurredAt: DateTime.utc(2026, 11, 19, 13, 15),
          ),
        );
        final FakeCloudBackend backend = FakeCloudBackend(
          initialUser: CloudUser(id: 'u1', email: 'keshab@example.com'),
        );
        final SyncEngine engine = SyncEngine(ledger: ledger, backend: backend);
        await engine.refreshStatus();

        await _pumpCard(
          tester,
          AccountCard(
            statusStream: engine.statusStream,
            onBackupNow: () => engine.syncNow(),
            onSignOut: () => engine.signOut(),
          ),
        );
        await tester.pump();

        expect(find.text('keshab@example.com'), findsOneWidget);

        // Cancel confirmation -> stays signed in.
        await tester.tap(find.byKey(const Key('account-card-logout-button')));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.tap(find.byKey(const Key('account-logout-cancel')));
        await tester.pumpAndSettle();
        expect(backend.signOutCalls, 0);
        expect(find.text('keshab@example.com'), findsOneWidget);

        // Confirm log out -> signs out, transitions card to local-only, and
        // local ledger entry remains intact.
        await tester.tap(find.byKey(const Key('account-card-logout-button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('account-logout-confirm')));
        await tester.pumpAndSettle();

        expect(backend.signOutCalls, 1);
        expect(find.text('Sign in to enable cloud backup'), findsOneWidget);
        expect(
          (await ledger.readSummary()).entries.single.description,
          'Lunch',
        );

        // Unmount first so the card's status listener is gone, then close
        // the engine and the database outside the fake-async zone.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() async {
          await engine.dispose();
          await backend.dispose();
          await ledger.close();
        });
      },
    );

    testWidgets(
      'Bengali labels render across all states and 320dp/200% scale',
      (WidgetTester tester) async {
        // 1. Local-only in Bengali
        await _pumpCard(
          tester,
          AccountCard(
            language: AppLanguage.bn,
            status: const SyncStatus.signedOut(),
            onSignIn: () {},
          ),
          size: const Size(320, 640),
          textScale: 2.0,
        );
        expect(
          find.text('ক্লাউড ব্যাকআপ চালু করতে সাইন ইন করুন'),
          findsOneWidget,
        );
        expect(find.text('সাইন ইন করুন'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // 2. Signed-in idle in Bengali (including Bengali digits for pending count)
        await _pumpCard(
          tester,
          AccountCard(
            language: AppLanguage.bn,
            status: SyncStatus.idle(
              userEmail: 'bn@example.com',
              lastSyncedAt: DateTime.utc(2026, 11, 20, 10, 30),
              pendingCount: 5,
            ),
            onBackupNow: () async => SyncOutcome.synced,
            onSignOut: () async {},
          ),
          size: const Size(320, 640),
          textScale: 2.0,
        );
        expect(find.text('৫টি অপেক্ষমাণ'), findsOneWidget);
        expect(find.text('এখন ব্যাকআপ নিন'), findsOneWidget);
        expect(find.text('লগ আউট'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // 3. Syncing in Bengali
        await _pumpCard(
          tester,
          AccountCard(
            language: AppLanguage.bn,
            status: SyncStatus.syncing(
              userEmail: 'bn@example.com',
              pendingCount: 1,
            ),
          ),
        );
        expect(find.text('ক্লাউড ব্যাকআপের সাথে সিঙ্ক হচ্ছে…'), findsOneWidget);

        // 4. Error in Bengali
        await _pumpCard(
          tester,
          AccountCard(
            language: AppLanguage.bn,
            status: SyncStatus.error(
              reason: 'নেটওয়ার্ক ত্রুটি',
              userEmail: 'bn@example.com',
              pendingCount: 2,
            ),
            onRetry: () async => SyncOutcome.synced,
            onSignOut: () async {},
          ),
        );
        expect(find.text('নেটওয়ার্ক ত্রুটি'), findsOneWidget);
        expect(find.text('আবার চেষ্টা করুন'), findsOneWidget);
      },
    );
  });

  group('AccountCard design polish', () {
    testWidgets('signed-in idle carries a crisp green up-to-date indicator', (
      WidgetTester tester,
    ) async {
      await _pumpCard(
        tester,
        AccountCard(
          status: SyncStatus.idle(
            userEmail: 'keshab@example.com',
            lastSyncedAt: DateTime.utc(2026, 11, 19, 15, 0),
            pendingCount: 0,
          ),
          onBackupNow: () async => SyncOutcome.synced,
          onSignOut: () async {},
        ),
      );

      expect(find.text('Up to date'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('Up to date')).style?.color,
        AppColors.greenSuccess,
      );

      // One warm-ivory card with the beige edge and a single soft shadow.
      final Container card = tester.widget<Container>(
        find.byKey(const Key('account-card')),
      );
      final BoxDecoration decoration = card.decoration! as BoxDecoration;
      expect(decoration.color, AppColors.surface);
      expect(decoration.borderRadius, BorderRadius.circular(20));
      expect((decoration.border! as Border).top.color, AppColors.outline);
      expect(decoration.boxShadow, hasLength(1));
    });

    testWidgets('a local-only card never claims to be up to date', (
      WidgetTester tester,
    ) async {
      await _pumpCard(
        tester,
        AccountCard(status: const SyncStatus.signedOut(), onSignIn: () {}),
      );

      expect(find.text('Up to date'), findsNothing);
      expect(find.text('Not signed in'), findsOneWidget);
      // The value copy is unchanged by the polish: same words, same numbers.
      expect(find.text('Local-only mode'), findsOneWidget);
      expect(find.text('Sign in to enable cloud backup'), findsOneWidget);
    });

    testWidgets('waiting state is named when entries are still pending', (
      WidgetTester tester,
    ) async {
      await _pumpCard(
        tester,
        AccountCard(
          status: SyncStatus.idle(
            userEmail: 'keshab@example.com',
            pendingCount: 2,
          ),
          onBackupNow: () async => SyncOutcome.synced,
          onSignOut: () async {},
        ),
      );

      expect(find.text('Waiting to sync'), findsOneWidget);
      expect(find.text('Up to date'), findsNothing);
      expect(find.text('2 pending'), findsOneWidget);
      expect(find.text('Last synced: Never'), findsOneWidget);
    });

    testWidgets('local-only and error states show their own state pill', (
      WidgetTester tester,
    ) async {
      await _pumpCard(
        tester,
        AccountCard(status: const SyncStatus.signedOut(), onSignIn: () {}),
      );
      expect(find.text('Not signed in'), findsOneWidget);
      expect(find.text('Local-only mode'), findsOneWidget);

      await _pumpCard(
        tester,
        AccountCard(
          status: SyncStatus.error(
            reason: 'Server temporarily unavailable',
            userEmail: 'keshab@example.com',
            pendingCount: 2,
          ),
          onRetry: () async => SyncOutcome.synced,
          onSignOut: () async {},
        ),
      );
      final Text failed = tester.widget<Text>(find.text('Sync failed'));
      expect(failed.style?.color, AppColors.expenseRed);
      expect(find.text('Server temporarily unavailable'), findsOneWidget);
    });

    testWidgets('syncing is a calm static panel, never a spinner', (
      WidgetTester tester,
    ) async {
      await _pumpCard(
        tester,
        AccountCard(
          status: SyncStatus.syncing(
            userEmail: 'keshab@example.com',
            pendingCount: 1,
          ),
        ),
      );

      expect(find.text('Syncing'), findsOneWidget);
      // Nothing on the card spins: no indeterminate animation, no dialog.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);

      // The state is named inside one light-green panel.
      final Container panel = tester.widget<Container>(
        find.byKey(const Key('account-card-syncing-panel')),
      );
      final BoxDecoration decoration = panel.decoration! as BoxDecoration;
      expect(decoration.color, AppColors.lightGreen);
      expect(decoration.borderRadius, BorderRadius.circular(14));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'account deletion requires confirmation and reports completion',
      (WidgetTester tester) async {
        int deleteCalls = 0;
        await _pumpCard(
          tester,
          AccountCard(
            status: SyncStatus.idle(userEmail: 'person@example.com'),
            onDeleteAccount: () async => deleteCalls++,
          ),
        );

        await tester.ensureVisible(
          find.byKey(const Key('account-card-delete-button')),
        );
        await tester.tap(find.byKey(const Key('account-card-delete-button')));
        await tester.pumpAndSettle();
        expect(
          find.text(
            'This permanently deletes your Khoroch Diary cloud account and all synced khatas and transactions. This cannot be undone. Local data on this device will remain. To remove it too, clear app data or uninstall the app.',
          ),
          findsOneWidget,
        );
        expect(deleteCalls, 0);
        await tester.tap(find.byKey(const Key('account-delete-cancel')));
        await tester.pumpAndSettle();
        expect(deleteCalls, 0);

        await tester.tap(find.byKey(const Key('account-card-delete-button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('account-delete-confirm')));
        await tester.pumpAndSettle();
        expect(deleteCalls, 1);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'syncing state stays inline at 320dp / 200% with no progress dialog',
      (WidgetTester tester) async {
        await _pumpCard(
          tester,
          AccountCard(
            status: SyncStatus.syncing(
              userEmail: 'keshab@example.com',
              pendingCount: 4,
            ),
          ),
          size: const Size(320, 640),
          textScale: 2.0,
        );
        expect(find.text('Syncing'), findsOneWidget);
        expect(find.text('Syncing with cloud backup…'), findsOneWidget);
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
