// Flutter 3.50 deprecates this import; migrate with the app's dependency update.
// ignore: deprecated_member_use
import 'package:flutter/semantics.dart';
// Flutter 3.50 deprecates this import; migrate with the app's dependency update.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khoroch_diary/core/theme/app_colors.dart';
import 'package:khoroch_diary/core/theme/app_theme.dart';
import 'package:khoroch_diary/features/entry/add_entry_screen.dart';
import 'package:khoroch_diary/features/home/models.dart';
import 'package:khoroch_diary/features/ledger/all_transactions_screen.dart';
import 'package:khoroch_diary/features/ledger/data/local_ledger.dart';

const Size smallPhone = Size(320, 568);
const Size midPhone = Size(360, 640);

/// Tall enough that every lazily built list child is mounted, so a missing
/// string really means "not on the screen".
const Size tallPhone = Size(400, 2400);

/// ₹10,000. This must never appear on the screen: the screen reports
/// transaction totals only.
const int kOpeningPaise = 1000000;

/// The time-of-day tail of the shared `dd MMM yyyy, h:mm a` helper: the row's
/// calendar tile and its day heading already carry the date, so a row card
/// shows only `category · time` instead of the same date three times. The full
/// date is still what the day heading prints, and it is still one shared
/// format - only the row's own metadata is shortened.
String rowMeta(String category, String dateTime) =>
    '$category · ${dateTime.substring(dateTime.lastIndexOf(',') + 1).trim()}';

LedgerEntry spent(String title, String category, DateTime at, int paise) =>
    LedgerEntry(title: title, category: category, at: at, amountPaise: paise);

LedgerEntry earned(String title, String category, DateTime at, int paise) =>
    LedgerEntry(
      title: title,
      category: category,
      at: at,
      amountPaise: paise,
      type: EntryType.income,
    );

/// Eight entries over three months:
///   Nov 2026 income ₹5,000, expense ₹2,280
///   Oct 2026 income ₹7,500, expense ₹2,500.50
///   Sep 2026 income ₹0, expense ₹25
LedgerSummary sampleSummary() => LedgerSummary(
  openingBalancePaise: kOpeningPaise,
  entries: <LedgerEntry>[
    spent(
      'Grocery Shopping',
      'Shopping',
      DateTime(2026, 11, 19, 20, 30),
      120000,
    ),
    spent('Lunch with Friends', 'Food', DateTime(2026, 11, 19, 13, 15), 58000),
    spent('Mobile Recharge', 'Bills', DateTime(2026, 11, 19, 10, 20), 19900),
    earned('Salary', 'Income', DateTime(2026, 11, 18, 19, 40), 500000),
    spent('Bus Fare', 'Travel', DateTime(2026, 11, 17, 9, 5), 30100),
    spent('Diwali Gift', 'Gifts', DateTime(2026, 10, 31, 18, 0), 250050),
    earned('Freelance Work', 'Income', DateTime(2026, 10, 15, 12, 0), 750000),
    spent('Tea Stall', 'Food', DateTime(2026, 9, 5, 8, 0), 2500),
  ],
);

/// Pumps the screen alone with the real app theme, at [scale] text size.
Future<void> pumpAllTransactions(
  WidgetTester tester,
  LedgerSummary summary, {
  Size size = tallPhone,
  double scale = 1.0,
  LocalLedger? ledger,
  String? khataId,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      builder: (BuildContext context, Widget? child) {
        final MediaQueryData media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(textScaler: TextScaler.linear(scale)),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: AllTransactionsScreen(
        summary: summary,
        ledger: ledger,
        khataId: khataId,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Scrolls the screen's list until [finder] exists and is visible.
///
/// `.first` because the search field owns an inner [Scrollable] of its own:
/// the list's scrollable is the outermost one in the tree, so this keeps
/// scrolling the list rather than the text box.
Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    120,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

/// Scrolls [finder] into view and taps it only if it can really be tapped.
Future<void> tapControl(WidgetTester tester, Finder finder) async {
  await reveal(tester, finder);
  expect(
    finder.hitTestable().evaluate().isNotEmpty,
    isTrue,
    reason: 'control is offscreen or covered and cannot be tapped',
  );
  await tester.tap(finder.hitTestable());
  await tester.pumpAndSettle();
}

/// Opens the filter panels, which start collapsed (the list is the first
/// screenful now, not the blank filter area). The summary card's search
/// button is the way in; the search pill only exists once the panels are
/// open, so it cannot be the thing that opens them.
Future<void> openFilters(WidgetTester tester) async {
  if (find.byKey(const Key('date-filter-from')).evaluate().isNotEmpty) {
    return;
  }
  await tester.tap(find.byKey(const Key('transactions-search')));
  await tester.pumpAndSettle();
}

Future<void> tapChip(WidgetTester tester, String key) async {
  await openFilters(tester);
  await tapControl(tester, find.byKey(Key(key)));
}

/// Taps something already on screen, without scrolling the list to it.
Future<void> revealTap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder.hitTestable());
  await tester.pumpAndSettle();
}

/// Opens a date control, taps [day] in the month it shows, and confirms.
///
/// The picker opens on the newest entry's month (Nov 2026 for [sampleSummary]),
/// so a two-digit day there is unambiguous.
Future<void> pickDate(WidgetTester tester, String key, String day) async {
  await openFilters(tester);
  await revealTap(tester, find.byKey(Key(key)));
  expect(find.byType(DatePickerDialog), findsOneWidget);
  await tester.tap(
    find
        .descendant(of: find.byType(DatePickerDialog), matching: find.text(day))
        .first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
  expect(find.byType(DatePickerDialog), findsNothing);
}

/// Cancels the picker the way a user does - its Cancel action, or a tap
/// outside it - and proves the dialog is gone. No day is chosen.
Future<void> dismissDatePicker(WidgetTester tester) async {
  expect(find.byType(DatePickerDialog), findsOneWidget);
  final Finder cancel = find.text('Cancel');
  if (cancel.evaluate().isEmpty) {
    await tester.tapAt(const Offset(5, 5));
  } else {
    await tester.tap(cancel);
  }
  await tester.pumpAndSettle();
  expect(find.byType(DatePickerDialog), findsNothing);
}

/// The query currently shown in the search box.
String searchText(WidgetTester tester) {
  final TextField field = tester.widget<TextField>(
    find.byKey(const Key('search-field')),
  );
  return field.controller?.text ?? '';
}

/// Whether the chip's selected state is visible as a check mark.
Finder chipCheck(String key) => find.descendant(
  of: find.byKey(Key(key)),
  matching: find.byIcon(Icons.check),
);

/// The month heading whose accessible label carries [totals]. The redesign
/// draws only the month name and keeps the figures for a screen reader, so
/// the totals are asserted on the label, not on a visible [Text].
Finder monthTotals(String month, String totals) => find.byWidgetPredicate(
  (Widget widget) =>
      widget is Semantics && widget.properties.label == '$month. $totals',
);

void main() {
  group('list content', () {
    testWidgets('shows every entry, more than four, newest first', (
      WidgetTester tester,
    ) async {
      await pumpAllTransactions(tester, sampleSummary());

      for (final String title in <String>[
        'Grocery Shopping',
        'Lunch with Friends',
        'Mobile Recharge',
        'Salary',
        'Bus Fare',
        'Diwali Gift',
        'Freelance Work',
        'Tea Stall',
      ]) {
        expect(find.text(title), findsOneWidget, reason: '$title is missing');
      }

      // Same day, newest time first.
      expect(
        tester.getTopLeft(find.text('Grocery Shopping')).dy,
        lessThan(tester.getTopLeft(find.text('Lunch with Friends')).dy),
      );
      expect(
        tester.getTopLeft(find.text('Lunch with Friends')).dy,
        lessThan(tester.getTopLeft(find.text('Mobile Recharge')).dy),
      );
      // ...and across days and months.
      expect(
        tester.getTopLeft(find.text('Mobile Recharge')).dy,
        lessThan(tester.getTopLeft(find.text('Salary')).dy),
      );
      expect(
        tester.getTopLeft(find.text('Bus Fare')).dy,
        lessThan(tester.getTopLeft(find.text('Diwali Gift')).dy),
      );
      expect(
        tester.getTopLeft(find.text('Freelance Work')).dy,
        lessThan(tester.getTopLeft(find.text('Tea Stall')).dy),
      );
    });

    testWidgets('breaks same-instant ties deterministically', (
      WidgetTester tester,
    ) async {
      final DateTime sameTime = DateTime(2026, 11, 19, 9, 0);
      await pumpAllTransactions(
        tester,
        LedgerSummary(
          openingBalancePaise: 0,
          entries: <LedgerEntry>[
            spent('Zebra', 'Food', sameTime, 1000),
            spent('Alpha', 'Food', sameTime, 1000),
            spent(
              'Mango',
              'Food',
              sameTime.subtract(const Duration(minutes: 1)),
              1000,
            ),
          ],
        ),
      );

      // Equal timestamps fall back to title, so the order never depends on the
      // order the caller happened to supply.
      expect(
        tester.getTopLeft(find.text('Alpha')).dy,
        lessThan(tester.getTopLeft(find.text('Zebra')).dy),
      );
      expect(
        tester.getTopLeft(find.text('Zebra')).dy,
        lessThan(tester.getTopLeft(find.text('Mango')).dy),
      );
    });

    testWidgets('groups by local day with month totals, opening excluded', (
      WidgetTester tester,
    ) async {
      await pumpAllTransactions(tester, sampleSummary());

      // Day headings come from the shared `dd MMM yyyy, h:mm a` helper.
      expect(find.text('19 Nov 2026'), findsOneWidget);
      expect(find.text('18 Nov 2026'), findsOneWidget);
      expect(find.text('31 Oct 2026'), findsOneWidget);
      expect(find.text('05 Sep 2026'), findsOneWidget);
      expect(find.text('Nov 2026'), findsOneWidget);
      expect(find.text('Oct 2026'), findsOneWidget);
      expect(find.text('Sep 2026'), findsOneWidget);

      // Rows keep the shared timestamp's time and signed paise amounts; the
      // row's own date is the tile on its left and the heading above it.
      expect(
        find.text(rowMeta('Bills', '19 Nov 2026, 10:20 AM')),
        findsOneWidget,
      );
      expect(find.text('Bills · 10:20 AM'), findsOneWidget);
      expect(find.text('-₹1,200'), findsOneWidget);
      expect(find.text('+₹5,000'), findsOneWidget);

      // The month heading carries its totals in its accessible label: the
      // figures are not drawn as text, but a screen reader hears them.
      expect(
        monthTotals('Nov 2026', 'Income ₹5,000, Expense ₹2,280.'),
        findsOneWidget,
      );
      expect(
        monthTotals('Oct 2026', 'Income ₹7,500, Expense ₹2,500.50.'),
        findsOneWidget,
      );
      expect(
        monthTotals('Sep 2026', 'Income ₹0, Expense ₹25.'),
        findsOneWidget,
      );
      // Paise survive: the row keeps its exact figure, not a rounded one.
      expect(find.text('-₹2,500.50'), findsOneWidget);
      expect(find.textContaining('₹2,501'), findsNothing);

      // The opening balance never leaks into any total. The card's accessible
      // label says so in words; the figure itself appears nowhere.
      expect(find.textContaining('₹10,000'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (Widget widget) =>
              widget is Semantics &&
              (widget.properties.label ?? '').contains('remaining balance.'),
        ),
        findsWidgets,
      );
    });
  });

  group('filters', () {
    testWidgets('type filter changes rows and month totals together', (
      WidgetTester tester,
    ) async {
      await pumpAllTransactions(tester, sampleSummary());

      await tapChip(tester, 'type-filter-income');

      expect(find.text('Salary'), findsOneWidget);
      expect(find.text('Freelance Work'), findsOneWidget);
      expect(find.text('Grocery Shopping'), findsNothing);
      expect(find.text('Tea Stall'), findsNothing);
      // September holds no income, so that month disappears entirely.
      expect(find.text('Sep 2026'), findsNothing);

      // The month heading's accessible label carries the filtered totals.
      expect(
        monthTotals('Nov 2026', 'Income ₹5,000, Expense ₹0.'),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('transactions-summary')),
          matching: find.text('₹0'),
        ),
        findsOneWidget,
      );
      expect(find.text('Showing 2 of 8 transactions'), findsOneWidget);
    });

    testWidgets('category filter, combined filter, and the no-match state', (
      WidgetTester tester,
    ) async {
      await pumpAllTransactions(tester, sampleSummary());

      await tapChip(tester, 'category-filter-Food');
      expect(find.text('Lunch with Friends'), findsOneWidget);
      expect(find.text('Tea Stall'), findsOneWidget);
      expect(find.text('Grocery Shopping'), findsNothing);
      expect(find.text('Showing 2 of 8 transactions'), findsOneWidget);
      expect(find.byKey(const Key('month-2026-10')), findsNothing);
      expect(
        monthTotals('Nov 2026', 'Income ₹0, Expense ₹580.'),
        findsOneWidget,
      );
      expect(
        monthTotals('Sep 2026', 'Income ₹0, Expense ₹25.'),
        findsOneWidget,
      );

      // Both filters apply at once; no Food entry is income.
      await tapChip(tester, 'type-filter-income');
      expect(find.byKey(const Key('transactions-no-match')), findsOneWidget);
      expect(find.text('No transactions match these filters'), findsOneWidget);
      expect(find.text('Showing 0 of 8 transactions'), findsOneWidget);
      expect(find.byKey(const Key('transactions-empty')), findsNothing);

      // The clear action is a real, tappable control of a usable size.
      final Finder clear = find.byKey(const Key('clear-filters'));
      expect(tester.getSize(clear).height, greaterThanOrEqualTo(44));
      await tapControl(tester, clear);

      expect(find.byKey(const Key('transactions-no-match')), findsNothing);
      expect(find.text('Grocery Shopping'), findsOneWidget);
      expect(find.text('Showing 8 transactions'), findsOneWidget);
      // Both chip groups are back to "All", shown by the check mark.
      expect(chipCheck('type-filter-all'), findsOneWidget);
      expect(chipCheck('category-filter-all'), findsOneWidget);
      expect(chipCheck('type-filter-income'), findsNothing);
      expect(chipCheck('category-filter-Food'), findsNothing);
    });

    testWidgets('empty khata is a different, honest message', (
      WidgetTester tester,
    ) async {
      await pumpAllTransactions(
        tester,
        const LedgerSummary(
          openingBalancePaise: kOpeningPaise,
          entries: <LedgerEntry>[],
        ),
      );

      expect(find.byKey(const Key('transactions-empty')), findsOneWidget);
      expect(find.text('No transactions yet'), findsOneWidget);
      expect(find.text('No transactions match these filters'), findsNothing);
      // Nothing to filter, no totals to state, and no money invented.
      expect(find.byKey(const Key('transactions-summary')), findsNothing);
      expect(find.byKey(const Key('type-filter-all')), findsNothing);
      expect(find.byKey(const Key('category-filter-all')), findsNothing);
      expect(find.byKey(const Key('search-field')), findsNothing);
      expect(find.byKey(const Key('date-filter-from')), findsNothing);
      expect(find.textContaining('₹'), findsNothing);
    });
  });

  group('search', () {
    testWidgets('trims, ignores case, and matches the category', (
      WidgetTester tester,
    ) async {
      await pumpAllTransactions(tester, sampleSummary());
      await openFilters(tester);
      expect(find.byKey(const Key('search-clear')), findsNothing);

      await tester.enterText(
        find.byKey(const Key('search-field')),
        '  grocerY  ',
      );
      await tester.pumpAndSettle();

      expect(find.text('Grocery Shopping'), findsOneWidget);
      expect(find.text('Lunch with Friends'), findsNothing);
      expect(find.text('Showing 1 of 8 transactions'), findsOneWidget);

      // A category is searchable even though no title contains it.
      await tester.enterText(find.byKey(const Key('search-field')), 'FOOD');
      await tester.pumpAndSettle();

      expect(find.text('Lunch with Friends'), findsOneWidget);
      expect(find.text('Tea Stall'), findsOneWidget);
      expect(find.text('Grocery Shopping'), findsNothing);
      expect(find.text('Showing 2 of 8 transactions'), findsOneWidget);
      // One match in each month, so both month headings stay.
      expect(find.text('Nov 2026'), findsOneWidget);
      expect(find.text('Sep 2026'), findsOneWidget);
      // Counts, month totals and the card describe exactly those two rows.
      expect(
        monthTotals('Nov 2026', 'Income ₹0, Expense ₹580.'),
        findsOneWidget,
      );
      expect(
        monthTotals('Sep 2026', 'Income ₹0, Expense ₹25.'),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('transactions-summary')),
          matching: find.text('₹605'),
        ),
        findsOneWidget,
      );
      // ...and the opening balance still never appears.
      expect(find.textContaining('₹10,000'), findsNothing);

      // The clear control is real, big enough, and empties the query.
      final Finder clear = find.byKey(const Key('search-clear'));
      expect(tester.getSize(clear).height, greaterThanOrEqualTo(44));
      await revealTap(tester, clear);

      expect(find.text('Showing 8 transactions'), findsOneWidget);
      expect(find.text('Grocery Shopping'), findsOneWidget);
      expect(find.byKey(const Key('search-clear')), findsNothing);
      expect(searchText(tester), isEmpty);
    });

    testWidgets('a query with no hits is a no-match, not an empty khata', (
      WidgetTester tester,
    ) async {
      await pumpAllTransactions(tester, sampleSummary());
      await openFilters(tester);

      await tester.enterText(find.byKey(const Key('search-field')), 'zzz');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('transactions-no-match')), findsOneWidget);
      expect(find.byKey(const Key('transactions-empty')), findsNothing);
      expect(find.text('Showing 0 of 8 transactions'), findsOneWidget);

      // "Clear filters" means all four filters, including the query.
      await tapControl(tester, find.byKey(const Key('clear-filters')));
      expect(find.text('Showing 8 transactions'), findsOneWidget);
      expect(searchText(tester), isEmpty);
    });

    testWidgets('a Bengali query matches Bengali text', (
      WidgetTester tester,
    ) async {
      await pumpAllTransactions(
        tester,
        LedgerSummary(
          openingBalancePaise: 0,
          entries: <LedgerEntry>[
            spent('চা ও নাস্তা', 'খাবার', DateTime(2026, 11, 19, 9, 0), 4000),
            earned('মাসিক বেতন', 'আয়', DateTime(2026, 11, 18, 10, 0), 300000),
            spent('বাজার', 'খাবার', DateTime(2026, 11, 17, 18, 0), 90000),
          ],
        ),
      );
      await openFilters(tester);

      await tester.enterText(find.byKey(const Key('search-field')), 'খাবার');
      await tester.pumpAndSettle();

      expect(find.text('চা ও নাস্তা'), findsOneWidget);
      expect(find.text('বাজার'), findsOneWidget);
      expect(find.text('মাসিক বেতন'), findsNothing);
      expect(find.text('Showing 2 of 3 transactions'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('search-field')), '  বাজার ');
      await tester.pumpAndSettle();

      expect(find.text('বাজার'), findsOneWidget);
      expect(find.text('চা ও নাস্তা'), findsNothing);
      expect(find.text('Showing 1 of 3 transactions'), findsOneWidget);
    });
  });

  group('date range', () {
    testWidgets('includes the picked day at both ends', (
      WidgetTester tester,
    ) async {
      await pumpAllTransactions(tester, sampleSummary());

      await pickDate(tester, 'date-filter-from', '18');
      expect(find.text('From: 18 Nov 2026'), findsOneWidget);
      expect(find.text('To: any date'), findsOneWidget);
      expect(find.text('Salary'), findsOneWidget);
      expect(find.text('Grocery Shopping'), findsOneWidget);
      expect(find.text('Bus Fare'), findsNothing);
      expect(find.text('Showing 4 of 8 transactions'), findsOneWidget);
      // October and September are entirely before the first day.
      expect(find.byKey(const Key('month-2026-10')), findsNothing);
      expect(find.byKey(const Key('month-2026-09')), findsNothing);

      // An end before the start is the same span, labelled in order.
      await pickDate(tester, 'date-filter-to', '17');
      expect(find.text('From: 17 Nov 2026'), findsOneWidget);
      expect(find.text('To: 18 Nov 2026'), findsOneWidget);
      expect(find.text('Bus Fare'), findsOneWidget);
      expect(find.text('Salary'), findsOneWidget);
      expect(find.text('Grocery Shopping'), findsNothing);
      expect(find.text('Showing 2 of 8 transactions'), findsOneWidget);

      await tapChip(tester, 'date-filter-clear');
      expect(find.text('From: any date'), findsOneWidget);
      expect(find.text('To: any date'), findsOneWidget);
      expect(find.byKey(const Key('date-filter-clear')), findsNothing);
      expect(find.text('Showing 8 transactions'), findsOneWidget);
    });

    testWidgets('a single bound remains open-ended', (
      WidgetTester tester,
    ) async {
      await pumpAllTransactions(tester, sampleSummary());
      await pickDate(tester, 'date-filter-from', '17');
      expect(find.text('Showing 5 of 8 transactions'), findsOneWidget);
      expect(find.text('Grocery Shopping'), findsOneWidget);
      expect(find.text('Bus Fare'), findsOneWidget);
      await tapChip(tester, 'date-filter-clear');
      await pickDate(tester, 'date-filter-to', '18');
      expect(find.text('Showing 5 of 8 transactions'), findsOneWidget);
      expect(find.text('Salary'), findsOneWidget);
      expect(find.text('Grocery Shopping'), findsNothing);
    });

    testWidgets('a single picked day keeps its first and last entry', (
      WidgetTester tester,
    ) async {
      await pumpAllTransactions(tester, sampleSummary());

      await pickDate(tester, 'date-filter-from', '19');
      await pickDate(tester, 'date-filter-to', '19');

      expect(find.text('Grocery Shopping'), findsOneWidget);
      expect(find.text('Lunch with Friends'), findsOneWidget);
      expect(find.text('Mobile Recharge'), findsOneWidget);
      expect(find.text('Salary'), findsNothing);
      expect(find.text('Showing 3 of 8 transactions'), findsOneWidget);
      // The month total follows the three rows that are left.
      expect(
        monthTotals('Nov 2026', 'Income ₹0, Expense ₹1,979.'),
        findsOneWidget,
      );
    });

    testWidgets('dismissing the picker changes nothing', (
      WidgetTester tester,
    ) async {
      await pumpAllTransactions(tester, sampleSummary());

      await openFilters(tester);
      await revealTap(tester, find.byKey(const Key('date-filter-from')));
      await dismissDatePicker(tester);
      expect(find.text('From: any date'), findsOneWidget);
      expect(find.text('Showing 8 transactions'), findsOneWidget);
      expect(find.byKey(const Key('date-filter-clear')), findsNothing);

      // A second dismissal keeps the first choice intact.
      await pickDate(tester, 'date-filter-from', '19');
      await revealTap(tester, find.byKey(const Key('date-filter-to')));
      await dismissDatePicker(tester);
      expect(find.text('From: 19 Nov 2026'), findsOneWidget);
      expect(find.text('To: any date'), findsOneWidget);
      expect(find.text('Showing 3 of 8 transactions'), findsOneWidget);
    });

    testWidgets('query, type, category and dates compose', (
      WidgetTester tester,
    ) async {
      await pumpAllTransactions(tester, sampleSummary());

      await tapChip(tester, 'category-filter-Food');
      await tapChip(tester, 'type-filter-expense');
      await tester.enterText(find.byKey(const Key('search-field')), 'lunch');
      await tester.pumpAndSettle();
      await pickDate(tester, 'date-filter-from', '18');

      expect(find.text('Lunch with Friends'), findsOneWidget);
      // The other Food row is in September, before the first day.
      expect(find.text('Tea Stall'), findsNothing);
      expect(find.text('Showing 1 of 8 transactions'), findsOneWidget);
      expect(
        monthTotals('Nov 2026', 'Income ₹0, Expense ₹580.'),
        findsOneWidget,
      );

      // One more filter that no row satisfies: still a no-match, not empty.
      await tapChip(tester, 'type-filter-income');
      expect(find.byKey(const Key('transactions-no-match')), findsOneWidget);
      expect(find.text('Showing 0 of 8 transactions'), findsOneWidget);

      // Clear all four at once.
      await tapControl(tester, find.byKey(const Key('clear-filters')));
      expect(find.text('Showing 8 transactions'), findsOneWidget);
      expect(find.text('Grocery Shopping'), findsOneWidget);
      expect(find.text('From: any date'), findsOneWidget);
      expect(find.text('To: any date'), findsOneWidget);
      expect(chipCheck('type-filter-all'), findsOneWidget);
      expect(chipCheck('category-filter-all'), findsOneWidget);
      expect(searchText(tester), isEmpty);
    });
  });

  group('filter rules', () {
    final DateTimeRange nov19 = DateTimeRange(
      start: DateTime(2026, 11, 19),
      end: DateTime(2026, 11, 19),
    );

    test('both ends of a single local day are inclusive', () {
      expect(matchesLocalDateRange(DateTime(2026, 11, 19), nov19), isTrue);
      expect(
        matchesLocalDateRange(DateTime(2026, 11, 19, 0, 0), nov19),
        isTrue,
      );
      expect(
        matchesLocalDateRange(DateTime(2026, 11, 19, 23, 59, 59, 999), nov19),
        isTrue,
      );
      // One instant either side of the day is already outside it.
      expect(
        matchesLocalDateRange(DateTime(2026, 11, 18, 23, 59, 59, 999), nov19),
        isFalse,
      );
      expect(matchesLocalDateRange(DateTime(2026, 11, 20), nov19), isFalse);
    });

    test('a UTC instant is read on the local day the user saw', () {
      for (final DateTime local in <DateTime>[
        DateTime(2026, 11, 19),
        DateTime(2026, 11, 19, 12, 30),
        DateTime(2026, 11, 19, 23, 59, 59),
      ]) {
        expect(
          matchesLocalDateRange(local.toUtc(), nov19),
          isTrue,
          reason: '${local.toIso8601String()} is 19 Nov in local time',
        );
      }
      for (final DateTime local in <DateTime>[
        DateTime(2026, 11, 18, 23, 59, 59),
        DateTime(2026, 11, 20),
      ]) {
        expect(
          matchesLocalDateRange(local.toUtc(), nov19),
          isFalse,
          reason: '${local.toIso8601String()} is outside 19 Nov locally',
        );
      }
    });

    test('no date filter matches every day', () {
      expect(matchesLocalDateRange(DateTime(2020, 1, 1), null), isTrue);
      expect(
        matchesLocalDateRange(DateTime(2030, 6, 15, 23, 30), null),
        isTrue,
      );
    });

    test('search trims and ignores case on title or category', () {
      final LedgerEntry entry = spent(
        'Grocery Shopping',
        'Shopping',
        DateTime(2026, 11, 19),
        120000,
      );
      expect(matchesSearchQuery(entry, ''), isTrue);
      expect(matchesSearchQuery(entry, '   '), isTrue);
      expect(matchesSearchQuery(entry, '  grocerY  '), isTrue);
      expect(matchesSearchQuery(entry, 'SHOP'), isTrue);
      expect(matchesSearchQuery(entry, 'Food'), isFalse);
    });

    test('search reads the stored description, not only the title', () {
      final LedgerEntry entry = LedgerEntry(
        title: 'Food',
        description: 'Chai and samosa',
        category: 'Food',
        at: DateTime(2026, 11, 19),
        amountPaise: 1000,
      );
      expect(matchesSearchQuery(entry, 'samosa'), isTrue);
      expect(matchesSearchQuery(entry, 'biryani'), isFalse);
    });
  });

  group('editing', () {
    testWidgets('an edit refresh keeps filters, even a vanished category', (
      WidgetTester tester,
    ) async {
      final LocalLedger ledger = LocalLedger(NativeDatabase.memory());
      await tester.runAsync(() async {
        await ledger.initialize();
        await ledger.addEntry(
          EntryFormResult(
            kind: EntryFormKind.expense,
            amountPaise: 12000,
            category: 'Food',
            description: 'Lunch',
            occurredAt: DateTime(2026, 11, 19, 13, 15),
          ),
        );
        await ledger.addEntry(
          EntryFormResult(
            kind: EntryFormKind.expense,
            amountPaise: 3000,
            category: 'Travel',
            description: 'Bus',
            occurredAt: DateTime(2026, 11, 18, 9, 0),
          ),
        );
      });
      final LedgerSummary? loaded = await tester.runAsync(
        () => ledger.readSummary(),
      );
      expect(loaded, isNotNull);

      await pumpAllTransactions(
        tester,
        loaded!,
        ledger: ledger,
        khataId: 'personal',
      );

      await openFilters(tester);
      await tester.enterText(find.byKey(const Key('search-field')), 'lunch');
      await tester.pumpAndSettle();
      await tapChip(tester, 'category-filter-Food');
      expect(find.text('Showing 1 of 2 transactions'), findsOneWidget);

      // Recategorise the only Food row; the filter must survive the refresh.
      await revealTap(tester, find.text('Lunch'));
      await revealTap(tester, find.byKey(const Key('editor-category-Travel')));
      await revealTap(tester, find.byKey(const Key('editor-update-button')));

      expect(find.text('Showing 0 of 2 transactions'), findsOneWidget);
      expect(find.byKey(const Key('transactions-no-match')), findsOneWidget);
      // The category no longer exists, yet the chip is still listed and still
      // selected, so the filter reads honestly and can be changed.
      expect(find.byKey(const Key('category-filter-Food')), findsOneWidget);
      expect(chipCheck('category-filter-Food'), findsOneWidget);
      expect(searchText(tester), 'lunch');

      await tapControl(tester, find.byKey(const Key('clear-filters')));
      expect(find.text('Showing 2 transactions'), findsOneWidget);
      expect(find.text('Lunch'), findsOneWidget);
      expect(find.text('Bus'), findsOneWidget);
    });
  });

  group('accessibility and layout', () {
    testWidgets('filters are 44 dp+, labelled and show selection in words', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();

      await pumpAllTransactions(tester, sampleSummary());
      await openFilters(tester);

      for (final String key in <String>[
        'type-filter-all',
        'type-filter-income',
        'type-filter-expense',
        'category-filter-all',
        'category-filter-Food',
        'date-filter-from',
        'date-filter-to',
        'search-field',
      ]) {
        expect(
          tester.getSize(find.byKey(Key(key))).height,
          greaterThanOrEqualTo(44),
          reason: '$key must be at least 44 dp tall',
        );
      }

      expect(find.bySemanticsLabel('Type filter: all entries'), findsWidgets);
      expect(find.bySemanticsLabel('Type filter: income'), findsWidgets);
      expect(find.bySemanticsLabel('Category filter: Food'), findsWidgets);
      expect(find.bySemanticsLabel('Date filter: from any date'), findsWidgets);
      expect(find.bySemanticsLabel('Date filter: to any date'), findsWidgets);

      // Selection is not carried by colour alone.
      expect(chipCheck('type-filter-all'), findsOneWidget);
      expect(chipCheck('type-filter-expense'), findsNothing);
      expect(chipCheck('date-filter-from'), findsNothing);
      handle.dispose();
    });

    testWidgets('the search box works at 320 dp and 200% text', (
      WidgetTester tester,
    ) async {
      await pumpAllTransactions(
        tester,
        sampleSummary(),
        size: smallPhone,
        scale: 2.0,
      );
      expect(tester.takeException(), isNull);

      await openFilters(tester);
      await reveal(tester, find.byKey(const Key('search-field')));
      await tester.enterText(find.byKey(const Key('search-field')), 'food');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Showing 2 of 8 transactions'), findsOneWidget);

      await reveal(tester, find.text('Lunch with Friends'));
      expect(find.text('Lunch with Friends'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('fits 320 dp at 200% text scale and keeps working', (
      WidgetTester tester,
    ) async {
      await pumpAllTransactions(
        tester,
        sampleSummary(),
        size: smallPhone,
        scale: 2.0,
      );
      expect(tester.takeException(), isNull);

      await tapChip(tester, 'type-filter-income');
      expect(tester.takeException(), isNull);

      // Income-only rows are further down a 568 dp window: scroll to them.
      await reveal(tester, find.text('Salary'));
      expect(find.text('Salary'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await reveal(tester, find.text('Freelance Work'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('fits the default phone at 100%', (WidgetTester tester) async {
      await pumpAllTransactions(tester, sampleSummary(), size: midPhone);
      expect(tester.takeException(), isNull);
      expect(find.text('All Transactions'), findsOneWidget);
      expect(find.text('Showing 8 transactions'), findsOneWidget);
    });
  });

  group('visual hierarchy', () {
    testWidgets('summary, search, filters and rows stack in reading order', (
      WidgetTester tester,
    ) async {
      await pumpAllTransactions(tester, sampleSummary());

      await openFilters(tester);

      final Finder card = find.byKey(const Key('transactions-summary'));
      final Finder field = find.byKey(const Key('search-field'));
      final Finder dates = find.byKey(const Key('date-filter-from'));
      final Finder row = find.text('Grocery Shopping');

      final double summaryTop = tester.getTopLeft(card).dy;
      final double searchTop = tester.getTopLeft(field).dy;
      final double datesTop = tester.getTopLeft(dates).dy;
      final double rowTop = tester.getTopLeft(row).dy;

      expect(summaryTop, lessThan(searchTop));
      expect(searchTop, lessThan(datesTop));
      expect(datesTop, lessThan(rowTop));
      expect(tester.takeException(), isNull);
    });
  });

  group('polish contract: scanning, chrome and quiet states', () {
    testWidgets('each transaction is one ivory card with a calendar tile', (
      WidgetTester tester,
    ) async {
      await pumpAllTransactions(tester, sampleSummary());

      // The reference frames each transaction instead of ruling a day into one
      // sheet, so the card is the unit: Nov 19 holds three of them.
      const List<String> titles = <String>[
        'Grocery Shopping',
        'Lunch with Friends',
        'Mobile Recharge',
        'Salary',
        'Bus Fare',
        'Diwali Gift',
        'Freelance Work',
        'Tea Stall',
      ];
      for (final String title in titles) {
        expect(
          find.byKey(Key('transaction-row-$title')),
          findsOneWidget,
          reason: '$title is not its own card',
        );
      }

      final Finder first = find.byKey(
        const Key('transaction-row-Grocery Shopping'),
      );
      expect(first, findsOneWidget);
      // The key sits on the card's own frame, so the decoration to inspect is
      // the finder's own widget, not one of its descendants.
      final Container card = tester.widget<Container>(first);
      final BoxDecoration decoration = card.decoration! as BoxDecoration;
      expect(decoration.color, AppColors.surface);
      expect(decoration.borderRadius, BorderRadius.circular(20));

      // Every card carries a local-calendar tile: the day number over the
      // month, so a row is dated without repeating a full timestamp.
      final Finder tile = find.descendant(
        of: first,
        matching: find.byKey(const Key('transaction-day-tile')),
      );
      expect(tile, findsOneWidget);
      expect(
        find.descendant(of: tile, matching: find.text('19')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: tile, matching: find.text('Nov')),
        findsOneWidget,
      );
    });

    testWidgets('amounts sit in one right-hand column, in tabular figures', (
      WidgetTester tester,
    ) async {
      await pumpAllTransactions(tester, sampleSummary());

      const List<String> amounts = <String>[
        '-₹1,200',
        '-₹580',
        '-₹199',
        '+₹5,000',
        '-₹301',
        '-₹2,500.50',
        '+₹7,500',
        '-₹25',
      ];
      final Set<double> rights = <double>{
        for (final String amount in amounts)
          tester.getRect(find.text(amount)).right,
      };
      // Eight rows, one right-hand edge: the column is the point.
      expect(rights, hasLength(1));

      for (final String amount in amounts) {
        final Text figure = tester.widget<Text>(find.text(amount));
        expect(
          figure.style?.fontFeatures,
          contains(FontFeature.tabularFigures()),
          reason: '$amount must use tabular figures',
        );
        expect(figure.textAlign, TextAlign.right, reason: amount);
        expect(figure.style?.fontSize, 18, reason: amount);
      }

      // The totals in the cards are set the same way, so a figure is one
      // kind of thing anywhere on the screen. The month headings carry their
      // totals in the accessible label now, so the visible totals to check
      // are the summary card's.
      final Finder summary = find.byKey(const Key('transactions-summary'));
      for (final String total in <String>['₹12,500', '₹4,805.50']) {
        expect(
          tester
              .widget<Text>(
                find.descendant(of: summary, matching: find.text(total)),
              )
              .style!
              .fontFeatures,
          contains(FontFeature.tabularFigures()),
          reason: '$total must use tabular figures',
        );
      }
    });

    testWidgets('headings step down in one scale', (WidgetTester tester) async {
      await pumpAllTransactions(tester, sampleSummary());

      double sizeOf(String text) =>
          tester.widget<Text>(find.text(text)).style!.fontSize!;
      expect(sizeOf('Nov 2026'), 18);
      expect(sizeOf('19 Nov 2026'), 16);
      // The count moved into the green ribbon on the totals card, where it is
      // the small caption of that card rather than its heading.
      expect(sizeOf('Showing 8 transactions'), 12);
      expect(sizeOf('Grocery Shopping'), 15);
      expect(sizeOf('Bills · 10:20 AM'), 14);
    });

    testWidgets('the search box and the chips use the entry screen chrome', (
      WidgetTester tester,
    ) async {
      await pumpAllTransactions(tester, sampleSummary());
      await openFilters(tester);

      // The search box is the reference's rounded pill: its frame is the
      // capsule around it, so the field itself draws no box. It keeps the
      // entry screens' value type, which is what makes typed text read the
      // same here and in the form.
      final TextField field = tester.widget<TextField>(
        find.byKey(const Key('search-field')),
      );
      expect(field.decoration!.border, InputBorder.none);
      expect(field.decoration!.focusedBorder, InputBorder.none);
      expect(field.style?.fontSize, 15);
      final Container pill = tester.widget<Container>(
        find.byKey(const Key('search-pill')),
      );
      final BoxDecoration pillShape = pill.decoration! as BoxDecoration;
      expect(pillShape.color, AppColors.surface);
      expect(pillShape.borderRadius, BorderRadius.circular(999));
      expect(
        (pillShape.border! as Border).top.color,
        AppColors.outline.withValues(alpha: 0.85),
      );

      // The panels are open now; check the chip chrome. The chip gap is
      // deliberately tight — the list is the thing on this screen.
      await openFilters(tester);
      for (final Wrap wrap in tester.widgetList<Wrap>(find.byType(Wrap))) {
        expect(wrap.spacing, 8);
        expect(wrap.runSpacing, 8);
      }
      final Text label = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('type-filter-all')),
          matching: find.text('All'),
        ),
      );
      expect(label.style?.fontSize, 12);
      expect(label.style?.fontWeight, FontWeight.w800);

      // A chosen chip is flat: the fill, the edge and the check mark already
      // say it is selected, so no elevation is needed.
      final Material chip = tester.widget<Material>(
        find.descendant(
          of: find.byKey(const Key('type-filter-all')),
          matching: find.byType(Material),
        ),
      );
      expect(chip.elevation, 0);
    });

    testWidgets('the end of the list is quiet and tells the truth', (
      WidgetTester tester,
    ) async {
      await pumpAllTransactions(tester, sampleSummary());

      // One card per row makes the list taller than the viewport, so the end
      // of it is reached by scrolling, exactly as a user reaches it.
      await reveal(tester, find.byKey(const Key('transactions-end')));
      expect(find.byKey(const Key('transactions-end')), findsOneWidget);
      expect(find.text('Nothing else in this khata'), findsOneWidget);
      expect(find.text('Nothing else under these filters'), findsNothing);

      // With a filter on, the same line says what has ended: the slice, not
      // the khata.
      await tapChip(tester, 'type-filter-income');
      await reveal(tester, find.byKey(const Key('transactions-end')));
      expect(find.text('Nothing else under these filters'), findsOneWidget);
      expect(find.text('Nothing else in this khata'), findsNothing);

      // No rows at all, so no end-of-list line either - only the no-match card.
      await tapChip(tester, 'category-filter-Food');
      expect(find.byKey(const Key('transactions-no-match')), findsOneWidget);
      expect(find.byKey(const Key('transactions-end')), findsNothing);
    });

    testWidgets('both empty states stay quiet and distinct', (
      WidgetTester tester,
    ) async {
      await pumpAllTransactions(
        tester,
        const LedgerSummary(
          openingBalancePaise: kOpeningPaise,
          entries: <LedgerEntry>[],
        ),
      );

      BoxDecoration cardOf(Finder key) =>
          tester
                  .widget<Container>(
                    find
                        .descendant(of: key, matching: find.byType(Container))
                        .first,
                  )
                  .decoration!
              as BoxDecoration;

      final Finder empty = find.byKey(const Key('transactions-empty'));
      expect(cardOf(empty).borderRadius, BorderRadius.circular(20));
      // A placeholder that carries no figures gets the softer edge.
      expect(
        cardOf(empty).border!.top.color,
        AppColors.outline.withValues(alpha: 0.6),
      );
      expect(cardOf(empty).boxShadow, isNull);
    });
  });
}
