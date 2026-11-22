/// Offline, versioned JSON backup of the local Khoroch Diary ledger.
///
/// This file is a standalone service with **no** file I/O, platform code,
/// network, UI or new dependency: it reads and writes the ledger tables
/// (`khatas`, `"transactions"`) and, for format version 2, the three side
/// areas the phone keeps on the same connection - the offline profile, the
/// custom categories and the note counter - through [LocalLedger] and nothing
/// else. The caller owns the file picker, the confirmation dialog and the
/// share sheet.
///
/// ```text
/// exportJson()          -> String (the whole phone, one read transaction)
/// inspect(json)         -> BackupInspection (synchronous, no writes)
/// restoreReplacing(json)-> Future<void>  (destructive, one write transaction)
/// ```
///
/// Version 2 carries everything the phone holds: the v1 ledger sections plus
/// `profile` (the offline profile, or null), `customCategories` (archived rows
/// included) and `noteCounter` (every row of the three `note_counter_*`
/// tables). Version 1 files restore exactly as they always did, and leave the
/// profile, the categories and the counter alone.
///
/// Rules this file exists to enforce:
///
/// * **Money stays integer paise.** A JSON number that is a `double` (even
///   `1000.0`) is rejected, so no value can lose precision on the way in.
/// * **Only this build's own format is accepted** - a fixed marker plus
///   `version: 1` or `version: 2`. Unknown versions, extra fields, missing
///   fields and wrong types are errors, not things to tolerate.
/// * **The file is validated in full, then written, in one transaction.**
///   `restoreReplacing` re-validates the string itself; it never trusts an
///   earlier [LedgerBackup.inspect]. A version 2 file replaces the ledger and
///   all three side areas in that same one transaction; any invalid part
///   rejects the whole file. Any failure leaves the existing ledger
///   byte-for-byte unchanged, and the side areas untouched with it.
/// * **Restore is a destructive replacement by design.** Every khata and
///   transaction row is removed first (child rows before parents) and replaced
///   by the file's rows, with `sync_state = 'pending'` so a later sync pushes
///   the restored data. A version 2 file also replaces the profile, the
///   custom categories and the note counter. Nothing else is touched: no
///   settings, no preferences, no schema, no other tables, and cloud sync is
///   never switched on. A version 1 file restores the ledger only and leaves
///   the side areas exactly as they are.
/// * **Tombstones travel with the data.** `deleted_at` is exported and
///   restored, so deleted entries stay deleted and history is preserved.
/// * **No secrets.** Only the ledger columns are serialised - never
///   credentials, tokens, device settings, database paths or account data.
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import '../../counter/note_counter_store.dart';

import 'local_ledger.dart';

/// Marker that identifies a Khoroch Diary ledger backup. The marker is checked
/// before anything else so a foreign JSON file is rejected as such.
///
/// The value keeps its pre-rename spelling on purpose: a backup exported before
/// the rename must keep importing.
const String kLedgerBackupFormat = 'khatabook-ledger-backup';

/// The backup format version this build writes. Version 2 adds the profile,
/// the custom categories and the note counter to the v1 ledger sections.
const int kLedgerBackupVersion = 2;

/// The previous format version, still readable. A v1 file restores the ledger
/// and nothing else.
const int kLedgerBackupVersionV1 = 1;

/// Largest backup accepted, in UTF-8 bytes (10 MiB).
///
/// A whole cash-book ledger is far smaller than this; the cap exists so a
/// malformed or hostile file cannot be decoded into a huge object graph.
const int kLedgerBackupMaxBytes = 10 * 1024 * 1024;

/// Thrown for anything that makes a backup unusable: bad JSON, a foreign or
/// unknown format, an unexpected field, an out-of-range amount, a duplicate id,
/// a dangling foreign key, a missing active personal khata or an oversized
/// payload.
class LedgerBackupException implements Exception {
  const LedgerBackupException(this.message);

  /// What is wrong, naming the offending field (e.g. `backup.khatas[0].name`).
  final String message;

  @override
  String toString() => 'LedgerBackupException: $message';
}

/// What one backup file contains, without touching the database.
///
/// [khataCount] counts every khata in the file including tombstoned ones;
/// [transactionCount] counts every entry; [deletedTransactionCount] counts the
/// tombstoned (soft-deleted) entries among them. [profileIncluded] reports
/// whether the file carries an offline profile; [customCategoryCount] counts
/// the custom categories (archived ones included); [khatasWithSavedCount]
/// counts the khatas the file holds at least one saved note count for;
/// [savedSessionCount] counts the saved note counts themselves. A version 1
/// file reports `false` and `0` for all four - it carries no side data.
class BackupInspection {
  const BackupInspection({
    required this.khataCount,
    required this.transactionCount,
    required this.deletedTransactionCount,
    required this.profileIncluded,
    required this.customCategoryCount,
    required this.khatasWithSavedCount,
    required this.savedSessionCount,
  });

  final int khataCount;
  final int transactionCount;
  final int deletedTransactionCount;
  final bool profileIncluded;
  final int customCategoryCount;
  final int khatasWithSavedCount;
  final int savedSessionCount;
}

/// One khatas row as it travels in a backup file.
class _KhataRecord {
  const _KhataRecord({
    required this.id,
    required this.name,
    required this.openingBalancePaise,
    required this.currency,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
    required this.deletedAt,
  });

  final String id;
  final String name;
  final int openingBalancePaise;
  final String currency;
  final int sortOrder;
  final String createdAt;
  final String updatedAt;
  final String? deletedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'opening_balance_paise': openingBalancePaise,
    'currency': currency,
    'sort_order': sortOrder,
    'created_at': createdAt,
    'updated_at': updatedAt,
    'deleted_at': deletedAt,
  };
}

/// One `"transactions"` row as it travels in a backup file.
class _TransactionRecord {
  const _TransactionRecord({
    required this.id,
    required this.khataId,
    required this.type,
    required this.amountPaise,
    required this.categoryId,
    required this.description,
    required this.occurredAt,
    required this.noteSessionId,
    required this.createdAt,
    required this.updatedAt,
    required this.deletedAt,
  });

  final String id;
  final String khataId;
  final String type;
  final int amountPaise;
  final String categoryId;
  final String? description;
  final String occurredAt;
  final String? noteSessionId;
  final String createdAt;
  final String updatedAt;
  final String? deletedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'khata_id': khataId,
    'type': type,
    'amount_paise': amountPaise,
    'category_id': categoryId,
    'description': description,
    'occurred_at': occurredAt,
    'note_session_id': noteSessionId,
    'created_at': createdAt,
    'updated_at': updatedAt,
    'deleted_at': deletedAt,
  };
}

/// One stored profile row. [avatarBytes] may be null (a name-only profile);
/// [avatarType] is `png` or `jpeg` whenever bytes are present.
class _ProfileRecord {
  const _ProfileRecord({required this.name, this.avatarBytes, this.avatarType});

  final String name;
  final Uint8List? avatarBytes;
  final String? avatarType;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'avatar': avatarBytes == null
        ? null
        : <String, Object?>{
            'type': avatarType,
            'base64': base64Encode(avatarBytes!),
          },
  };
}

/// One `custom_categories` row as it travels in a backup file. Archived rows
/// travel too - archiving keeps the row for historical entries.
class _CustomCategoryRecord {
  const _CustomCategoryRecord({
    required this.id,
    required this.name,
    required this.iconIndex,
    required this.colorIndex,
    required this.archived,
  });

  final String id;
  final String name;
  final int iconIndex;
  final int colorIndex;
  final bool archived;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'icon_index': iconIndex,
    'color_index': colorIndex,
    'archived': archived,
  };
}

/// One `note_counter_quantities` row.
class _CounterQuantityRecord {
  const _CounterQuantityRecord({
    required this.khataId,
    required this.denominationPaise,
    required this.quantity,
    required this.updatedAt,
  });

  final String khataId;
  final int denominationPaise;
  final int quantity;
  final String updatedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'khata_id': khataId,
    'denomination_paise': denominationPaise,
    'quantity': quantity,
    'updated_at': updatedAt,
  };
}

/// One `note_counter_state` row.
class _CounterStateRecord {
  const _CounterStateRecord({
    required this.khataId,
    required this.selectedDenominationPaise,
    required this.showTwoThousand,
    required this.updatedAt,
  });

  final String khataId;
  final int selectedDenominationPaise;
  final bool showTwoThousand;
  final String updatedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'khata_id': khataId,
    'selected_denomination_paise': selectedDenominationPaise,
    'show_two_thousand': showTwoThousand,
    'updated_at': updatedAt,
  };
}

/// One `note_counter_saved_sessions` row. [quantities] maps a denomination in
/// paise to its quantity - exactly the shape the store keeps in
/// `quantities_json`.
class _SavedSessionRecord {
  const _SavedSessionRecord({
    required this.id,
    required this.khataId,
    required this.savedAt,
    required this.quantities,
    required this.selectedDenominationPaise,
    required this.showTwoThousand,
  });

  final String id;
  final String khataId;
  final String savedAt;

  /// Every counted denomination, keyed by paise.
  final Map<int, int> quantities;
  final int selectedDenominationPaise;
  final bool showTwoThousand;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'khata_id': khataId,
    'saved_at': savedAt,
    'quantities': <String, int>{
      for (final MapEntry<int, int> entry in quantities.entries)
        entry.key.toString(): entry.value,
    },
    'selected_denomination_paise': selectedDenominationPaise,
    'show_two_thousand': showTwoThousand,
  };
}

/// One `note_counter_quantities` row as stored, for a version 1 restore.
class _PreservedQuantity {
  const _PreservedQuantity({
    required this.khataId,
    required this.denominationPaise,
    required this.quantity,
    required this.updatedAt,
  });

  final String khataId;
  final int denominationPaise;
  final int quantity;
  final String updatedAt;
}

/// One `note_counter_state` row as stored, for a version 1 restore.
class _PreservedState {
  const _PreservedState({
    required this.khataId,
    required this.selectedDenominationPaise,
    required this.showTwoThousand,
    required this.updatedAt,
  });

  final String khataId;
  final int selectedDenominationPaise;
  final int showTwoThousand;
  final String updatedAt;
}

/// One `note_counter_saved_sessions` row as stored, for a version 1 restore.
class _PreservedSession {
  const _PreservedSession({
    required this.id,
    required this.khataId,
    required this.savedAt,
    required this.quantitiesJson,
    required this.selectedDenominationPaise,
    required this.showTwoThousand,
  });

  final String id;
  final String khataId;
  final String savedAt;
  final String quantitiesJson;
  final int selectedDenominationPaise;
  final int showTwoThousand;
}

/// The note counter rows of this phone, read at the start of a version 1
/// restore (which leaves the side areas alone) so they can be written back
/// after the whole-ledger replace. The counter tables cascade on a khata
/// delete; without this the ledger replace would empty them.
class _CounterPreservation {
  const _CounterPreservation({
    required this.quantities,
    required this.state,
    required this.savedSessions,
  });

  final List<_PreservedQuantity> quantities;
  final List<_PreservedState> state;
  final List<_PreservedSession> savedSessions;
}

/// Everything the counter holds, as validated in memory.
class _CounterBackup {
  const _CounterBackup({
    required this.quantities,
    required this.state,
    required this.savedSessions,
  });

  final List<_CounterQuantityRecord> quantities;
  final List<_CounterStateRecord> state;
  final List<_SavedSessionRecord> savedSessions;

  Map<String, Object?> toJson() => <String, Object?>{
    'quantities': quantities
        .map((_CounterQuantityRecord row) => row.toJson())
        .toList(),
    'state': state.map((_CounterStateRecord row) => row.toJson()).toList(),
    'saved_sessions': savedSessions
        .map((_SavedSessionRecord row) => row.toJson())
        .toList(),
  };
}

/// A whole validated backup file, in memory.
class _Backup {
  const _Backup({
    required this.version,
    required this.khatas,
    required this.transactions,
    this.profile,
    this.customCategories = const <_CustomCategoryRecord>[],
    this.noteCounter = const _CounterBackup(
      quantities: <_CounterQuantityRecord>[],
      state: <_CounterStateRecord>[],
      savedSessions: <_SavedSessionRecord>[],
    ),
  });

  /// The file's declared version (1 or 2).
  final int version;
  final List<_KhataRecord> khatas;
  final List<_TransactionRecord> transactions;

  /// The stored profile, `null` when the file (or the phone) has none.
  final _ProfileRecord? profile;
  final List<_CustomCategoryRecord> customCategories;
  final _CounterBackup noteCounter;

  /// Distinct khatas the file holds at least one saved count for. In the
  /// app's own words a saved count is a saved session, so this counts the
  /// khatas appearing in [noteCounter]'s saved sessions.
  int get khatasWithSavedCount => noteCounter.savedSessions
      .map((_SavedSessionRecord session) => session.khataId)
      .toSet()
      .length;
}

/// The default personal khata, which every backup must carry exactly once and
/// must not be tombstoned. It is the khata the app opens on.
const String _personalKhataId = 'personal';

/// Khata names are 1...40 characters (docs/spec/data-model.md).
const int _maxKhataNameLength = 40;

/// Descriptions are at most 120 characters (schema + spec).
const int _maxDescriptionLength = 120;

/// Ids are client-generated strings; UUID v4 is 36 characters, `personal` is
/// short, and anything wildly longer is junk rather than data.
const int _maxIdLength = 64;

/// Expense categories are short labels (`Shopping`, `Food`, ...).
const int _maxCategoryLength = 64;

const Set<String> _khataKeys = <String>{
  'id',
  'name',
  'opening_balance_paise',
  'currency',
  'sort_order',
  'created_at',
  'updated_at',
  'deleted_at',
};

const Set<String> _transactionKeys = <String>{
  'id',
  'khata_id',
  'type',
  'amount_paise',
  'category_id',
  'description',
  'occurred_at',
  'note_session_id',
  'created_at',
  'updated_at',
  'deleted_at',
};

const Set<String> _rootKeysV1 = <String>{
  'format',
  'version',
  'khatas',
  'transactions',
};

const Set<String> _rootKeysV2 = <String>{
  'format',
  'version',
  'khatas',
  'transactions',
  'profile',
  'customCategories',
  'noteCounter',
};

const Set<String> _profileKeys = <String>{'name', 'avatar'};

const Set<String> _avatarKeys = <String>{'type', 'base64'};

const Set<String> _customCategoryKeys = <String>{
  'id',
  'name',
  'icon_index',
  'color_index',
  'archived',
};

const Set<String> _noteCounterKeys = <String>{
  'quantities',
  'state',
  'saved_sessions',
};

const Set<String> _counterQuantityKeys = <String>{
  'khata_id',
  'denomination_paise',
  'quantity',
  'updated_at',
};

const Set<String> _counterStateKeys = <String>{
  'khata_id',
  'selected_denomination_paise',
  'show_two_thousand',
  'updated_at',
};

const Set<String> _savedSessionKeys = <String>{
  'id',
  'khata_id',
  'saved_at',
  'quantities',
  'selected_denomination_paise',
  'show_two_thousand',
};

/// Profile names are 1...60 characters (profile_store.dart at a0e3c0e).
const int _maxProfileNameLength = 60;

/// Custom category names are 1...30 characters (category_store.dart at
/// a0e3c0e).
const int _maxCustomCategoryNameLength = 30;

/// The offline profile photo limit, 2 MiB (profile_store.dart at a0e3c0e).
const int _maxAvatarBytes = 2 * 1024 * 1024;

/// The custom category appearance sets (`categoryIcons` / `categoryColors` in
/// category_store.dart at a0e3c0e) each hold six entries; the valid indexes
/// are 0...5. Kept in step by hand - the store file is deliberately not
/// imported here.
const int _customCategoryAppearanceCount = 6;

/// The avatar media types the format carries, mapped to their magic bytes.
const String _avatarTypePng = 'png';
const String _avatarTypeJpeg = 'jpeg';

/// UTC ISO-8601 with a mandatory `Z`, optional fraction. Local-time strings
/// and `+05:30` offsets are rejected: storage is always UTC.
final RegExp _utcTimestampPattern = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$',
);

/// Versioned JSON export and validated, atomic restore of the local ledger.
///
/// Construct it around the app's [LocalLedger]; it holds no state of its own,
/// so one instance can export, inspect and restore in any order.
class LedgerBackup {
  LedgerBackup(this.ledger);

  /// The database this backup reads from and restores into.
  final LocalLedger ledger;

  /// Serialises everything the phone holds to this build's JSON format:
  /// every khata and every transaction (tombstones included), the offline
  /// profile, every custom category (archived ones included) and every row of
  /// the three `note_counter_*` tables, for every khata.
  ///
  /// The tables are read inside one transaction, so the snapshot is
  /// consistent: an entry written after the export started cannot appear
  /// without its khata (or the other way round).
  ///
  /// Throws [LedgerBackupException] when the database does not hold exactly one
  /// active personal khata, or when a stored row could not itself be restored.
  /// Exporting something that would be rejected on the way back in is worse
  /// than refusing: the caller would keep a backup that cannot be used. So the
  /// finished document is run through the same validation [inspect] and
  /// [restoreReplacing] use before it is returned.
  Future<String> exportJson() async {
    return ledger.transaction<String>(() async {
      final List<_KhataRecord> khatas = await _readKhatas();
      final List<_TransactionRecord> transactions = await _readTransactions();
      final _ProfileRecord? profile = await _readProfile();
      final List<_CustomCategoryRecord> customCategories =
          await _readCustomCategories();
      final _CounterBackup noteCounter = await _readNoteCounter(
        khatas.map((_KhataRecord k) => k.id).toSet(),
      );
      final Map<String, Object?> root = <String, Object?>{
        'format': kLedgerBackupFormat,
        'version': kLedgerBackupVersion,
        'khatas': khatas.map((_KhataRecord k) => k.toJson()).toList(),
        'transactions': transactions
            .map((_TransactionRecord t) => t.toJson())
            .toList(),
        'profile': profile?.toJson(),
        'customCategories': customCategories
            .map((_CustomCategoryRecord c) => c.toJson())
            .toList(),
        'noteCounter': noteCounter.toJson(),
      };
      final String json = const JsonEncoder.withIndent('  ').convert(root);
      _decodeAndValidate(json);
      return json;
    });
  }

  /// Counts what [json] would restore, without writing anything.
  ///
  /// Fully validates the file, so a caller can show "N khatas, M entries (K
  /// deleted) - this will replace your current ledger" from a trustworthy
  /// number, and can throw the same [LedgerBackupException] it would get from
  /// [restoreReplacing]. The result is advisory: [restoreReplacing] validates
  /// the string again before it touches the database.
  BackupInspection inspect(String json) {
    final _Backup backup = _decodeAndValidate(json);
    int deleted = 0;
    for (final _TransactionRecord transaction in backup.transactions) {
      if (transaction.deletedAt != null) deleted++;
    }
    return BackupInspection(
      khataCount: backup.khatas.length,
      transactionCount: backup.transactions.length,
      deletedTransactionCount: deleted,
      profileIncluded: backup.profile != null,
      customCategoryCount: backup.customCategories.length,
      khatasWithSavedCount: backup.khatasWithSavedCount,
      savedSessionCount: backup.noteCounter.savedSessions.length,
    );
  }

  /// Replaces the local ledger with the contents of [json].
  ///
  /// **Destructive by design:** every existing khata and transaction is
  /// removed. The caller is responsible for explicit user confirmation; a
  /// backup codec cannot know whether the user meant it.
  ///
  /// The whole file is validated first, then the replace runs in a single
  /// SQLite transaction (child rows deleted before parents, khatas inserted
  /// before their entries). A version 2 file replaces the offline profile,
  /// the custom categories and every note counter row in that same
  /// transaction, so the phone either ends up fully restored or completely
  /// unchanged. Any error - a bad field or a failing statement - rolls the
  /// transaction back, so a failed restore leaves the previous ledger
  /// exactly as it was. Restored ledger rows get `sync_state = 'pending'`;
  /// settings and every other table are untouched. A version 1 file restores
  /// the ledger only; the profile, the custom categories and the note
  /// counter are left exactly as they are. The counter tables cascade on a
  /// khata delete, so for a version 1 file their rows are read inside the
  /// transaction and written straight back (rows whose khata survives the
  /// replace are kept; rows for a khata the file no longer carries cannot
  /// survive, and a dangling reference would break the next export).
  Future<void> restoreReplacing(String json) async {
    // Validate the entire file again here; a prior `inspect` is not a licence
    // to skip it, because the string may have changed since.
    final _Backup backup = _decodeAndValidate(json);
    await ledger.transaction<void>(() async {
      // A version 1 file leaves the note counter alone, which the khata
      // delete cascades through. Read the rows first so they can be written
      // back below; a version 2 file replaces them from the file instead.
      final _CounterPreservation? preserved =
          backup.version == kLedgerBackupVersionV1
          ? await _readCounterForPreservation()
          : null;
      if (backup.version == kLedgerBackupVersion) {
        // The side tables are created lazily by their stores; a phone that
        // never opened the profile or the counter has none. Create them in
        // the transaction, so a failed restore leaves a fresh phone exactly
        // as it was - no new tables either. A v1 restore never touches
        // them; the DDL is transactional in SQLite, so this rolls back
        // with everything else on failure.
        await _ensureSideTables();
        // Child rows before parents, exactly as the ledger tables below.
        await ledger.customStatement('DELETE FROM note_counter_saved_sessions');
        await ledger.customStatement('DELETE FROM note_counter_state');
        await ledger.customStatement('DELETE FROM note_counter_quantities');
        await ledger.customStatement('DELETE FROM custom_categories');
        await ledger.customStatement('DELETE FROM local_profile');
      }
      await ledger.customStatement('DELETE FROM "transactions"');
      await ledger.customStatement('DELETE FROM khatas');
      for (final _KhataRecord khata in backup.khatas) {
        await ledger.customStatement(
          'INSERT INTO khatas (id, name, opening_balance_paise, currency, '
          'sort_order, created_at, updated_at, deleted_at, sync_state) '
          "VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'pending')",
          <Object?>[
            khata.id,
            khata.name,
            khata.openingBalancePaise,
            khata.currency,
            khata.sortOrder,
            khata.createdAt,
            khata.updatedAt,
            khata.deletedAt,
          ],
        );
      }
      for (final _TransactionRecord transaction in backup.transactions) {
        await ledger.customStatement(
          'INSERT INTO "transactions" (id, khata_id, type, amount_paise, '
          'category_id, description, occurred_at, note_session_id, '
          'created_at, updated_at, deleted_at, sync_state) '
          "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending')",
          <Object?>[
            transaction.id,
            transaction.khataId,
            transaction.type,
            transaction.amountPaise,
            transaction.categoryId,
            transaction.description,
            transaction.occurredAt,
            transaction.noteSessionId,
            transaction.createdAt,
            transaction.updatedAt,
            transaction.deletedAt,
          ],
        );
      }
      if (backup.version == kLedgerBackupVersion) {
        final _ProfileRecord? profile = backup.profile;
        if (profile != null) {
          await ledger.customStatement(
            'INSERT INTO local_profile (id, name, avatar) VALUES (1, ?, ?)',
            <Object?>[profile.name, profile.avatarBytes],
          );
        }
        for (final _CustomCategoryRecord category in backup.customCategories) {
          await ledger.customStatement(
            'INSERT INTO custom_categories '
            '(id, name, icon_index, color_index, archived) '
            'VALUES (?, ?, ?, ?, ?)',
            <Object?>[
              category.id,
              category.name,
              category.iconIndex,
              category.colorIndex,
              category.archived ? 1 : 0,
            ],
          );
        }
        for (final _CounterQuantityRecord row
            in backup.noteCounter.quantities) {
          await ledger.customStatement(
            'INSERT INTO note_counter_quantities '
            '(khata_id, denomination_paise, quantity, updated_at) '
            'VALUES (?, ?, ?, ?)',
            <Object?>[
              row.khataId,
              row.denominationPaise,
              row.quantity,
              row.updatedAt,
            ],
          );
        }
        for (final _CounterStateRecord row in backup.noteCounter.state) {
          await ledger.customStatement(
            'INSERT INTO note_counter_state '
            '(khata_id, selected_denomination_paise, show_two_thousand, '
            'updated_at) VALUES (?, ?, ?, ?)',
            <Object?>[
              row.khataId,
              row.selectedDenominationPaise,
              row.showTwoThousand ? 1 : 0,
              row.updatedAt,
            ],
          );
        }
        for (final _SavedSessionRecord row
            in backup.noteCounter.savedSessions) {
          await ledger.customStatement(
            'INSERT INTO note_counter_saved_sessions '
            '(id, khata_id, saved_at, quantities_json, '
            'selected_denomination_paise, show_two_thousand) '
            'VALUES (?, ?, ?, ?, ?, ?)',
            <Object?>[
              row.id,
              row.khataId,
              row.savedAt,
              _encodeSessionQuantities(row.quantities),
              row.selectedDenominationPaise,
              row.showTwoThousand ? 1 : 0,
            ],
          );
        }
      }
      if (preserved != null) {
        // A version 1 file: write the phone's own counter rows back, for
        // the khatas that survived the replace.
        final Set<String> restoredKhataIds = <String>{
          for (final _KhataRecord khata in backup.khatas) khata.id,
        };
        await _restoreCounterForPreservation(preserved, restoredKhataIds);
      }
    });
  }

  /// Creates the side tables a version 2 restore writes into, if they do not
  /// exist yet. The ledger tables are drift's; these are not, so drift does
  /// not create them.
  ///
  /// The DDL mirrors the stores that own these tables (profile_store.dart and
  /// entry/category_store.dart at a0e3c0e, and NoteCounterStore here) so the
  /// restore works on a phone whose profile or counter was never opened. The
  /// stores are deliberately not imported - their files belong to other
  /// workers, and SQL keeps this file honest about what it touches.
  Future<void> _ensureSideTables() async {
    await ledger.customStatement('''
CREATE TABLE IF NOT EXISTS local_profile (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  name TEXT NOT NULL,
  avatar BLOB
)
''');
    await ledger.customStatement('''
CREATE TABLE IF NOT EXISTS custom_categories (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  icon_index INTEGER NOT NULL,
  color_index INTEGER NOT NULL,
  archived INTEGER NOT NULL DEFAULT 0
)
''');
    await NoteCounterStore(ledger).ensureTables();
  }

  /// Reads the note counter rows for a version 1 restore, which leaves the
  /// side areas alone. Raw rows, exactly as stored - no validation: they
  /// were written by this phone's own store and are kept verbatim. When the
  /// counter tables are absent (the counter was never opened), the counter
  /// is left alone too, and there is nothing to preserve.
  Future<_CounterPreservation?> _readCounterForPreservation() async {
    if (!await _tableExists('note_counter_quantities') ||
        !await _tableExists('note_counter_state') ||
        !await _tableExists('note_counter_saved_sessions')) {
      return null;
    }
    final List<QueryRow> quantityRows = await ledger
        .customSelect(
          'SELECT khata_id, denomination_paise, quantity, updated_at '
          'FROM note_counter_quantities ORDER BY 1, 2',
        )
        .get();
    final List<QueryRow> stateRows = await ledger
        .customSelect(
          'SELECT khata_id, selected_denomination_paise, show_two_thousand, '
          'updated_at FROM note_counter_state ORDER BY 1',
        )
        .get();
    final List<QueryRow> sessionRows = await ledger
        .customSelect(
          'SELECT id, khata_id, saved_at, quantities_json, '
          'selected_denomination_paise, show_two_thousand '
          'FROM note_counter_saved_sessions ORDER BY 1, 2',
        )
        .get();
    return _CounterPreservation(
      quantities: <_PreservedQuantity>[
        for (final QueryRow row in quantityRows)
          _PreservedQuantity(
            khataId: row.read<String>('khata_id'),
            denominationPaise: row.read<int>('denomination_paise'),
            quantity: row.read<int>('quantity'),
            updatedAt: row.read<String>('updated_at'),
          ),
      ],
      state: <_PreservedState>[
        for (final QueryRow row in stateRows)
          _PreservedState(
            khataId: row.read<String>('khata_id'),
            selectedDenominationPaise: row.read<int>(
              'selected_denomination_paise',
            ),
            showTwoThousand: row.read<int>('show_two_thousand'),
            updatedAt: row.read<String>('updated_at'),
          ),
      ],
      savedSessions: <_PreservedSession>[
        for (final QueryRow row in sessionRows)
          _PreservedSession(
            id: row.read<String>('id'),
            khataId: row.read<String>('khata_id'),
            savedAt: row.read<String>('saved_at'),
            quantitiesJson: row.read<String>('quantities_json'),
            selectedDenominationPaise: row.read<int>(
              'selected_denomination_paise',
            ),
            showTwoThousand: row.read<int>('show_two_thousand'),
          ),
      ],
    );
  }

  /// Writes the preserved counter rows back after a version 1 replace, for
  /// the khatas that survived in the file. Rows for a khata the file no
  /// longer carries are dropped: the khata is gone from the ledger, and a
  /// counter row pointing at it would fail the next export's khata check.
  Future<void> _restoreCounterForPreservation(
    _CounterPreservation preserved,
    Set<String> restoredKhataIds,
  ) async {
    for (final _PreservedQuantity row in preserved.quantities) {
      if (!restoredKhataIds.contains(row.khataId)) continue;
      // The retired ₹2,000 note is repaired away, never written back.
      if (row.denominationPaise == kRetiredTwoThousandPaise) continue;
      await ledger.customStatement(
        'INSERT INTO note_counter_quantities '
        '(khata_id, denomination_paise, quantity, updated_at) '
        'VALUES (?, ?, ?, ?)',
        <Object?>[
          row.khataId,
          row.denominationPaise,
          row.quantity,
          row.updatedAt,
        ],
      );
    }
    for (final _PreservedState row in preserved.state) {
      if (!restoredKhataIds.contains(row.khataId)) continue;
      // Retired ₹2,000 selection repairs to the default; the old
      // show_two_thousand flag repairs away to 0.
      final int selection =
          row.selectedDenominationPaise == kRetiredTwoThousandPaise
          ? kDefaultDenominationPaise
          : row.selectedDenominationPaise;
      await ledger.customStatement(
        'INSERT INTO note_counter_state '
        '(khata_id, selected_denomination_paise, show_two_thousand, '
        'updated_at) VALUES (?, ?, ?, ?)',
        <Object?>[row.khataId, selection, 0, row.updatedAt],
      );
    }
    for (final _PreservedSession row in preserved.savedSessions) {
      if (!restoredKhataIds.contains(row.khataId)) continue;
      // Scrub the retired ₹2,000 note from the session's quantities. Every
      // non-retired value must still be an integer; otherwise the row is
      // kept verbatim and the counter's load-time repair reports it.
      String quantitiesJson = row.quantitiesJson;
      try {
        final Object? decoded = jsonDecode(row.quantitiesJson);
        if (decoded is Map<dynamic, dynamic>) {
          bool scrubSafe = true;
          for (final MapEntry<dynamic, dynamic> entry in decoded.entries) {
            if (entry.key.toString() == '$kRetiredTwoThousandPaise') continue;
            if (entry.value is! int) {
              scrubSafe = false;
              break;
            }
          }
          if (scrubSafe) {
            quantitiesJson = jsonEncode(<String, int>{
              for (final MapEntry<dynamic, dynamic> entry in decoded.entries)
                if (entry.key.toString() != '$kRetiredTwoThousandPaise')
                  entry.key.toString(): entry.value! as int,
            });
          }
        }
      } catch (_) {
        // Keep the row verbatim; the load-time repair will report it.
      }
      final int selection =
          row.selectedDenominationPaise == kRetiredTwoThousandPaise
          ? kDefaultDenominationPaise
          : row.selectedDenominationPaise;
      await ledger.customStatement(
        'INSERT INTO note_counter_saved_sessions '
        '(id, khata_id, saved_at, quantities_json, '
        'selected_denomination_paise, show_two_thousand) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        <Object?>[
          row.id,
          row.khataId,
          row.savedAt,
          quantitiesJson,
          selection,
          0,
        ],
      );
    }
  }

  /// Every khata, tombstoned ones included, in the app's display order.
  Future<List<_KhataRecord>> _readKhatas() async {
    const String sql =
        'SELECT id, name, opening_balance_paise, currency, sort_order, '
        'created_at, updated_at, deleted_at FROM khatas '
        'ORDER BY sort_order ASC, created_at ASC, id ASC';
    final List<QueryRow> rows = await ledger.customSelect(sql).get();
    return rows
        .map((QueryRow row) {
          final String id = row.read<String>('id');
          return _KhataRecord(
            id: id,
            name: row.read<String>('name'),
            openingBalancePaise: row.read<int>('opening_balance_paise'),
            currency: row.read<String>('currency'),
            sortOrder: row.read<int>('sort_order'),
            createdAt: _checkTimestamp(
              row.read<String>('created_at'),
              'khatas[$id].created_at',
            ),
            updatedAt: _checkTimestamp(
              row.read<String>('updated_at'),
              'khatas[$id].updated_at',
            ),
            deletedAt: _readTimestamp(
              row.readNullable<String>('deleted_at'),
              'khatas[$id].deleted_at',
            ),
          );
        })
        .toList(growable: false);
  }

  /// Every transaction, tombstoned ones included, in a stable order.
  Future<List<_TransactionRecord>> _readTransactions() async {
    const String sql =
        'SELECT id, khata_id, type, amount_paise, category_id, description, '
        'occurred_at, note_session_id, created_at, updated_at, deleted_at '
        'FROM "transactions" ORDER BY khata_id ASC, occurred_at ASC, id ASC';
    final List<QueryRow> rows = await ledger.customSelect(sql).get();
    return rows
        .map((QueryRow row) {
          final String id = row.read<String>('id');
          return _TransactionRecord(
            id: id,
            khataId: row.read<String>('khata_id'),
            type: row.read<String>('type'),
            amountPaise: row.read<int>('amount_paise'),
            categoryId: row.read<String>('category_id'),
            description: row.readNullable<String>('description'),
            occurredAt: _checkTimestamp(
              row.read<String>('occurred_at'),
              'transactions[$id].occurred_at',
            ),
            noteSessionId: row.readNullable<String>('note_session_id'),
            createdAt: _checkTimestamp(
              row.read<String>('created_at'),
              'transactions[$id].created_at',
            ),
            updatedAt: _checkTimestamp(
              row.read<String>('updated_at'),
              'transactions[$id].updated_at',
            ),
            deletedAt: _readTimestamp(
              row.readNullable<String>('deleted_at'),
              'transactions[$id].deleted_at',
            ),
          );
        })
        .toList(growable: false);
  }

  /// Whether [table] exists in this database. The side areas are created
  /// lazily by their stores, so an export must not assume them - a phone that
  /// never opened the profile screen legitimately has no `local_profile`.
  Future<bool> _tableExists(String table) async {
    final List<QueryRow> rows = await ledger
        .customSelect(
          'SELECT name FROM sqlite_master '
          "WHERE type = 'table' AND name = ?",
          variables: <Variable<Object>>[Variable<String>(table)],
        )
        .get();
    return rows.isNotEmpty;
  }

  /// The stored offline profile, or null when there is none (no table, or no
  /// row). A stored row that could not be restored is an error, not a skipped
  /// profile: the export must refuse rather than keep an unusable backup.
  Future<_ProfileRecord?> _readProfile() async {
    if (!await _tableExists('local_profile')) return null;
    final List<QueryRow> rows = await ledger
        .customSelect('SELECT name, avatar FROM local_profile WHERE id = 1')
        .get();
    if (rows.isEmpty) return null;
    final String name = rows.first.read<String>('name');
    // ProfileStore permits clearing the name, including while retaining an
    // avatar; blank names are valid profile data and must round-trip.
    if (name.runes.length > _maxProfileNameLength) {
      throw LedgerBackupException(
        'local_profile.name must be at most $_maxProfileNameLength characters '
        'to export',
      );
    }
    final Uint8List? avatar = rows.first.readNullable<Uint8List>('avatar');
    if (avatar != null) {
      _checkAvatar(avatar, 'local_profile.avatar', declaredType: null);
      return _ProfileRecord(
        name: name,
        avatarBytes: avatar,
        avatarType: _avatarTypeOf(avatar),
      );
    }
    return _ProfileRecord(name: name);
  }

  /// Every `custom_categories` row, archived ones included.
  Future<List<_CustomCategoryRecord>> _readCustomCategories() async {
    if (!await _tableExists('custom_categories')) {
      return const <_CustomCategoryRecord>[];
    }
    final List<QueryRow> rows = await ledger
        .customSelect(
          'SELECT id, name, icon_index, color_index, archived '
          'FROM custom_categories ORDER BY id ASC',
        )
        .get();
    return <_CustomCategoryRecord>[
      for (final QueryRow row in rows)
        _checkedCategoryRow(
          id: row.read<String>('id'),
          name: row.read<String>('name'),
          iconIndex: row.read<int>('icon_index'),
          colorIndex: row.read<int>('color_index'),
          archived: row.read<int>('archived'),
          path: 'custom_categories[${row.read<String>('id')}]',
        ),
    ];
  }

  /// Every row of the three `note_counter_*` tables, for every khata.
  ///
  /// [khataIds] is the set of khata ids the export already read; a counter
  /// row pointing at a khata that is not in the file would fail restore, so
  /// the export refuses it here instead.
  Future<_CounterBackup> _readNoteCounter(Set<String> khataIds) async {
    const _CounterBackup empty = _CounterBackup(
      quantities: <_CounterQuantityRecord>[],
      state: <_CounterStateRecord>[],
      savedSessions: <_SavedSessionRecord>[],
    );
    if (!await _tableExists('note_counter_quantities')) return empty;
    final List<QueryRow> quantityRows = await ledger
        .customSelect(
          'SELECT khata_id, denomination_paise, quantity, updated_at '
          'FROM note_counter_quantities '
          'ORDER BY khata_id ASC, denomination_paise ASC',
        )
        .get();
    final List<_CounterQuantityRecord> quantities = <_CounterQuantityRecord>[
      for (final QueryRow row in quantityRows)
        if (_checkedQuantityRow(
              khataId: row.read<String>('khata_id'),
              denominationPaise: row.read<int>('denomination_paise'),
              quantity: row.read<int>('quantity'),
              updatedAt: row.read<String>('updated_at'),
              khataIds: khataIds,
              path: 'note_counter_quantities',
            )
            case final _CounterQuantityRecord record)
          record,
    ];
    final List<_CounterStateRecord> state = <_CounterStateRecord>[];
    if (await _tableExists('note_counter_state')) {
      final List<QueryRow> stateRows = await ledger
          .customSelect(
            'SELECT khata_id, selected_denomination_paise, show_two_thousand, '
            'updated_at FROM note_counter_state ORDER BY khata_id ASC',
          )
          .get();
      state.addAll(<_CounterStateRecord>[
        for (final QueryRow row in stateRows)
          _checkedStateRow(
            khataId: row.read<String>('khata_id'),
            selectedDenominationPaise: row.read<int>(
              'selected_denomination_paise',
            ),
            showTwoThousand: row.read<int>('show_two_thousand'),
            updatedAt: row.read<String>('updated_at'),
            khataIds: khataIds,
            path: 'note_counter_state',
          ),
      ]);
    }
    final List<_SavedSessionRecord> savedSessions = <_SavedSessionRecord>[];
    if (await _tableExists('note_counter_saved_sessions')) {
      final List<QueryRow> sessionRows = await ledger
          .customSelect(
            'SELECT id, khata_id, saved_at, quantities_json, '
            'selected_denomination_paise, show_two_thousand '
            'FROM note_counter_saved_sessions '
            'ORDER BY saved_at ASC, id ASC',
          )
          .get();
      savedSessions.addAll(<_SavedSessionRecord>[
        for (final QueryRow row in sessionRows)
          _checkedSessionRow(
            id: row.read<String>('id'),
            khataId: row.read<String>('khata_id'),
            savedAt: row.read<String>('saved_at'),
            quantitiesJson: row.read<String>('quantities_json'),
            selectedDenominationPaise: row.read<int>(
              'selected_denomination_paise',
            ),
            showTwoThousand: row.read<int>('show_two_thousand'),
            khataIds: khataIds,
            path: 'note_counter_saved_sessions[${row.read<String>('id')}]',
          ),
      ]);
    }
    return _CounterBackup(
      quantities: quantities,
      state: state,
      savedSessions: savedSessions,
    );
  }

  /// Parses and validates one complete backup file.
  ///
  /// Every check that `restoreReplacing` relies on lives here, so `inspect` and
  /// `restoreReplacing` reject exactly the same inputs.
  _Backup _decodeAndValidate(String json) {
    if (json.trim().isEmpty) {
      throw const LedgerBackupException('Backup is empty');
    }
    final int byteLength = utf8.encode(json).length;
    if (byteLength > kLedgerBackupMaxBytes) {
      throw LedgerBackupException(
        'Backup is $byteLength bytes; the limit is $kLedgerBackupMaxBytes',
      );
    }

    Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException catch (error) {
      throw LedgerBackupException('Backup is not valid JSON: ${error.message}');
    }
    if (decoded is! Map<String, Object?>) {
      throw const LedgerBackupException('Backup root must be a JSON object');
    }
    // Marker first, so a foreign JSON file is rejected as such.
    if (decoded['format'] != kLedgerBackupFormat) {
      throw const LedgerBackupException(
        'Backup format marker is missing or not recognised',
      );
    }
    final Object? version = decoded['version'];
    if (version is! int) {
      throw const LedgerBackupException('Backup version must be an integer');
    }
    if (version != kLedgerBackupVersion && version != kLedgerBackupVersionV1) {
      throw LedgerBackupException(
        'Unsupported backup version $version; this build reads '
        'versions $kLedgerBackupVersionV1 and $kLedgerBackupVersion',
      );
    }
    // The version decides the expected key set: v1 files do not carry the
    // side sections, v2 files must carry all of them.
    _expectExactKeys(
      decoded,
      version == kLedgerBackupVersionV1 ? _rootKeysV1 : _rootKeysV2,
      'backup',
    );

    final List<Object?> khataItems = _expectList(decoded, 'khatas', 'backup');
    final List<Object?> transactionItems = _expectList(
      decoded,
      'transactions',
      'backup',
    );
    final List<_KhataRecord> khatas = <_KhataRecord>[
      for (int i = 0; i < khataItems.length; i++)
        _parseKhata(khataItems[i], 'backup.khatas[$i]'),
    ];
    final List<_TransactionRecord> transactions = <_TransactionRecord>[
      for (int i = 0; i < transactionItems.length; i++)
        _parseTransaction(transactionItems[i], 'backup.transactions[$i]'),
    ];

    _requireActivePersonalKhata(khatas);
    _checkRelationships(khatas, transactions);
    if (version == kLedgerBackupVersionV1) {
      // A v1 file restores the ledger and nothing else. The side sections are
      // not read, which is what leaves the profile, the custom categories and
      // the note counter exactly as they are on the phone.
      return _Backup(
        version: version,
        khatas: khatas,
        transactions: transactions,
      );
    }
    final Set<String> khataIds = <String>{
      for (final _KhataRecord khata in khatas) khata.id,
    };
    final _ProfileRecord? profile = _parseProfile(
      decoded['profile'],
      'backup.profile',
    );
    final List<_CustomCategoryRecord> customCategories = _parseCustomCategories(
      decoded['customCategories'],
      'backup.customCategories',
    );
    final _CounterBackup noteCounter = _parseNoteCounter(
      decoded['noteCounter'],
      'backup.noteCounter',
      khataIds,
    );
    return _Backup(
      version: version,
      khatas: khatas,
      transactions: transactions,
      profile: profile,
      customCategories: customCategories,
      noteCounter: noteCounter,
    );
  }

  /// Exactly one `personal` khata, and it must be active.
  void _requireActivePersonalKhata(List<_KhataRecord> khatas) {
    int personalKhatas = 0;
    int activePersonalKhatas = 0;
    for (final _KhataRecord khata in khatas) {
      if (khata.id != _personalKhataId) continue;
      personalKhatas++;
      if (khata.deletedAt == null) activePersonalKhatas++;
    }
    if (personalKhatas != 1 || activePersonalKhatas != 1) {
      throw const LedgerBackupException(
        'Backup must contain exactly one active $_personalKhataId khata',
      );
    }
  }

  /// Duplicate ids and dangling foreign keys are rejected: both would break
  /// the app's own reads, and the schema's `REFERENCES`/`PRIMARY KEY` would
  /// refuse them anyway once the rows reach SQLite.
  ///
  /// Deliberately *not* checked: whether `category_id` matches `type`. The
  /// editor lets a user flip an entry from expense to income without touching
  /// its category, so income + `Food` is real data this app has written, not
  /// corruption. The category is a label; the direction is `type`.
  void _checkRelationships(
    List<_KhataRecord> khatas,
    List<_TransactionRecord> transactions,
  ) {
    final Set<String> khataIds = <String>{};
    for (final _KhataRecord khata in khatas) {
      if (!khataIds.add(khata.id)) {
        throw LedgerBackupException('Duplicate khata id ${khata.id}');
      }
    }
    final Set<String> transactionIds = <String>{};
    for (final _TransactionRecord transaction in transactions) {
      if (!transactionIds.add(transaction.id)) {
        throw LedgerBackupException(
          'Duplicate transaction id ${transaction.id}',
        );
      }
      if (!khataIds.contains(transaction.khataId)) {
        throw LedgerBackupException(
          'Transaction ${transaction.id} refers to missing khata '
          '${transaction.khataId}',
        );
      }
    }
  }

  _KhataRecord _parseKhata(Object? value, String path) {
    final Map<String, Object?> map = _expectObject(value, path);
    _expectExactKeys(map, _khataKeys, path);
    final String id = _expectId(map, 'id', path);
    final Object? rawName = map['name'];
    if (rawName is! String) {
      throw LedgerBackupException('$path.name must be a string');
    }
    // Preserve exact stored names while rejecting blank names.
    final String name = rawName;
    if (name.trim().isEmpty) {
      throw LedgerBackupException('$path.name must not be blank');
    }
    if (name.runes.length > _maxKhataNameLength) {
      throw LedgerBackupException(
        '$path.name must be at most $_maxKhataNameLength characters',
      );
    }
    final int openingBalancePaise = _expectInt(
      map,
      'opening_balance_paise',
      path,
    );
    final String currency = _expectString(map, 'currency', path, maxLength: 8);
    if (currency != 'INR') {
      throw LedgerBackupException(
        '$path.currency must be INR in this version, not $currency',
      );
    }
    return _KhataRecord(
      id: id,
      name: name,
      openingBalancePaise: openingBalancePaise,
      currency: currency,
      sortOrder: _expectInt(map, 'sort_order', path),
      createdAt: _expectTimestamp(map, 'created_at', path),
      updatedAt: _expectTimestamp(map, 'updated_at', path),
      deletedAt: _expectNullableTimestamp(map, 'deleted_at', path),
    );
  }

  _TransactionRecord _parseTransaction(Object? value, String path) {
    final Map<String, Object?> map = _expectObject(value, path);
    _expectExactKeys(map, _transactionKeys, path);
    final String type = _expectString(map, 'type', path, maxLength: 16);
    if (type != 'income' && type != 'expense') {
      throw LedgerBackupException(
        '$path.type must be income or expense, not $type',
      );
    }
    final int amountPaise = _expectInt(map, 'amount_paise', path);
    if (amountPaise <= 0) {
      throw LedgerBackupException('$path.amount_paise must be positive');
    }
    final Object? rawCategory = map['category_id'];
    if (rawCategory is! String) {
      throw LedgerBackupException('$path.category_id must be a string');
    }
    final String categoryId = rawCategory;
    if (categoryId.trim().isEmpty) {
      throw LedgerBackupException('$path.category_id must not be blank');
    }
    if (categoryId.runes.length > _maxCategoryLength) {
      throw LedgerBackupException(
        '$path.category_id must be at most $_maxCategoryLength characters',
      );
    }
    // Preserve raw descriptions, including whitespace, empty string and null.
    final String? rawDescription = _expectNullableText(
      map,
      'description',
      path,
      maxLength: _maxDescriptionLength,
    );
    final String? description = rawDescription;
    return _TransactionRecord(
      id: _expectId(map, 'id', path),
      khataId: _expectId(map, 'khata_id', path),
      type: type,
      amountPaise: amountPaise,
      categoryId: categoryId,
      description: description,
      occurredAt: _expectTimestamp(map, 'occurred_at', path),
      noteSessionId: _expectNullableText(
        map,
        'note_session_id',
        path,
        maxLength: _maxIdLength,
      ),
      createdAt: _expectTimestamp(map, 'created_at', path),
      updatedAt: _expectTimestamp(map, 'updated_at', path),
      deletedAt: _expectNullableTimestamp(map, 'deleted_at', path),
    );
  }
}

/// A JSON object, or a clear exception naming [path].
Map<String, Object?> _expectObject(Object? value, String path) {
  if (value is! Map<String, Object?>) {
    throw LedgerBackupException('$path must be a JSON object');
  }
  return value;
}

/// Both directions of the field-set check: an extra field is as much an error
/// as a missing one, so a file from a different writer cannot slip through.
void _expectExactKeys(
  Map<String, Object?> map,
  Set<String> expected,
  String path,
) {
  for (final String key in map.keys) {
    if (!expected.contains(key)) {
      throw LedgerBackupException('$path has unexpected field $key');
    }
  }
  for (final String key in expected) {
    if (!map.containsKey(key)) {
      throw LedgerBackupException('$path is missing field $key');
    }
  }
}

List<Object?> _expectList(Map<String, Object?> map, String key, String path) {
  final Object? value = map[key];
  if (value is! List<Object?>) {
    throw LedgerBackupException('$path.$key must be a JSON array');
  }
  return value;
}

/// A string of at most [maxLength] characters. Blank is rejected by default;
/// profile names opt in because the profile store allows clearing the name.
String _expectString(
  Map<String, Object?> map,
  String key,
  String path, {
  int? maxLength,
  bool allowBlank = false,
}) {
  final Object? value = map[key];
  if (value is! String) {
    throw LedgerBackupException('$path.$key must be a string');
  }
  if (!allowBlank && value.trim().isEmpty) {
    throw LedgerBackupException('$path.$key must not be blank');
  }
  if (maxLength != null && value.runes.length > maxLength) {
    throw LedgerBackupException(
      '$path.$key must be at most $maxLength characters',
    );
  }
  return value;
}

/// An optional free-text field: `null` (or absent-null) is fine, and a present
/// value may be any string within [maxLength] - including one that needs
/// trimming. Only the *type* is enforced here; `description` is the one field
/// with an extra rule, applied by the caller.
String? _expectNullableText(
  Map<String, Object?> map,
  String key,
  String path, {
  int? maxLength,
}) {
  final Object? value = map[key];
  if (value == null) return null;
  if (value is! String) {
    throw LedgerBackupException('$path.$key must be a string or null');
  }
  if (maxLength != null && value.runes.length > maxLength) {
    throw LedgerBackupException(
      '$path.$key must be at most $maxLength characters',
    );
  }
  return value;
}

/// An integer id: non-blank, not padded with whitespace, and short enough to be
/// a real client id rather than a blob.
String _expectId(Map<String, Object?> map, String key, String path) {
  final String value = _expectString(map, key, path, maxLength: _maxIdLength);
  if (value.trim() != value) {
    throw LedgerBackupException(
      '$path.$key must not start or end with whitespace',
    );
  }
  return value;
}

/// A JSON **integer**. `1000.0`, `1e3` and `"1000"` are all rejected: only an
/// `int` can carry paise without a rounding step.
int _expectInt(Map<String, Object?> map, String key, String path) {
  final Object? value = map[key];
  if (value is! int) {
    throw LedgerBackupException('$path.$key must be an integer');
  }
  return value;
}

String _expectTimestamp(Map<String, Object?> map, String key, String path) {
  final Object? value = map[key];
  if (value is! String) {
    throw LedgerBackupException('$path.$key must be a UTC timestamp');
  }
  return _checkTimestamp(value, '$path.$key');
}

String? _expectNullableTimestamp(
  Map<String, Object?> map,
  String key,
  String path,
) {
  if (map[key] == null) return null;
  return _expectTimestamp(map, key, path);
}

/// Validates one stored or supplied timestamp and returns it unchanged.
/// The accepted language is fixed (a UTC ISO-8601 string ending in `Z`,
/// checked against `DateTime.tryParse`), so returning the input verbatim -
/// instead of re-emitting it through `toIso8601String()` - keeps an export
/// byte-for-byte identical to the rows it was read from, whatever fraction
/// width the writer used, and an export can always be restored and
/// re-exported unchanged.
String _checkTimestamp(String value, String path) {
  if (!_utcTimestampPattern.hasMatch(value)) {
    throw LedgerBackupException(
      '$path must be a UTC ISO-8601 timestamp ending in Z, not $value',
    );
  }
  final DateTime? parsed = DateTime.tryParse(value);
  if (parsed == null ||
      !parsed.isUtc ||
      parsed.year != int.parse(value.substring(0, 4)) ||
      parsed.month != int.parse(value.substring(5, 7)) ||
      parsed.day != int.parse(value.substring(8, 10)) ||
      parsed.hour != int.parse(value.substring(11, 13)) ||
      parsed.minute != int.parse(value.substring(14, 16)) ||
      parsed.second != int.parse(value.substring(17, 19))) {
    throw LedgerBackupException('$path is not a valid timestamp: $value');
  }
  return value;
}

/// [_checkTimestamp] for a nullable column read from the database.
String? _readTimestamp(String? value, String path) {
  if (value == null) return null;
  return _checkTimestamp(value, path);
}

/// A JSON **boolean**: only `true`/`false`, never `0`/`1` or `"yes"`.
bool _expectBool(Map<String, Object?> map, String key, String path) {
  final Object? value = map[key];
  if (value is! bool) {
    throw LedgerBackupException('$path.$key must be true or false');
  }
  return value;
}

/// A known note denomination, in paise. Anything else - including another
/// integer - is rejected.
int _checkedDenomination(int value, String path) {
  if (!kAllDenominationsPaise.contains(value)) {
    throw LedgerBackupException(
      '$path must be a known note denomination in paise, not $value',
    );
  }
  return value;
}

int _asDenomination(Object? value, String path) {
  if (value is! int) {
    throw LedgerBackupException('$path must be an integer');
  }
  // The retired ₹2,000 note cannot be selected any more; a stored selection
  // repairs to the default instead of failing (or resurrecting) the note.
  if (value == kRetiredTwoThousandPaise) return kDefaultDenominationPaise;
  return _checkedDenomination(value, path);
}

/// A note quantity in 0...[kMaxNoteQuantity].
int _checkedQuantity(int value, String path) {
  if (value < 0 || value > kMaxNoteQuantity) {
    throw LedgerBackupException(
      '$path must be between 0 and $kMaxNoteQuantity, not $value',
    );
  }
  return value;
}

int _asQuantity(Object? value, String path) {
  if (value is! int) {
    throw LedgerBackupException('$path must be an integer');
  }
  return _checkedQuantity(value, path);
}

/// A counter row may only reference a khata that travels in the same file.
void _checkKhataRef(String khataId, Set<String> khataIds, String path) {
  if (!khataIds.contains(khataId)) {
    throw LedgerBackupException(
      '$path refers to khata $khataId, which is missing from this file',
    );
  }
}

/// The JSON array at [path].
List<Object?> _asList(Object? value, String path) {
  if (value is! List<Object?>) {
    throw LedgerBackupException('$path must be a JSON array');
  }
  return value;
}

/// The PNG/JPEG magic-byte check shared by export re-validation and restore,
/// and the 2 MiB cap. When [declaredType] is given the bytes must match it.
void _checkAvatar(
  Uint8List bytes,
  String path, {
  required String? declaredType,
}) {
  if (bytes.length > _maxAvatarBytes) {
    throw LedgerBackupException(
      '$path must be at most $_maxAvatarBytes bytes, not ${bytes.length}',
    );
  }
  final String? type = _avatarTypeOfOrNull(bytes);
  if (type == null) {
    throw LedgerBackupException('$path must be a PNG or JPEG image');
  }
  if (declaredType != null && declaredType != type) {
    throw LedgerBackupException(
      '$path is declared as $declaredType but the bytes are not',
    );
  }
}

/// The image type implied by the magic bytes, or null when it is neither a
/// PNG nor a JPEG.
String? _avatarTypeOfOrNull(Uint8List bytes) {
  const List<int> png = <int>[137, 80, 78, 71, 13, 10, 26, 10];
  final bool isPng =
      bytes.length >= png.length &&
      Iterable<int>.generate(png.length).every((i) => bytes[i] == png[i]);
  final bool isJpeg =
      bytes.length >= 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff;
  if (isPng) return _avatarTypePng;
  if (isJpeg) return _avatarTypeJpeg;
  return null;
}

/// [_avatarTypeOfOrNull] for bytes already checked by [_checkAvatar].
String _avatarTypeOf(Uint8List bytes) => _avatarTypeOfOrNull(bytes)!;

/// The stored profile, validated exactly as restore would require it.
_ProfileRecord? _parseProfile(Object? value, String path) {
  if (value == null) return null;
  final Map<String, Object?> map = _expectObject(value, path);
  _expectExactKeys(map, _profileKeys, path);
  final String name = _expectString(
    map,
    'name',
    path,
    maxLength: _maxProfileNameLength,
    allowBlank: true,
  );
  final Object? avatar = map['avatar'];
  if (avatar == null) return _ProfileRecord(name: name);
  final Map<String, Object?> avatarMap = _expectObject(avatar, '$path.avatar');
  _expectExactKeys(avatarMap, _avatarKeys, '$path.avatar');
  final Object? typeValue = avatarMap['type'];
  if (typeValue != _avatarTypePng && typeValue != _avatarTypeJpeg) {
    throw LedgerBackupException('$path.avatar.type must be png or jpeg');
  }
  final String type = typeValue! as String;
  final Object? encoded = avatarMap['base64'];
  if (encoded is! String || encoded.isEmpty) {
    throw LedgerBackupException(
      '$path.avatar.base64 must be a non-empty string',
    );
  }
  final Uint8List bytes;
  try {
    bytes = base64Decode(encoded);
  } on FormatException {
    throw LedgerBackupException('$path.avatar.base64 is not valid base64');
  }
  _checkAvatar(bytes, '$path.avatar', declaredType: type);
  return _ProfileRecord(name: name, avatarBytes: bytes, avatarType: type);
}

/// One custom category, with the checks the store applies (name 1...30
/// characters, appearance indexes inside the six-entry sets).
_CustomCategoryRecord _categoryRecord({
  required String id,
  required String name,
  required int iconIndex,
  required int colorIndex,
  required bool archived,
  required String path,
}) {
  if (id.trim().isEmpty || id.trim() != id || id.runes.length > _maxIdLength) {
    throw LedgerBackupException(
      '$path.id must be a non-blank id of at most $_maxIdLength characters',
    );
  }
  if (name.trim().isEmpty) {
    throw LedgerBackupException('$path.name must not be blank');
  }
  if (name.runes.length > _maxCustomCategoryNameLength) {
    throw LedgerBackupException(
      '$path.name must be at most $_maxCustomCategoryNameLength characters',
    );
  }
  if (iconIndex < 0 || iconIndex >= _customCategoryAppearanceCount) {
    throw LedgerBackupException(
      '$path.icon_index must be between 0 and ${_customCategoryAppearanceCount - 1}',
    );
  }
  if (colorIndex < 0 || colorIndex >= _customCategoryAppearanceCount) {
    throw LedgerBackupException(
      '$path.color_index must be between 0 and ${_customCategoryAppearanceCount - 1}',
    );
  }
  return _CustomCategoryRecord(
    id: id,
    name: name,
    iconIndex: iconIndex,
    colorIndex: colorIndex,
    archived: archived,
  );
}

/// The category list of a v2 file, archived rows included. Ids must be
/// unique.
List<_CustomCategoryRecord> _parseCustomCategories(Object? value, String path) {
  final List<Object?> items = _asList(value, path);
  final Set<String> ids = <String>{};
  final List<_CustomCategoryRecord> categories = <_CustomCategoryRecord>[
    for (int i = 0; i < items.length; i++)
      _parseCustomCategory(items[i], '$path[$i]', ids),
  ];
  return categories;
}

_CustomCategoryRecord _parseCustomCategory(
  Object? value,
  String path,
  Set<String> ids,
) {
  final Map<String, Object?> map = _expectObject(value, path);
  _expectExactKeys(map, _customCategoryKeys, path);
  final String id = _expectId(map, 'id', path);
  final Object? rawName = map['name'];
  if (rawName is! String) {
    throw LedgerBackupException('$path.name must be a string');
  }
  final _CustomCategoryRecord record = _categoryRecord(
    id: id,
    name: rawName,
    iconIndex: _expectInt(map, 'icon_index', path),
    colorIndex: _expectInt(map, 'color_index', path),
    archived: _expectBool(map, 'archived', path),
    path: path,
  );
  if (!ids.add(record.id)) {
    throw LedgerBackupException('Duplicate custom category id ${record.id}');
  }
  return record;
}

/// The counter section of a v2 file. [khataIds] are the khata ids the file
/// already carries; a counter row pointing anywhere else rejects the file.
_CounterBackup _parseNoteCounter(
  Object? value,
  String path,
  Set<String> khataIds,
) {
  final Map<String, Object?> map = _expectObject(value, path);
  _expectExactKeys(map, _noteCounterKeys, path);
  return _CounterBackup(
    quantities: _parseQuantityList(
      _asList(map['quantities'], '$path.quantities'),
      '$path.quantities',
      khataIds,
    ),
    state: _parseStateList(
      _asList(map['state'], '$path.state'),
      '$path.state',
      khataIds,
    ),
    savedSessions: _parseSessionList(
      _asList(map['saved_sessions'], '$path.saved_sessions'),
      '$path.saved_sessions',
      khataIds,
    ),
  );
}

List<_CounterQuantityRecord> _parseQuantityList(
  List<Object?> items,
  String path,
  Set<String> khataIds,
) {
  final Set<String> seen = <String>{};
  final List<_CounterQuantityRecord> records = <_CounterQuantityRecord>[];
  for (int i = 0; i < items.length; i++) {
    final _CounterQuantityRecord? record = _parseQuantityItem(
      items[i],
      '$path[$i]',
      khataIds,
      seen,
    );
    // A retired-denomination row is dropped (repaired away), not restored.
    if (record != null) records.add(record);
  }
  return records;
}

/// Parses one quantity row. Returns `null` for a row whose denomination is
/// the retired ₹2,000 note, which this version repairs away -
/// it must never reach the database, kept or silently ignored.
_CounterQuantityRecord? _parseQuantityItem(
  Object? value,
  String path,
  Set<String> khataIds,
  Set<String> seen,
) {
  final Map<String, Object?> map = _expectObject(value, path);
  _expectExactKeys(map, _counterQuantityKeys, path);
  final String khataId = _expectId(map, 'khata_id', path);
  final Object? denominationRaw = map['denomination_paise'];
  if (denominationRaw is int && denominationRaw == kRetiredTwoThousandPaise) {
    return null;
  }
  _checkKhataRef(khataId, khataIds, '$path.khata_id');
  final int denominationPaise = _asDenomination(
    map['denomination_paise'],
    '$path.denomination_paise',
  );
  if (!seen.add('$khataId:$denominationPaise')) {
    throw LedgerBackupException(
      'Duplicate counter quantity for khata $khataId, denomination '
      '$denominationPaise',
    );
  }
  return _CounterQuantityRecord(
    khataId: khataId,
    denominationPaise: denominationPaise,
    quantity: _asQuantity(map['quantity'], '$path.quantity'),
    updatedAt: _expectTimestamp(map, 'updated_at', path),
  );
}

List<_CounterStateRecord> _parseStateList(
  List<Object?> items,
  String path,
  Set<String> khataIds,
) {
  final Set<String> seen = <String>{};
  return <_CounterStateRecord>[
    for (int i = 0; i < items.length; i++)
      _parseStateItem(items[i], '$path[$i]', khataIds, seen),
  ];
}

_CounterStateRecord _parseStateItem(
  Object? value,
  String path,
  Set<String> khataIds,
  Set<String> seen,
) {
  final Map<String, Object?> map = _expectObject(value, path);
  _expectExactKeys(map, _counterStateKeys, path);
  final String khataId = _expectId(map, 'khata_id', path);
  _checkKhataRef(khataId, khataIds, '$path.khata_id');
  // Required to be a real JSON boolean; the retired flag repairs away to
  // false in the record below.
  _expectBool(map, 'show_two_thousand', path);
  if (!seen.add(khataId)) {
    throw LedgerBackupException('Duplicate counter state for khata $khataId');
  }
  return _CounterStateRecord(
    khataId: khataId,
    selectedDenominationPaise: _asDenomination(
      map['selected_denomination_paise'],
      '$path.selected_denomination_paise',
    ),
    // Required to be a real JSON boolean; the retired flag repairs away.
    showTwoThousand: false,
    updatedAt: _expectTimestamp(map, 'updated_at', path),
  );
}

List<_SavedSessionRecord> _parseSessionList(
  List<Object?> items,
  String path,
  Set<String> khataIds,
) {
  final Set<String> ids = <String>{};
  return <_SavedSessionRecord>[
    for (int i = 0; i < items.length; i++)
      _parseSessionItem(items[i], '$path[$i]', khataIds, ids),
  ];
}

_SavedSessionRecord _parseSessionItem(
  Object? value,
  String path,
  Set<String> khataIds,
  Set<String> ids,
) {
  final Map<String, Object?> map = _expectObject(value, path);
  _expectExactKeys(map, _savedSessionKeys, path);
  // Required to be a real JSON boolean; the retired flag repairs away to
  // false in the record below.
  _expectBool(map, 'show_two_thousand', path);
  final String id = _expectId(map, 'id', path);
  if (!ids.add(id)) {
    throw LedgerBackupException('Duplicate saved session id $id');
  }
  final String khataId = _expectId(map, 'khata_id', path);
  _checkKhataRef(khataId, khataIds, '$path.khata_id');
  return _SavedSessionRecord(
    id: id,
    khataId: khataId,
    savedAt: _expectTimestamp(map, 'saved_at', path),
    quantities: _sessionQuantitiesOf(map['quantities'], '$path.quantities'),
    selectedDenominationPaise: _asDenomination(
      map['selected_denomination_paise'],
      '$path.selected_denomination_paise',
    ),
    // Required to be a real JSON boolean; the retired flag repairs away.
    showTwoThousand: false,
  );
}

/// A saved session's quantities: a JSON object keyed by denomination in paise
/// (decimal), every value an integer in 0...[kMaxNoteQuantity].
Map<int, int> _sessionQuantitiesOf(Object? value, String path) {
  final Map<String, Object?> map = _expectObject(value, path);
  final Map<int, int> quantities = <int, int>{};
  for (final MapEntry<String, Object?> entry in map.entries) {
    final int? denomination = int.tryParse(entry.key);
    if (denomination == null) {
      throw LedgerBackupException(
        '$path has a non-integer denomination ${entry.key}',
      );
    }
    // A retired ₹2,000 entry is dropped (repaired away), not restored.
    if (denomination == kRetiredTwoThousandPaise) continue;
    _checkedDenomination(denomination, '$path.${entry.key}');
    final Object? rawQuantity = entry.value;
    if (rawQuantity is! int) {
      throw LedgerBackupException('$path.${entry.key} must be an integer');
    }
    _checkedQuantity(rawQuantity, '$path.${entry.key}');
    quantities[denomination] = rawQuantity;
  }
  return quantities;
}

/// [_sessionQuantitiesOf] fed from the stored `quantities_json` TEXT column.
Map<int, int> _sessionQuantitiesFromJson(String json, String path) {
  Object? decoded;
  try {
    decoded = jsonDecode(json);
  } on FormatException catch (error) {
    throw LedgerBackupException(
      '$path.quantities_json is not valid JSON: ${error.message}',
    );
  }
  return _sessionQuantitiesOf(decoded, '$path.quantities_json');
}

/// The counter store keeps quantities as a JSON object keyed by denomination
/// in paise - the same shape this writes.
String _encodeSessionQuantities(Map<int, int> quantities) =>
    jsonEncode(<String, int>{
      for (final MapEntry<int, int> entry in quantities.entries)
        entry.key.toString(): entry.value,
    });

/// A `show_two_thousand` column stored as 0/1, checked before it is trusted.
bool _checkedFlag(int value, String path) {
  if (value != 0 && value != 1) {
    throw LedgerBackupException('$path must be 0 or 1, not $value');
  }
  return value == 1;
}

/// Validates the stored 0/1 `show_two_thousand` flag exactly like
/// [_checkedFlag], then returns `false`: the flag is retired with the ₹2,000
/// note, and a backup written from any phone - repaired or not yet repaired -
/// never carries it.
bool _retiredFlag(int value, String path) {
  _checkedFlag(value, path);
  return false;
}

/// Export-side re-checks, so a stored row that restore would reject fails the
/// export loudly instead of being written into an unusable backup.
_CustomCategoryRecord _checkedCategoryRow({
  required String id,
  required String name,
  required int iconIndex,
  required int colorIndex,
  required int archived,
  required String path,
}) => _categoryRecord(
  id: id,
  name: name,
  iconIndex: iconIndex,
  colorIndex: colorIndex,
  archived: _checkedFlag(archived, '$path.archived'),
  path: path,
);

_CounterQuantityRecord? _checkedQuantityRow({
  required String khataId,
  required int denominationPaise,
  required int quantity,
  required String updatedAt,
  required Set<String> khataIds,
  required String path,
}) {
  _checkKhataRef(khataId, khataIds, '$path.khata_id');
  // The retired ₹2,000 note is never written into a new backup; a stale
  // stored row is dropped (the next counter load removes it from the phone).
  if (denominationPaise == kRetiredTwoThousandPaise) return null;
  return _CounterQuantityRecord(
    khataId: khataId,
    denominationPaise: _checkedDenomination(
      denominationPaise,
      '$path.denomination_paise',
    ),
    quantity: _checkedQuantity(quantity, '$path.quantity'),
    updatedAt: _checkTimestamp(updatedAt, '$path.updated_at'),
  );
}

_CounterStateRecord _checkedStateRow({
  required String khataId,
  required int selectedDenominationPaise,
  required int showTwoThousand,
  required String updatedAt,
  required Set<String> khataIds,
  required String path,
}) {
  _checkKhataRef(khataId, khataIds, '$path.khata_id');
  return _CounterStateRecord(
    khataId: khataId,
    selectedDenominationPaise:
        selectedDenominationPaise == kRetiredTwoThousandPaise
        ? kDefaultDenominationPaise
        : _checkedDenomination(
            selectedDenominationPaise,
            '$path.selected_denomination_paise',
          ),
    // Validated as 0/1 (a stray non-0/1 still fails the export loudly),
    // then repaired away: a fresh backup never carries the retired flag.
    showTwoThousand: _retiredFlag(showTwoThousand, '$path.show_two_thousand'),
    updatedAt: _checkTimestamp(updatedAt, '$path.updated_at'),
  );
}

_SavedSessionRecord _checkedSessionRow({
  required String id,
  required String khataId,
  required String savedAt,
  required String quantitiesJson,
  required int selectedDenominationPaise,
  required int showTwoThousand,
  required Set<String> khataIds,
  required String path,
}) {
  _checkKhataRef(khataId, khataIds, '$path.khata_id');
  if (id.trim().isEmpty || id.trim() != id || id.runes.length > _maxIdLength) {
    throw LedgerBackupException(
      '$path.id must be a non-blank id of at most $_maxIdLength characters',
    );
  }
  return _SavedSessionRecord(
    id: id,
    khataId: khataId,
    savedAt: _checkTimestamp(savedAt, '$path.saved_at'),
    quantities: _sessionQuantitiesFromJson(quantitiesJson, path),
    selectedDenominationPaise:
        selectedDenominationPaise == kRetiredTwoThousandPaise
        ? kDefaultDenominationPaise
        : _checkedDenomination(
            selectedDenominationPaise,
            '$path.selected_denomination_paise',
          ),
    // Validated as 0/1, then repaired away.
    showTwoThousand: _retiredFlag(showTwoThousand, '$path.show_two_thousand'),
  );
}
