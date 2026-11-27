// Flutter 3.50 deprecates this import; migrate to material_ui in a dedicated dependency update.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khoroch_diary/core/format/money.dart';
import 'package:khoroch_diary/core/l10n/app_strings.dart';
import 'package:khoroch_diary/core/theme/app_colors.dart';
import 'package:khoroch_diary/core/theme/app_theme.dart';
import 'package:khoroch_diary/features/home/home_screen.dart';
import 'package:khoroch_diary/features/home/models.dart';

/// A supplied ledger with more than four entries: only the newest four may
/// reach the preview list, and none of the seeded B1 titles may appear.
LedgerSummary liveSummary() {
  return LedgerSummary(
    openingBalancePaise: 125000,
    entries: <LedgerEntry>[
      LedgerEntry(
        title: 'Freelance Payment',
        category: 'Income',
        at: DateTime(2026, 11, 19, 18, 30),
        amountPaise: 300000,
        type: EntryType.income,
      ),
      LedgerEntry(
        title: 'Live Groceries',
        category: 'Shopping',
        at: DateTime(2026, 11, 19, 17),
        amountPaise: 45000,
      ),
      LedgerEntry(
        title: 'Live Coffee',
        category: 'Food',
        at: DateTime(2026, 11, 19, 9, 15),
        amountPaise: 8000,
      ),
      LedgerEntry(
        title: 'Live Bus Pass',
        category: 'Travel',
        at: DateTime(2026, 11, 18, 8),
        amountPaise: 12000,
      ),
      LedgerEntry(
        title: 'Live Electricity',
        category: 'Bills',
        at: DateTime(2026, 11, 17, 16, 30),
        amountPaise: 25000,
      ),
    ],
  );
}

/// A long, realistic ledger: every row is *stored* (it carries an id), which is
/// the only kind of row Home may offer to edit. The names and amounts are the
/// long ones from the brief, so the same fixture proves the layout survives a
/// 320 dp phone at 200% text.
LedgerSummary persistedSummary() {
  return LedgerSummary(
    openingBalancePaise: 0,
    entries: <LedgerEntry>[
      LedgerEntry(
        title: 'Freelance Payment',
        category: 'Income',
        at: DateTime(2026, 11, 19, 18, 30),
        amountPaise: 300000,
        type: EntryType.income,
        id: 'entry-freelance',
      ),
      LedgerEntry(
        title: 'Monthly grocery and household supplies for the whole family',
        category: 'Shopping',
        at: DateTime(2026, 11, 19, 17),
        amountPaise: 45000,
        id: 'entry-groceries',
      ),
      LedgerEntry(
        title: 'Live Coffee',
        category: 'Food',
        at: DateTime(2026, 11, 19, 9, 15),
        amountPaise: 8000,
        id: 'entry-coffee',
      ),
      LedgerEntry(
        title: 'Live Bus Pass',
        category: 'Travel',
        at: DateTime(2026, 11, 18, 8),
        amountPaise: 12000,
        id: 'entry-bus-pass',
      ),
      LedgerEntry(
        title: 'Live Electricity',
        category: 'Bills',
        at: DateTime(2026, 11, 17, 16, 30),
        amountPaise: 25000,
        id: 'entry-electricity',
      ),
    ],
  );
}

/// The same five rows without an id: what a preview or sample ledger looks
/// like. Nothing here may be offered to an editor.
LedgerSummary unpersistedSummary() {
  return LedgerSummary(
    openingBalancePaise: 0,
    entries: <LedgerEntry>[
      for (final LedgerEntry entry in persistedSummary().entries)
        LedgerEntry(
          title: entry.title,
          category: entry.category,
          at: entry.at,
          amountPaise: entry.amountPaise,
          type: entry.type,
        ),
    ],
  );
}

/// A different live snapshot used to prove the widget rebuilds on new data.
LedgerSummary replacementSummary() {
  return LedgerSummary(
    openingBalancePaise: 0,
    entries: <LedgerEntry>[
      LedgerEntry(
        title: 'Replacement Salary',
        category: 'Income',
        at: DateTime(2026, 11, 19, 12),
        amountPaise: 750000,
        type: EntryType.income,
      ),
      LedgerEntry(
        title: 'Replacement Taxi',
        category: 'Travel',
        at: DateTime(2026, 11, 18, 11),
        amountPaise: 25000,
      ),
    ],
  );
}

/// Pumps the home screen as a parent would: with live data and only the
/// callbacks the parent chooses to supply.
Future<void> pumpLive(
  WidgetTester tester, {
  required LedgerSummary summary,
  VoidCallback? onAddEntry,
  VoidCallback? onViewAll,
  ValueChanged<LedgerEntry>? onRecentEntry,
  AppLanguage language = AppLanguage.en,
  Size size = const Size(320, 568),
  double scale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      builder: (BuildContext context, Widget? child) {
        return MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: HomeScreen(
        language: language,
        summary: summary,
        onAddEntry: onAddEntry,
        onViewAll: onViewAll,
        onRecentEntry: onRecentEntry,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// One recent row, found by the key the screen gives it.
Finder recentRow(String title) => find.byKey(Key('home-recent-$title'));

/// The tap target inside a row: present on every row, wired only on the ones
/// that may be edited.
InkWell rowInk(WidgetTester tester, String title) => tester.widget<InkWell>(
  find.descendant(of: recentRow(title), matching: find.byType(InkWell)),
);

void expectNoLayoutErrors(WidgetTester tester) {
  expect(
    tester.takeException(),
    isNull,
    reason: 'live home layout must not overflow or throw',
  );
}

void main() {
  group('LedgerSummary totals and recent rows', () {
    LedgerEntry row(
      String title,
      int paise,
      DateTime at, {
      EntryType type = EntryType.expense,
    }) {
      return LedgerEntry(
        title: title,
        category: 'Food',
        at: at,
        amountPaise: paise,
        type: type,
      );
    }

    List<String> titles(List<LedgerEntry> rows) =>
        rows.map((LedgerEntry entry) => entry.title).toList();

    test(
      'totals fold the opening balance into income and match the getters',
      () {
        final LedgerSummary summary = LedgerSummary(
          openingBalancePaise: 1000,
          entries: <LedgerEntry>[
            row('Salary', 5000, DateTime(2026, 11, 3), type: EntryType.income),
            row('Tea', 300, DateTime(2026, 11, 2)),
            row('Bus', 450, DateTime(2026, 11, 1)),
          ],
        );

        final LedgerSummaryTotals totals = summary.totals;
        expect(totals.totalIncomePaise, 6000);
        expect(totals.totalExpensePaise, 750);
        expect(totals.remainingPaise, 5250);
        expect(summary.totalIncomePaise, totals.totalIncomePaise);
        expect(summary.totalExpensePaise, totals.totalExpensePaise);
        expect(summary.remainingPaise, totals.remainingPaise);
      },
    );

    test('a ledger with no entries is just its opening balance', () {
      const LedgerSummary empty = LedgerSummary(
        openingBalancePaise: 2500,
        entries: <LedgerEntry>[],
      );

      expect(empty.totals.totalIncomePaise, 2500);
      expect(empty.totals.totalExpensePaise, 0);
      expect(empty.totals.remainingPaise, 2500);
      expect(empty.recent(), isEmpty);
    });

    test('recent returns the newest rows whatever order they arrive in', () {
      final List<LedgerEntry> arrival = <LedgerEntry>[
        row('c', 3, DateTime(2026, 11, 3)),
        row('a', 1, DateTime(2026, 11, 1)),
        row('e', 5, DateTime(2026, 11, 5)),
        row('b', 2, DateTime(2026, 11, 2)),
        row('d', 4, DateTime(2026, 11, 4)),
        row('f', 6, DateTime(2026, 11, 6)),
      ];
      final LedgerSummary summary = LedgerSummary(
        openingBalancePaise: 0,
        entries: arrival,
      );

      expect(titles(summary.recent()), <String>['f', 'e', 'd', 'c']);
      expect(titles(summary.recent(2)), <String>['f', 'e']);
      expect(titles(summary.recent(10)), <String>[
        'f',
        'e',
        'd',
        'c',
        'b',
        'a',
      ]);
      expect(summary.recent(0), isEmpty);
      expect(() => summary.recent(-1), throwsArgumentError);
      // Reading the newest rows leaves the summary's own list as it was.
      expect(titles(arrival), <String>['c', 'a', 'e', 'b', 'd', 'f']);
    });

    test('rows at the same instant keep the order they were read in', () {
      final DateTime same = DateTime(2026, 11, 4, 10);
      final LedgerSummary summary = LedgerSummary(
        openingBalancePaise: 0,
        entries: <LedgerEntry>[
          row('first', 1, same),
          row('second', 2, same),
          row('older', 3, DateTime(2026, 11, 3)),
          row('third', 4, same),
        ],
      );

      expect(titles(summary.recent(3)), <String>['first', 'second', 'third']);
    });
  });

  group('supplied live data', () {
    testWidgets(
      'renders supplied totals, four newest rows and no preview notice',
      (WidgetTester tester) async {
        final LedgerSummary summary = liveSummary();
        await pumpLive(tester, summary: summary);

        expect(find.text('Remaining Balance'), findsOneWidget);
        expect(find.text(formatPaise(summary.remainingPaise)), findsOneWidget);
        expect(
          find.text(formatPaise(summary.totalIncomePaise)),
          findsOneWidget,
        );
        expect(
          find.text(formatPaise(summary.totalExpensePaise)),
          findsOneWidget,
        );

        for (final String title in <String>[
          'Freelance Payment',
          'Live Groceries',
          'Live Coffee',
          'Live Bus Pass',
        ]) {
          expect(find.text(title), findsOneWidget, reason: title);
        }
        // The fifth entry and every seeded preview entry stay out of the list.
        expect(find.text('Live Electricity'), findsNothing);
        expect(find.text('Grocery Shopping'), findsNothing);
        expect(find.text('Sample ledger · preview data only'), findsNothing);
        expectNoLayoutErrors(tester);
      },
    );

    testWidgets('rebuilds figures and rows when a new summary arrives', (
      WidgetTester tester,
    ) async {
      final LedgerSummary first = liveSummary();
      final LedgerSummary second = replacementSummary();
      await pumpLive(tester, summary: first);

      expect(find.text(formatPaise(first.remainingPaise)), findsOneWidget);
      expect(find.text('Live Groceries'), findsOneWidget);

      await pumpLive(tester, summary: second);

      expect(find.text(formatPaise(first.remainingPaise)), findsNothing);
      expect(find.text('Live Groceries'), findsNothing);
      expect(find.text('Freelance Payment'), findsNothing);
      expect(find.text(formatPaise(second.remainingPaise)), findsOneWidget);
      expect(find.text(formatPaise(second.totalIncomePaise)), findsOneWidget);
      expect(
        find.text(formatPaise(second.totalExpensePaise)),
        findsNWidgets(2),
      );
      expect(find.text('Replacement Salary'), findsOneWidget);
      expect(find.text('Replacement Taxi'), findsOneWidget);
      expectNoLayoutErrors(tester);
    });

    testWidgets('an empty ledger shows a meaningful state and zero totals', (
      WidgetTester tester,
    ) async {
      const LedgerSummary empty = LedgerSummary(
        openingBalancePaise: 100000,
        entries: <LedgerEntry>[],
      );
      await pumpLive(tester, summary: empty);

      expect(find.text('Recent Transactions'), findsOneWidget);
      expect(
        find.text('No transactions yet. Add an entry to see it here.'),
        findsOneWidget,
      );
      expect(
        find.text(formatPaise(empty.remainingPaise)),
        findsNWidgets(empty.openingBalancePaise == 0 ? 3 : 2),
      );
      expect(find.text(formatPaise(empty.totalIncomePaise)), findsNWidgets(2));
      expect(find.text(formatPaise(empty.totalExpensePaise)), findsOneWidget);
      expect(
        find.text('Preview data - local ledger arrives in B2'),
        findsNothing,
      );
      expectNoLayoutErrors(tester);
    });
  });

  group('callbacks', () {
    testWidgets('the CTA and View All call their supplied handlers', (
      WidgetTester tester,
    ) async {
      int addTaps = 0;
      int viewTaps = 0;
      await pumpLive(
        tester,
        summary: liveSummary(),
        onAddEntry: () => addTaps++,
        onViewAll: () => viewTaps++,
      );

      final Finder cta = find.text('Add New Entry');
      await tester.ensureVisible(cta);
      await tester.pumpAndSettle();
      await tester.tap(cta);
      await tester.pumpAndSettle();
      expect(addTaps, 1);

      final Finder viewAll = find.text('View All');
      await tester.ensureVisible(viewAll);
      await tester.pumpAndSettle();
      await tester.tap(viewAll);
      await tester.pumpAndSettle();
      expect(viewTaps, 1);
      expectNoLayoutErrors(tester);
    });

    testWidgets('null handlers leave both controls visibly disabled', (
      WidgetTester tester,
    ) async {
      await pumpLive(tester, summary: liveSummary());

      final FilledButton addButton = tester.widget<FilledButton>(
        find.byType(FilledButton),
      );
      expect(addButton.onPressed, isNull);

      final TextButton viewButton = tester.widget<TextButton>(
        find.byType(TextButton),
      );
      expect(viewButton.onPressed, isNull);
      final Text label = tester.widget<Text>(find.text('View All'));
      expect(label.style?.color, AppColors.navigationGrey);

      // Disabled controls are inert, not fake actions that throw or navigate.
      await tester.tap(find.text('View All'));
      await tester.pumpAndSettle();
      final Finder cta = find.text('Add New Entry');
      await tester.ensureVisible(cta);
      await tester.pumpAndSettle();
      await tester.tap(cta);
      await tester.pumpAndSettle();
      expectNoLayoutErrors(tester);
    });
  });

  group('recent activity is actionable', () {
    testWidgets('a stored row calls back once with that exact entry', (
      WidgetTester tester,
    ) async {
      final LedgerSummary summary = persistedSummary();
      final List<LedgerEntry> taps = <LedgerEntry>[];
      await pumpLive(tester, summary: summary, onRecentEntry: taps.add);

      await tester.ensureVisible(find.text('Live Coffee'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Live Coffee'));
      await tester.pumpAndSettle();

      expect(taps, hasLength(1));
      // The exact row object, id and all: the parent needs the stored id to
      // build its editor, and a copy would be the wrong entry.
      expect(identical(taps.single, summary.entries[2]), isTrue);
      expect(taps.single.id, 'entry-coffee');
      expect(taps.single.amountPaise, 8000);
      expect(taps.single.title, 'Live Coffee');
      expectNoLayoutErrors(tester);
    });

    testWidgets('each stored row is its own target with its own payload', (
      WidgetTester tester,
    ) async {
      final LedgerSummary summary = persistedSummary();
      final List<LedgerEntry> taps = <LedgerEntry>[];
      await pumpLive(tester, summary: summary, onRecentEntry: taps.add);

      for (final int index in <int>[0, 3]) {
        final String title = summary.entries[index].title;
        await tester.ensureVisible(find.text(title));
        await tester.pumpAndSettle();
        await tester.tap(find.text(title));
        await tester.pumpAndSettle();
      }

      expect(taps.map((LedgerEntry entry) => entry.id), <String?>[
        'entry-freelance',
        'entry-bus-pass',
      ]);
      // Tapping rows never invents data or navigates: Home stays on screen.
      expect(find.byType(HomeScreen), findsOneWidget);
      expectNoLayoutErrors(tester);
    });

    testWidgets('rows without an id stay inert even when a handler is given', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      int taps = 0;
      await pumpLive(
        tester,
        summary: unpersistedSummary(),
        onRecentEntry: (_) => taps++,
      );

      await tester.ensureVisible(find.text('Live Coffee'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Live Coffee'));
      await tester.pumpAndSettle();

      // No callback, and the row announces nothing an editor could act on:
      // an id-less entry is not "editable", so it carries no affordance.
      expect(taps, 0);
      expect(rowInk(tester, 'Live Coffee').onTap, isNull);
      expect(
        tester.getSemantics(recentRow('Live Coffee')).label,
        isNot(contains('Tap to edit')),
      );
      semantics.dispose();
      expectNoLayoutErrors(tester);
    });

    testWidgets('a stored row without a handler stays inert', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await pumpLive(tester, summary: persistedSummary());

      // Stored, but Home was built without the callback: still not a control.
      expect(rowInk(tester, 'Live Coffee').onTap, isNull);
      expect(
        tester.getSemantics(recentRow('Live Coffee')).label,
        isNot(contains('Tap to edit')),
      );

      // Tapping a row with no handler must be a no-op, not a crash or a route.
      await tester.ensureVisible(find.text('Live Coffee'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Live Coffee'));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      semantics.dispose();
      expectNoLayoutErrors(tester);
    });

    testWidgets('an actionable row announces that it can be edited', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await pumpLive(
        tester,
        summary: persistedSummary(),
        onRecentEntry: (_) {},
      );
      await tester.ensureVisible(find.text('Live Coffee'));
      await tester.pumpAndSettle();

      expect(rowInk(tester, 'Live Coffee').onTap, isNotNull);
      // The affordance is spoken, localized and tied to this row's own data -
      // direction in words, because the amount's colour is not a label.
      expect(
        tester.getSemantics(recentRow('Live Coffee')).label,
        contains('Live Coffee'),
      );
      expect(
        tester.getSemantics(recentRow('Live Coffee')).label,
        contains('Expense -'),
      );
      expect(
        tester.getSemantics(recentRow('Live Coffee')).label,
        contains('Tap to edit'),
      );
      semantics.dispose();
    });

    testWidgets('the seeded preview is never offered to the editor', (
      WidgetTester tester,
    ) async {
      int taps = 0;
      // No summary at all: every row is sample data, even with a handler that
      // a live ledger would have honoured.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: HomeScreen(onRecentEntry: (_) => taps++),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Grocery Shopping'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Grocery Shopping'));
      await tester.pumpAndSettle();

      expect(taps, 0);
      expect(rowInk(tester, 'Grocery Shopping').onTap, isNull);
      expect(find.text('Sample ledger · preview data only'), findsOneWidget);
      expectNoLayoutErrors(tester);
    });
  });

  group('responsive live layout', () {
    testWidgets(
      'long titles, large amounts and the edit target survive 320dp at 200%',
      (WidgetTester tester) async {
        final LedgerSummary summary = LedgerSummary(
          openingBalancePaise: 987654321,
          entries: <LedgerEntry>[
            LedgerEntry(
              title:
                  'Advance payment for the new kitchen, the plumbing and every '
                  'labour charge the contractor billed',
              category: 'Shopping',
              at: DateTime(2026, 11, 19, 18, 30),
              amountPaise: 123456789,
              id: 'entry-long-expense',
            ),
            LedgerEntry(
              title:
                  'Freelance invoice settled by the client for the festival '
                  'campaign and the extra revisions',
              category: 'Income',
              at: DateTime(2026, 11, 19, 12),
              amountPaise: 876543210,
              type: EntryType.income,
              id: 'entry-long-income',
            ),
          ],
        );
        int taps = 0;

        for (final AppLanguage language in AppLanguage.values) {
          await pumpLive(
            tester,
            summary: summary,
            language: language,
            onRecentEntry: (_) => taps++,
            scale: 2.0,
          );

          expectNoLayoutErrors(tester);
          // The action and the rows stay reachable; the amounts are still
          // findable, and the target itself is never thinner than 44 dp.
          final Finder cta = find.text(
            AppStrings(language).text(AppString.addNewEntry),
          );
          expect(cta.hitTestable(), findsOneWidget);
          final Finder row = recentRow(
            'Freelance invoice settled by the client for the festival '
            'campaign and the extra revisions',
          );
          await tester.ensureVisible(row);
          await tester.pumpAndSettle();
          expect(tester.getSize(row).height, greaterThanOrEqualTo(44));
          expect(row.hitTestable(), findsOneWidget);
          expectNoLayoutErrors(tester);
        }
        expect(taps, 0, reason: 'laying out a row must not call its handler');
      },
    );

    testWidgets('200% text scale keeps live rows and controls reachable', (
      WidgetTester tester,
    ) async {
      final LedgerSummary summary = liveSummary();
      await pumpLive(tester, summary: summary, scale: 2.0);

      expectNoLayoutErrors(tester);
      expect(find.text(formatPaise(summary.remainingPaise)), findsOneWidget);
      expect(find.text(formatPaise(summary.totalIncomePaise)), findsOneWidget);
      expect(find.text(formatPaise(summary.totalExpensePaise)), findsOneWidget);
      for (final String title in <String>[
        'Freelance Payment',
        'Live Groceries',
        'Live Coffee',
        'Live Bus Pass',
      ]) {
        expect(find.text(title), findsOneWidget, reason: title);
      }

      final Finder cta = find.text('Add New Entry');
      await tester.ensureVisible(cta);
      await tester.pumpAndSettle();
      expectNoLayoutErrors(tester);
    });

    testWidgets('200% text scale keeps the empty state readable', (
      WidgetTester tester,
    ) async {
      const LedgerSummary empty = LedgerSummary(
        openingBalancePaise: 0,
        entries: <LedgerEntry>[],
      );
      await pumpLive(tester, summary: empty, scale: 2.0);

      expect(
        find.text('No transactions yet. Add an entry to see it here.'),
        findsOneWidget,
      );
      expect(
        find.text(formatPaise(empty.remainingPaise)),
        findsNWidgets(empty.openingBalancePaise == 0 ? 3 : 2),
      );
      expectNoLayoutErrors(tester);
    });
  });
}
