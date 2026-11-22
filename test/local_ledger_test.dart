import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khoroch_diary/features/entry/add_entry_screen.dart';
import 'package:khoroch_diary/features/home/models.dart';
import 'package:khoroch_diary/features/ledger/data/ledger_backup.dart';
import 'package:khoroch_diary/features/ledger/data/local_ledger.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('entries persist across close and reopen with exact paise', () async {
    final Directory dir = await Directory.systemTemp.createTemp('khata_test_');
    final File file = File('${dir.path}/ledger.sqlite');
    try {
      LocalLedger ledger = LocalLedger(NativeDatabase(file));
      await ledger.initialize();
      expect((await ledger.readSummary()).remainingPaise, 0);
      await ledger.addEntry(
        _entry(
          kind: EntryFormKind.income,
          amountPaise: 1000000,
          category: 'Income',
          occurredAt: DateTime(2026, 1, 2),
        ),
      );
      await ledger.addEntry(
        _entry(
          kind: EntryFormKind.expense,
          amountPaise: 58005,
          category: 'Food',
          description: 'Lunch',
          occurredAt: DateTime(2026, 1, 3),
        ),
      );
      await ledger.close();
      ledger = LocalLedger(NativeDatabase(file));
      await ledger.initialize();
      final LedgerSummary summary = await ledger.readSummary();
      expect(summary.totalIncomePaise, 1000000);
      expect(summary.totalExpensePaise, 58005);
      expect(summary.remainingPaise, 941995);
      expect(summary.entries.first.title, 'Lunch');
      expect(summary.entries.length, 2);
      await ledger.close();
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('v1 on-disk migration preserves khatas and transactions', () async {
    final Directory dir = await Directory.systemTemp.createTemp(
      'khata_v1_migration_',
    );
    final File file = File('${dir.path}/ledger.sqlite');
    try {
      final LocalLedger ledger = LocalLedger(
        NativeDatabase(
          file,
          setup: (database) {
            database.execute('''
              CREATE TABLE khatas (
                id TEXT PRIMARY KEY NOT NULL,
                name TEXT NOT NULL,
                opening_balance_paise INTEGER NOT NULL DEFAULT 0
                  CHECK (typeof(opening_balance_paise) = 'integer'),
                currency TEXT NOT NULL DEFAULT 'INR',
                sort_order INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                deleted_at TEXT,
                sync_state TEXT NOT NULL DEFAULT 'pending'
              )
            ''');
            database.execute('''
              CREATE TABLE "transactions" (
                id TEXT PRIMARY KEY NOT NULL,
                khata_id TEXT NOT NULL REFERENCES khatas(id),
                type TEXT NOT NULL CHECK (type IN ('income','expense')),
                amount_paise INTEGER NOT NULL
                  CHECK (typeof(amount_paise) = 'integer' AND amount_paise > 0),
                category_id TEXT NOT NULL,
                description TEXT CHECK (description IS NULL OR length(description) <= 120),
                occurred_at TEXT NOT NULL,
                note_session_id TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                deleted_at TEXT,
                sync_state TEXT NOT NULL DEFAULT 'pending'
              )
            ''');
            database.execute(
              'CREATE INDEX idx_transactions_khata_occurred_at '
              'ON "transactions" (khata_id, occurred_at DESC)',
            );
            database.execute(
              'CREATE INDEX idx_transactions_sync_state '
              'ON "transactions" (sync_state)',
            );
            database.execute('''
              INSERT INTO khatas
                (id, name, opening_balance_paise, created_at, updated_at)
              VALUES
                ('personal', 'Personal Khata', 0, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
                ('business-v1', 'Business', 250000, '2026-01-02T00:00:00Z', '2026-01-02T00:00:00Z')
            ''');
            database.execute('''
              INSERT INTO "transactions"
                (id, khata_id, type, amount_paise, category_id, description,
                 occurred_at, created_at, updated_at)
              VALUES
                ('entry-v1', 'business-v1', 'expense', 12500, 'Bills', 'V1 record',
                 '2026-01-03T00:00:00Z', '2026-01-03T00:00:00Z', '2026-01-03T00:00:00Z')
            ''');
            database.execute('PRAGMA user_version = 1');
          },
        ),
      );

      expect(await ledger.readActiveKhataId(), 'personal');
      final List<LocalKhata> khatas = await ledger.listKhatas();
      expect(khatas.map((LocalKhata khata) => khata.id), <String>[
        'personal',
        'business-v1',
      ]);
      final LedgerSummary business = await ledger.readSummary(
        khataId: 'business-v1',
      );
      expect(business.openingBalancePaise, 250000);
      expect(business.entries.single.id, 'entry-v1');
      expect(business.entries.single.title, 'V1 record');
      expect(business.totalExpensePaise, 12500);
      expect(business.remainingPaise, 237500);
      expect(
        (await ledger.customSelect('PRAGMA foreign_key_check').get()).isEmpty,
        isTrue,
      );
      await ledger.setActiveKhataId('business-v1');
      await ledger.close();

      final LocalLedger reopened = LocalLedger(NativeDatabase(file));
      expect(await reopened.readActiveKhataId(), 'business-v1');
      expect(
        (await reopened.readSummary(khataId: 'business-v1')).remainingPaise,
        237500,
      );
      await reopened.close();
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test(
    'v2 on-disk migration adds sync_metadata without touching data',
    () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'khata_v2_migration_',
      );
      final File file = File('${dir.path}/ledger.sqlite');
      try {
        final LocalLedger ledger = LocalLedger(
          NativeDatabase(
            file,
            setup: (database) {
              database.execute('''
              CREATE TABLE khatas (
                id TEXT PRIMARY KEY NOT NULL,
                name TEXT NOT NULL,
                opening_balance_paise INTEGER NOT NULL DEFAULT 0
                  CHECK (typeof(opening_balance_paise) = 'integer'),
                currency TEXT NOT NULL DEFAULT 'INR',
                sort_order INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                deleted_at TEXT,
                sync_state TEXT NOT NULL DEFAULT 'pending'
              )
            ''');
              database.execute('''
              CREATE TABLE "transactions" (
                id TEXT PRIMARY KEY NOT NULL,
                khata_id TEXT NOT NULL REFERENCES khatas(id),
                type TEXT NOT NULL CHECK (type IN ('income','expense')),
                amount_paise INTEGER NOT NULL
                  CHECK (typeof(amount_paise) = 'integer' AND amount_paise > 0),
                category_id TEXT NOT NULL,
                description TEXT CHECK (description IS NULL OR length(description) <= 120),
                occurred_at TEXT NOT NULL,
                note_session_id TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                deleted_at TEXT,
                sync_state TEXT NOT NULL DEFAULT 'pending'
              )
            ''');
              database.execute('''
              CREATE TABLE active_khata_preference (
                singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
                khata_id TEXT NOT NULL
              )
            ''');
              database.execute('''
              INSERT INTO khatas
                (id, name, opening_balance_paise, created_at, updated_at)
              VALUES
                ('personal', 'Personal Khata', 0, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
                ('biz-v2', 'Business V2', 50000, '2026-01-02T00:00:00Z', '2026-01-02T00:00:00Z')
            ''');
              database.execute(
                "INSERT INTO active_khata_preference (singleton, khata_id) VALUES (1, 'biz-v2')",
              );
              database.execute('PRAGMA user_version = 2');
            },
          ),
        );

        expect(await ledger.readActiveKhataId(), 'biz-v2');
        expect(
          (await ledger.customSelect('PRAGMA user_version').getSingle())
              .read<int>('user_version'),
          4,
        );
        expect(await ledger.readSyncMetadata(), LocalSyncMetadata());
        final List<QueryRow> cursorIndexes = await ledger
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'index' "
              "AND name IN ('idx_khatas_pending_cursor', "
              "'idx_transactions_pending_cursor') ORDER BY name",
            )
            .get();
        expect(
          cursorIndexes.map((QueryRow row) => row.read<String>('name')),
          <String>[
            'idx_khatas_pending_cursor',
            'idx_transactions_pending_cursor',
          ],
        );
        expect(await ledger.readPendingSyncCount(), 2);
        await ledger.close();
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );

  test('active khata defaults, persists, and rejects stale selections', () async {
    final Directory dir = await Directory.systemTemp.createTemp(
      'khata_selection_',
    );
    final File file = File('${dir.path}/ledger.sqlite');
    try {
      LocalLedger ledger = LocalLedger(NativeDatabase(file));
      await ledger.initialize();
      expect(
        (await ledger.customSelect('PRAGMA user_version').getSingle())
            .read<int>('user_version'),
        4,
      );
      expect(
        (await ledger
                .customSelect(
                  "SELECT name FROM sqlite_master WHERE type = 'table' "
                  "AND name = 'active_khata_preference'",
                )
                .get())
            .length,
        1,
      );
      expect(
        (await ledger
                .customSelect(
                  "SELECT name FROM sqlite_master WHERE type = 'table' "
                  "AND name = 'sync_metadata'",
                )
                .get())
            .length,
        1,
      );
      expect(await ledger.readActiveKhataId(), 'personal');
      final LocalKhata business = await ledger.createKhata(
        name: 'Business',
        openingBalancePaise: 10000,
      );
      await ledger.setActiveKhataId(business.id);
      await expectLater(
        ledger.setActiveKhataId('missing'),
        throwsA(isA<KhataNotFoundException>()),
      );
      expect(await ledger.readActiveKhataId(), business.id);
      await ledger.close();

      ledger = LocalLedger(NativeDatabase(file));
      expect(await ledger.readActiveKhataId(), business.id);
      await ledger.customStatement(
        'UPDATE khatas SET deleted_at = ? WHERE id = ?',
        <Object?>[DateTime.now().toUtc().toIso8601String(), business.id],
      );
      expect(await ledger.readActiveKhataId(), 'personal');
      final QueryRow preference = await ledger
          .customSelect(
            'SELECT khata_id FROM active_khata_preference WHERE singleton = 1',
          )
          .getSingle();
      expect(preference.read<String>('khata_id'), 'personal');
      await ledger.close();
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('deleted personal fallback does not recreate a khata', () async {
    final LocalLedger ledger = LocalLedger(NativeDatabase.memory());
    await ledger.initialize();
    await ledger.customStatement(
      'UPDATE khatas SET deleted_at = ? WHERE id = ?',
      <Object?>[DateTime.now().toUtc().toIso8601String(), 'personal'],
    );
    await expectLater(
      ledger.readActiveKhataId(),
      throwsA(isA<KhataNotFoundException>()),
    );
    expect(await ledger.listKhatas(), isEmpty);
    await ledger.close();
  });

  test('initialize is idempotent and keeps the default khata empty', () async {
    final LocalLedger ledger = LocalLedger(NativeDatabase.memory());
    await ledger.initialize();
    await ledger.initialize();
    await ledger.initialize();

    final List<LocalKhata> khatas = await ledger.listKhatas();
    expect(khatas.length, 1);
    expect(khatas.single.id, 'personal');
    expect(khatas.single.name, 'Personal Khata');
    expect(khatas.single.openingBalancePaise, 0);

    final LedgerSummary summary = await ledger.readSummary();
    expect(summary.openingBalancePaise, 0);
    expect(summary.entries, isEmpty);
    expect(summary.totalIncomePaise, 0);
    expect(summary.totalExpensePaise, 0);
    expect(summary.remainingPaise, 0);

    // A second initialize after data exists changes nothing.
    await ledger.addEntry(
      _entry(
        kind: EntryFormKind.income,
        amountPaise: 500,
        category: 'Income',
        occurredAt: DateTime(2026, 2, 1),
      ),
    );
    await ledger.initialize();
    expect((await ledger.listKhatas()).length, 1);
    expect((await ledger.readSummary()).remainingPaise, 500);
    await ledger.close();
  });

  test('two khatas keep opening balances and summaries isolated', () async {
    final LocalLedger ledger = LocalLedger(NativeDatabase.memory());
    await ledger.initialize();

    final LocalKhata business = await ledger.createKhata(
      name: '  Business Khata  ',
      openingBalancePaise: 250000,
    );
    expect(business.name, 'Business Khata'); // trimmed on the way in
    expect(business.openingBalancePaise, 250000);
    expect(business.id, isNot('personal'));
    expect(business.id.length, greaterThan(0));

    final List<LocalKhata> khatas = await ledger.listKhatas();
    expect(khatas.length, 2);
    expect(khatas.first.id, 'personal'); // default khata is deterministic first
    expect(khatas.map((LocalKhata k) => k.id), contains(business.id));
    expect(
      (await ledger.listKhatas()).map((LocalKhata k) => k.id).toList(),
      khatas.map((LocalKhata k) => k.id).toList(),
    );

    // Personal: income only.
    await ledger.addEntry(
      _entry(
        kind: EntryFormKind.income,
        amountPaise: 700000,
        category: 'Income',
        occurredAt: DateTime(2026, 3, 1),
      ),
    );
    // Business: its own income and expense.
    await ledger.addEntry(
      _entry(
        kind: EntryFormKind.income,
        amountPaise: 300000,
        category: 'Income',
        description: 'Client payment',
        occurredAt: DateTime(2026, 3, 2),
      ),
      khataId: business.id,
    );
    await ledger.addEntry(
      _entry(
        kind: EntryFormKind.expense,
        amountPaise: 45000,
        category: 'Bills',
        description: 'Electricity',
        occurredAt: DateTime(2026, 3, 3),
      ),
      khataId: business.id,
    );

    final LedgerSummary personal = await ledger.readSummary();
    expect(personal.openingBalancePaise, 0);
    expect(personal.entries.length, 1);
    expect(personal.totalIncomePaise, 700000);
    expect(personal.totalExpensePaise, 0);
    expect(personal.remainingPaise, 700000);

    final LedgerSummary businessSummary = await ledger.readSummary(
      khataId: business.id,
    );
    expect(businessSummary.openingBalancePaise, 250000);
    expect(businessSummary.entries.length, 2);
    expect(businessSummary.totalIncomePaise, 550000);
    expect(businessSummary.totalExpensePaise, 45000);
    expect(businessSummary.remainingPaise, 505000);
    expect(
      businessSummary.entries.map((LedgerEntry e) => e.title),
      containsAll(<String>['Client payment', 'Electricity']),
    );
    // No entry from one khata leaks into the other.
    expect(
      businessSummary.entries.any((LedgerEntry e) => e.title == 'Income'),
      isFalse,
    );

    await ledger.close();
  });

  test('createKhata rejects bad names and amounts', () async {
    final LocalLedger ledger = LocalLedger(NativeDatabase.memory());
    await ledger.initialize();
    final int before = (await ledger.listKhatas()).length;

    for (final String bad in <String>['', '   ', '\n\t']) {
      await expectLater(
        ledger.createKhata(name: bad, openingBalancePaise: 0),
        throwsArgumentError,
      );
    }
    final String forty = List<String>.filled(40, 'a').join();
    await expectLater(
      ledger.createKhata(name: '$forty!', openingBalancePaise: 0),
      throwsArgumentError,
    );
    // Exactly 40 characters is allowed.
    final LocalKhata maxName = await ledger.createKhata(
      name: forty,
      openingBalancePaise: 0,
    );
    expect(maxName.name.length, 40);

    await expectLater(
      ledger.createKhata(name: 'Negative', openingBalancePaise: -1),
      throwsArgumentError,
    );
    await expectLater(
      ledger.createKhata(name: 'Too big', openingBalancePaise: 100000000000),
      throwsArgumentError,
    );

    // Only the valid khata was written; failures left no partial rows.
    expect((await ledger.listKhatas()).length, before + 1);
    await ledger.close();
  });

  test('summary and addEntry reject missing or deleted khatas', () async {
    final LocalLedger ledger = LocalLedger(NativeDatabase.memory());
    await ledger.initialize();

    await expectLater(
      ledger.readSummary(khataId: 'does-not-exist'),
      throwsA(isA<KhataNotFoundException>()),
    );
    await expectLater(
      ledger.addEntry(
        _entry(
          kind: EntryFormKind.expense,
          amountPaise: 100,
          category: 'Food',
          occurredAt: DateTime(2026, 4, 1),
        ),
        khataId: 'does-not-exist',
      ),
      throwsA(isA<KhataNotFoundException>()),
    );
    // A blank id is just another unknown khata, not a fallback to personal.
    await expectLater(
      ledger.readSummary(khataId: '  '),
      throwsA(isA<KhataNotFoundException>()),
    );

    final LocalKhata temp = await ledger.createKhata(
      name: 'Temp',
      openingBalancePaise: 1000,
    );
    await ledger.addEntry(
      _entry(
        kind: EntryFormKind.expense,
        amountPaise: 100,
        category: 'Food',
        occurredAt: DateTime(2026, 4, 2),
      ),
      khataId: temp.id,
    );
    // Tombstone it (tombstones are the schema's delete) and check it is gone.
    await ledger.customStatement(
      'UPDATE khatas SET deleted_at = ? WHERE id = ?',
      <Object?>[DateTime.now().toUtc().toIso8601String(), temp.id],
    );
    expect(
      (await ledger.listKhatas()).map((LocalKhata k) => k.id),
      isNot(contains(temp.id)),
    );
    await expectLater(
      ledger.readSummary(khataId: temp.id),
      throwsA(isA<KhataNotFoundException>()),
    );
    await expectLater(
      ledger.addEntry(
        _entry(
          kind: EntryFormKind.expense,
          amountPaise: 100,
          category: 'Food',
          occurredAt: DateTime(2026, 4, 3),
        ),
        khataId: temp.id,
      ),
      throwsA(isA<KhataNotFoundException>()),
    );

    // The rejected write did not land in the personal khata either.
    final LedgerSummary personal = await ledger.readSummary();
    expect(personal.entries, isEmpty);
    expect(personal.remainingPaise, 0);
    // The deleted khata's own row is untouched.
    final int kept =
        (await ledger
                .customSelect(
                  'SELECT COUNT(*) AS n FROM "transactions" WHERE khata_id = ?',
                  variables: <Variable<Object>>[Variable<String>(temp.id)],
                )
                .getSingle())
            .read<int>('n');
    expect(kept, 1);

    await ledger.close();
  });

  test('multiple khatas and their entries persist across reopen', () async {
    final Directory dir = await Directory.systemTemp.createTemp('khata_multi_');
    final File file = File('${dir.path}/ledger.sqlite');
    try {
      LocalLedger ledger = LocalLedger(NativeDatabase(file));
      await ledger.initialize();
      final LocalKhata shop = await ledger.createKhata(
        name: 'Shop Khata',
        openingBalancePaise: 123456,
      );
      await ledger.addEntry(
        _entry(
          kind: EntryFormKind.expense,
          amountPaise: 2345,
          category: 'Shopping',
          description: 'Stock',
          occurredAt: DateTime(2026, 5, 1),
        ),
        khataId: shop.id,
      );
      await ledger.close();

      ledger = LocalLedger(NativeDatabase(file));
      await ledger.initialize();
      final List<LocalKhata> khatas = await ledger.listKhatas();
      expect(khatas.length, 2);
      final LocalKhata reopened = khatas.firstWhere(
        (LocalKhata k) => k.id == shop.id,
      );
      expect(reopened.name, 'Shop Khata');
      expect(reopened.openingBalancePaise, 123456);

      final LedgerSummary shopSummary = await ledger.readSummary(
        khataId: shop.id,
      );
      expect(shopSummary.openingBalancePaise, 123456);
      expect(shopSummary.totalExpensePaise, 2345);
      expect(shopSummary.remainingPaise, 121111);
      expect(shopSummary.entries.single.title, 'Stock');

      final LedgerSummary personal = await ledger.readSummary();
      expect(personal.entries, isEmpty);
      expect(personal.remainingPaise, 0);
      await ledger.close();
    } finally {
      await dir.delete(recursive: true);
    }
  });

  group('entry ids and descriptions', () {
    test('reads expose the stored id and raw nullable description', () async {
      final LocalLedger ledger = LocalLedger(NativeDatabase.memory());
      await ledger.initialize();
      await ledger.addEntry(
        _entry(
          kind: EntryFormKind.expense,
          amountPaise: 45000,
          category: 'Bills',
          description: '  Electricity  ',
          occurredAt: DateTime(2026, 1, 1),
        ),
      );
      await ledger.addEntry(
        _entry(
          kind: EntryFormKind.income,
          amountPaise: 300000,
          category: 'Income',
          occurredAt: DateTime(2026, 1, 2),
        ),
      );

      final LedgerSummary summary = await ledger.readSummary();
      final LedgerEntry withText = summary.entries.firstWhere(
        (LedgerEntry e) => e.category == 'Bills',
      );
      final LedgerEntry noText = summary.entries.firstWhere(
        (LedgerEntry e) => e.category == 'Income',
      );

      // Real ids, unique and non-empty.
      expect(withText.id, isNotNull);
      expect(noText.id, isNotNull);
      expect(withText.id, isNot(noText.id));
      expect(withText.id, isNotEmpty);

      // Stored description is trimmed before insert and reported as stored.
      expect(withText.description, 'Electricity');
      expect(withText.title, 'Electricity');

      // An empty description stays null; the category is only the title
      // fallback and is never reported as stored data.
      expect(noText.description, isNull);
      expect(noText.title, 'Income');

      // The default constructor's optional fields stay compatible.
      final LedgerEntry legacy = LedgerEntry(
        title: 'Lunch',
        category: 'Food',
        at: DateTime(2026, 1, 1),
        amountPaise: 1,
      );
      expect(legacy.id, isNull);
      expect(legacy.description, isNull);
      await ledger.close();
    });
  });

  group('edit, soft delete and restore', () {
    late LocalLedger ledger;
    late String personalEntryId;
    late String businessEntryId;
    late LocalKhata business;

    setUp(() async {
      ledger = LocalLedger(NativeDatabase.memory());
      await ledger.initialize();
      business = await ledger.createKhata(
        name: 'Business',
        openingBalancePaise: 100000,
      );
      await ledger.addEntry(
        _entry(
          kind: EntryFormKind.expense,
          amountPaise: 45000,
          category: 'Bills',
          description: 'Electricity',
          occurredAt: DateTime(2026, 2, 1),
        ),
      );
      await ledger.addEntry(
        _entry(
          kind: EntryFormKind.expense,
          amountPaise: 10000,
          category: 'Food',
          description: 'Stock lunch',
          occurredAt: DateTime(2026, 2, 2),
        ),
        khataId: business.id,
      );
      personalEntryId = (await ledger.readSummary()).entries.single.id!;
      businessEntryId = (await ledger.readSummary(khataId: business.id))
          .entries
          .single
          .id!;
    });

    tearDown(() async {
      await ledger.close();
    });

    Future<QueryRow> row(String id) => ledger
        .customSelect(
          'SELECT * FROM "transactions" WHERE id = ?',
          variables: <Variable<Object>>[Variable<String>(id)],
        )
        .getSingle();

    test('update edits the exact row and moves the balance', () async {
      final QueryRow before = await row(personalEntryId);
      final String createdAt = before.read<String>('created_at');

      final bool ok = await ledger.updateEntry(
        khataId: 'personal',
        entryId: personalEntryId,
        entry: _entry(
          kind: EntryFormKind.income,
          amountPaise: 99900,
          category: 'Gifts',
          description: 'Diwali gift',
          occurredAt: DateTime(2026, 3, 5),
        ),
      );
      expect(ok, isTrue);

      final LedgerSummary summary = await ledger.readSummary();
      expect(summary.entries.length, 1);
      final LedgerEntry edited = summary.entries.single;
      expect(edited.id, personalEntryId);
      expect(edited.type, EntryType.income);
      expect(edited.amountPaise, 99900);
      expect(edited.category, 'Gifts');
      expect(edited.description, 'Diwali gift');
      expect(edited.title, 'Diwali gift');
      expect(edited.at, DateTime(2026, 3, 5).toLocal());
      expect(summary.totalExpensePaise, 0);
      expect(summary.remainingPaise, 99900);

      // id and created_at are preserved; updated_at and sync_state are bumped.
      final QueryRow after = await row(personalEntryId);
      expect(after.read<String>('id'), personalEntryId);
      expect(after.read<String>('created_at'), createdAt);
      expect(after.read<String>('sync_state'), 'pending');
      expect(after.readNullable<String>('deleted_at'), isNull);

      // The other khata is untouched.
      final LedgerSummary other = await ledger.readSummary(
        khataId: business.id,
      );
      expect(other.entries.single.amountPaise, 10000);
      expect(other.remainingPaise, 90000);
    });

    test(
      'update can clear a description back to NULL, never the category',
      () async {
        final bool ok = await ledger.updateEntry(
          khataId: 'personal',
          entryId: personalEntryId,
          entry: _entry(
            kind: EntryFormKind.expense,
            amountPaise: 45000,
            category: 'Bills',
            occurredAt: DateTime(2026, 2, 1),
          ),
        );
        expect(ok, isTrue);
        expect(
          (await row(personalEntryId)).readNullable<String>('description'),
          isNull,
        );
        final LedgerEntry entry = (await ledger.readSummary()).entries.single;
        expect(entry.description, isNull);
        expect(entry.title, 'Bills'); // display fallback only
      },
    );

    test('soft delete removes an entry and restore brings it back', () async {
      expect((await ledger.readSummary()).remainingPaise, -45000);

      expect(
        await ledger.softDeleteEntry(
          khataId: 'personal',
          entryId: personalEntryId,
        ),
        isTrue,
      );
      LedgerSummary deleted = await ledger.readSummary();
      expect(deleted.entries, isEmpty);
      expect(deleted.remainingPaise, 0);
      // The row survives as a tombstone; nothing was destroyed.
      final QueryRow tombstone = await row(personalEntryId);
      expect(tombstone.readNullable<String>('deleted_at'), isNotNull);
      expect(tombstone.read<String>('sync_state'), 'pending');

      expect(
        await ledger.restoreEntry(
          khataId: 'personal',
          entryId: personalEntryId,
        ),
        isTrue,
      );
      deleted = await ledger.readSummary();
      expect(deleted.entries.single.id, personalEntryId);
      expect(deleted.entries.single.title, 'Electricity');
      expect(deleted.remainingPaise, -45000);
      expect(
        (await row(personalEntryId)).readNullable<String>('deleted_at'),
        isNull,
      );
    });

    test('wrong khata, missing ids and wrong states are no-ops', () async {
      // Cross-khata: a real id addressed through the other khata.
      expect(
        await ledger.updateEntry(
          khataId: business.id,
          entryId: personalEntryId,
          entry: _entry(
            kind: EntryFormKind.income,
            amountPaise: 1,
            category: 'Income',
            occurredAt: DateTime(2026, 4, 4),
          ),
        ),
        isFalse,
      );
      expect(
        await ledger.softDeleteEntry(
          khataId: business.id,
          entryId: personalEntryId,
        ),
        isFalse,
      );
      // Missing ids.
      expect(
        await ledger.softDeleteEntry(khataId: 'personal', entryId: 'nope'),
        isFalse,
      );
      expect(
        await ledger.restoreEntry(khataId: 'personal', entryId: 'nope'),
        isFalse,
      );
      // Unknown khata is reported false, not redirected to personal.
      expect(
        await ledger.softDeleteEntry(
          khataId: 'ghost',
          entryId: personalEntryId,
        ),
        isFalse,
      );

      // Nothing changed anywhere.
      expect((await row(personalEntryId)).read<int>('amount_paise'), 45000);
      expect(
        (await row(personalEntryId)).readNullable<String>('deleted_at'),
        isNull,
      );
      expect((await ledger.readSummary()).entries.length, 1);
      expect(
        (await ledger.readSummary(khataId: business.id)).entries.length,
        1,
      );

      // Already deleted: second delete is false; restoring an active row is
      // false.
      expect(
        await ledger.softDeleteEntry(
          khataId: 'personal',
          entryId: personalEntryId,
        ),
        isTrue,
      );
      expect(
        await ledger.softDeleteEntry(
          khataId: 'personal',
          entryId: personalEntryId,
        ),
        isFalse,
      );
      expect(
        await ledger.restoreEntry(
          khataId: business.id,
          entryId: businessEntryId,
        ),
        isFalse,
      );
      expect(
        await ledger.restoreEntry(
          khataId: 'personal',
          entryId: personalEntryId,
        ),
        isTrue,
      );
      expect(
        await ledger.restoreEntry(
          khataId: 'personal',
          entryId: personalEntryId,
        ),
        isFalse,
      );
    });

    test('an edit inside a deleted khata writes nothing', () async {
      await ledger.customStatement(
        'UPDATE khatas SET deleted_at = ? WHERE id = ?',
        <Object?>[DateTime.now().toUtc().toIso8601String(), business.id],
      );
      expect(
        await ledger.updateEntry(
          khataId: business.id,
          entryId: businessEntryId,
          entry: _entry(
            kind: EntryFormKind.income,
            amountPaise: 7,
            category: 'Income',
            occurredAt: DateTime(2026, 5, 5),
          ),
        ),
        isFalse,
      );
      expect(
        await ledger.restoreEntry(
          khataId: business.id,
          entryId: businessEntryId,
        ),
        isFalse,
      );
      expect((await row(businessEntryId)).read<int>('amount_paise'), 10000);
    });

    test(
      'invalid edits throw and leave the row byte-for-byte unchanged',
      () async {
        Map<String, Object?> snapshot(QueryRow r) => <String, Object?>{
          for (final String column in <String>[
            'type',
            'amount_paise',
            'category_id',
            'description',
            'occurred_at',
            'updated_at',
            'deleted_at',
            'sync_state',
          ])
            column: r.data[column],
        };
        final Map<String, Object?> before = snapshot(
          await row(personalEntryId),
        );

        for (final EntryFormResult invalid in <EntryFormResult>[
          // Zero and negative amounts.
          _entry(
            kind: EntryFormKind.expense,
            amountPaise: 0,
            category: 'Bills',
            occurredAt: DateTime(2026, 6, 1),
          ),
          _entry(
            kind: EntryFormKind.expense,
            amountPaise: -500,
            category: 'Bills',
            occurredAt: DateTime(2026, 6, 1),
          ),
          // Blank and whitespace-only categories.
          _entry(
            kind: EntryFormKind.expense,
            amountPaise: 100,
            category: '',
            occurredAt: DateTime(2026, 6, 1),
          ),
          _entry(
            kind: EntryFormKind.expense,
            amountPaise: 100,
            category: '   ',
            occurredAt: DateTime(2026, 6, 1),
          ),
          // 121 Unicode characters (runes, not bytes).
          _entry(
            kind: EntryFormKind.expense,
            amountPaise: 100,
            category: 'Bills',
            description: List<String>.filled(121, '₹').join(),
            occurredAt: DateTime(2026, 6, 1),
          ),
        ]) {
          await expectLater(
            ledger.updateEntry(
              khataId: 'personal',
              entryId: personalEntryId,
              entry: invalid,
            ),
            throwsArgumentError,
          );
        }

        expect(snapshot(await row(personalEntryId)), before);

        // A 120-rune description with multi-byte characters is accepted.
        expect(
          await ledger.updateEntry(
            khataId: 'personal',
            entryId: personalEntryId,
            entry: _entry(
              kind: EntryFormKind.expense,
              amountPaise: 45000,
              category: 'Bills',
              description: List<String>.filled(120, '₹').join(),
              occurredAt: DateTime(2026, 2, 1),
            ),
          ),
          isTrue,
        );
      },
    );

    test('edits, deletes and restores survive close and reopen', () async {
      final Directory dir = await Directory.systemTemp.createTemp('khata_upd_');
      final File file = File('${dir.path}/ledger.sqlite');
      try {
        LocalLedger store = LocalLedger(NativeDatabase(file));
        await store.initialize();
        final LocalKhata shop = await store.createKhata(
          name: 'Shop',
          openingBalancePaise: 50000,
        );
        await store.addEntry(
          _entry(
            kind: EntryFormKind.expense,
            amountPaise: 12000,
            category: 'Shopping',
            description: 'Boxes',
            occurredAt: DateTime(2026, 7, 1),
          ),
          khataId: shop.id,
        );
        await store.addEntry(
          _entry(
            kind: EntryFormKind.income,
            amountPaise: 8000,
            category: 'Income',
            occurredAt: DateTime(2026, 7, 2),
          ),
          khataId: shop.id,
        );
        final List<LedgerEntry> entries = (await store.readSummary(
          khataId: shop.id,
        )).entries;
        final String boxesId = entries
            .firstWhere((LedgerEntry e) => e.description == 'Boxes')
            .id!;
        final String salaryId = entries
            .firstWhere((LedgerEntry e) => e.description == null)
            .id!;

        await store.updateEntry(
          khataId: shop.id,
          entryId: boxesId,
          entry: _entry(
            kind: EntryFormKind.expense,
            amountPaise: 15000,
            category: 'Shopping',
            description: 'Bigger boxes',
            occurredAt: DateTime(2026, 7, 1),
          ),
        );
        await store.softDeleteEntry(khataId: shop.id, entryId: salaryId);
        await store.close();

        store = LocalLedger(NativeDatabase(file));
        await store.initialize();
        LedgerSummary reopened = await store.readSummary(khataId: shop.id);
        expect(reopened.entries.length, 1);
        expect(reopened.entries.single.id, boxesId);
        expect(reopened.entries.single.amountPaise, 15000);
        expect(reopened.entries.single.description, 'Bigger boxes');
        expect(reopened.totalExpensePaise, 15000);
        expect(reopened.remainingPaise, 35000);

        // The tombstone persisted, so it can still be restored after a reopen.
        expect(
          await store.restoreEntry(khataId: shop.id, entryId: salaryId),
          isTrue,
        );
        reopened = await store.readSummary(khataId: shop.id);
        expect(reopened.entries.length, 2);
        expect(reopened.remainingPaise, 43000);
        expect((await store.readSummary()).entries, isEmpty);
        await store.close();
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });

  group('khata rename, archive and unarchive', () {
    Future<QueryRow> khataRow(LocalLedger ledger, String id) => ledger
        .customSelect(
          'SELECT * FROM khatas WHERE id = ?',
          variables: <Variable<Object>>[Variable<String>(id)],
        )
        .getSingle();

    Future<List<QueryRow>> entries(LocalLedger ledger, String khataId) async {
      return ledger
          .customSelect(
            'SELECT * FROM "transactions" WHERE khata_id = ? ORDER BY id ASC',
            variables: <Variable<Object>>[Variable<String>(khataId)],
          )
          .get();
    }

    Future<String?> selectedKhataId(LocalLedger ledger) async {
      final List<QueryRow> rows = await ledger
          .customSelect(
            'SELECT khata_id FROM active_khata_preference WHERE singleton = 1',
          )
          .get();
      return rows.isEmpty ? null : rows.single.read<String>('khata_id');
    }

    test(
      'rename trims the name and keeps the id, balance and entries',
      () async {
        final LocalLedger ledger = LocalLedger(NativeDatabase.memory());
        await ledger.initialize();
        final LocalKhata business = await ledger.createKhata(
          name: 'Business',
          openingBalancePaise: 250000,
        );
        await ledger.addEntry(
          _entry(
            kind: EntryFormKind.income,
            amountPaise: 120000,
            category: 'Income',
            description: 'Client payment',
            occurredAt: DateTime(2026, 5, 1),
          ),
          khataId: business.id,
        );
        final LedgerSummary before = await ledger.readSummary(
          khataId: business.id,
        );
        final QueryRow beforeRow = await khataRow(ledger, business.id);
        final String createdAt = beforeRow.read<String>('created_at');

        final LocalKhata renamed = await ledger.renameKhata(
          khataId: business.id,
          name: '  Shop Khata  ',
        );
        expect(renamed.id, business.id);
        expect(renamed.name, 'Shop Khata');
        expect(renamed.openingBalancePaise, 250000);

        final QueryRow row = await khataRow(ledger, business.id);
        expect(row.read<String>('name'), 'Shop Khata');
        expect(row.read<String>('created_at'), createdAt);
        expect(row.read<int>('opening_balance_paise'), 250000);
        expect(row.read<String>('sync_state'), 'pending');
        expect(row.readNullable<String>('deleted_at'), isNull);

        // Renaming moves no money: same entries, same opening balance.
        final LedgerSummary after = await ledger.readSummary(
          khataId: business.id,
        );
        expect(after.openingBalancePaise, 250000);
        expect(after.entries.single.id, before.entries.single.id);
        expect(after.entries.single.amountPaise, 120000);
        expect(after.remainingPaise, 370000);

        // The other khata keeps its own name.
        final List<LocalKhata> khatas = await ledger.listKhatas();
        expect(khatas.map((LocalKhata k) => k.id), <String>[
          'personal',
          business.id,
        ]);
        expect(khatas.first.name, 'Personal Khata');
        expect(khatas.last.name, 'Shop Khata');
        await ledger.close();
      },
    );

    test(
      'rename counts Unicode runes and writes nothing when invalid',
      () async {
        final LocalLedger ledger = LocalLedger(NativeDatabase.memory());
        await ledger.initialize();
        final LocalKhata shop = await ledger.createKhata(
          name: 'Shop',
          openingBalancePaise: 1000,
        );

        for (final String bad in <String>['', '   ', '\n\t']) {
          await expectLater(
            ledger.renameKhata(khataId: shop.id, name: bad),
            throwsArgumentError,
          );
        }
        final String fortyDevanagari = List<String>.filled(40, 'क').join();
        final String fortyOneDevanagari = List<String>.filled(41, 'क').join();
        expect(fortyDevanagari.runes.length, 40);
        expect(fortyOneDevanagari.runes.length, 41);
        await expectLater(
          ledger.renameKhata(khataId: shop.id, name: fortyOneDevanagari),
          throwsArgumentError,
        );

        // 40 emoji are 80 UTF-16 units but still 40 characters (runes).
        final String fortyEmoji = List<String>.filled(40, '🙂').join();
        expect(fortyEmoji.length, 80);
        expect(fortyEmoji.runes.length, 40);
        final LocalKhata renamed = await ledger.renameKhata(
          khataId: shop.id,
          name: fortyEmoji,
        );
        expect(renamed.name, fortyEmoji);
        final QueryRow emojiRow = await khataRow(ledger, shop.id);
        expect(emojiRow.read<String>('name'), fortyEmoji);

        // Surrounding whitespace is trimmed before the length check.
        final LocalKhata trimmed = await ledger.renameKhata(
          khataId: shop.id,
          name: '  $fortyDevanagari  ',
        );
        expect(trimmed.name, fortyDevanagari);
        await ledger.close();
      },
    );

    test('rename rejects unknown and archived khatas', () async {
      final LocalLedger ledger = LocalLedger(NativeDatabase.memory());
      await ledger.initialize();
      final LocalKhata temp = await ledger.createKhata(
        name: 'Temp',
        openingBalancePaise: 0,
      );
      await expectLater(
        ledger.renameKhata(khataId: 'does-not-exist', name: 'Nope'),
        throwsA(isA<KhataNotFoundException>()),
      );
      await expectLater(
        ledger.renameKhata(khataId: '  ', name: 'Nope'),
        throwsA(isA<KhataNotFoundException>()),
      );
      await ledger.archiveKhata(khataId: temp.id);
      await expectLater(
        ledger.renameKhata(khataId: temp.id, name: 'Nope'),
        throwsA(isA<KhataNotFoundException>()),
      );
      expect((await ledger.listArchivedKhatas()).single.name, 'Temp');

      // The personal khata may be renamed; only archiving it is forbidden.
      final LocalKhata personal = await ledger.renameKhata(
        khataId: 'personal',
        name: 'My Cash',
      );
      expect(personal.id, 'personal');
      expect(personal.name, 'My Cash');
      expect((await ledger.listKhatas()).first.name, 'My Cash');
      await ledger.close();
    });

    test('archive hides a populated khata but keeps every entry row', () async {
      final LocalLedger ledger = LocalLedger(NativeDatabase.memory());
      await ledger.initialize();
      final LocalKhata business = await ledger.createKhata(
        name: 'Business',
        openingBalancePaise: 250000,
      );
      await ledger.addEntry(
        _entry(
          kind: EntryFormKind.income,
          amountPaise: 300000,
          category: 'Income',
          description: 'Client payment',
          occurredAt: DateTime(2026, 6, 1),
        ),
        khataId: business.id,
      );
      await ledger.addEntry(
        _entry(
          kind: EntryFormKind.expense,
          amountPaise: 45000,
          category: 'Bills',
          description: 'Electricity',
          occurredAt: DateTime(2026, 6, 2),
        ),
        khataId: business.id,
      );
      final List<QueryRow> entriesBefore = await entries(ledger, business.id);
      expect(entriesBefore.length, 2);

      await ledger.archiveKhata(khataId: business.id);

      // Gone from the ordinary active list, present in the archive list.
      expect((await ledger.listKhatas()).map((LocalKhata k) => k.id), <String>[
        'personal',
      ]);
      final List<LocalKhata> archived = await ledger.listArchivedKhatas();
      expect(archived.single.id, business.id);
      expect(archived.single.name, 'Business');
      expect(archived.single.openingBalancePaise, 250000);

      // Inactive everywhere: reads and writes reject it, and no entry leaks
      // into the personal khata totals.
      await expectLater(
        ledger.readSummary(khataId: business.id),
        throwsA(isA<KhataNotFoundException>()),
      );
      await expectLater(
        ledger.addEntry(
          _entry(
            kind: EntryFormKind.expense,
            amountPaise: 100,
            category: 'Food',
            occurredAt: DateTime(2026, 6, 3),
          ),
          khataId: business.id,
        ),
        throwsA(isA<KhataNotFoundException>()),
      );
      expect((await ledger.readSummary()).entries, isEmpty);
      expect((await ledger.readSummary()).remainingPaise, 0);

      // Every entry row is untouched: same ids, amounts and khata ids, no
      // tombstone, no re-parenting.
      final List<QueryRow> entriesAfter = await entries(ledger, business.id);
      expect(entriesAfter.length, entriesBefore.length);
      for (int i = 0; i < entriesAfter.length; i++) {
        expect(
          entriesAfter[i].read<String>('id'),
          entriesBefore[i].read<String>('id'),
        );
        expect(
          entriesAfter[i].read<int>('amount_paise'),
          entriesBefore[i].read<int>('amount_paise'),
        );
        expect(entriesAfter[i].read<String>('khata_id'), business.id);
        expect(entriesAfter[i].readNullable<String>('deleted_at'), isNull);
      }

      // Only the khata row carries the archive marker.
      final QueryRow khata = await khataRow(ledger, business.id);
      expect(khata.readNullable<String>('deleted_at'), isNotNull);
      expect(khata.read<String>('sync_state'), 'pending');
      expect(khata.read<int>('opening_balance_paise'), 250000);
      await ledger.close();
    });

    test(
      'archive rejects the personal, unknown and already-archived khatas',
      () async {
        final LocalLedger ledger = LocalLedger(NativeDatabase.memory());
        await ledger.initialize();
        final LocalKhata temp = await ledger.createKhata(
          name: 'Temp',
          openingBalancePaise: 0,
        );

        await expectLater(
          ledger.archiveKhata(khataId: 'personal'),
          throwsA(isA<KhataPersonalArchiveException>()),
        );
        await expectLater(
          ledger.archiveKhata(khataId: 'does-not-exist'),
          throwsA(isA<KhataNotFoundException>()),
        );
        await ledger.archiveKhata(khataId: temp.id);
        await expectLater(
          ledger.archiveKhata(khataId: temp.id),
          throwsA(isA<KhataNotFoundException>()),
        );

        // The mandatory personal khata is still active and unmarked.
        final List<LocalKhata> active = await ledger.listKhatas();
        expect(active.single.id, 'personal');
        final QueryRow personalRow = await khataRow(ledger, 'personal');
        expect(personalRow.readNullable<String>('deleted_at'), isNull);
        expect(await ledger.listArchivedKhatas(), hasLength(1));
        await ledger.close();
      },
    );

    test('unarchive restores the same entries and opening balance', () async {
      final LocalLedger ledger = LocalLedger(NativeDatabase.memory());
      await ledger.initialize();
      final LocalKhata shop = await ledger.createKhata(
        name: 'Shop',
        openingBalancePaise: 50000,
      );
      await ledger.addEntry(
        _entry(
          kind: EntryFormKind.expense,
          amountPaise: 12000,
          category: 'Shopping',
          description: 'Boxes',
          occurredAt: DateTime(2026, 7, 1),
        ),
        khataId: shop.id,
      );
      final LedgerSummary before = await ledger.readSummary(khataId: shop.id);
      final String entryId = before.entries.single.id!;
      final QueryRow beforeRow = await khataRow(ledger, shop.id);
      final String createdAt = beforeRow.read<String>('created_at');

      await ledger.archiveKhata(khataId: shop.id);
      await ledger.unarchiveKhata(khataId: shop.id);

      final LedgerSummary after = await ledger.readSummary(khataId: shop.id);
      expect(after.openingBalancePaise, 50000);
      expect(after.entries.single.id, entryId);
      expect(after.entries.single.amountPaise, 12000);
      expect(after.entries.single.description, 'Boxes');
      expect(after.remainingPaise, 38000);

      final QueryRow row = await khataRow(ledger, shop.id);
      expect(row.readNullable<String>('deleted_at'), isNull);
      expect(row.read<String>('created_at'), createdAt);
      expect(row.read<String>('name'), 'Shop');
      expect(await ledger.listArchivedKhatas(), isEmpty);

      // Restoring an active or unknown khata is reported, never silent.
      await expectLater(
        ledger.unarchiveKhata(khataId: shop.id),
        throwsA(isA<KhataNotArchivedException>()),
      );
      await expectLater(
        ledger.unarchiveKhata(khataId: 'personal'),
        throwsA(isA<KhataNotArchivedException>()),
      );
      await expectLater(
        ledger.unarchiveKhata(khataId: 'does-not-exist'),
        throwsA(isA<KhataNotFoundException>()),
      );
      await ledger.close();
    });

    test(
      'archiving the selected khata falls back to personal and persists',
      () async {
        final Directory dir = await Directory.systemTemp.createTemp(
          'khata_archive_',
        );
        final File file = File('${dir.path}/ledger.sqlite');
        try {
          LocalLedger store = LocalLedger(NativeDatabase(file));
          await store.initialize();
          final LocalKhata business = await store.createKhata(
            name: 'Business',
            openingBalancePaise: 10000,
          );
          await store.addEntry(
            _entry(
              kind: EntryFormKind.income,
              amountPaise: 5000,
              category: 'Income',
              description: 'Sale',
              occurredAt: DateTime(2026, 8, 1),
            ),
            khataId: business.id,
          );
          final LedgerSummary opened = await store.readSummary(
            khataId: business.id,
          );
          final String entryId = opened.entries.single.id!;
          await store.setActiveKhataId(business.id);
          expect(await store.readActiveKhataId(), business.id);

          await store.archiveKhata(khataId: business.id);
          // The preference moved in the same transaction, so no reader sees an
          // archived khata as the active choice.
          expect(await store.readActiveKhataId(), 'personal');
          expect(await selectedKhataId(store), 'personal');
          await store.close();

          // Reopen: the archive and the fallback both persisted.
          store = LocalLedger(NativeDatabase(file));
          await store.initialize();
          expect(await store.readActiveKhataId(), 'personal');
          expect(await selectedKhataId(store), 'personal');
          expect(
            (await store.listKhatas()).map((LocalKhata k) => k.id),
            <String>['personal'],
          );
          expect(
            (await store.listArchivedKhatas()).map((LocalKhata k) => k.id),
            <String>[business.id],
          );

          // Restore after the reopen brings the entry back unchanged, and does
          // not steal the selection back.
          await store.unarchiveKhata(khataId: business.id);
          final LedgerSummary restored = await store.readSummary(
            khataId: business.id,
          );
          expect(restored.openingBalancePaise, 10000);
          expect(restored.entries.single.id, entryId);
          expect(restored.entries.single.amountPaise, 5000);
          expect(restored.remainingPaise, 15000);
          expect(await store.readActiveKhataId(), 'personal');
          await store.close();
        } finally {
          await dir.delete(recursive: true);
        }
      },
    );

    test(
      'archiving a khata that is not selected keeps the selection',
      () async {
        final LocalLedger ledger = LocalLedger(NativeDatabase.memory());
        await ledger.initialize();
        final LocalKhata business = await ledger.createKhata(
          name: 'Business',
          openingBalancePaise: 0,
        );
        expect(await ledger.readActiveKhataId(), 'personal');

        await ledger.archiveKhata(khataId: business.id);

        expect(await ledger.readActiveKhataId(), 'personal');
        expect(await selectedKhataId(ledger), 'personal');
        await ledger.close();
      },
    );

    test(
      'archiving with an unusable personal khata drops the stale selection',
      () async {
        final LocalLedger ledger = LocalLedger(NativeDatabase.memory());
        await ledger.initialize();
        final LocalKhata business = await ledger.createKhata(
          name: 'Business',
          openingBalancePaise: 0,
        );
        await ledger.setActiveKhataId(business.id);
        await ledger.customStatement(
          'UPDATE khatas SET deleted_at = ? WHERE id = ?',
          <Object?>[DateTime.now().toUtc().toIso8601String(), 'personal'],
        );

        await ledger.archiveKhata(khataId: business.id);

        // A broken personal khata is never replaced by an archived id.
        expect(await selectedKhataId(ledger), isNull);
        final List<String> archivedIds = (await ledger.listArchivedKhatas())
            .map((LocalKhata k) => k.id)
            .toList();
        expect(archivedIds, hasLength(2));
        expect(archivedIds, containsAll(<String>[business.id, 'personal']));
        await expectLater(
          ledger.readActiveKhataId(),
          throwsA(isA<KhataNotFoundException>()),
        );
        await ledger.close();
      },
    );

    test(
      'failed rename, archive and unarchive leave every khata row unchanged',
      () async {
        final LocalLedger ledger = LocalLedger(NativeDatabase.memory());
        await ledger.initialize();
        final LocalKhata business = await ledger.createKhata(
          name: 'Business',
          openingBalancePaise: 25000,
        );
        await ledger.setActiveKhataId(business.id);
        const String sql =
            'SELECT id, name, opening_balance_paise, created_at, updated_at, '
            'deleted_at, sync_state FROM khatas ORDER BY id ASC';
        final List<QueryRow> before = await ledger.customSelect(sql).get();

        await expectLater(
          ledger.renameKhata(
            khataId: business.id,
            name: List<String>.filled(41, 'a').join(),
          ),
          throwsArgumentError,
        );
        await expectLater(
          ledger.archiveKhata(khataId: 'personal'),
          throwsA(isA<KhataPersonalArchiveException>()),
        );
        await expectLater(
          ledger.unarchiveKhata(khataId: business.id),
          throwsA(isA<KhataNotArchivedException>()),
        );

        final List<QueryRow> after = await ledger.customSelect(sql).get();
        expect(after.length, before.length);
        for (int i = 0; i < after.length; i++) {
          expect(after[i].data, before[i].data);
        }
        expect(await ledger.readActiveKhataId(), business.id);
        await ledger.close();
      },
    );

    test('archived khatas travel through a backup and restore', () async {
      final LocalLedger source = LocalLedger(NativeDatabase.memory());
      await source.initialize();
      final LocalKhata business = await source.createKhata(
        name: 'Business',
        openingBalancePaise: 1000,
      );
      await source.addEntry(
        _entry(
          kind: EntryFormKind.expense,
          amountPaise: 250,
          category: 'Food',
          description: 'Tea',
          occurredAt: DateTime(2026, 9, 1),
        ),
        khataId: business.id,
      );
      await source.archiveKhata(khataId: business.id);

      // The unchanged codec already exports and validates khata tombstones.
      final String json = await LedgerBackup(source).exportJson();
      final BackupInspection inspection = LedgerBackup(source).inspect(json);
      expect(inspection.khataCount, 2);
      expect(inspection.transactionCount, 1);
      await source.close();

      final LocalLedger target = LocalLedger(NativeDatabase.memory());
      await target.initialize();
      await LedgerBackup(target).restoreReplacing(json);
      expect((await target.listKhatas()).single.id, 'personal');
      expect((await target.listArchivedKhatas()).single.id, business.id);

      await target.unarchiveKhata(khataId: business.id);
      final LedgerSummary restored = await target.readSummary(
        khataId: business.id,
      );
      expect(restored.openingBalancePaise, 1000);
      expect(restored.entries.single.amountPaise, 250);
      expect(restored.entries.single.description, 'Tea');
      expect(restored.remainingPaise, 750);
      await target.close();
    });
  });
}
