import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khoroch_diary/features/entry/add_entry_screen.dart';
import 'package:khoroch_diary/features/home/models.dart';
import 'package:khoroch_diary/features/ledger/data/local_ledger.dart';
import 'package:khoroch_diary/features/sync/cloud_backend.dart';
import 'package:khoroch_diary/features/sync/sync_engine.dart';
import 'package:khoroch_diary/features/sync/sync_scheduler.dart';
import 'package:khoroch_diary/features/sync/sync_status.dart';

import 'support/fake_cloud_backend.dart';

EntryFormResult _entry({
  required EntryFormKind kind,
  required int amountPaise,
  required String category,
  String description = '',
  required DateTime occurredAt,
}) {
  return EntryFormResult(
    kind: kind,
    amountPaise: amountPaise,
    category: category,
    description: description,
    occurredAt: occurredAt,
  );
}

final CloudUser _alice = CloudUser(
  id: 'user-alice',
  email: 'alice@example.com',
);
final CloudUser _bob = CloudUser(id: 'user-bob', email: 'bob@example.com');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SyncEngine + LocalLedger + FakeCloudBackend', () {
    late LocalLedger ledger;
    late FakeCloudBackend backend;
    late SyncEngine engine;
    DateTime fakeNow = DateTime.utc(2026, 11, 20, 10, 0, 0);

    setUp(() async {
      fakeNow = DateTime.utc(2026, 11, 20, 10, 0, 0);
      ledger = LocalLedger(NativeDatabase.memory());
      await ledger.initialize();
      backend = FakeCloudBackend(
        initialUser: _alice,
        initialServerTime: DateTime.utc(2026, 11, 20, 9, 0, 0),
      );
      engine = SyncEngine(
        ledger: ledger,
        backend: backend,
        batchSize: 2,
        now: () => fakeNow,
      );
    });

    tearDown(() async {
      await engine.dispose();
      await backend.dispose();
      await ledger.close();
    });

    test(
      'account deletion removes remote copies but preserves local ledger',
      () async {
        final LocalKhata khata = await ledger.createKhata(
          name: 'Local remains',
          openingBalancePaise: 4200,
        );
        backend.seedRemoteKhata(
          _alice.id,
          CloudKhataRow(
            userId: _alice.id,
            id: 'remote-only',
            name: 'Remote only',
            openingBalancePaise: 0,
            currency: 'INR',
            sortOrder: 0,
            createdAt: DateTime.utc(2026, 11, 20),
            updatedAt: DateTime.utc(2026, 11, 20),
          ),
        );

        await engine.deleteAccount();

        expect(backend.currentUser, isNull);
        expect(backend.callOrder, contains('deleteAccount'));
        final List<LocalKhata> localKhatas = await ledger.listKhatas();
        expect(
          localKhatas,
          hasLength(2),
        ); // default Personal Khata + the user row
        expect(localKhatas.any((LocalKhata row) => row.id == khata.id), isTrue);
        expect(backend.remoteKhatasFor(_alice.id), isEmpty);
        expect(backend.remoteTransactionsFor(_alice.id), isEmpty);
      },
    );

    test('push -> synced in batches (khatas before transactions) and pending count drops to 0', () async {
      final LocalKhata shop = await ledger.createKhata(
        name: 'Shop',
        openingBalancePaise: 50000,
      );
      final LocalKhata home = await ledger.createKhata(
        name: 'Home',
        openingBalancePaise: 10000,
      );
      await ledger.addEntry(
        _entry(
          kind: EntryFormKind.expense,
          amountPaise: 1200,
          category: 'Food',
          description: 'Tea',
          occurredAt: DateTime.utc(2026, 11, 20, 8, 0),
        ),
        khataId: shop.id,
      );
      await ledger.addEntry(
        _entry(
          kind: EntryFormKind.income,
          amountPaise: 5000,
          category: 'Income',
          description: 'Sale 1',
          occurredAt: DateTime.utc(2026, 11, 20, 8, 5),
        ),
        khataId: shop.id,
      );
      await ledger.addEntry(
        _entry(
          kind: EntryFormKind.expense,
          amountPaise: 300,
          category: 'Bills',
          description: 'Electricity',
          occurredAt: DateTime.utc(2026, 11, 20, 8, 10),
        ),
        khataId: home.id,
      );

      // 3 khatas (personal + shop + home) + 3 transactions = 6 pending rows.
      expect(await ledger.readPendingSyncCount(), 6);

      final List<SyncStatus> statuses = <SyncStatus>[];
      final StreamSubscription<SyncStatus> sub = engine.statusStream.listen(
        statuses.add,
      );

      final SyncOutcome outcome = await engine.syncNow();
      expect(outcome, SyncOutcome.synced);
      expect(await ledger.readPendingSyncCount(), 0);
      expect(await ledger.readPendingKhatas(), isEmpty);
      expect(await ledger.readPendingTransactions(), isEmpty);

      // Khatas pushed in batches of 2 (2 + 1) strictly before transactions (2 + 1).
      expect(backend.pushedKhataBatches.length, 2);
      expect(backend.pushedTransactionBatches.length, 2);
      final int lastKhataCall = backend.callOrder.lastIndexWhere(
        (String s) => s.startsWith('upsertKhatas:'),
      );
      final int firstTxCall = backend.callOrder.indexWhere(
        (String s) => s.startsWith('upsertTransactions:'),
      );
      expect(lastKhataCall, lessThan(firstTxCall));

      // Metadata stored: cursor, lastSyncedAt, lastSyncedAccountId, no error.
      final LocalSyncMetadata meta = await ledger.readSyncMetadata();
      expect(meta.lastSyncedAt, fakeNow);
      expect(meta.lastSyncedAccountId, _alice.id);
      expect(meta.lastError, isNull);
      expect(meta.cursor, isNotNull);

      expect(engine.currentStatus.isIdle, isTrue);
      expect(engine.currentStatus.pendingCount, 0);
      expect(engine.currentStatus.lastSyncedAt, fakeNow);
      expect(
        statuses.any((SyncStatus s) => s.kind == SyncStateKind.syncing),
        isTrue,
      );
      await sub.cancel();
    });

    test('bounded cursor continues past a row edited during push', () async {
      for (int index = 0; index < 7; index++) {
        await ledger.addEntry(
          _entry(
            kind: EntryFormKind.expense,
            amountPaise: 100 + index,
            category: 'Food',
            description: 'Entry $index',
            occurredAt: DateTime.utc(2026, 11, 20, 8, index),
          ),
        );
      }
      String? editedId;
      backend.beforeUpsertTransactions =
          (List<CloudTransactionRow> batch) async {
            if (editedId != null) return;
            editedId = batch.first.id;
            await ledger.updateEntry(
              khataId: 'personal',
              entryId: editedId!,
              entry: _entry(
                kind: EntryFormKind.expense,
                amountPaise: 999,
                category: 'Food',
                description: 'Changed in flight',
                occurredAt: DateTime.utc(2026, 11, 20),
              ),
            );
          };

      expect(await engine.syncNow(), SyncOutcome.synced);
      final List<CloudTransactionRow> sent = backend.pushedTransactionBatches
          .expand((List<CloudTransactionRow> batch) => batch)
          .toList();
      expect(sent, hasLength(7));
      expect(
        sent.map((CloudTransactionRow row) => row.id).toSet(),
        hasLength(7),
      );
      expect(
        backend.pushedTransactionBatches.every(
          (List<CloudTransactionRow> batch) => batch.length <= 2,
        ),
        isTrue,
      );
      expect((await ledger.readPendingTransactions()).single.id, editedId);
      expect(await engine.syncNow(), SyncOutcome.synced);
      expect(await ledger.readPendingTransactions(), isEmpty);
    });

    test('idempotent re-push sends nothing when nothing changed and pulls with 60s overlap', () async {
      await ledger.addEntry(
        _entry(
          kind: EntryFormKind.expense,
          amountPaise: 2500,
          category: 'Food',
          description: 'Breakfast',
          occurredAt: DateTime.utc(2026, 11, 20, 7, 30),
        ),
      );

      expect(await engine.syncNow(), SyncOutcome.synced);
      final DateTime firstCursor = (await ledger.readSyncMetadata()).cursor!;
      final int khataBatchesAfterFirst = backend.pushedKhataBatches.length;
      final int txBatchesAfterFirst = backend.pushedTransactionBatches.length;

      fakeNow = fakeNow.add(const Duration(minutes: 5));
      expect(await engine.syncNow(), SyncOutcome.synced);

      // Nothing pending -> zero new push calls.
      expect(backend.pushedKhataBatches.length, khataBatchesAfterFirst);
      expect(backend.pushedTransactionBatches.length, txBatchesAfterFirst);

      // Second pull uses cursor minus 60-second overlap, and re-applying the
      // overlapped rows is completely idempotent.
      expect(
        backend.fetchSinceArgs.last,
        firstCursor.subtract(const Duration(seconds: 60)),
      );
      expect(await ledger.readPendingSyncCount(), 0);
      final LedgerSummary summary = await ledger.readSummary();
      expect(summary.entries.length, 1);
      expect(summary.totalExpensePaise, 2500);
    });

    test('concurrent local edit during push stays pending and is not marked synced', () async {
      await ledger.addEntry(
        _entry(
          kind: EntryFormKind.expense,
          amountPaise: 1000,
          category: 'Shopping',
          description: 'Initial item',
          occurredAt: DateTime.utc(2026, 11, 20, 8, 0),
        ),
      );
      final String entryId = (await ledger.readSummary()).entries.single.id!;

      bool mutatedDuringPush = false;
      backend.beforeUpsertTransactions =
          (List<CloudTransactionRow> batch) async {
            if (!mutatedDuringPush) {
              mutatedDuringPush = true;
              await ledger.updateEntry(
                khataId: 'personal',
                entryId: entryId,
                entry: _entry(
                  kind: EntryFormKind.expense,
                  amountPaise: 4500,
                  category: 'Shopping',
                  description: 'Edited while pushing',
                  occurredAt: DateTime.utc(2026, 11, 20, 8, 0),
                ),
              );
            }
          };

      expect(await engine.syncNow(), SyncOutcome.synced);

      // Neither the push completion nor the 60s overlap pull overwrote the
      // newer concurrent local edit, and it remains pending for the next sync.
      final LedgerSummary afterFirstSync = await ledger.readSummary();
      expect(afterFirstSync.entries.single.amountPaise, 4500);
      expect(afterFirstSync.entries.single.description, 'Edited while pushing');
      expect(await ledger.readPendingSyncCount(), 1);
      expect((await ledger.readPendingTransactions()).single.id, entryId);

      // Next sync pushes the updated version and settles pending to 0.
      expect(await engine.syncNow(), SyncOutcome.synced);
      expect(await ledger.readPendingSyncCount(), 0);
      expect(
        backend
            .storedTransactionsFor(_alice.id)
            .singleWhere((CloudTransactionRow r) => r.id == entryId)
            .amountPaise,
        4500,
      );
    });

    test('pull applies newer remote rows, inserts unknown ids, and ignores older remote rows', () async {
      // Sync initial personal khata first.
      expect(await engine.syncNow(), SyncOutcome.synced);

      // Local entry edited at T=10:05.
      await ledger.addEntry(
        _entry(
          kind: EntryFormKind.expense,
          amountPaise: 9000,
          category: 'Bills',
          description: 'Local newer bill',
          occurredAt: DateTime.utc(2026, 11, 20, 9, 0),
        ),
      );
      final String localNewerId =
          (await ledger.readSummary()).entries.single.id!;
      final CloudTransactionRow localRow =
          (await ledger.readPendingTransactions()).single;
      // Mark it already synced locally with a newer updatedAt than what arrives remotely.
      await ledger.markTransactionsSyncedIfUnchanged(<CloudTransactionRow>[
        localRow,
      ]);

      // Remote has:
      // 1) A brand-new khata + transaction from another device.
      final DateTime remoteTime = localRow.updatedAt.add(
        const Duration(minutes: 2),
      );
      backend.seedRemoteKhata(
        _alice.id,
        CloudKhataRow(
          id: 'remote-trip',
          name: 'Trip Khata',
          openingBalancePaise: 200000,
          createdAt: remoteTime,
          updatedAt: remoteTime,
        ),
      );
      backend.seedRemoteTransaction(
        _alice.id,
        CloudTransactionRow(
          id: 'remote-tx-1',
          khataId: 'remote-trip',
          type: CloudTransactionType.expense,
          amountPaise: 35000,
          categoryId: 'Travel',
          description: 'Train ticket',
          occurredAt: remoteTime,
          createdAt: remoteTime,
          updatedAt: remoteTime,
        ),
      );

      // 2) A stale version of `localNewerId` with an older `updatedAt`.
      final DateTime olderTime = localRow.updatedAt.subtract(
        const Duration(minutes: 10),
      );
      backend.seedRemoteTransaction(
        _alice.id,
        CloudTransactionRow(
          id: localNewerId,
          khataId: 'personal',
          type: CloudTransactionType.expense,
          amountPaise: 111,
          categoryId: 'Bills',
          description: 'Stale remote copy',
          occurredAt: olderTime,
          createdAt: olderTime,
          updatedAt: olderTime,
        ),
      );

      expect(await engine.syncNow(), SyncOutcome.synced);

      // Unknown khata & tx inserted as synced.
      final LedgerSummary trip = await ledger.readSummary(
        khataId: 'remote-trip',
      );
      expect(trip.openingBalancePaise, 200000);
      expect(trip.entries.single.description, 'Train ticket');
      expect(trip.remainingPaise, 165000);

      // Older remote row ignored: local 9000 preserved.
      final LedgerSummary personal = await ledger.readSummary();
      expect(personal.entries.single.amountPaise, 9000);
      expect(personal.entries.single.description, 'Local newer bill');
      expect(await ledger.readPendingSyncCount(), 0);
    });

    test('tombstone and unarchive cases: tie keeps tombstone, newer unarchive clears deleted_at, never hard-deletes', () async {
      expect(await engine.syncNow(), SyncOutcome.synced);

      final DateTime t1 = DateTime.utc(2026, 11, 20, 11, 0, 0);
      // Seed live khata and live transaction locally via remote pull.
      backend.seedRemoteKhata(
        _alice.id,
        CloudKhataRow(
          id: 'khata-arch',
          name: 'Seasonal',
          openingBalancePaise: 10000,
          createdAt: t1,
          updatedAt: t1,
        ),
      );
      backend.seedRemoteTransaction(
        _alice.id,
        CloudTransactionRow(
          id: 'tx-tie',
          khataId: 'personal',
          type: CloudTransactionType.expense,
          amountPaise: 500,
          categoryId: 'Food',
          description: 'Snack',
          occurredAt: t1,
          createdAt: t1,
          updatedAt: t1,
        ),
      );
      expect(await engine.syncNow(), SyncOutcome.synced);
      expect((await ledger.readSummary()).entries.single.id, 'tx-tie');

      // Tie on updatedAt=t1 where incoming row has a tombstone -> tombstone wins!
      await ledger.applyRemoteTransactions(<CloudTransactionRow>[
        CloudTransactionRow(
          id: 'tx-tie',
          khataId: 'personal',
          type: CloudTransactionType.expense,
          amountPaise: 500,
          categoryId: 'Food',
          description: 'Snack',
          occurredAt: t1,
          createdAt: t1,
          updatedAt: t1,
          deletedAt: t1,
        ),
      ]);
      expect((await ledger.readSummary()).entries, isEmpty);

      // Tie on updatedAt=t1 where incoming row is live -> existing tombstone stays!
      await ledger.applyRemoteTransactions(<CloudTransactionRow>[
        CloudTransactionRow(
          id: 'tx-tie',
          khataId: 'personal',
          type: CloudTransactionType.expense,
          amountPaise: 500,
          categoryId: 'Food',
          description: 'Snack',
          occurredAt: t1,
          createdAt: t1,
          updatedAt: t1,
          deletedAt: null,
        ),
      ]);
      expect((await ledger.readSummary()).entries, isEmpty);
      // Row was never hard-deleted from SQLite.
      final QueryRow rawTx = await ledger
          .customSelect(
            'SELECT deleted_at FROM "transactions" WHERE id = ?',
            variables: <Variable<Object>>[Variable<String>('tx-tie')],
          )
          .getSingle();
      expect(rawTx.readNullable<String>('deleted_at'), isNotNull);

      // Remote archive of khata sets deleted_at; newer unarchive clears it.
      final DateTime t2 = t1.add(const Duration(minutes: 5));
      backend.seedRemoteKhata(
        _alice.id,
        CloudKhataRow(
          id: 'khata-arch',
          name: 'Seasonal',
          openingBalancePaise: 10000,
          createdAt: t1,
          updatedAt: t2,
          deletedAt: t2,
        ),
      );
      expect(await engine.syncNow(), SyncOutcome.synced);
      expect(
        (await ledger.listArchivedKhatas()).map((LocalKhata k) => k.id),
        contains('khata-arch'),
      );

      final DateTime t3 = t2.add(const Duration(minutes: 5));
      backend.seedRemoteKhata(
        _alice.id,
        CloudKhataRow(
          id: 'khata-arch',
          name: 'Seasonal Reopened',
          openingBalancePaise: 10000,
          createdAt: t1,
          updatedAt: t3,
          deletedAt: null,
        ),
      );
      expect(await engine.syncNow(), SyncOutcome.synced);
      expect(await ledger.listArchivedKhatas(), isEmpty);
      expect(
        (await ledger.listKhatas())
            .singleWhere((LocalKhata k) => k.id == 'khata-arch')
            .name,
        'Seasonal Reopened',
      );
    });

    test(
      'server-kept-newer row on upsert is applied locally and marked synced',
      () async {
        // Ensure personal khata is on the server first.
        expect(await engine.syncNow(), SyncOutcome.synced);

        // Insert a pending local khata and transaction with an older updated_at
        // than the version already stored on the server.
        final DateTime oldClientTime = DateTime.utc(2026, 11, 20, 8, 0, 0);
        final DateTime newerServerTime = DateTime.utc(2026, 11, 20, 12, 0, 0);

        await ledger.customStatement(
          'INSERT INTO khatas (id, name, opening_balance_paise, created_at, '
          "updated_at, sync_state) VALUES ('shared-k', 'Old Local Name', 1000, "
          "?, ?, 'pending')",
          <Object>[
            oldClientTime.toIso8601String(),
            oldClientTime.toIso8601String(),
          ],
        );
        await ledger.customStatement(
          'INSERT INTO "transactions" (id, khata_id, type, amount_paise, '
          'category_id, description, occurred_at, created_at, updated_at, '
          "sync_state) VALUES ('shared-tx', 'shared-k', 'expense', 200, "
          "'Food', 'Old local note', ?, ?, ?, 'pending')",
          <Object>[
            oldClientTime.toIso8601String(),
            oldClientTime.toIso8601String(),
            oldClientTime.toIso8601String(),
          ],
        );

        // Server already has newer versions of both rows.
        backend.seedRemoteKhata(
          _alice.id,
          CloudKhataRow(
            id: 'shared-k',
            name: 'Newer Server Name',
            openingBalancePaise: 9000,
            createdAt: oldClientTime,
            updatedAt: newerServerTime,
          ),
        );
        backend.seedRemoteTransaction(
          _alice.id,
          CloudTransactionRow(
            id: 'shared-tx',
            khataId: 'shared-k',
            type: CloudTransactionType.expense,
            amountPaise: 750,
            categoryId: 'Food',
            description: 'Newer server note',
            occurredAt: oldClientTime,
            createdAt: oldClientTime,
            updatedAt: newerServerTime,
          ),
        );

        expect(await engine.syncNow(), SyncOutcome.synced);

        // Both local rows adopted the server's newer values and are now synced.
        final LocalKhata syncedKhata = (await ledger.listKhatas()).singleWhere(
          (LocalKhata k) => k.id == 'shared-k',
        );
        expect(syncedKhata.name, 'Newer Server Name');
        expect(syncedKhata.openingBalancePaise, 9000);

        final LedgerSummary summary = await ledger.readSummary(
          khataId: 'shared-k',
        );
        expect(summary.entries.single.amountPaise, 750);
        expect(summary.entries.single.description, 'Newer server note');
        expect(await ledger.readPendingSyncCount(), 0);
      },
    );

    test('failure leaves local data intact, records error, and schedules capped exponential backoff', () async {
      await ledger.addEntry(
        _entry(
          kind: EntryFormKind.expense,
          amountPaise: 32100,
          category: 'Bills',
          description: 'Keep safe offline',
          occurredAt: DateTime.utc(2026, 11, 20, 9, 15),
        ),
      );

      backend.nextError = Exception('Gateway timeout 504');
      final SyncOutcome firstFail = await engine.syncNow();
      expect(firstFail, SyncOutcome.failed);

      // Local data and pending count untouched.
      final LedgerSummary summary = await ledger.readSummary();
      expect(summary.entries.single.amountPaise, 32100);
      expect(summary.entries.single.description, 'Keep safe offline');
      expect(await ledger.readPendingSyncCount(), 2); // personal + entry

      // Error persisted and emitted in statusStream.
      final LocalSyncMetadata meta = await ledger.readSyncMetadata();
      expect(meta.lastError, 'Gateway timeout 504');
      expect(engine.currentStatus.isError, isTrue);
      expect(engine.currentStatus.errorReason, 'Gateway timeout 504');
      expect(engine.currentStatus.pendingCount, 2);
      expect(engine.scheduler.failureCount, 1);
      expect(engine.scheduler.scheduledRetryDelay, const Duration(seconds: 2));

      // Second consecutive failure doubles backoff to 4s.
      backend.nextError = Exception('Gateway timeout 504 again');
      expect(await engine.syncNow(), SyncOutcome.failed);
      expect(engine.scheduler.failureCount, 2);
      expect(engine.scheduler.scheduledRetryDelay, const Duration(seconds: 4));

      // Subsequent recovery clears error, resets backoff, and syncs everything.
      expect(await engine.syncNow(), SyncOutcome.synced);
      expect(engine.scheduler.failureCount, 0);
      expect(engine.scheduler.hasScheduledRetry, isFalse);
      expect((await ledger.readSyncMetadata()).lastError, isNull);
      expect(engine.currentStatus.isIdle, isTrue);
      expect(await ledger.readPendingSyncCount(), 0);
    });

    test('account-switch guard blocks pushing to a different account until confirmed', () async {
      await ledger.addEntry(
        _entry(
          kind: EntryFormKind.income,
          amountPaise: 15000,
          category: 'Income',
          description: 'Alice salary',
          occurredAt: DateTime.utc(2026, 11, 20, 8, 0),
        ),
      );
      expect(await engine.syncNow(), SyncOutcome.synced);
      expect((await ledger.readSyncMetadata()).lastSyncedAccountId, _alice.id);

      // Add a new local entry while signed out, then sign in as Bob.
      await engine.signOut();
      expect(engine.currentStatus.isSignedOut, isTrue);
      // Sign-out never deletes local data.
      expect((await ledger.readSummary()).entries.length, 1);

      await ledger.addEntry(
        _entry(
          kind: EntryFormKind.expense,
          amountPaise: 2000,
          category: 'Food',
          description: 'Unsynced lunch',
          occurredAt: DateTime.utc(2026, 11, 20, 9, 0),
        ),
      );

      final int pushCountBeforeBob =
          backend.pushedKhataBatches.length +
          backend.pushedTransactionBatches.length;
      backend.setSignedInUser(_bob);
      await Future<void>.delayed(Duration.zero);

      // Attempting syncNow without confirmation pushes NOTHING to Bob's account.
      final SyncOutcome blocked = await engine.syncNow();
      expect(blocked, SyncOutcome.accountSwitchConfirmationRequired);
      expect(engine.currentStatus.requiresAccountSwitchConfirmation, isTrue);
      expect(engine.currentStatus.previousAccountId, _alice.id);
      expect(
        backend.pushedKhataBatches.length +
            backend.pushedTransactionBatches.length,
        pushCountBeforeBob,
      );
      expect(backend.storedKhatasFor(_bob.id), isEmpty);
      expect(backend.storedTransactionsFor(_bob.id), isEmpty);

      // Once the user confirms, all local khatas & transactions push to Bob.
      final SyncOutcome confirmed = await engine.confirmAccountSwitchAndSync();
      expect(confirmed, SyncOutcome.synced);
      expect(engine.currentStatus.requiresAccountSwitchConfirmation, isFalse);
      expect((await ledger.readSyncMetadata()).lastSyncedAccountId, _bob.id);
      expect(backend.storedKhatasFor(_bob.id), hasLength(1));
      expect(backend.storedTransactionsFor(_bob.id), hasLength(2));
      expect(await ledger.readPendingSyncCount(), 0);
    });

    test(
      'signed out and offline states are clean no-ops without exceptions',
      () async {
        await engine.signOut();
        expect(await engine.syncNow(), SyncOutcome.signedOut);
        expect(engine.currentStatus.isSignedOut, isTrue);

        backend.setSignedInUser(_alice);
        backend.offline = true;
        expect(await engine.syncNow(), SyncOutcome.offline);
        expect(engine.currentStatus.isIdle, isTrue);
        expect(engine.currentStatus.isOffline, isTrue);
        expect((await ledger.readSyncMetadata()).lastError, isNull);
      },
    );
  });

  group('SyncScheduler debounce and capped exponential backoff', () {
    test('kick() debounces rapid local writes and retries with capped backoff', () {
      fakeAsync((FakeAsync async) {
        int runs = 0;
        bool shouldSucceed = false;

        final SyncScheduler scheduler = SyncScheduler(
          debounce: const Duration(milliseconds: 500),
          baseBackoff: const Duration(seconds: 2),
          maxBackoff: const Duration(seconds: 10),
          runSync: () async {
            runs++;
            return shouldSucceed;
          },
        );

        // Three rapid kicks within 500ms coalesce into a single sync execution.
        scheduler.kick();
        async.elapse(const Duration(milliseconds: 200));
        scheduler.kick();
        async.elapse(const Duration(milliseconds: 200));
        scheduler.kick();
        async.elapse(const Duration(milliseconds: 499));
        expect(runs, 0);

        async.elapse(const Duration(milliseconds: 1));
        expect(runs, 1);
        // Attempt 1 failed -> retry in 2s.
        expect(scheduler.failureCount, 1);
        expect(scheduler.scheduledRetryDelay, const Duration(seconds: 2));

        async.elapse(const Duration(seconds: 2));
        expect(runs, 2);
        // Attempt 2 failed -> retry in 4s.
        expect(scheduler.failureCount, 2);
        expect(scheduler.scheduledRetryDelay, const Duration(seconds: 4));

        async.elapse(const Duration(seconds: 4));
        expect(runs, 3);
        // Attempt 3 failed -> retry in 8s.
        expect(scheduler.failureCount, 3);
        expect(scheduler.scheduledRetryDelay, const Duration(seconds: 8));

        async.elapse(const Duration(seconds: 8));
        expect(runs, 4);
        // Attempt 4 failed -> 16s capped at maxBackoff (10s).
        expect(scheduler.failureCount, 4);
        expect(scheduler.scheduledRetryDelay, const Duration(seconds: 10));

        shouldSucceed = true;
        async.elapse(const Duration(seconds: 10));
        expect(runs, 5);
        expect(scheduler.failureCount, 0);
        expect(scheduler.hasScheduledRetry, isFalse);

        scheduler.dispose();
      });
    });
  });
}
