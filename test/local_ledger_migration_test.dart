// Migration tests: build a real database at an *old* schema version on disk,
// reopen it with today's LocalLedger, and prove that drift's `onUpgrade` path
// creates the newer tables while every pre-existing row survives untouched.
//
// Version history being exercised (see LocalLedger.migration):
//   v1  schema.sql only (khatas, transactions, indexes)
//   v2  + active_khata_preference
//   v3  + sync_metadata
//   v4  + pending-cursor indexes (idx_khatas_pending_cursor,
//       idx_transactions_pending_cursor)

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:khoroch_diary/features/ledger/data/local_ledger.dart';

/// A ledger frozen at an old schema version. `onCreate` writes exactly what
/// that version shipped: the schema.sql DDL, plus `active_khata_preference`
/// from v2 on. Opening a file created by this class with [LocalLedger] forces
/// the real `onUpgrade(from: version, to: 4)` to run.
class _LegacyLedger extends GeneratedDatabase {
  _LegacyLedger(super.executor, {required this.version})
    : assert(version == 1 || version == 2, 'legacy versions are 1 and 2');

  final int version;

  @override
  int get schemaVersion => version;

  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      final String sql = await rootBundle.loadString(
        'lib/features/ledger/data/schema.sql',
      );
      final String ddl = sql
          .split('\n')
          .where((String line) => !line.trimLeft().startsWith('--'))
          .join('\n');
      for (final String statement in ddl.split(';')) {
        if (statement.trim().isNotEmpty) await customStatement(statement);
      }
      if (version >= 2) {
        await customStatement(
          'CREATE TABLE IF NOT EXISTS active_khata_preference ('
          'singleton INTEGER PRIMARY KEY CHECK (singleton = 1), '
          'khata_id TEXT NOT NULL)',
        );
      }
    },
    beforeOpen: (OpeningDetails details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}

const String _t0 = '2026-01-10T09:00:00.000Z';

/// Seeds one custom khata and one expense into a legacy database using plain
/// SQL, exactly as an old build would have left them on disk.
Future<void> _seedLegacyData(_LegacyLedger db) async {
  await db.customStatement(
    'INSERT INTO khatas (id, name, opening_balance_paise, created_at, '
    "updated_at, sync_state) VALUES ('khata-legacy', 'Shop Khata', 50000, "
    "'$_t0', '$_t0', 'pending')",
  );
  await db.customStatement(
    'INSERT INTO transactions (id, khata_id, type, amount_paise, '
    'category_id, description, occurred_at, created_at, updated_at, '
    "sync_state) VALUES ('tx-legacy', 'khata-legacy', 'expense', 12345, "
    "'groceries', 'Rice and dal', '$_t0', '$_t0', '$_t0', 'pending')",
  );
}

Future<int> _userVersion(LocalLedger ledger) async {
  final List<QueryRow> rows = await ledger
      .customSelect('PRAGMA user_version')
      .get();
  return rows.single.read<int>('user_version');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('khata_migration_test_');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test('v1 database upgrades to v4 and keeps every legacy row', () async {
    final File file = File('${dir.path}/ledger.sqlite');

    final _LegacyLedger legacy = _LegacyLedger(
      NativeDatabase(file),
      version: 1,
    );
    await _seedLegacyData(legacy);
    await legacy.close();

    final LocalLedger ledger = LocalLedger(NativeDatabase(file));
    try {
      await ledger.initialize();

      // onUpgrade stamped the new version.
      expect(await _userVersion(ledger), 4);

      // The v2 table exists and works: the fallback selection resolves to the
      // default personal khata that initialize() re-confirms.
      expect(await ledger.readActiveKhataId(), 'personal');

      // The v3 table exists and starts empty.
      expect(await ledger.readSyncMetadata(), LocalSyncMetadata());

      // The v4 pending-cursor indexes exist: the v3→v4 step ran, not just
      // the version stamp.
      final List<QueryRow> indexRows = await ledger
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'index' "
            "AND name IN ('idx_khatas_pending_cursor', "
            "'idx_transactions_pending_cursor')",
          )
          .get();
      expect(
        indexRows.map((QueryRow r) => r.read<String>('name')),
        containsAll(<String>[
          'idx_khatas_pending_cursor',
          'idx_transactions_pending_cursor',
        ]),
      );

      // Legacy rows survived the upgrade byte for byte.
      final List<LocalKhata> khatas = await ledger.listKhatas();
      final LocalKhata shop = khatas.singleWhere(
        (LocalKhata k) => k.id == 'khata-legacy',
      );
      expect(shop.name, 'Shop Khata');
      expect(shop.openingBalancePaise, 50000);

      final List<QueryRow> txRows = await ledger
          .customSelect(
            'SELECT amount_paise, description FROM transactions '
            "WHERE id = 'tx-legacy' AND deleted_at IS NULL",
          )
          .get();
      expect(txRows, hasLength(1));
      expect(txRows.single.read<int>('amount_paise'), 12345);
      expect(txRows.single.read<String>('description'), 'Rice and dal');
    } finally {
      await ledger.close();
    }
  });

  test(
    'v2 database upgrades to v4 and keeps the active-khata choice',
    () async {
      final File file = File('${dir.path}/ledger.sqlite');

      final _LegacyLedger legacy = _LegacyLedger(
        NativeDatabase(file),
        version: 2,
      );
      await _seedLegacyData(legacy);
      await legacy.customStatement(
        'INSERT INTO active_khata_preference (singleton, khata_id) '
        "VALUES (1, 'khata-legacy')",
      );
      await legacy.close();

      final LocalLedger ledger = LocalLedger(NativeDatabase(file));
      try {
        await ledger.initialize();

        expect(await _userVersion(ledger), 4);

        // The stored selection survived: no reset to 'personal'.
        expect(await ledger.readActiveKhataId(), 'khata-legacy');

        // sync_metadata was created by the v2→v3 step and persists writes.
        expect(await ledger.readSyncMetadata(), LocalSyncMetadata());
        await ledger.writeSyncMetadata(lastError: 'probe');
        expect((await ledger.readSyncMetadata()).lastError, 'probe');
      } finally {
        await ledger.close();
      }
    },
  );

  test('an already-migrated database reopens without data loss', () async {
    final File file = File('${dir.path}/ledger.sqlite');

    final _LegacyLedger legacy = _LegacyLedger(
      NativeDatabase(file),
      version: 1,
    );
    await _seedLegacyData(legacy);
    await legacy.close();

    LocalLedger ledger = LocalLedger(NativeDatabase(file));
    await ledger.initialize();
    await ledger.writeSyncMetadata(lastError: 'first-open error');
    await ledger.close();

    // Second open: no onUpgrade runs (versions match); state is untouched.
    ledger = LocalLedger(NativeDatabase(file));
    try {
      await ledger.initialize();
      expect(await _userVersion(ledger), 4);
      expect((await ledger.readSyncMetadata()).lastError, 'first-open error');
      expect(
        (await ledger.listKhatas()).map((LocalKhata k) => k.id),
        containsAll(<String>['personal', 'khata-legacy']),
      );
    } finally {
      await ledger.close();
    }
  });
}
