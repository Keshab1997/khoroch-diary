import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khoroch_diary/features/entry/add_entry_screen.dart';
import 'package:khoroch_diary/features/home/models.dart';
import 'package:khoroch_diary/features/ledger/data/local_ledger.dart';
import 'package:khoroch_diary/features/sync/cloud_backend.dart';
import 'package:khoroch_diary/features/sync/cloud_config.dart';
import 'package:khoroch_diary/features/sync/cloud_sync.dart';

import 'support/fake_cloud_backend.dart';

CloudUser get _alice => CloudUser(id: 'user-alice', email: 'alice@example.com');

Future<void> _settleSync([int ms = 40]) async {
  await Future<void>.delayed(Duration(milliseconds: ms));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CloudConfig & CloudSync.start', () {
    test(
      'CloudSync.start returns the service when the project is configured',
      () async {
        const CloudConfig configured = CloudConfig(
          url: 'https://project.supabase.co',
          publishableKey: 'pub-key-123',
        );
        expect(configured.isConfigured, isTrue);
        expect(
          configured.redirectTo,
          'com.keshabstudios.khorochdiary://login-callback',
        );
        expect(
          const CloudConfig(
            url: 'https://project.supabase.co',
            publishableKey: 'pub-key-123',
          ).isConfigured,
          isTrue,
        );
        expect(
          const CloudConfig(
            url: 'not-a-valid-url',
            publishableKey: 'pub-key-123',
          ).isConfigured,
          isFalse,
        );

        final LocalLedger ledger = LocalLedger(NativeDatabase.memory());
        await ledger.initialize();
        addTearDown(ledger.close);

        final CloudSync? started = await CloudSync.start(
          ledger: ledger,
          config: const CloudConfig(url: '', publishableKey: ''),
        );
        expect(started, isNull);
      },
    );
  });

  group('CloudSync lifecycle & orchestration', () {
    test('syncs once at start when already signed in', () async {
      final LocalLedger ledger = LocalLedger(NativeDatabase.memory());
      await ledger.initialize();
      await ledger.addEntry(
        EntryFormResult(
          kind: EntryFormKind.expense,
          amountPaise: 24000,
          category: 'Food',
          description: 'Morning tea',
          occurredAt: DateTime.utc(2026, 11, 20, 7, 30),
        ),
      );

      final FakeCloudBackend backend = FakeCloudBackend(initialUser: _alice);
      final CloudSync sync = CloudSync(
        ledger: ledger,
        backend: backend,
        debounce: const Duration(milliseconds: 25),
      );

      await _settleSync();

      expect(backend.storedKhatasFor(_alice.id), hasLength(1));
      expect(backend.storedTransactionsFor(_alice.id), hasLength(1));
      expect(await ledger.readPendingSyncCount(), 0);
      expect(sync.currentStatus.isIdle, isTrue);
      expect(sync.currentStatus.userEmail, _alice.email);

      await sync.dispose();
      await backend.dispose();
      await ledger.close();
    });

    test('syncs automatically after sign-in, debounces notifyLocalChange, triggers on app resume, and stops cleanly on dispose', () async {
      final LocalLedger ledger = LocalLedger(NativeDatabase.memory());
      await ledger.initialize();
      await ledger.addEntry(
        EntryFormResult(
          kind: EntryFormKind.income,
          amountPaise: 75000,
          category: 'Income',
          description: 'Shop sale',
          occurredAt: DateTime.utc(2026, 11, 20, 8, 0),
        ),
      );

      final FakeCloudBackend backend = FakeCloudBackend();
      backend.nextSignInUser = _alice;

      final CloudSync sync = CloudSync(
        ledger: ledger,
        backend: backend,
        debounce: const Duration(milliseconds: 30),
      );
      await _settleSync(10);

      expect(sync.currentStatus.isSignedOut, isTrue);
      expect(backend.fetchCalls, 0);

      // 1. Sign in -> automatically syncs pending local rows!
      final CloudUser? user = await backend.signInWithGoogle();
      expect(user, _alice);
      await _settleSync(60);

      expect(backend.storedKhatasFor(_alice.id), hasLength(1));
      expect(backend.storedTransactionsFor(_alice.id), hasLength(1));
      expect(await ledger.readPendingSyncCount(), 0);

      // 2. Rapid local writes + notifyLocalChange() coalesce into one push.
      final int txBatchesBeforeWrites = backend.pushedTransactionBatches.length;
      for (int i = 0; i < 3; i++) {
        await ledger.addEntry(
          EntryFormResult(
            kind: EntryFormKind.expense,
            amountPaise: 1000 * (i + 1),
            category: 'Other',
            description: 'Rapid item $i',
            occurredAt: DateTime.utc(2026, 11, 20, 9, i),
          ),
        );
        sync.notifyLocalChange();
      }

      // Still within debounce window -> not pushed yet.
      expect(backend.pushedTransactionBatches.length, txBatchesBeforeWrites);

      await _settleSync(80);
      expect(
        backend.pushedTransactionBatches.length,
        txBatchesBeforeWrites + 1,
      );
      expect(backend.storedTransactionsFor(_alice.id), hasLength(4));
      expect(await ledger.readPendingSyncCount(), 0);

      // 3. App resume triggers a fresh sync (pulling remote changes).
      backend.seedRemoteTransaction(
        _alice.id,
        CloudTransactionRow(
          userId: _alice.id,
          id: 'remote-resume-tx',
          khataId: 'personal',
          type: CloudTransactionType.income,
          amountPaise: 50000,
          categoryId: 'Income',
          description: 'Added on other phone',
          occurredAt: DateTime.utc(2026, 11, 20, 10, 0),
          createdAt: DateTime.utc(2026, 11, 20, 10, 0),
          updatedAt: DateTime.utc(2026, 11, 20, 10, 0),
          serverUpdatedAt: DateTime.now().toUtc().add(
            const Duration(seconds: 5),
          ),
        ),
      );

      final int fetchesBeforeResume = backend.fetchCalls;
      WidgetsBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.inactive,
      );
      WidgetsBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
      await _settleSync(60);

      expect(backend.fetchCalls, greaterThan(fetchesBeforeResume));
      final LedgerSummary afterResume = await ledger.readSummary();
      expect(
        afterResume.entries.any((LedgerEntry e) => e.id == 'remote-resume-tx'),
        isTrue,
      );

      // 4. Sign out never deletes local data.
      await sync.signOut();
      expect(sync.currentStatus.isSignedOut, isTrue);
      expect((await ledger.readSummary()).entries, hasLength(5));

      // 5. Dispose stops all further reactions to resume or notifyLocalChange.
      backend.setSignedInUser(_alice);
      await _settleSync(50);
      final int fetchesBeforeDispose = backend.fetchCalls;
      await sync.dispose();

      sync.notifyLocalChange();
      WidgetsBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.inactive,
      );
      WidgetsBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
      await _settleSync(80);
      expect(backend.fetchCalls, fetchesBeforeDispose);

      await backend.dispose();
      await ledger.close();
    });
  });
}
