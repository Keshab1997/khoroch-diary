/// Dependency-free ledger domain rules for Khoroch Diary (B2 First).
///
/// This file is the pure, in-memory half of the ledger: it holds no database,
/// no network, no Flutter imports and no seeded rows. It mirrors
/// `docs/spec/data-model.md`:
///
/// * money is **integer paise**, never `double`;
/// * an amount is always **strictly positive** and direction comes from
///   [LedgerKind];
/// * ids are client-generated strings, so a row can exist before it has ever
///   been synced;
/// * timestamps are UTC instants;
/// * deletes are tombstones (`deletedAt != null`), never row removal.
///
/// Totals follow the spec formulas exactly:
///
/// ```text
/// totalIncomePaise  = openingBalancePaise + Σ(amountPaise where kind == income)
/// totalExpensePaise =                        Σ(amountPaise where kind == expense)
/// remainingPaise    = totalIncomePaise - totalExpensePaise
/// ```
///
/// Only non-deleted transactions of the requested khata take part. Ordering
/// and ties are resolved deterministically so equal inputs always produce
/// equal output.
library;

/// The direction of a [LedgerTransaction].
///
/// The amount itself is always positive; this enum says which side of the
/// ledger it belongs to.
enum LedgerKind {
  income,
  expense;

  /// Whether this kind adds to the ledger balance.
  bool get isIncome => this == LedgerKind.income;

  /// Whether this kind subtracts from the ledger balance.
  bool get isExpense => this == LedgerKind.expense;
}

/// Longest description the ledger accepts, in characters.
const int kLedgerDescriptionMaxLength = 120;

/// One immutable, validated income or expense row.
///
/// Constructing is the only way to get an instance, and the constructor
/// rejects anything the spec forbids, so every `LedgerTransaction` in memory is
/// valid by construction. Instances are immutable: changing a row means
/// creating a new one (an edit appends a corrected row and tombstones the old
/// one, keeping history).
class LedgerTransaction {
  /// Validates and normalizes one transaction.
  ///
  /// * [id] and [khataId] must be non-blank client-supplied strings.
  /// * [amountPaise] must be a strictly positive integer number of paise.
  /// * [category] must be non-blank.
  /// * [description] is optional; when present it must contain something and
  ///   be at most [kLedgerDescriptionMaxLength] characters.
  /// * [occurredAt], [createdAt] and [updatedAt] are stored as UTC instants;
  ///   any local `DateTime` is converted with `toUtc()`.
  /// * [updatedAt] may not precede [createdAt]; a tombstone [deletedAt] may not
  ///   precede [createdAt] either.
  ///
  /// Throws [ArgumentError] when a value is invalid.
  factory LedgerTransaction({
    required String id,
    required String khataId,
    required LedgerKind kind,
    required int amountPaise,
    required String category,
    required DateTime occurredAt,
    required DateTime createdAt,
    required DateTime updatedAt,
    String? description,
    DateTime? deletedAt,
  }) {
    final String validId = _requireToken(id, 'id');
    final String validKhataId = _requireToken(khataId, 'khataId');
    final String validCategory = _requireToken(category, 'category');

    if (amountPaise <= 0) {
      throw ArgumentError.value(
        amountPaise,
        'amountPaise',
        'must be a strictly positive integer number of paise',
      );
    }

    final String? validDescription = _validateDescription(description);

    final DateTime validCreatedAt = createdAt.toUtc();
    final DateTime validUpdatedAt = updatedAt.toUtc();
    final DateTime validOccurredAt = occurredAt.toUtc();
    final DateTime? validDeletedAt = deletedAt?.toUtc();

    if (validUpdatedAt.isBefore(validCreatedAt)) {
      throw ArgumentError.value(
        updatedAt,
        'updatedAt',
        'must not be before createdAt',
      );
    }
    if (validDeletedAt != null && validDeletedAt.isBefore(validCreatedAt)) {
      throw ArgumentError.value(
        deletedAt,
        'deletedAt',
        'must not be before createdAt',
      );
    }

    return LedgerTransaction._(
      id: validId,
      khataId: validKhataId,
      kind: kind,
      amountPaise: amountPaise,
      category: validCategory,
      description: validDescription,
      occurredAt: validOccurredAt,
      createdAt: validCreatedAt,
      updatedAt: validUpdatedAt,
      deletedAt: validDeletedAt,
    );
  }

  const LedgerTransaction._({
    required this.id,
    required this.khataId,
    required this.kind,
    required this.amountPaise,
    required this.category,
    required this.description,
    required this.occurredAt,
    required this.createdAt,
    required this.updatedAt,
    required this.deletedAt,
  });

  /// Client-supplied primary key, also the sync idempotency key.
  final String id;

  /// The ledger ([Khata]) this row belongs to.
  final String khataId;

  /// Whether the row is income or expense.
  final LedgerKind kind;

  /// Always strictly positive integer paise; direction comes from [kind].
  final int amountPaise;

  /// Category id (for example `Food`, `Bills`, `Income`).
  final String category;

  /// Optional user-facing note, at most [kLedgerDescriptionMaxLength]
  /// characters.
  final String? description;

  /// When the money actually moved, as chosen by the user (UTC).
  final DateTime occurredAt;

  /// Row creation instant (UTC).
  final DateTime createdAt;

  /// Last edit instant (UTC).
  final DateTime updatedAt;

  /// Tombstone instant (UTC), or `null` for a live row.
  final DateTime? deletedAt;

  /// Whether this row has been tombstoned and must be ignored by totals.
  bool get isDeleted => deletedAt != null;

  /// Whether this row still contributes to a ledger.
  bool get isLive => deletedAt == null;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is LedgerTransaction &&
        other.id == id &&
        other.khataId == khataId &&
        other.kind == kind &&
        other.amountPaise == amountPaise &&
        other.category == category &&
        other.description == description &&
        other.occurredAt == occurredAt &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        other.deletedAt == deletedAt;
  }

  @override
  int get hashCode => Object.hash(
    id,
    khataId,
    kind,
    amountPaise,
    category,
    description,
    occurredAt,
    createdAt,
    updatedAt,
    deletedAt,
  );

  @override
  String toString() {
    final String descriptionText = description == null
        ? ''
        : ', description: $description';
    final String deletedText = deletedAt == null
        ? ''
        : ', deletedAt: $deletedAt';
    return 'LedgerTransaction(id: $id, khataId: $khataId, '
        'kind: ${kind.name}, amountPaise: $amountPaise, '
        'category: $category, occurredAt: $occurredAt'
        '$descriptionText$deletedText)';
  }
}

/// Derived totals for one khata at one moment, plus its recent rows.
///
/// A value object: build it from a snapshot of transactions and read the
/// numbers. It never writes, stores, or recomputes lazily, so two totals built
/// from the same inputs are interchangeable.
///
/// [fromTransactions] ignores rows whose [LedgerTransaction.deletedAt] is set
/// and rows belonging to any other khata, so a caller can hand it the whole
/// local table without filtering first.
class LedgerTotals {
  /// Computes income (including [openingBalancePaise]), expense and remaining
  /// for [khataId] over the live rows in [transactions].
  ///
  /// [transactions] is read exactly once, so a lazy iterable is fine. The
  /// resulting [transactions] view is unmodifiable and sorted newest-first by
  /// [LedgerTransaction.occurredAt], with equal instants broken by ascending
  /// [LedgerTransaction.id] so the order never depends on input order.
  ///
  /// Throws [ArgumentError] if [khataId] is blank.
  factory LedgerTotals.fromTransactions({
    required int openingBalancePaise,
    required String khataId,
    required Iterable<LedgerTransaction> transactions,
  }) {
    final String validKhataId = _requireToken(khataId, 'khataId');

    final List<LedgerTransaction> visible = <LedgerTransaction>[
      for (final LedgerTransaction transaction in transactions)
        if (transaction.isLive && transaction.khataId == validKhataId)
          transaction,
    ]..sort(_newestFirst);

    int incomePaise = 0;
    int expensePaise = 0;
    for (final LedgerTransaction transaction in visible) {
      if (transaction.kind.isIncome) {
        incomePaise += transaction.amountPaise;
      } else {
        expensePaise += transaction.amountPaise;
      }
    }

    final int totalIncomePaise = openingBalancePaise + incomePaise;
    return LedgerTotals._(
      khataId: validKhataId,
      openingBalancePaise: openingBalancePaise,
      totalIncomePaise: totalIncomePaise,
      totalExpensePaise: expensePaise,
      remainingPaise: totalIncomePaise - expensePaise,
      transactions: List<LedgerTransaction>.unmodifiable(visible),
    );
  }

  const LedgerTotals._({
    required this.khataId,
    required this.openingBalancePaise,
    required this.totalIncomePaise,
    required this.totalExpensePaise,
    required this.remainingPaise,
    required this.transactions,
  });

  /// The khata these totals describe.
  final String khataId;

  /// The khata's starting balance in paise, included in [totalIncomePaise].
  final int openingBalancePaise;

  /// [openingBalancePaise] plus every live income amount.
  final int totalIncomePaise;

  /// Every live expense amount.
  final int totalExpensePaise;

  /// [totalIncomePaise] minus [totalExpensePaise]; may be negative.
  final int remainingPaise;

  /// Live, matching rows, newest first (see [fromTransactions]). Unmodifiable.
  final List<LedgerTransaction> transactions;

  /// The most recent rows, newest first.
  ///
  /// [limit] defaults to the four rows the Home screen shows. Pass `0` for an
  /// empty list; a negative [limit] throws [ArgumentError].
  List<LedgerTransaction> recent({int limit = 4}) {
    if (limit < 0) {
      throw ArgumentError.value(limit, 'limit', 'must not be negative');
    }
    if (limit == 0) {
      return const <LedgerTransaction>[];
    }
    return List<LedgerTransaction>.unmodifiable(transactions.take(limit));
  }

  /// Number of live rows in this khata.
  int get transactionCount => transactions.length;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is LedgerTotals &&
        other.khataId == khataId &&
        other.openingBalancePaise == openingBalancePaise &&
        other.totalIncomePaise == totalIncomePaise &&
        other.totalExpensePaise == totalExpensePaise &&
        other.remainingPaise == remainingPaise &&
        _sameRows(other.transactions, transactions);
  }

  @override
  int get hashCode => Object.hash(
    khataId,
    openingBalancePaise,
    totalIncomePaise,
    totalExpensePaise,
    remainingPaise,
    Object.hashAll(transactions),
  );

  @override
  String toString() {
    return 'LedgerTotals(khataId: $khataId, '
        'openingBalancePaise: $openingBalancePaise, '
        'totalIncomePaise: $totalIncomePaise, '
        'totalExpensePaise: $totalExpensePaise, '
        'remainingPaise: $remainingPaise, '
        'transactions: ${transactions.length})';
  }
}

/// Newest [LedgerTransaction.occurredAt] first, then ascending id.
///
/// The id tie-break keeps sorting stable for rows logged at the same instant,
/// which is common when a batch is created from one note-counting session.
int _newestFirst(LedgerTransaction a, LedgerTransaction b) {
  final int byOccurredAt = b.occurredAt.compareTo(a.occurredAt);
  if (byOccurredAt != 0) {
    return byOccurredAt;
  }
  return a.id.compareTo(b.id);
}

bool _sameRows(List<LedgerTransaction> a, List<LedgerTransaction> b) {
  if (a.length != b.length) {
    return false;
  }
  for (int index = 0; index < a.length; index++) {
    if (a[index] != b[index]) {
      return false;
    }
  }
  return true;
}

String _requireToken(String value, String field) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, field, 'must not be blank');
  }
  return value;
}

String? _validateDescription(String? description) {
  if (description == null) {
    return null;
  }
  if (description.trim().isEmpty) {
    throw ArgumentError.value(description, 'description', 'must not be blank');
  }
  if (description.runes.length > kLedgerDescriptionMaxLength) {
    throw ArgumentError.value(
      description,
      'description',
      'must be at most $kLedgerDescriptionMaxLength characters',
    );
  }
  return description;
}
