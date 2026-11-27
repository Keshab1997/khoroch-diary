/// B1 uses an in-memory preview ledger. B2 replaces it with the Drift database
/// described in docs/spec/data-model.md; the totals formula stays the same.
enum EntryType { expense, income }

class LedgerEntry {
  const LedgerEntry({
    required this.title,
    required this.category,
    required this.at,
    required this.amountPaise,
    this.type = EntryType.expense,
    this.id,
    this.description,
  });

  /// Display label. For an entry read from the database this is the stored
  /// description, falling back to the category when the description is empty or
  /// null - a display-only fallback, never the stored data.
  final String title;
  final String category;
  final DateTime at;
  final int amountPaise;
  final EntryType type;

  /// The persisted transaction id, present only on rows read from the database.
  ///
  /// Edit/delete/restore act on this id. Preview and seed entries leave it
  /// null, so a preview row can never be mistaken for a stored one.
  final String? id;

  /// The stored description exactly as persisted: `null` when the row has no
  /// description, and never the category substituted in. [title] is the
  /// display fallback for this value.
  final String? description;
}

class LedgerSummary {
  const LedgerSummary({
    required this.openingBalancePaise,
    required this.entries,
  });

  final int openingBalancePaise;
  final List<LedgerEntry> entries;

  /// Income (opening balance included), expense and what remains, summed in a
  /// single pass over [entries]. A screen that shows more than one of the
  /// figures reads this once per build instead of walking the whole history
  /// for each of them.
  LedgerSummaryTotals get totals {
    int incomePaise = openingBalancePaise;
    int expensePaise = 0;
    for (final LedgerEntry entry in entries) {
      switch (entry.type) {
        case EntryType.income:
          incomePaise += entry.amountPaise;
        case EntryType.expense:
          expensePaise += entry.amountPaise;
      }
    }
    return LedgerSummaryTotals(
      totalIncomePaise: incomePaise,
      totalExpensePaise: expensePaise,
    );
  }

  int get totalIncomePaise => totals.totalIncomePaise;

  int get totalExpensePaise => totals.totalExpensePaise;

  int get remainingPaise => totals.remainingPaise;

  /// Home shows the newest four rows; `View All` opens the full list (D5).
  ///
  /// Home asks on every rebuild and the history only grows, so this picks the
  /// newest [limit] rows in one pass instead of copying and sorting all of
  /// them. Rows with the same timestamp keep the order they have in [entries].
  List<LedgerEntry> recent([int limit = 4]) {
    RangeError.checkNotNegative(limit, 'limit');
    final List<LedgerEntry> newest = <LedgerEntry>[];
    for (final LedgerEntry entry in entries) {
      int slot = newest.length;
      while (slot > 0 && entry.at.isAfter(newest[slot - 1].at)) {
        slot--;
      }
      if (slot >= limit) {
        continue;
      }
      newest.insert(slot, entry);
      if (newest.length > limit) {
        newest.removeLast();
      }
    }
    return newest.toList(growable: false);
  }
}

/// The three figures a ledger screen shows, from one pass over a
/// [LedgerSummary]. [totalIncomePaise] already includes the opening balance.
class LedgerSummaryTotals {
  const LedgerSummaryTotals({
    required this.totalIncomePaise,
    required this.totalExpensePaise,
  });

  final int totalIncomePaise;
  final int totalExpensePaise;

  int get remainingPaise => totalIncomePaise - totalExpensePaise;
}

/// Seed reproduces the numbers in docs/design/ui-preview.png exactly:
/// ₹10,000 income, ₹3,580 expense, ₹6,420 remaining.
const int kSeedOpeningBalancePaise = 1000000;

final List<LedgerEntry> kSeedEntries = <LedgerEntry>[
  LedgerEntry(
    title: 'Grocery Shopping',
    category: 'Shopping',
    at: DateTime(2026, 11, 19, 20, 30),
    amountPaise: 120000,
  ),
  LedgerEntry(
    title: 'Lunch with Friends',
    category: 'Food',
    at: DateTime(2026, 11, 19, 13, 15),
    amountPaise: 58000,
  ),
  LedgerEntry(
    title: 'Mobile Recharge',
    category: 'Bills',
    at: DateTime(2026, 11, 19, 10, 20),
    amountPaise: 19900,
  ),
  LedgerEntry(
    title: 'Gift for Mom',
    category: 'Gifts',
    at: DateTime(2026, 11, 18, 19, 40),
    amountPaise: 100000,
  ),
  // Older entries account for the ₹601 that the four visible rows do not.
  LedgerEntry(
    title: 'Bus Fare',
    category: 'Travel',
    at: DateTime(2026, 11, 17, 9, 5),
    amountPaise: 30100,
  ),
  LedgerEntry(
    title: 'Tea with Team',
    category: 'Food',
    at: DateTime(2026, 11, 16, 17, 20),
    amountPaise: 30000,
  ),
];
