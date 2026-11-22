import 'package:flutter_test/flutter_test.dart';
import 'package:khoroch_diary/features/ledger/ledger_domain.dart';

/// Fixed UTC instants, so ordering assertions never depend on the clock.
DateTime at(int hour, [int minute = 0, int day = 19]) =>
    DateTime.utc(2026, 11, day, hour, minute);

/// A live expense in the default khata unless told otherwise.
LedgerTransaction expenseAt({
  required String id,
  required int amountPaise,
  required int hour,
  int minute = 0,
  int day = 19,
  String khataId = 'khata-a',
  String category = 'Food',
  String? description,
}) {
  return LedgerTransaction(
    id: id,
    khataId: khataId,
    kind: LedgerKind.expense,
    amountPaise: amountPaise,
    category: category,
    description: description,
    occurredAt: at(hour, minute, day),
    createdAt: at(9),
    updatedAt: at(9),
  );
}

/// A live income in the default khata unless told otherwise.
LedgerTransaction incomeAt({
  required String id,
  required int amountPaise,
  required int hour,
  int minute = 0,
  String khataId = 'khata-a',
  String category = 'Income',
}) {
  return LedgerTransaction(
    id: id,
    khataId: khataId,
    kind: LedgerKind.income,
    amountPaise: amountPaise,
    category: category,
    occurredAt: at(hour, minute),
    createdAt: at(9),
    updatedAt: at(9),
  );
}

/// The same row as [expenseAt] but tombstoned.
LedgerTransaction deleted(
  LedgerTransaction transaction, {
  DateTime? deletedAt,
}) {
  return LedgerTransaction(
    id: transaction.id,
    khataId: transaction.khataId,
    kind: transaction.kind,
    amountPaise: transaction.amountPaise,
    category: transaction.category,
    description: transaction.description,
    occurredAt: transaction.occurredAt,
    createdAt: transaction.createdAt,
    updatedAt: transaction.updatedAt,
    deletedAt: deletedAt ?? DateTime.utc(2026, 11, 20, 8),
  );
}

LedgerTotals totals(
  Iterable<LedgerTransaction> transactions, {
  int openingBalancePaise = 0,
  String khataId = 'khata-a',
}) {
  return LedgerTotals.fromTransactions(
    openingBalancePaise: openingBalancePaise,
    khataId: khataId,
    transactions: transactions,
  );
}

void main() {
  group('LedgerKind', () {
    test('has exactly income and expense, and reports direction', () {
      expect(LedgerKind.values, <LedgerKind>[
        LedgerKind.income,
        LedgerKind.expense,
      ]);
      expect(LedgerKind.income.isIncome, isTrue);
      expect(LedgerKind.income.isExpense, isFalse);
      expect(LedgerKind.expense.isExpense, isTrue);
      expect(LedgerKind.expense.isIncome, isFalse);
    });
  });

  group('LedgerTransaction accepts valid values', () {
    test('keeps every supplied field', () {
      final LedgerTransaction row = LedgerTransaction(
        id: 'txn-1',
        khataId: 'khata-a',
        kind: LedgerKind.expense,
        amountPaise: 58000,
        category: 'Food',
        description: 'Lunch with Friends',
        occurredAt: at(13, 15),
        createdAt: at(9),
        updatedAt: at(10),
        deletedAt: null,
      );

      expect(row.id, 'txn-1');
      expect(row.khataId, 'khata-a');
      expect(row.kind, LedgerKind.expense);
      expect(row.amountPaise, 58000);
      expect(row.category, 'Food');
      expect(row.description, 'Lunch with Friends');
      expect(row.occurredAt, DateTime.utc(2026, 11, 19, 13, 15));
      expect(row.createdAt, DateTime.utc(2026, 11, 19, 9));
      expect(row.updatedAt, DateTime.utc(2026, 11, 19, 10));
      expect(row.deletedAt, isNull);
      expect(row.isDeleted, isFalse);
      expect(row.isLive, isTrue);
    });

    test('accepts the smallest legal amount, one paise', () {
      expect(expenseAt(id: 'txn-1', amountPaise: 1, hour: 12).amountPaise, 1);
    });

    test('normalizes local timestamps to UTC', () {
      final DateTime local = DateTime(2026, 11, 19, 13, 15);
      final LedgerTransaction row = LedgerTransaction(
        id: 'txn-1',
        khataId: 'khata-a',
        kind: LedgerKind.income,
        amountPaise: 100000,
        category: 'Income',
        occurredAt: local,
        createdAt: local,
        updatedAt: local,
      );

      expect(row.occurredAt.isUtc, isTrue);
      expect(row.createdAt.isUtc, isTrue);
      expect(row.updatedAt.isUtc, isTrue);
      expect(row.occurredAt.isAtSameMomentAs(local), isTrue);
    });

    test('treats the description as optional and leaves it null', () {
      final LedgerTransaction row = LedgerTransaction(
        id: 'txn-1',
        khataId: 'khata-a',
        kind: LedgerKind.income,
        amountPaise: 1000000,
        category: 'Income',
        occurredAt: at(9),
        createdAt: at(9),
        updatedAt: at(9),
      );
      expect(row.description, isNull);
    });

    test('accepts a description of exactly 120 characters', () {
      final String description = 'a' * kLedgerDescriptionMaxLength;
      expect(
        expenseAt(
          id: 'txn-1',
          amountPaise: 100,
          hour: 12,
          description: description,
        ).description,
        description,
      );
    });

    test('counts description length in characters, not UTF-16 units', () {
      // U+1F600 is a single character but two UTF-16 code units, so a naive
      // `length` check would reject a legal 120-character description.
      final String description = '\u{1F600}' * kLedgerDescriptionMaxLength;
      expect(
        description.length,
        greaterThan(kLedgerDescriptionMaxLength),
        reason: 'the fixture must exercise surrogate pairs',
      );
      expect(
        expenseAt(
          id: 'txn-1',
          amountPaise: 100,
          hour: 12,
          description: description,
        ).description,
        description,
      );
    });
  });

  group('LedgerTransaction rejects invalid values', () {
    test('rejects zero, negative and non-positive amounts', () {
      for (final int amount in <int>[0, -1, -58000, -1000000]) {
        expect(
          () => expenseAt(id: 'txn-1', amountPaise: amount, hour: 12),
          throwsA(isA<ArgumentError>()),
          reason: 'amount $amount must be rejected',
        );
      }
    });

    test('rejects blank or empty ids, khata ids and categories', () {
      LedgerTransaction build({
        String id = 'txn-1',
        String khataId = 'khata-a',
        String category = 'Food',
      }) {
        return LedgerTransaction(
          id: id,
          khataId: khataId,
          kind: LedgerKind.expense,
          amountPaise: 100,
          category: category,
          occurredAt: at(12),
          createdAt: at(9),
          updatedAt: at(9),
        );
      }

      expect(() => build(id: ''), throwsA(isA<ArgumentError>()));
      expect(() => build(id: '   '), throwsA(isA<ArgumentError>()));
      expect(() => build(khataId: ''), throwsA(isA<ArgumentError>()));
      expect(() => build(khataId: ' \t '), throwsA(isA<ArgumentError>()));
      expect(() => build(category: ''), throwsA(isA<ArgumentError>()));
      expect(() => build(category: '  '), throwsA(isA<ArgumentError>()));
    });

    test('rejects a description longer than 120 characters', () {
      expect(
        () => expenseAt(
          id: 'txn-1',
          amountPaise: 100,
          hour: 12,
          description: 'a' * (kLedgerDescriptionMaxLength + 1),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects a blank description instead of storing whitespace', () {
      expect(
        () =>
            expenseAt(id: 'txn-1', amountPaise: 100, hour: 12, description: ''),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => expenseAt(
          id: 'txn-1',
          amountPaise: 100,
          hour: 12,
          description: '   ',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects an updatedAt before createdAt', () {
      expect(
        () => LedgerTransaction(
          id: 'txn-1',
          khataId: 'khata-a',
          kind: LedgerKind.income,
          amountPaise: 100,
          category: 'Income',
          occurredAt: at(12),
          createdAt: at(10),
          updatedAt: at(9),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects a tombstone before the row existed', () {
      expect(
        () => LedgerTransaction(
          id: 'txn-1',
          khataId: 'khata-a',
          kind: LedgerKind.expense,
          amountPaise: 100,
          category: 'Food',
          occurredAt: at(12),
          createdAt: at(10),
          updatedAt: at(10),
          deletedAt: at(9),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('LedgerTransaction is an immutable value', () {
    test('equal field sets compare equal and hash equally', () {
      final LedgerTransaction a = expenseAt(
        id: 'txn-1',
        amountPaise: 120000,
        hour: 20,
        minute: 30,
        description: 'Grocery Shopping',
      );
      final LedgerTransaction b = expenseAt(
        id: 'txn-1',
        amountPaise: 120000,
        hour: 20,
        minute: 30,
        description: 'Grocery Shopping',
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(expenseAt(id: 'txn-2', amountPaise: 120000, hour: 20)));
      expect(a, isNot(deleted(a)));
    });

    test('a tombstone keeps the original fields and gains only deletedAt', () {
      final LedgerTransaction live = expenseAt(
        id: 'txn-1',
        amountPaise: 19900,
        hour: 10,
        description: 'Mobile Recharge',
      );
      final LedgerTransaction tomb = deleted(live);

      expect(tomb.id, live.id);
      expect(tomb.khataId, live.khataId);
      expect(tomb.kind, live.kind);
      expect(tomb.amountPaise, live.amountPaise);
      expect(tomb.category, live.category);
      expect(tomb.description, live.description);
      expect(tomb.occurredAt, live.occurredAt);
      expect(tomb.isDeleted, isTrue);
      expect(tomb.isLive, isFalse);
    });

    test('toString stays readable for debugging', () {
      expect(
        expenseAt(id: 'txn-1', amountPaise: 100, hour: 12).toString(),
        contains('LedgerTransaction(id: txn-1'),
      );
    });
  });

  group('LedgerTotals arithmetic follows the spec formula', () {
    test('adds income and opening balance, subtracts expenses', () {
      final LedgerTotals result = totals(<LedgerTransaction>[
        incomeAt(id: 'in-1', amountPaise: 500000, hour: 9),
        expenseAt(id: 'out-1', amountPaise: 120000, hour: 20),
        expenseAt(id: 'out-2', amountPaise: 58000, hour: 13),
      ], openingBalancePaise: 1000000);

      expect(result.totalIncomePaise, 1500000);
      expect(result.totalExpensePaise, 178000);
      expect(result.remainingPaise, 1322000);
      expect(result.openingBalancePaise, 1000000);
      expect(result.khataId, 'khata-a');
      expect(result.transactionCount, 3);
    });

    test('an empty ledger is just its opening balance', () {
      final LedgerTotals result = totals(
        const <LedgerTransaction>[],
        openingBalancePaise: 1000000,
      );

      expect(result.totalIncomePaise, 1000000);
      expect(result.totalExpensePaise, 0);
      expect(result.remainingPaise, 1000000);
      expect(result.transactions, isEmpty);
      expect(result.recent(), isEmpty);
    });

    test('zero opening balance with income stays positive', () {
      final LedgerTotals result = totals(<LedgerTransaction>[
        incomeAt(id: 'in-1', amountPaise: 5000, hour: 9),
      ]);
      expect(result.totalIncomePaise, 5000);
      expect(result.totalExpensePaise, 0);
      expect(result.remainingPaise, 5000);
    });

    test('overspending produces a negative remaining balance, not a clamp', () {
      final LedgerTotals result = totals(<LedgerTransaction>[
        expenseAt(id: 'out-1', amountPaise: 500, hour: 9),
      ], openingBalancePaise: 200);
      expect(result.remainingPaise, -300);
    });

    test('a negative opening balance is still pure arithmetic', () {
      final LedgerTotals result = totals(<LedgerTransaction>[
        incomeAt(id: 'in-1', amountPaise: 100, hour: 9),
      ], openingBalancePaise: -400);
      expect(result.totalIncomePaise, -300);
      expect(result.remainingPaise, -300);
    });

    test('reproduces the preview numbers: 10,000 - 3,580 = 6,420', () {
      final LedgerTotals result = totals(<LedgerTransaction>[
        expenseAt(id: 'grocery', amountPaise: 120000, hour: 20, minute: 30),
        expenseAt(id: 'lunch', amountPaise: 58000, hour: 13, minute: 15),
        expenseAt(id: 'recharge', amountPaise: 19900, hour: 10, minute: 20),
        expenseAt(id: 'gift', amountPaise: 100000, hour: 19, day: 18),
        expenseAt(id: 'bus', amountPaise: 30100, hour: 9, day: 17),
        expenseAt(id: 'tea', amountPaise: 30000, hour: 17, day: 16),
      ], openingBalancePaise: 1000000);

      expect(result.totalIncomePaise, 1000000);
      expect(result.totalExpensePaise, 358000);
      expect(result.remainingPaise, 642000);
    });
  });

  group('khata isolation', () {
    test('ignores rows belonging to another khata', () {
      final LedgerTotals result = totals(<LedgerTransaction>[
        expenseAt(id: 'mine-1', amountPaise: 1000, hour: 10),
        expenseAt(id: 'theirs-1', amountPaise: 999999, hour: 11, khataId: 'b'),
        incomeAt(id: 'theirs-2', amountPaise: 888888, hour: 12, khataId: 'b'),
        incomeAt(id: 'mine-2', amountPaise: 2500, hour: 13),
      ]);

      expect(result.transactionCount, 2);
      expect(result.totalIncomePaise, 2500);
      expect(result.totalExpensePaise, 1000);
      expect(result.remainingPaise, 1500);
      expect(result.transactions.map((LedgerTransaction t) => t.id), <String>[
        'mine-2',
        'mine-1',
      ]);
    });

    test('a khata with no rows reports only its opening balance', () {
      final LedgerTotals result = totals(
        <LedgerTransaction>[
          expenseAt(
            id: 'theirs-1',
            amountPaise: 999999,
            hour: 11,
            khataId: 'b',
          ),
        ],
        openingBalancePaise: 750,
        khataId: 'empty-khata',
      );

      expect(result.khataId, 'empty-khata');
      expect(result.transactions, isEmpty);
      expect(result.totalIncomePaise, 750);
      expect(result.totalExpensePaise, 0);
      expect(result.remainingPaise, 750);
    });

    test('khata matching is exact, including case', () {
      final LedgerTotals result = totals(<LedgerTransaction>[
        expenseAt(id: 'lower', amountPaise: 100, hour: 10),
        expenseAt(id: 'upper', amountPaise: 200, hour: 11, khataId: 'KHATA-A'),
      ]);
      expect(result.transactionCount, 1);
      expect(result.transactions.single.id, 'lower');
    });

    test('rejects a blank khata id', () {
      expect(
        () => totals(const <LedgerTransaction>[], khataId: '  '),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('tombstones', () {
    test('deleted rows never count towards totals', () {
      final LedgerTransaction live = expenseAt(
        id: 'out-1',
        amountPaise: 4000,
        hour: 10,
      );
      final LedgerTransaction removed = deleted(
        expenseAt(id: 'out-2', amountPaise: 6000, hour: 11),
      );

      final LedgerTotals result = totals(<LedgerTransaction>[
        live,
        removed,
      ], openingBalancePaise: 10000);

      expect(result.totalExpensePaise, 4000);
      expect(result.remainingPaise, 6000);
      expect(result.transactionCount, 1);
      expect(result.transactions.single.id, 'out-1');
    });

    test('a tombstoned income row drops out of total income too', () {
      final LedgerTotals result = totals(<LedgerTransaction>[
        incomeAt(id: 'in-1', amountPaise: 5000, hour: 9),
        deleted(incomeAt(id: 'in-2', amountPaise: 7000, hour: 10)),
      ], openingBalancePaise: 1000);
      expect(result.totalIncomePaise, 6000);
      expect(result.totalExpensePaise, 0);
      expect(result.remainingPaise, 6000);
    });

    test('tombstoned rows are excluded from recent()', () {
      final LedgerTotals result = totals(<LedgerTransaction>[
        expenseAt(id: 'old', amountPaise: 100, hour: 9),
        deleted(expenseAt(id: 'newest', amountPaise: 200, hour: 20)),
        expenseAt(id: 'middle', amountPaise: 300, hour: 12),
      ]);

      expect(result.recent().map((LedgerTransaction t) => t.id), <String>[
        'middle',
        'old',
      ]);
    });

    test('an all-tombstoned ledger keeps only its opening balance', () {
      final LedgerTotals result = totals(<LedgerTransaction>[
        deleted(expenseAt(id: 'out-1', amountPaise: 500, hour: 10)),
        deleted(incomeAt(id: 'in-1', amountPaise: 900, hour: 11)),
      ], openingBalancePaise: 1000);

      expect(result.transactions, isEmpty);
      expect(result.totalIncomePaise, 1000);
      expect(result.totalExpensePaise, 0);
      expect(result.remainingPaise, 1000);
    });

    test('the original live row object is untouched by tombstoning', () {
      final LedgerTransaction live = expenseAt(
        id: 'out-1',
        amountPaise: 500,
        hour: 10,
      );
      deleted(live);
      expect(live.isLive, isTrue);
      expect(live.deletedAt, isNull);
    });
  });

  group('recent() ordering', () {
    test('returns newest first, default limit four', () {
      final List<LedgerTransaction> rows = <LedgerTransaction>[
        expenseAt(id: 'h9', amountPaise: 100, hour: 9),
        expenseAt(id: 'h20', amountPaise: 200, hour: 20),
        expenseAt(id: 'h13', amountPaise: 300, hour: 13),
        expenseAt(id: 'h17', amountPaise: 400, hour: 17),
        expenseAt(id: 'h11', amountPaise: 500, hour: 11),
        expenseAt(id: 'h15', amountPaise: 600, hour: 15),
      ];

      final List<String> ids = totals(rows)
          .recent()
          .map((LedgerTransaction t) => t.id)
          .toList();

      expect(ids, <String>['h20', 'h17', 'h15', 'h13']);
      expect(totals(rows).recent().length, 4);
    });

    test('honours an explicit limit larger and smaller than the row count', () {
      final List<LedgerTransaction> rows = <LedgerTransaction>[
        expenseAt(id: 'a', amountPaise: 100, hour: 9),
        expenseAt(id: 'b', amountPaise: 200, hour: 10),
        expenseAt(id: 'c', amountPaise: 300, hour: 11),
      ];
      final LedgerTotals result = totals(rows);

      final List<String> limited = result
          .recent(limit: 2)
          .map((LedgerTransaction t) => t.id)
          .toList();

      expect(limited, <String>['c', 'b']);
      expect(result.recent(limit: 99).length, 3);
      expect(result.recent(limit: 0), isEmpty);
      expect(() => result.recent(limit: -1), throwsA(isA<ArgumentError>()));
    });

    test('equal occurredAt breaks by ascending id, whatever the order', () {
      final List<LedgerTransaction> forwards = <LedgerTransaction>[
        expenseAt(id: 'b', amountPaise: 100, hour: 12),
        expenseAt(id: 'a', amountPaise: 200, hour: 12),
        expenseAt(id: 'c', amountPaise: 300, hour: 12),
      ];
      final List<LedgerTransaction> backwards = forwards.reversed.toList();

      expect(
        totals(forwards).recent().map((LedgerTransaction t) => t.id),
        <String>['a', 'b', 'c'],
      );
      expect(
        totals(backwards).recent().map((LedgerTransaction t) => t.id),
        <String>['a', 'b', 'c'],
      );
    });

    test('orders by occurredAt, not by createdAt or input position', () {
      final LedgerTransaction laterCreated = LedgerTransaction(
        id: 'evening',
        khataId: 'khata-a',
        kind: LedgerKind.expense,
        amountPaise: 100,
        category: 'Food',
        occurredAt: at(20),
        createdAt: at(15),
        updatedAt: at(15),
      );
      final LedgerTransaction earlierCreated = LedgerTransaction(
        id: 'morning',
        khataId: 'khata-a',
        kind: LedgerKind.expense,
        amountPaise: 200,
        category: 'Food',
        occurredAt: at(8),
        createdAt: at(21),
        updatedAt: at(21),
      );

      expect(
        totals(<LedgerTransaction>[earlierCreated, laterCreated]).transactions
            .map((LedgerTransaction t) => t.id),
        <String>['evening', 'morning'],
      );
    });

    test('spans days, newest day first', () {
      final LedgerTotals result = totals(<LedgerTransaction>[
        expenseAt(id: 'tea', amountPaise: 30000, hour: 17, day: 16),
        expenseAt(id: 'bus', amountPaise: 30100, hour: 9, day: 17),
        expenseAt(id: 'grocery', amountPaise: 120000, hour: 20, day: 19),
      ]);
      expect(result.recent().map((LedgerTransaction t) => t.id), <String>[
        'grocery',
        'bus',
        'tea',
      ]);
    });

    test('recent() is a copy: mutating it cannot corrupt the totals', () {
      final LedgerTotals result = totals(<LedgerTransaction>[
        expenseAt(id: 'a', amountPaise: 100, hour: 9),
        expenseAt(id: 'b', amountPaise: 200, hour: 10),
      ]);
      final List<LedgerTransaction> recent = result.recent();
      expect(() => recent.add(recent.first), throwsUnsupportedError);
      expect(result.transactionCount, 2);
      expect(result.totalExpensePaise, 300);
    });

    test('the transactions view is unmodifiable', () {
      final LedgerTotals result = totals(<LedgerTransaction>[
        expenseAt(id: 'a', amountPaise: 100, hour: 9),
      ]);
      expect(() => result.transactions.removeAt(0), throwsUnsupportedError);
    });
  });

  group('large integer amounts', () {
    test('handles amounts near the 63-bit boundary without overflow', () {
      const int huge = 9007199254740991; // 2^53 - 1, exact in JS too.
      final LedgerTotals result = totals(<LedgerTransaction>[
        incomeAt(id: 'in-1', amountPaise: huge, hour: 9),
        incomeAt(id: 'in-2', amountPaise: huge, hour: 10),
        expenseAt(id: 'out-1', amountPaise: huge, hour: 11),
      ]);

      expect(result.totalIncomePaise, huge * 2);
      expect(result.totalExpensePaise, huge);
      expect(result.remainingPaise, huge);
    });

    test('sums many large rows and keeps remaining == income - expense', () {
      const int big = 1000000000000; // ₹10,00,00,00,000 in paise.
      final List<LedgerTransaction> rows = <LedgerTransaction>[
        for (int index = 0; index < 50; index++)
          index.isEven
              ? incomeAt(id: 'in-$index', amountPaise: big, hour: 0, minute: 0)
              : expenseAt(id: 'out-$index', amountPaise: big, hour: 0),
      ];

      final LedgerTotals result = totals(rows, openingBalancePaise: big);

      expect(result.totalIncomePaise, big * 26);
      expect(result.totalExpensePaise, big * 25);
      expect(
        result.remainingPaise,
        result.totalIncomePaise - result.totalExpensePaise,
      );
      expect(result.remainingPaise, big);
    });

    test('the max int amount is accepted and reported unchanged', () {
      const int maxInt = 9223372036854775807;
      final LedgerTotals result = totals(<LedgerTransaction>[
        incomeAt(id: 'in-1', amountPaise: maxInt, hour: 9),
      ]);
      expect(result.totalIncomePaise, maxInt);
      expect(result.remainingPaise, maxInt);
    });
  });

  group('LedgerTotals is a value object', () {
    test('same inputs give equal totals regardless of input order', () {
      final List<LedgerTransaction> forward = <LedgerTransaction>[
        expenseAt(id: 'a', amountPaise: 100, hour: 9),
        incomeAt(id: 'b', amountPaise: 200, hour: 10),
        deleted(expenseAt(id: 'c', amountPaise: 300, hour: 11)),
      ];
      final List<LedgerTransaction> back = forward.reversed.toList();

      final LedgerTotals a = totals(forward, openingBalancePaise: 1000);
      final LedgerTotals b = totals(back, openingBalancePaise: 1000);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.toString(), contains('remainingPaise: 1100'));
      expect(a, isNot(totals(forward, openingBalancePaise: 999)));
    });

    test('a lazy iterable is consumed once and fully', () {
      int visits = 0;
      final Iterable<LedgerTransaction> rows =
          <LedgerTransaction>[
            expenseAt(id: 'a', amountPaise: 100, hour: 9),
            expenseAt(id: 'b', amountPaise: 200, hour: 10),
          ].map((LedgerTransaction t) {
            visits++;
            return t;
          });

      final LedgerTotals result = totals(rows);
      expect(visits, 2);
      expect(result.totalExpensePaise, 300);
      expect(result.transactionCount, 2);
    });
  });
}
