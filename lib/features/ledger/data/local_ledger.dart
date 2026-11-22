import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../entry/add_entry_screen.dart';
import '../../home/models.dart';
import '../../sync/cloud_backend.dart';

/// A local khata (one ledger) as stored in the existing `khatas` table.
///
/// This is an immutable value: it is a snapshot, not a live handle, so callers
/// cannot accidentally write through it and so it is safe to compare in tests.
/// Money is always integer paise.
final class LocalKhata {
  const LocalKhata({
    required this.id,
    required this.name,
    required this.openingBalancePaise,
  });

  final String id;
  final String name;
  final int openingBalancePaise;

  @override
  bool operator ==(Object other) =>
      other is LocalKhata &&
      other.id == id &&
      other.name == name &&
      other.openingBalancePaise == openingBalancePaise;

  @override
  int get hashCode => Object.hash(id, name, openingBalancePaise);

  @override
  String toString() =>
      'LocalKhata(id: $id, name: $name, '
      'openingBalancePaise: $openingBalancePaise)';
}

/// Thrown when a caller names a khata that does not exist (or was tombstoned).
///
/// Reads and writes reject an unknown id instead of falling back to the
/// personal khata, so a bug can never silently file an entry under the wrong
/// ledger.
class KhataNotFoundException implements Exception {
  const KhataNotFoundException(this.khataId);

  final String khataId;

  @override
  String toString() => 'KhataNotFoundException: no active khata $khataId';
}

/// Thrown when a caller tries to archive the personal khata.
///
/// The personal khata is the one the app opens on and the one every backup
/// file must carry active, so it is a mandatory ledger and can never be
/// archived. Archiving any other khata stays reversible through
/// [LocalLedger.unarchiveKhata].
class KhataPersonalArchiveException implements Exception {
  const KhataPersonalArchiveException(this.khataId);

  final String khataId;

  @override
  String toString() =>
      'KhataPersonalArchiveException: khata $khataId is the personal khata '
      'and cannot be archived';
}

/// Thrown when [LocalLedger.unarchiveKhata] names a khata that is not archived.
///
/// Restoring an already-active khata is a no-op request that did not happen, so
/// it is reported instead of being silently accepted; an unknown id is
/// [KhataNotFoundException] rather than this.
class KhataNotArchivedException implements Exception {
  const KhataNotArchivedException(this.khataId);

  final String khataId;

  @override
  String toString() =>
      'KhataNotArchivedException: khata $khataId is not archived';
}

/// Persisted cloud-sync metadata stored on this device.
///
/// Kept in the singleton `sync_metadata` table so cursor progress, the last
/// successful sync timestamp, the most recent sync failure reason and the
/// account id this device last synced with survive app restarts.
final class LocalSyncMetadata {
  LocalSyncMetadata({
    DateTime? cursor,
    DateTime? lastSyncedAt,
    this.lastError,
    this.lastSyncedAccountId,
  }) : cursor = cursor?.toUtc(),
       lastSyncedAt = lastSyncedAt?.toUtc();

  final DateTime? cursor;
  final DateTime? lastSyncedAt;
  final String? lastError;
  final String? lastSyncedAccountId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocalSyncMetadata &&
          other.cursor == cursor &&
          other.lastSyncedAt == lastSyncedAt &&
          other.lastError == lastError &&
          other.lastSyncedAccountId == lastSyncedAccountId;

  @override
  int get hashCode =>
      Object.hash(cursor, lastSyncedAt, lastError, lastSyncedAccountId);

  @override
  String toString() =>
      'LocalSyncMetadata(cursor: $cursor, lastSyncedAt: $lastSyncedAt, '
      'lastError: $lastError, lastSyncedAccountId: $lastSyncedAccountId)';
}

/// A single local database. The SQL schema is also exercised independently
/// by tests/test_ledger_schema.py.
class LocalLedger extends GeneratedDatabase {
  LocalLedger(super.executor);

  // The on-disk name predates the Khoroch Diary rename. It stays 'khatabook'
  // so an app update opens the ledger already on the device instead of an
  // empty one.
  factory LocalLedger.device() => LocalLedger(driftDatabase(name: 'khatabook'));

  static const String _defaultKhata = 'personal';
  static const Uuid _uuid = Uuid();

  /// Khata names are trimmed and must be 1…40 characters
  /// (docs/spec/data-model.md, validation rules).
  static const int _maxKhataNameLength = 40;

  /// Nine integer digits of rupees in paise: the largest opening balance the
  /// amount rule allows (₹99,99,99,999.99). SQLite would store more, but the
  /// spec does not, and an out-of-range value would break totals later.
  static const int _maxOpeningBalancePaise = 99999999999;

  /// Monotonically increasing UTC timestamp helper so rapid local mutations
  /// within the same millisecond still strictly advance `updated_at`.
  DateTime? _lastWriteInstantUtc;

  String _nextUtcIso8601() {
    DateTime candidate = DateTime.now().toUtc();
    final DateTime? previous = _lastWriteInstantUtc;
    if (previous != null && !candidate.isAfter(previous)) {
      candidate = previous.add(const Duration(microseconds: 1));
    }
    _lastWriteInstantUtc = candidate;
    return candidate.toIso8601String();
  }

  @override
  int get schemaVersion => 4;

  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      final String sql = await rootBundle.loadString(
        'lib/features/ledger/data/schema.sql',
      );
      // Schema comments can contain semicolons; strip them before splitting.
      final String ddl = sql
          .split('\n')
          .where((String line) => !line.trimLeft().startsWith('--'))
          .join('\n');
      for (final String statement in ddl.split(';')) {
        if (statement.trim().isNotEmpty) await customStatement(statement);
      }
      await _createActiveKhataPreferenceTable();
      await _createSyncMetadataTable();
      await _createPendingCursorIndexes();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2) await _createActiveKhataPreferenceTable();
      if (from < 3) await _createSyncMetadataTable();
      if (from < 4) await _createPendingCursorIndexes();
    },
    beforeOpen: (OpeningDetails details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Future<void> _createPendingCursorIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_khatas_pending_cursor '
      'ON khatas (sync_state, id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_transactions_pending_cursor '
      'ON "transactions" (sync_state, id)',
    );
  }

  Future<void> _createActiveKhataPreferenceTable() async {
    await customStatement(
      'CREATE TABLE IF NOT EXISTS active_khata_preference ('
      'singleton INTEGER PRIMARY KEY CHECK (singleton = 1), '
      'khata_id TEXT NOT NULL)',
    );
  }

  Future<void> _createSyncMetadataTable() async {
    await customStatement(
      'CREATE TABLE IF NOT EXISTS sync_metadata ('
      'singleton INTEGER PRIMARY KEY CHECK (singleton = 1), '
      'cursor TEXT, '
      'last_synced_at TEXT, '
      'last_error TEXT, '
      'last_synced_account_id TEXT)',
    );
  }

  /// Returns the last selected active khata, or the active personal khata when
  /// no usable selection has been stored. A stale selection is replaced only
  /// after confirming that personal still exists; no khata row is recreated.
  Future<String> readActiveKhataId() async {
    return transaction<String>(() async {
      final List<QueryRow> rows = await customSelect(
        'SELECT khata_id FROM active_khata_preference WHERE singleton = 1',
      ).get();
      if (rows.isNotEmpty) {
        final String storedId = rows.single.read<String>('khata_id');
        if (await _findActiveKhata(storedId) != null) return storedId;
      }

      if (await _findActiveKhata(_defaultKhata) == null) {
        throw const KhataNotFoundException(_defaultKhata);
      }
      await _writeActiveKhataId(_defaultKhata);
      return _defaultKhata;
    });
  }

  /// Stores a selection only when it names an existing, non-tombstoned khata.
  /// Validation and persistence share a transaction so a rejected selection
  /// never changes the saved choice.
  Future<void> setActiveKhataId(String id) async {
    await transaction(() async {
      if (await _findActiveKhata(id) == null) throw KhataNotFoundException(id);
      await _writeActiveKhataId(id);
    });
  }

  Future<void> _writeActiveKhataId(String id) async {
    await customStatement(
      'INSERT INTO active_khata_preference (singleton, khata_id) VALUES (1, ?) '
      'ON CONFLICT(singleton) DO UPDATE SET khata_id = excluded.khata_id',
      <Object>[id],
    );
  }

  /// Creates a zero-balance local khata once, never replacing existing data.
  ///
  /// Idempotent: running it against a populated database only re-confirms the
  /// default row, so the personal khata stays empty/zero on a fresh install and
  /// keeps every existing entry on later launches.
  Future<void> initialize() async {
    final String now = _nextUtcIso8601();
    await customStatement(
      'INSERT OR IGNORE INTO khatas (id, name, opening_balance_paise, '
      "created_at, updated_at, sync_state) VALUES (?, ?, ?, ?, ?, 'pending')",
      <Object>[_defaultKhata, 'Personal Khata', 0, now, now],
    );
  }

  /// Active (non-archived) khatas in a stable order: the default personal
  /// khata first, then `sort_order`, then creation time and id.
  ///
  /// Archived khatas are excluded because archiving sets the khata's
  /// `deleted_at`; [listArchivedKhatas] is the only way to see them again.
  Future<List<LocalKhata>> listKhatas() async {
    final List<QueryRow> rows = await customSelect(
      'SELECT id, name, opening_balance_paise FROM khatas '
      'WHERE deleted_at IS NULL '
      'ORDER BY CASE WHEN id = ? THEN 0 ELSE 1 END, sort_order ASC, '
      'created_at ASC, id ASC',
      variables: <Variable<Object>>[Variable<String>(_defaultKhata)],
    ).get();
    return List<LocalKhata>.unmodifiable(rows.map(_khataFromRow));
  }

  /// Archived (soft-deleted) khatas, oldest archive first, then by id.
  ///
  /// This is the mirror of [listKhatas]: the same [LocalKhata] shape, so a
  /// restore screen only needs the id. An archived khata keeps its entries,
  /// amounts and opening balance while it is listed here; nothing about its
  /// data is hidden, only the khata's own `deleted_at` marks it archived.
  Future<List<LocalKhata>> listArchivedKhatas() async {
    final List<QueryRow> rows = await customSelect(
      'SELECT id, name, opening_balance_paise FROM khatas '
      'WHERE deleted_at IS NOT NULL '
      'ORDER BY deleted_at ASC, id ASC',
    ).get();
    return List<LocalKhata>.unmodifiable(rows.map(_khataFromRow));
  }

  /// Maps one `khatas` row to the immutable value callers compare in tests.
  static LocalKhata _khataFromRow(QueryRow row) => LocalKhata(
    id: row.read<String>('id'),
    name: row.read<String>('name'),
    openingBalancePaise: row.read<int>('opening_balance_paise'),
  );

  /// Creates one UUID-backed khata in the existing schema.
  ///
  /// [name] is trimmed before validation and storage; blank or
  /// longer-than-40-rune names are rejected, as are negative or out-of-range
  /// [openingBalancePaise] values. Nothing is written on error. The name rule
  /// is shared with [renameKhata].
  Future<LocalKhata> createKhata({
    required String name,
    required int openingBalancePaise,
  }) async {
    final String trimmedName = _validateKhataName(name);
    if (openingBalancePaise < 0 ||
        openingBalancePaise > _maxOpeningBalancePaise) {
      throw ArgumentError.value(
        openingBalancePaise,
        'openingBalancePaise',
        'Opening balance must be between 0 and $_maxOpeningBalancePaise paise',
      );
    }
    final String id = _uuid.v4();
    final String now = _nextUtcIso8601();
    await customStatement(
      'INSERT INTO khatas (id, name, opening_balance_paise, created_at, '
      "updated_at, sync_state) VALUES (?, ?, ?, ?, ?, 'pending')",
      <Object>[id, trimmedName, openingBalancePaise, now, now],
    );
    return LocalKhata(
      id: id,
      name: trimmedName,
      openingBalancePaise: openingBalancePaise,
    );
  }

  /// Renames one active khata and returns its new value.
  ///
  /// The name rule is exactly the one [createKhata] uses: the string is
  /// trimmed, then must be 1…40 Unicode runes, so emoji and Indic scripts
  /// count as characters, not UTF-16 units. An invalid name throws
  /// [ArgumentError] and writes nothing.
  ///
  /// Only `name`, `updated_at` and `sync_state` (back to `'pending'`, so the
  /// change is pushed later) are touched: `id`, `opening_balance_paise`,
  /// `created_at`, `sort_order` and every `"transactions"` row stay exactly as
  /// they were, so totals cannot move just because a ledger was renamed.
  ///
  /// An unknown or already-archived [khataId] throws [KhataNotFoundException].
  /// There is no silent success and no fallback to the personal khata, so a
  /// stale UI cannot rename the wrong ledger. The existence check and the
  /// update share one transaction, so a rename cannot land on a khata that was
  /// archived in between. The personal khata may be renamed - only archiving
  /// it is forbidden.
  Future<LocalKhata> renameKhata({
    required String khataId,
    required String name,
  }) async {
    final String trimmedName = _validateKhataName(name);
    final String now = _nextUtcIso8601();
    return transaction<LocalKhata>(() async {
      final LocalKhata? khata = await _findActiveKhata(khataId);
      if (khata == null) throw KhataNotFoundException(khataId);
      final int changed = await customUpdate(
        'UPDATE khatas SET name = ?, updated_at = ?, '
        "sync_state = 'pending' WHERE id = ? AND deleted_at IS NULL",
        variables: <Variable<Object>>[
          Variable<String>(trimmedName),
          Variable<String>(now),
          Variable<String>(khataId),
        ],
      );
      if (changed != 1) throw KhataNotFoundException(khataId);
      return LocalKhata(
        id: khata.id,
        name: trimmedName,
        openingBalancePaise: khata.openingBalancePaise,
      );
    });
  }

  /// Soft-archives one khata: sets its `deleted_at`, and nothing else.
  ///
  /// Archive is a reversible marker on the **khata row only**. No
  /// `"transactions"` row is deleted, updated, re-parented or re-summed, so
  /// every entry, its amount, its category and the khata's opening balance stay
  /// attached to the same `id` and come back untouched from [unarchiveKhata].
  /// While archived, the khata is excluded from [listKhatas] (the ordinary
  /// active list) and [readSummary] / [addEntry] reject it as inactive, so its
  /// entries are outside every active list and wallet total instead of being
  /// mixed into another ledger.
  ///
  /// The personal khata can never be archived: it throws
  /// [KhataPersonalArchiveException]. It is the mandatory fallback selection
  /// and the khata every backup file must carry active.
  ///
  /// If the archived khata is the persisted active selection, the same
  /// transaction re-points `active_khata_preference` at the personal khata, so
  /// no reader can observe an archived khata as the active choice. If the
  /// personal khata itself is unusable the stale preference row is removed
  /// instead of being left pointing at an archived id; [readActiveKhataId] then
  /// reports the broken personal khata rather than returning the archived one.
  ///
  /// Throws [KhataNotFoundException] for an unknown or already-archived id.
  /// `updated_at` is bumped and `sync_state` returns to `'pending'`.
  Future<void> archiveKhata({required String khataId}) async {
    if (khataId == _defaultKhata) {
      throw const KhataPersonalArchiveException(_defaultKhata);
    }
    final String now = _nextUtcIso8601();
    await transaction(() async {
      if (await _findActiveKhata(khataId) == null) {
        throw KhataNotFoundException(khataId);
      }
      final int changed = await customUpdate(
        'UPDATE khatas SET deleted_at = ?, updated_at = ?, '
        "sync_state = 'pending' WHERE id = ? AND deleted_at IS NULL",
        variables: <Variable<Object>>[
          Variable<String>(now),
          Variable<String>(now),
          Variable<String>(khataId),
        ],
      );
      if (changed != 1) throw KhataNotFoundException(khataId);

      final List<QueryRow> selected = await customSelect(
        'SELECT khata_id FROM active_khata_preference WHERE singleton = 1',
      ).get();
      final bool wasSelected =
          selected.isNotEmpty &&
          selected.single.read<String>('khata_id') == khataId;
      if (wasSelected) {
        if (await _findActiveKhata(_defaultKhata) != null) {
          await _writeActiveKhataId(_defaultKhata);
        } else {
          await customStatement(
            'DELETE FROM active_khata_preference WHERE singleton = 1',
          );
        }
      }
    });
  }

  /// Reverses [archiveKhata]: clears `deleted_at` on the archived khata.
  ///
  /// Restore preserves the khata's original `id`, `name`, opening balance,
  /// creation time and every entry (including entry ids, amounts and
  /// soft-delete tombstones), because archiving never changed them.
  /// `updated_at` is bumped and `sync_state` returns to `'pending'`.
  ///
  /// Restoring does **not** re-select the khata: the active selection stays
  /// whatever it is now (normally the personal khata the archive switched to),
  /// so a reopen never lands the user somewhere they did not choose. Throws
  /// [KhataNotFoundException] for an unknown id and [KhataNotArchivedException]
  /// for a khata that is already active; nothing is written in either case.
  Future<void> unarchiveKhata({required String khataId}) async {
    final String now = _nextUtcIso8601();
    await transaction(() async {
      final List<QueryRow> archived = await customSelect(
        'SELECT id FROM khatas WHERE id = ? AND deleted_at IS NOT NULL',
        variables: <Variable<Object>>[Variable<String>(khataId)],
      ).get();
      if (archived.isEmpty) {
        // Distinguish a wrong id from a redundant request; both are rejected.
        if (await _findActiveKhata(khataId) != null) {
          throw KhataNotArchivedException(khataId);
        }
        throw KhataNotFoundException(khataId);
      }
      final int changed = await customUpdate(
        'UPDATE khatas SET deleted_at = NULL, updated_at = ?, '
        "sync_state = 'pending' WHERE id = ? AND deleted_at IS NOT NULL",
        variables: <Variable<Object>>[
          Variable<String>(now),
          Variable<String>(khataId),
        ],
      );
      if (changed != 1) throw KhataNotFoundException(khataId);
    });
  }

  /// The khata-name rule shared by [createKhata] and [renameKhata]: trimmed,
  /// then 1…40 Unicode runes. Returns the trimmed name; throws
  /// [ArgumentError] without writing anything.
  String _validateKhataName(String name) {
    final String trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Khata name must not be blank');
    }
    if (trimmedName.runes.length > _maxKhataNameLength) {
      throw ArgumentError.value(
        name,
        'name',
        'Khata name must be at most $_maxKhataNameLength characters',
      );
    }
    return trimmedName;
  }

  /// Reads the opening balance and every non-deleted entry of exactly one
  /// active khata. Totals are never mixed across khatas, and an archived khata
  /// reads as inactive ([KhataNotFoundException]) instead of contributing its
  /// entries anywhere.
  Future<LedgerSummary> readSummary({String khataId = 'personal'}) async {
    final LocalKhata? khata = await _findActiveKhata(khataId);
    if (khata == null) throw KhataNotFoundException(khataId);
    final List<QueryRow> rows = await customSelect(
      'SELECT id, type, amount_paise, category_id, description, occurred_at FROM "transactions" WHERE khata_id = ? AND deleted_at IS NULL ORDER BY occurred_at DESC, id ASC',
      variables: <Variable<Object>>[Variable<String>(khataId)],
    ).get();
    return LedgerSummary(
      openingBalancePaise: khata.openingBalancePaise,
      entries: rows
          .map((QueryRow row) {
            final String category = row.read<String>('category_id');
            // Kept exactly as stored; the category is only a display fallback
            // for `title`, never written back as data.
            final String? description = row.readNullable<String>('description');
            return LedgerEntry(
              id: row.read<String>('id'),
              title: description == null || description.trim().isEmpty
                  ? category
                  : description,
              description: description,
              category: category,
              at: DateTime.parse(row.read<String>('occurred_at')).toLocal(),
              amountPaise: row.read<int>('amount_paise'),
              type: row.read<String>('type') == 'income'
                  ? EntryType.income
                  : EntryType.expense,
            );
          })
          .toList(growable: false),
    );
  }

  /// Appends one entry to the named khata.
  ///
  /// The khata must exist and be active; a missing id throws
  /// [KhataNotFoundException] instead of writing to another ledger.
  Future<void> addEntry(
    EntryFormResult entry, {
    String khataId = 'personal',
  }) async {
    final String description = _validateEntry(entry);
    final String now = _nextUtcIso8601();
    // One transaction so the existence check and the insert cannot be
    // interleaved with a tombstone written elsewhere.
    await transaction(() async {
      if (await _findActiveKhata(khataId) == null) {
        throw KhataNotFoundException(khataId);
      }
      await customStatement(
        'INSERT INTO "transactions" (id, khata_id, type, amount_paise, '
        'category_id, description, occurred_at, created_at, updated_at, '
        'sync_state) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        <Object?>[
          _uuid.v4(),
          khataId,
          entry.kind.name,
          entry.amountPaise,
          entry.category,
          description.isEmpty ? null : description,
          entry.occurredAt.toUtc().toIso8601String(),
          now,
          now,
          'pending',
        ],
      );
    });
  }

  /// Edits one active entry inside one active khata.
  ///
  /// Only the editable columns change - type, amount, category, description and
  /// `occurred_at`; `id` and `created_at` are preserved. Returns `false` (and
  /// writes nothing) when the khata is unknown/tombstoned, the entry is
  /// missing, belongs to another khata, or is already soft-deleted. Invalid
  /// values throw [ArgumentError] without touching the row, using the same
  /// rules as [addEntry]. Never falls back to the personal khata.
  Future<bool> updateEntry({
    required String khataId,
    required String entryId,
    required EntryFormResult entry,
  }) async {
    final String description = _validateEntry(entry);
    final bool hasDescription = description.isNotEmpty;
    // `description` is bound as a real NULL when it is empty, never as the
    // category text: only the placeholder (or the literal NULL) goes into the
    // SQL, and every actual value stays a bound parameter.
    final String setDescription = hasDescription ? '?' : 'NULL';
    final List<Variable<Object>> fields = <Variable<Object>>[
      Variable<String>(entry.kind.name),
      Variable<int>(entry.amountPaise),
      Variable<String>(entry.category),
      if (hasDescription) Variable<String>(description),
      Variable<String>(entry.occurredAt.toUtc().toIso8601String()),
    ];
    return _mutateActiveEntry(khataId, (String now) {
      return customUpdate(
        'UPDATE "transactions" SET type = ?, amount_paise = ?, '
        'category_id = ?, description = $setDescription, occurred_at = ?, '
        "updated_at = ?, sync_state = 'pending' WHERE id = ? AND khata_id = ? "
        'AND deleted_at IS NULL',
        variables: <Variable<Object>>[
          ...fields,
          Variable<String>(now),
          Variable<String>(entryId),
          Variable<String>(khataId),
        ],
      );
    });
  }

  /// Soft-deletes one active entry inside one active khata by setting
  /// `deleted_at`; the row is never destroyed. Returns `false` and writes
  /// nothing for an unknown khata, a missing/wrong-khata entry or an entry that
  /// is already deleted.
  Future<bool> softDeleteEntry({
    required String khataId,
    required String entryId,
  }) async {
    return _mutateActiveEntry(
      khataId,
      (String now) => customUpdate(
        'UPDATE "transactions" SET deleted_at = ?, updated_at = ?, '
        "sync_state = 'pending' WHERE id = ? AND khata_id = ? "
        'AND deleted_at IS NULL',
        variables: <Variable<Object>>[
          Variable<String>(now),
          Variable<String>(now),
          Variable<String>(entryId),
          Variable<String>(khataId),
        ],
      ),
    );
  }

  /// Clears `deleted_at` on one soft-deleted entry inside one active khata.
  /// Returns `false` and writes nothing when the entry is missing, belongs to
  /// another khata, or is already active.
  Future<bool> restoreEntry({
    required String khataId,
    required String entryId,
  }) async {
    return _mutateActiveEntry(
      khataId,
      (String now) => customUpdate(
        'UPDATE "transactions" SET deleted_at = NULL, updated_at = ?, '
        "sync_state = 'pending' WHERE id = ? AND khata_id = ? "
        'AND deleted_at IS NOT NULL',
        variables: <Variable<Object>>[
          Variable<String>(now),
          Variable<String>(entryId),
          Variable<String>(khataId),
        ],
      ),
    );
  }

  /// Runs one conditional [statement] against the single matching row, inside a
  /// transaction that first proves the khata is active.
  ///
  /// The statement itself carries `khata_id` and the deleted/active condition,
  /// so a row in another khata or in the wrong state can never be touched: the
  /// update simply matches nothing and this returns `false`.
  Future<bool> _mutateActiveEntry(
    String khataId,
    Future<int> Function(String nowUtc) statement,
  ) async {
    final String now = _nextUtcIso8601();
    return transaction(() async {
      // A tombstoned or unknown khata is inactive: report false and never let a
      // restore resurrect an entry inside a deleted khata.
      if (await _findActiveKhata(khataId) == null) return false;
      final int changed = await statement(now);
      return changed == 1;
    });
  }

  /// The add/edit rules shared by [addEntry], [updateEntry] and the form:
  /// positive integer-paise amount, non-blank category and a trimmed
  /// description of at most 120 Unicode characters. Returns the trimmed
  /// description; throws [ArgumentError] without writing anything.
  String _validateEntry(EntryFormResult entry) {
    if (entry.amountPaise <= 0) {
      throw ArgumentError('Invalid transaction amount');
    }
    if (entry.category.trim().isEmpty) {
      throw ArgumentError('Category must not be blank');
    }
    final String description = entry.description.trim();
    if (description.runes.length > 120) {
      throw ArgumentError('Description too long');
    }
    return description;
  }

  /// The active khata matching [khataId], or `null` when the id is blank,
  /// unknown or archived — all of which callers must reject.
  ///
  /// Every read and write path above goes through here, so archived khatas
  /// inherit the same rule everywhere: their entries are unreachable until
  /// [unarchiveKhata] clears `deleted_at` again.
  Future<LocalKhata?> _findActiveKhata(String khataId) async {
    if (khataId.trim().isEmpty) return null;
    final List<QueryRow> rows = await customSelect(
      'SELECT id, name, opening_balance_paise FROM khatas '
      'WHERE id = ? AND deleted_at IS NULL',
      variables: <Variable<Object>>[Variable<String>(khataId)],
    ).get();
    return rows.isEmpty ? null : _khataFromRow(rows.single);
  }

  // ---------------------------------------------------------------------------
  // Cloud sync support (B5)
  // ---------------------------------------------------------------------------

  /// Total number of khata and transaction rows waiting to be pushed
  /// (`sync_state = 'pending'`).
  Future<int> readPendingSyncCount() async {
    final QueryRow row = await customSelect(
      'SELECT '
      "  (SELECT COUNT(*) FROM khatas WHERE sync_state = 'pending') + "
      "  (SELECT COUNT(*) FROM \"transactions\" WHERE sync_state = 'pending') "
      'AS pending_count',
    ).getSingle();
    return row.read<int>('pending_count');
  }

  /// Reads pending khata rows (`sync_state = 'pending'`) in deterministic order
  /// so they can be pushed before dependent transactions.
  Future<List<CloudKhataRow>> readPendingKhatas({
    int? limit,
    String? afterId,
  }) async {
    final String limitClause = limit == null ? '' : ' LIMIT ?';
    final List<QueryRow> rows = await customSelect(
      'SELECT id, name, opening_balance_paise, currency, sort_order, '
      'created_at, updated_at, deleted_at FROM khatas '
      "WHERE sync_state = 'pending' "
      '${afterId == null ? '' : 'AND id > ? '}'
      'ORDER BY id ASC$limitClause',
      variables: <Variable<Object>>[
        if (afterId != null) Variable<String>(afterId),
        if (limit != null) Variable<int>(limit),
      ],
    ).get();
    return List<CloudKhataRow>.unmodifiable(rows.map(_cloudKhataFromRow));
  }

  /// Reads pending transaction rows (`sync_state = 'pending'`) in deterministic
  /// order.
  Future<List<CloudTransactionRow>> readPendingTransactions({
    int? limit,
    String? afterId,
  }) async {
    final String limitClause = limit == null ? '' : ' LIMIT ?';
    final List<QueryRow> rows = await customSelect(
      'SELECT id, khata_id, type, amount_paise, category_id, description, '
      'occurred_at, note_session_id, created_at, updated_at, deleted_at '
      'FROM "transactions" '
      "WHERE sync_state = 'pending' "
      '${afterId == null ? '' : 'AND id > ? '}'
      'ORDER BY id ASC$limitClause',
      variables: <Variable<Object>>[
        if (afterId != null) Variable<String>(afterId),
        if (limit != null) Variable<int>(limit),
      ],
    ).get();
    return List<CloudTransactionRow>.unmodifiable(
      rows.map(_cloudTransactionFromRow),
    );
  }

  /// Marks each khata in [pushed] as `synced` **only** if its local
  /// `updated_at` has not changed since it was read for push. Returns how many
  /// rows transitioned to `synced`.
  Future<int> markKhatasSyncedIfUnchanged(
    Iterable<CloudKhataRow> pushed,
  ) async {
    return transaction<int>(() async {
      int marked = 0;
      for (final CloudKhataRow row in pushed) {
        final String expectedUpdatedAt = row.updatedAt
            .toUtc()
            .toIso8601String();
        final List<QueryRow> existing = await customSelect(
          'SELECT updated_at, sync_state FROM khatas WHERE id = ?',
          variables: <Variable<Object>>[Variable<String>(row.id)],
        ).get();
        if (existing.isEmpty) continue;
        final DateTime currentUpdatedAt = DateTime.parse(
          existing.single.read<String>('updated_at'),
        ).toUtc();
        if (!currentUpdatedAt.isAtSameMomentAs(row.updatedAt)) continue;
        final int changed = await customUpdate(
          "UPDATE khatas SET sync_state = 'synced' "
          "WHERE id = ? AND updated_at = ? AND sync_state = 'pending'",
          variables: <Variable<Object>>[
            Variable<String>(row.id),
            Variable<String>(expectedUpdatedAt),
          ],
        );
        if (changed == 0 &&
            existing.single.read<String>('sync_state') == 'pending') {
          // Handle equivalent UTC formatting differences (e.g. `.000Z` vs `Z`)
          // when the instant itself is identical.
          marked += await customUpdate(
            "UPDATE khatas SET sync_state = 'synced' "
            "WHERE id = ? AND updated_at = ? AND sync_state = 'pending'",
            variables: <Variable<Object>>[
              Variable<String>(row.id),
              Variable<String>(existing.single.read<String>('updated_at')),
            ],
          );
        } else {
          marked += changed;
        }
      }
      return marked;
    });
  }

  /// Marks each transaction in [pushed] as `synced` **only** if its local
  /// `updated_at` has not changed since it was read for push. Returns how many
  /// rows transitioned to `synced`.
  Future<int> markTransactionsSyncedIfUnchanged(
    Iterable<CloudTransactionRow> pushed,
  ) async {
    return transaction<int>(() async {
      int marked = 0;
      for (final CloudTransactionRow row in pushed) {
        final String expectedUpdatedAt = row.updatedAt
            .toUtc()
            .toIso8601String();
        final List<QueryRow> existing = await customSelect(
          'SELECT updated_at, sync_state FROM "transactions" WHERE id = ?',
          variables: <Variable<Object>>[Variable<String>(row.id)],
        ).get();
        if (existing.isEmpty) continue;
        final DateTime currentUpdatedAt = DateTime.parse(
          existing.single.read<String>('updated_at'),
        ).toUtc();
        if (!currentUpdatedAt.isAtSameMomentAs(row.updatedAt)) continue;
        final int changed = await customUpdate(
          "UPDATE \"transactions\" SET sync_state = 'synced' "
          "WHERE id = ? AND updated_at = ? AND sync_state = 'pending'",
          variables: <Variable<Object>>[
            Variable<String>(row.id),
            Variable<String>(expectedUpdatedAt),
          ],
        );
        if (changed == 0 &&
            existing.single.read<String>('sync_state') == 'pending') {
          marked += await customUpdate(
            "UPDATE \"transactions\" SET sync_state = 'synced' "
            "WHERE id = ? AND updated_at = ? AND sync_state = 'pending'",
            variables: <Variable<Object>>[
              Variable<String>(row.id),
              Variable<String>(existing.single.read<String>('updated_at')),
            ],
          );
        } else {
          marked += changed;
        }
      }
      return marked;
    });
  }

  /// Applies remote khata rows in a single transaction using the B5 conflict
  /// rules:
  /// * Unknown `id` -> inserted with `sync_state = 'synced'`.
  /// * Remote `updated_at` newer than local -> applied with
  ///   `sync_state = 'synced'` (never hard-deleting; archives set or clear
  ///   `deleted_at`, except the mandatory `personal` khata is kept active if
  ///   a corrupt remote tombstone ever arrives).
  /// * Local row is newer (including a newer `pending` local edit) -> kept
  ///   untouched.
  /// * Equal `updated_at` tie -> a tombstone wins (`deleted_at != null` beats
  ///   `deleted_at == null`); if local is `pending` and has identical content
  ///   to the remote row, it transitions to `synced`.
  Future<int> applyRemoteKhatas(Iterable<CloudKhataRow> remoteRows) async {
    return transaction<int>(() async {
      int applied = 0;
      for (final CloudKhataRow incoming in remoteRows) {
        final DateTime? incomingDeletedAt = incoming.id == _defaultKhata
            ? null
            : incoming.deletedAt;
        final CloudKhataRow normalized = incoming.copyWith(
          deletedAt: incomingDeletedAt,
        );
        final List<QueryRow> existingRows = await customSelect(
          'SELECT id, name, opening_balance_paise, currency, sort_order, '
          'created_at, updated_at, deleted_at, sync_state '
          'FROM khatas WHERE id = ?',
          variables: <Variable<Object>>[Variable<String>(normalized.id)],
        ).get();

        if (existingRows.isEmpty) {
          await customStatement(
            'INSERT INTO khatas (id, name, opening_balance_paise, currency, '
            'sort_order, created_at, updated_at, deleted_at, sync_state) '
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'synced')",
            <Object?>[
              normalized.id,
              normalized.name,
              normalized.openingBalancePaise,
              normalized.currency,
              normalized.sortOrder,
              normalized.createdAt.toIso8601String(),
              normalized.updatedAt.toIso8601String(),
              normalized.deletedAt?.toIso8601String(),
            ],
          );
          applied++;
          continue;
        }

        final QueryRow localRow = existingRows.single;
        final CloudKhataRow local = _cloudKhataFromRow(localRow);
        final String localSyncState = localRow.read<String>('sync_state');

        if (_shouldApplyRemote(
          localUpdatedAt: local.updatedAt,
          localIsTombstone: local.deletedAt != null,
          localIsPending: localSyncState == 'pending',
          localMatchesRemote: local.sameContentAs(normalized),
          remoteUpdatedAt: normalized.updatedAt,
          remoteIsTombstone: normalized.deletedAt != null,
        )) {
          await customStatement(
            'UPDATE khatas SET name = ?, opening_balance_paise = ?, '
            'currency = ?, sort_order = ?, created_at = ?, updated_at = ?, '
            "deleted_at = ?, sync_state = 'synced' WHERE id = ?",
            <Object?>[
              normalized.name,
              normalized.openingBalancePaise,
              normalized.currency,
              normalized.sortOrder,
              normalized.createdAt.toIso8601String(),
              normalized.updatedAt.toIso8601String(),
              normalized.deletedAt?.toIso8601String(),
              normalized.id,
            ],
          );
          if (normalized.deletedAt != null) {
            await _reconcileSelectionAfterRemoteArchive(normalized.id);
          }
          applied++;
        }
      }
      return applied;
    });
  }

  /// Applies remote transaction rows in a single transaction using the B5
  /// conflict rules:
  /// * Unknown `id` -> inserted with `sync_state = 'synced'` when its khata
  ///   exists locally.
  /// * Newer `updated_at` wins; on a tie, a tombstone stays; newer local
  ///   `pending` rows are never overwritten; applied rows become `synced`;
  ///   rows are never hard-deleted.
  Future<int> applyRemoteTransactions(
    Iterable<CloudTransactionRow> remoteRows,
  ) async {
    return transaction<int>(() async {
      int applied = 0;
      for (final CloudTransactionRow incoming in remoteRows) {
        final List<QueryRow> khataExists = await customSelect(
          'SELECT id FROM khatas WHERE id = ?',
          variables: <Variable<Object>>[Variable<String>(incoming.khataId)],
        ).get();
        if (khataExists.isEmpty) continue;

        final List<QueryRow> existingRows = await customSelect(
          'SELECT id, khata_id, type, amount_paise, category_id, description, '
          'occurred_at, note_session_id, created_at, updated_at, deleted_at, '
          'sync_state FROM "transactions" WHERE id = ?',
          variables: <Variable<Object>>[Variable<String>(incoming.id)],
        ).get();

        if (existingRows.isEmpty) {
          await customStatement(
            'INSERT INTO "transactions" (id, khata_id, type, amount_paise, '
            'category_id, description, occurred_at, note_session_id, '
            'created_at, updated_at, deleted_at, sync_state) '
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'synced')",
            <Object?>[
              incoming.id,
              incoming.khataId,
              incoming.type.wireValue,
              incoming.amountPaise,
              incoming.categoryId,
              incoming.description,
              incoming.occurredAt.toIso8601String(),
              incoming.noteSessionId,
              incoming.createdAt.toIso8601String(),
              incoming.updatedAt.toIso8601String(),
              incoming.deletedAt?.toIso8601String(),
            ],
          );
          applied++;
          continue;
        }

        final QueryRow localRow = existingRows.single;
        final CloudTransactionRow local = _cloudTransactionFromRow(localRow);
        final String localSyncState = localRow.read<String>('sync_state');

        if (_shouldApplyRemote(
          localUpdatedAt: local.updatedAt,
          localIsTombstone: local.deletedAt != null,
          localIsPending: localSyncState == 'pending',
          localMatchesRemote: local.sameContentAs(incoming),
          remoteUpdatedAt: incoming.updatedAt,
          remoteIsTombstone: incoming.deletedAt != null,
        )) {
          await customStatement(
            'UPDATE "transactions" SET khata_id = ?, type = ?, '
            'amount_paise = ?, category_id = ?, description = ?, '
            'occurred_at = ?, note_session_id = ?, created_at = ?, '
            "updated_at = ?, deleted_at = ?, sync_state = 'synced' "
            'WHERE id = ?',
            <Object?>[
              incoming.khataId,
              incoming.type.wireValue,
              incoming.amountPaise,
              incoming.categoryId,
              incoming.description,
              incoming.occurredAt.toIso8601String(),
              incoming.noteSessionId,
              incoming.createdAt.toIso8601String(),
              incoming.updatedAt.toIso8601String(),
              incoming.deletedAt?.toIso8601String(),
              incoming.id,
            ],
          );
          applied++;
        }
      }
      return applied;
    });
  }

  /// Reads the persisted sync cursor, last synced time, last error and last
  /// synced account id. Returns an all-null [LocalSyncMetadata] before the
  /// first sync.
  Future<LocalSyncMetadata> readSyncMetadata() async {
    final List<QueryRow> rows = await customSelect(
      'SELECT cursor, last_synced_at, last_error, last_synced_account_id '
      'FROM sync_metadata WHERE singleton = 1',
    ).get();
    if (rows.isEmpty) return LocalSyncMetadata();
    final QueryRow row = rows.single;
    final String? cursorRaw = row.readNullable<String>('cursor');
    final String? lastSyncedRaw = row.readNullable<String>('last_synced_at');
    return LocalSyncMetadata(
      cursor: cursorRaw == null ? null : DateTime.parse(cursorRaw).toUtc(),
      lastSyncedAt: lastSyncedRaw == null
          ? null
          : DateTime.parse(lastSyncedRaw).toUtc(),
      lastError: row.readNullable<String>('last_error'),
      lastSyncedAccountId: row.readNullable<String>('last_synced_account_id'),
    );
  }

  /// Updates selected fields of the singleton `sync_metadata` row. Unspecified
  /// fields preserve their existing stored values.
  Future<void> writeSyncMetadata({
    Object? cursor = _keepExistingValue,
    Object? lastSyncedAt = _keepExistingValue,
    Object? lastError = _keepExistingValue,
    Object? lastSyncedAccountId = _keepExistingValue,
  }) async {
    await transaction(() async {
      final LocalSyncMetadata current = await readSyncMetadata();
      final DateTime? nextCursor = identical(cursor, _keepExistingValue)
          ? current.cursor
          : (cursor as DateTime?)?.toUtc();
      final DateTime? nextLastSyncedAt =
          identical(lastSyncedAt, _keepExistingValue)
          ? current.lastSyncedAt
          : (lastSyncedAt as DateTime?)?.toUtc();
      final String? nextLastError = identical(lastError, _keepExistingValue)
          ? current.lastError
          : lastError as String?;
      final String? nextAccountId =
          identical(lastSyncedAccountId, _keepExistingValue)
          ? current.lastSyncedAccountId
          : lastSyncedAccountId as String?;

      await customStatement(
        'INSERT INTO sync_metadata (singleton, cursor, last_synced_at, '
        'last_error, last_synced_account_id) VALUES (1, ?, ?, ?, ?) '
        'ON CONFLICT(singleton) DO UPDATE SET '
        'cursor = excluded.cursor, '
        'last_synced_at = excluded.last_synced_at, '
        'last_error = excluded.last_error, '
        'last_synced_account_id = excluded.last_synced_account_id',
        <Object?>[
          nextCursor?.toIso8601String(),
          nextLastSyncedAt?.toIso8601String(),
          nextLastError,
          nextAccountId,
        ],
      );
    });
  }

  /// Re-marks all local khatas and transactions as `pending` and resets the
  /// pull cursor when the user explicitly confirms syncing with a different
  /// cloud account than the one this device previously synced with.
  Future<void> prepareForAccountSwitch(String newAccountId) async {
    final String trimmed = newAccountId.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(
        newAccountId,
        'newAccountId',
        'must not be blank',
      );
    }
    await transaction(() async {
      await customStatement("UPDATE khatas SET sync_state = 'pending'");
      await customStatement(
        'UPDATE "transactions" SET sync_state = ?',
        <Object>['pending'],
      );
      await writeSyncMetadata(
        cursor: null,
        lastSyncedAt: null,
        lastError: null,
        lastSyncedAccountId: trimmed,
      );
    });
  }

  Future<void> _reconcileSelectionAfterRemoteArchive(String khataId) async {
    final List<QueryRow> selected = await customSelect(
      'SELECT khata_id FROM active_khata_preference WHERE singleton = 1',
    ).get();
    final bool wasSelected =
        selected.isNotEmpty &&
        selected.single.read<String>('khata_id') == khataId;
    if (!wasSelected) return;
    if (await _findActiveKhata(_defaultKhata) != null) {
      await _writeActiveKhataId(_defaultKhata);
    } else {
      await customStatement(
        'DELETE FROM active_khata_preference WHERE singleton = 1',
      );
    }
  }

  static bool _shouldApplyRemote({
    required DateTime localUpdatedAt,
    required bool localIsTombstone,
    required bool localIsPending,
    required bool localMatchesRemote,
    required DateTime remoteUpdatedAt,
    required bool remoteIsTombstone,
  }) {
    if (remoteUpdatedAt.isAfter(localUpdatedAt)) {
      return true;
    }
    if (remoteUpdatedAt.isBefore(localUpdatedAt)) {
      return false;
    }
    // Tie on updated_at: a tombstone always stays/wins.
    if (localIsTombstone && !remoteIsTombstone) {
      return false;
    }
    if (remoteIsTombstone && !localIsTombstone) {
      return true;
    }
    // Both live or both tombstoned at the exact same instant:
    // never overwrite a divergent pending local row, but if content already
    // matches (or local is already synced), apply/settle as synced.
    if (localIsPending && !localMatchesRemote) {
      return false;
    }
    return !localMatchesRemote || localIsPending;
  }

  static CloudKhataRow _cloudKhataFromRow(QueryRow row) {
    final String? deletedRaw = row.readNullable<String>('deleted_at');
    return CloudKhataRow(
      id: row.read<String>('id'),
      name: row.read<String>('name'),
      openingBalancePaise: row.read<int>('opening_balance_paise'),
      currency: row.read<String>('currency'),
      sortOrder: row.read<int>('sort_order'),
      createdAt: DateTime.parse(row.read<String>('created_at')).toUtc(),
      updatedAt: DateTime.parse(row.read<String>('updated_at')).toUtc(),
      deletedAt: deletedRaw == null ? null : DateTime.parse(deletedRaw).toUtc(),
    );
  }

  static CloudTransactionRow _cloudTransactionFromRow(QueryRow row) {
    final String? deletedRaw = row.readNullable<String>('deleted_at');
    return CloudTransactionRow(
      id: row.read<String>('id'),
      khataId: row.read<String>('khata_id'),
      type: CloudTransactionType.fromWire(row.read<String>('type')),
      amountPaise: row.read<int>('amount_paise'),
      categoryId: row.read<String>('category_id'),
      description: row.readNullable<String>('description'),
      occurredAt: DateTime.parse(row.read<String>('occurred_at')).toUtc(),
      noteSessionId: row.readNullable<String>('note_session_id'),
      createdAt: DateTime.parse(row.read<String>('created_at')).toUtc(),
      updatedAt: DateTime.parse(row.read<String>('updated_at')).toUtc(),
      deletedAt: deletedRaw == null ? null : DateTime.parse(deletedRaw).toUtc(),
    );
  }
}

const Object _keepExistingValue = Object();
