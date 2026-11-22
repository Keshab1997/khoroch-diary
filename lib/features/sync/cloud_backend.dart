/// Abstract cloud backend contract and wire-free row models for Khoroch Diary B5.
///
/// Nothing in this library imports Supabase or any HTTP client: [SyncEngine]
/// and the sync widgets depend only on [CloudBackend], while the concrete
/// adapter lives outside this layer and is wired at app start-up.
///
/// Rules shared with `docs/spec/data-model.md`:
/// * Money is integer paise (`int`), never `double`.
/// * Every timestamp is normalized to UTC (`toUtc()`).
/// * Deletes and khata archives are tombstones (`deletedAt != null`), never
///   hard deletes.
library;

/// Authenticated cloud account identity.
final class CloudUser {
  CloudUser({required String id, required String email})
    : id = _requireNonBlank(id, 'id'),
      email = _requireNonBlank(email, 'email');

  final String id;
  final String email;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CloudUser && other.id == id && other.email == email;

  @override
  int get hashCode => Object.hash(id, email);

  @override
  String toString() => 'CloudUser(id: $id, email: $email)';
}

/// Direction of a synced transaction, matching remote `transactions.type`.
enum CloudTransactionType {
  income('income'),
  expense('expense');

  const CloudTransactionType(this.wireValue);

  final String wireValue;

  static CloudTransactionType fromWire(String value) {
    return switch (value) {
      'income' => CloudTransactionType.income,
      'expense' => CloudTransactionType.expense,
      _ => throw ArgumentError.value(
        value,
        'value',
        'Transaction type must be income or expense',
      ),
    };
  }
}

/// One row of the remote `khatas` table:
/// `(user_id, id, name, opening_balance_paise, currency, sort_order,
/// created_at, updated_at, deleted_at, server_updated_at)`.
///
/// On outbound pushes, [userId] and [serverUpdatedAt] may be `null` before the
/// server stamps them; rows returned by the server carry both fields.
final class CloudKhataRow {
  CloudKhataRow({
    this.userId,
    required String id,
    required String name,
    required this.openingBalancePaise,
    this.currency = 'INR',
    this.sortOrder = 0,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? deletedAt,
    DateTime? serverUpdatedAt,
  }) : id = _requireNonBlank(id, 'id'),
       name = _requireNonBlank(name, 'name'),
       createdAt = createdAt.toUtc(),
       updatedAt = updatedAt.toUtc(),
       deletedAt = deletedAt?.toUtc(),
       serverUpdatedAt = serverUpdatedAt?.toUtc() {
    final String? uid = userId;
    if (uid != null && uid.trim().isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'must not be blank');
    }
    if (currency.trim().length != 3) {
      throw ArgumentError.value(
        currency,
        'currency',
        'must be a 3-letter currency code',
      );
    }
  }

  final String? userId;
  final String id;
  final String name;
  final int openingBalancePaise;
  final String currency;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final DateTime? serverUpdatedAt;

  bool get isArchived => deletedAt != null;

  /// Compares all client-owned ledger columns, ignoring [userId] and
  /// [serverUpdatedAt] so the engine can tell whether the server accepted the
  /// pushed payload verbatim or returned a newer server-stored row.
  bool sameContentAs(CloudKhataRow other) =>
      id == other.id &&
      name == other.name &&
      openingBalancePaise == other.openingBalancePaise &&
      currency == other.currency &&
      sortOrder == other.sortOrder &&
      createdAt == other.createdAt &&
      updatedAt == other.updatedAt &&
      deletedAt == other.deletedAt;

  CloudKhataRow copyWith({
    String? userId,
    String? id,
    String? name,
    int? openingBalancePaise,
    String? currency,
    int? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? deletedAt = _sentinel,
    Object? serverUpdatedAt = _sentinel,
  }) {
    return CloudKhataRow(
      userId: userId ?? this.userId,
      id: id ?? this.id,
      name: name ?? this.name,
      openingBalancePaise: openingBalancePaise ?? this.openingBalancePaise,
      currency: currency ?? this.currency,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: identical(deletedAt, _sentinel)
          ? this.deletedAt
          : deletedAt as DateTime?,
      serverUpdatedAt: identical(serverUpdatedAt, _sentinel)
          ? this.serverUpdatedAt
          : serverUpdatedAt as DateTime?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CloudKhataRow &&
          other.userId == userId &&
          other.id == id &&
          other.name == name &&
          other.openingBalancePaise == openingBalancePaise &&
          other.currency == currency &&
          other.sortOrder == sortOrder &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt &&
          other.deletedAt == deletedAt &&
          other.serverUpdatedAt == serverUpdatedAt;

  @override
  int get hashCode => Object.hash(
    userId,
    id,
    name,
    openingBalancePaise,
    currency,
    sortOrder,
    createdAt,
    updatedAt,
    deletedAt,
    serverUpdatedAt,
  );

  @override
  String toString() =>
      'CloudKhataRow(id: $id, name: $name, '
      'openingBalancePaise: $openingBalancePaise, '
      'updatedAt: $updatedAt, deletedAt: $deletedAt)';
}

/// One row of the remote `transactions` table:
/// `(user_id, id, khata_id, type, amount_paise, category_id, description,
/// occurred_at, note_session_id, created_at, updated_at, deleted_at,
/// server_updated_at)`.
final class CloudTransactionRow {
  CloudTransactionRow({
    this.userId,
    required String id,
    required String khataId,
    required this.type,
    required this.amountPaise,
    required String categoryId,
    this.description,
    required DateTime occurredAt,
    this.noteSessionId,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? deletedAt,
    DateTime? serverUpdatedAt,
  }) : id = _requireNonBlank(id, 'id'),
       khataId = _requireNonBlank(khataId, 'khataId'),
       categoryId = _requireNonBlank(categoryId, 'categoryId'),
       occurredAt = occurredAt.toUtc(),
       createdAt = createdAt.toUtc(),
       updatedAt = updatedAt.toUtc(),
       deletedAt = deletedAt?.toUtc(),
       serverUpdatedAt = serverUpdatedAt?.toUtc() {
    final String? uid = userId;
    if (uid != null && uid.trim().isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'must not be blank');
    }
    if (amountPaise <= 0) {
      throw ArgumentError.value(
        amountPaise,
        'amountPaise',
        'must be strictly positive paise',
      );
    }
    final String? desc = description;
    if (desc != null && desc.runes.length > 120) {
      throw ArgumentError.value(
        description,
        'description',
        'must be at most 120 characters',
      );
    }
  }

  final String? userId;
  final String id;
  final String khataId;
  final CloudTransactionType type;
  final int amountPaise;
  final String categoryId;
  final String? description;
  final DateTime occurredAt;
  final String? noteSessionId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final DateTime? serverUpdatedAt;

  bool get isDeleted => deletedAt != null;

  /// Compares all client-owned transaction columns, ignoring [userId] and
  /// [serverUpdatedAt].
  bool sameContentAs(CloudTransactionRow other) =>
      id == other.id &&
      khataId == other.khataId &&
      type == other.type &&
      amountPaise == other.amountPaise &&
      categoryId == other.categoryId &&
      description == other.description &&
      occurredAt == other.occurredAt &&
      noteSessionId == other.noteSessionId &&
      createdAt == other.createdAt &&
      updatedAt == other.updatedAt &&
      deletedAt == other.deletedAt;

  CloudTransactionRow copyWith({
    String? userId,
    String? id,
    String? khataId,
    CloudTransactionType? type,
    int? amountPaise,
    String? categoryId,
    Object? description = _sentinel,
    DateTime? occurredAt,
    Object? noteSessionId = _sentinel,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? deletedAt = _sentinel,
    Object? serverUpdatedAt = _sentinel,
  }) {
    return CloudTransactionRow(
      userId: userId ?? this.userId,
      id: id ?? this.id,
      khataId: khataId ?? this.khataId,
      type: type ?? this.type,
      amountPaise: amountPaise ?? this.amountPaise,
      categoryId: categoryId ?? this.categoryId,
      description: identical(description, _sentinel)
          ? this.description
          : description as String?,
      occurredAt: occurredAt ?? this.occurredAt,
      noteSessionId: identical(noteSessionId, _sentinel)
          ? this.noteSessionId
          : noteSessionId as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: identical(deletedAt, _sentinel)
          ? this.deletedAt
          : deletedAt as DateTime?,
      serverUpdatedAt: identical(serverUpdatedAt, _sentinel)
          ? this.serverUpdatedAt
          : serverUpdatedAt as DateTime?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CloudTransactionRow &&
          other.userId == userId &&
          other.id == id &&
          other.khataId == khataId &&
          other.type == type &&
          other.amountPaise == amountPaise &&
          other.categoryId == categoryId &&
          other.description == description &&
          other.occurredAt == occurredAt &&
          other.noteSessionId == noteSessionId &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt &&
          other.deletedAt == deletedAt &&
          other.serverUpdatedAt == serverUpdatedAt;

  @override
  int get hashCode => Object.hash(
    userId,
    id,
    khataId,
    type,
    amountPaise,
    categoryId,
    description,
    occurredAt,
    noteSessionId,
    createdAt,
    updatedAt,
    deletedAt,
    serverUpdatedAt,
  );

  @override
  String toString() =>
      'CloudTransactionRow(id: $id, khataId: $khataId, '
      'type: ${type.wireValue}, amountPaise: $amountPaise, '
      'updatedAt: $updatedAt, deletedAt: $deletedAt)';
}

/// Incremental pull response from [CloudBackend.fetchChanges].
///
/// [khatas] and [transactions] contain every row whose `server_updated_at` is
/// strictly after the supplied `since` timestamp (or all rows when `since` is
/// `null`). [cursor] is the new high-water mark to store for the next pull, or
/// `null` when no rows have ever been observed and no cursor existed before.
final class CloudChangeSet {
  CloudChangeSet({
    required Iterable<CloudKhataRow> khatas,
    required Iterable<CloudTransactionRow> transactions,
    DateTime? cursor,
  }) : khatas = List<CloudKhataRow>.unmodifiable(khatas),
       transactions = List<CloudTransactionRow>.unmodifiable(transactions),
       cursor = cursor?.toUtc();

  final List<CloudKhataRow> khatas;
  final List<CloudTransactionRow> transactions;
  final DateTime? cursor;
}

/// Thrown by a [CloudBackend] when the device has no network connectivity.
class CloudOfflineException implements Exception {
  const CloudOfflineException([this.message = 'Device is offline']);

  final String message;

  @override
  String toString() => 'CloudOfflineException: $message';
}

/// Injectable remote store and auth boundary for cloud backup & sync.
abstract class CloudBackend {
  /// Currently signed-in user, or `null` in local-only mode.
  CloudUser? get currentUser;

  /// Emits whenever the signed-in user changes (`null` on sign-out).
  Stream<CloudUser?> get userChanges;

  /// Launches Google sign-in. Returns the signed-in [CloudUser], or `null`
  /// when the user cancels the flow without signing in.
  Future<CloudUser?> signInWithGoogle();

  /// Signs out of the cloud account without touching local data.
  Future<void> signOut();

  /// Upserts a batch of khatas and returns the rows as stored on the server
  /// (including any row where the server kept its newer copy).
  Future<List<CloudKhataRow>> upsertKhatas(List<CloudKhataRow> rows);

  /// Upserts a batch of transactions and returns the rows as stored on the
  /// server (including any row where the server kept its newer copy).
  Future<List<CloudTransactionRow>> upsertTransactions(
    List<CloudTransactionRow> rows,
  );

  /// Returns khatas and transactions whose `serverUpdatedAt` is after [since]
  /// (or all rows when [since] is `null`), along with the new cursor.
  Future<CloudChangeSet> fetchChanges(DateTime? since);
}

const Object _sentinel = Object();

String _requireNonBlank(String value, String field) {
  final String trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(value, field, 'must not be blank');
  }
  return trimmed;
}
