// Bilingual coverage for the ledger screens: All Transactions, Wallet Summary,
// the khata switcher and Manage Khatas.
//
// Every test here has one of two jobs: prove the default English screen is
// byte-for-byte what it was before localization, or prove the Bengali screen is
// translated while the data underneath - stored categories, user-entered
// titles, ids and integer paise - is still handled exactly as the English
// screen handles it.

// Flutter 3.50 deprecates these imports; migrate with the app's dependency
// update.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
// ignore: deprecated_member_use
import 'package:flutter/semantics.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khoroch_diary/core/l10n/app_strings.dart';
import 'package:khoroch_diary/features/entry/add_entry_screen.dart';
import 'package:khoroch_diary/features/home/models.dart';
import 'package:khoroch_diary/features/ledger/all_transactions_screen.dart';
import 'package:khoroch_diary/features/ledger/data/local_ledger.dart';
import 'package:khoroch_diary/features/ledger/khata_manage_screen.dart';
import 'package:khoroch_diary/features/ledger/khata_switcher.dart';
import 'package:khoroch_diary/features/ledger/wallet_summary_screen.dart';

const AppStrings bn = AppStrings(AppLanguage.bn);

/// Tall enough that every list child is built, so a missing string really means
/// "not on the screen".
const Size tallPhone = Size(400, 2400);
const Size smallPhone = Size(320, 1200);

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

/// Four rows over two local days, with the ₹10,000 opening balance that must
/// never appear on All Transactions.
LedgerSummary sampleSummary() => LedgerSummary(
  openingBalancePaise: 1000000,
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
  ],
);

Future<void> pumpScreen(
  WidgetTester tester,
  Widget screen, {
  Size size = tallPhone,
  double scale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: screen,
    ),
  );
  await tester.pumpAndSettle();
}

/// Opens the All Transactions filter panels when the target is inside them.
/// The summary card's search button is the way in; the tune cap only exists
/// once the panels are already open. On any other screen this is a no-op, so
/// [tapKey] can call it unconditionally.
Future<void> openFilters(WidgetTester tester) async {
  if (find.byKey(const Key('date-filter-from')).evaluate().isNotEmpty) {
    return;
  }
  final Finder search = find.byKey(const Key('transactions-search'));
  if (search.evaluate().isEmpty) {
    return;
  }
  await tester.tap(search);
  await tester.pumpAndSettle();
}

Future<void> tapKey(WidgetTester tester, String key) async {
  await openFilters(tester);
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

/// Scrolls a lazily built list until [finder] is on screen.
Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

/// The value shown inside the filter-aware summary card.
Finder summaryText(String value) => find.descendant(
  of: find.byKey(const Key('transactions-summary')),
  matching: find.text(value),
);

EntryFormResult entryForm({
  required EntryFormKind kind,
  required int amountPaise,
  required String category,
  required DateTime occurredAt,
}) => EntryFormResult(
  kind: kind,
  amountPaise: amountPaise,
  category: category,
  description: '',
  occurredAt: occurredAt,
);

void main() {
  group('All Transactions', () {
    testWidgets('defaults to the unchanged English copy', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester, AllTransactionsScreen(summary: sampleSummary()));
      await openFilters(tester);

      expect(find.text('All Transactions'), findsOneWidget);
      expect(find.text('Showing 4 transactions'), findsOneWidget);
      expect(find.text('Search transactions'), findsOneWidget);
      expect(find.text('Description or category'), findsOneWidget);
      expect(find.text('Date'), findsOneWidget);
      expect(find.text('Type'), findsOneWidget);
      expect(find.text('Category'), findsOneWidget);
      expect(find.text('From: any date'), findsOneWidget);
      expect(find.text('To: any date'), findsOneWidget);
      // The quick-filter pills say "All" too, so the word appears more than
      // once; what matters is the panels carry it.
      expect(find.text('All'), findsWidgets);
      expect(find.text('Food'), findsOneWidget); // canonical category chip
      expect(find.text('Grocery Shopping'), findsOneWidget);
      // A row card shows `category · time`; the date itself is the calendar
      // tile on its left and the day heading above it, in the shared format.
      expect(find.text('Bills · 10:20 AM'), findsOneWidget);
      expect(summaryText('₹5,000'), findsOneWidget);
      expect(summaryText('₹1,979'), findsOneWidget);
      // The opening balance is never on this screen, in either language.
      expect(find.textContaining('₹10,000'), findsNothing);
    });

    testWidgets('Bengali translates labels but leaves the data untouched', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        AllTransactionsScreen(
          summary: sampleSummary(),
          language: AppLanguage.bn,
        ),
      );
      await openFilters(tester);

      expect(find.text(bn.text(AppString.allTransactions)), findsOneWidget);
      expect(
        find.text(bn.transactionCount(shown: 4, total: 4)),
        findsOneWidget,
      );
      expect(find.text(bn.text(AppString.searchTransactions)), findsOneWidget);
      expect(find.text(bn.text(AppString.date)), findsOneWidget);
      expect(find.text(bn.text(AppString.type)), findsOneWidget);
      expect(find.text(bn.text(AppString.category)), findsOneWidget);
      // The quick-filter pills say "সব" too; the panels carry it as well.
      expect(find.text(bn.text(AppString.all)), findsWidgets);
      expect(find.text(bn.text(AppString.food)), findsOneWidget);
      expect(find.text(bn.text(AppString.fromAnyDate)), findsOneWidget);

      // User-entered titles, the stored month and the money all survive as
      // themselves; only the digits are Bengali.
      expect(find.text('Grocery Shopping'), findsOneWidget);
      expect(find.text('Lunch with Friends'), findsOneWidget);
      expect(find.text('Salary'), findsOneWidget);
      expect(find.text(bn.monthYear(DateTime(2026, 11))), findsOneWidget);
      // The row's metadata is the category plus the shared helper's time
      // tail; its date is the calendar tile beside it and the day heading
      // above, both still printed in the shared format. Only the row's own
      // repeat of the date is dropped, in both languages alike.
      expect(
        find.text(
          '${bn.text(AppString.bills)} · '
          '${bn.dateTime(DateTime(2026, 11, 19, 10, 20)).split(',').last.trim()}',
        ),
        findsOneWidget,
      );
      expect(find.text(bn.signedMoney(120000, income: false)), findsOneWidget);
      expect(summaryText(bn.money(500000)), findsOneWidget);
      expect(find.textContaining(bn.money(1000000)), findsNothing);
    });

    testWidgets('a translated category chip filters the same canonical rows', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        AllTransactionsScreen(
          summary: sampleSummary(),
          language: AppLanguage.bn,
        ),
      );
      await openFilters(tester);

      // The chip reads Bengali, its key and filter value are still `Food`.
      expect(find.byKey(const Key('category-filter-Food')), findsOneWidget);
      await tapKey(tester, 'category-filter-Food');

      expect(find.text('Lunch with Friends'), findsOneWidget);
      expect(find.text('Grocery Shopping'), findsNothing);
      expect(find.text('Mobile Recharge'), findsNothing);
      expect(
        find.text(bn.transactionCount(shown: 1, total: 4)),
        findsOneWidget,
      );
      // The chosen category reads in Bengali on both the quick pill and the
      // panel chip, so the word appears twice.
      expect(find.text(bn.text(AppString.food)), findsWidgets);

      // Clearing the filter brings every row back, still in Bengali.
      await tapKey(tester, 'category-filter-all');
      expect(find.text('Grocery Shopping'), findsOneWidget);
      expect(
        find.text(bn.transactionCount(shown: 4, total: 4)),
        findsOneWidget,
      );
    });

    testWidgets('search reads stored user data, never a translated label', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        AllTransactionsScreen(
          summary: sampleSummary(),
          language: AppLanguage.bn,
        ),
      );
      await openFilters(tester);

      await tester.enterText(find.byKey(const Key('search-field')), 'lunch');
      await tester.pumpAndSettle();
      expect(find.text('Lunch with Friends'), findsOneWidget);
      expect(find.text('Grocery Shopping'), findsNothing);

      // A Bengali category label is a display string, not stored data, so it
      // must not match anything: matching on labels would make the result
      // depend on the UI language.
      await tester.enterText(
        find.byKey(const Key('search-field')),
        bn.text(AppString.food),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('transactions-no-match')), findsOneWidget);
      expect(find.text('Lunch with Friends'), findsNothing);
    });

    testWidgets('the live totals follow a chip in Bengali', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        AllTransactionsScreen(
          summary: sampleSummary(),
          language: AppLanguage.bn,
        ),
      );

      await tapKey(tester, 'type-filter-income');
      expect(
        find.text(bn.transactionCount(shown: 1, total: 4)),
        findsOneWidget,
      );
      expect(summaryText(bn.money(500000)), findsOneWidget);
      expect(summaryText(bn.money(0)), findsOneWidget);
      expect(find.text('Salary'), findsOneWidget);
      expect(find.text('Grocery Shopping'), findsNothing);
    });

    testWidgets('chips and rows are labelled in Bengali for a screen reader', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpScreen(
        tester,
        AllTransactionsScreen(
          summary: sampleSummary(),
          language: AppLanguage.bn,
        ),
      );
      await openFilters(tester);

      expect(
        find.bySemanticsLabel(bn.text(AppString.incomeFilter)),
        findsWidgets,
      );
      expect(
        find.bySemanticsLabel(bn.text(AppString.expenseFilter)),
        findsWidgets,
      );
      expect(
        find.bySemanticsLabel(bn.text(AppString.allTypesFilter)),
        findsWidgets,
      );
      expect(
        find.bySemanticsLabel(bn.text(AppString.fromAnyDateFilter)),
        findsWidgets,
      );
      expect(
        find.bySemanticsLabel(
          bn.categoryLabel(bn.text(AppString.food), filter: true),
        ),
        findsWidgets,
      );
      handle.dispose();
    });

    testWidgets('320 dp at 200% text scale fits in Bengali', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        AllTransactionsScreen(
          summary: sampleSummary(),
          language: AppLanguage.bn,
        ),
        size: smallPhone,
        scale: 2,
      );

      expect(tester.takeException(), isNull);
      expect(find.text(bn.text(AppString.allTransactions)), findsOneWidget);
      // The rows live below the filter block on a short screen, so scroll to
      // them instead of assuming they were built.
      await reveal(tester, find.text('Grocery Shopping'));
      expect(find.text('Grocery Shopping'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Wallet Summary', () {
    testWidgets('defaults to English and translates to Bengali', (
      WidgetTester tester,
    ) async {
      final LocalLedger ledger = LocalLedger(NativeDatabase.memory());
      await tester.runAsync(() => ledger.initialize());
      await tester.runAsync(
        () => ledger.addEntry(
          entryForm(
            kind: EntryFormKind.income,
            amountPaise: 200000,
            category: 'Income',
            occurredAt: DateTime(2026, 11, 1),
          ),
        ),
      );

      await pumpScreen(tester, WalletSummaryScreen(ledger: ledger));
      expect(find.text('Wallet Summary'), findsOneWidget);
      expect(find.text('Combined remaining'), findsOneWidget);
      expect(find.text('1 entry'), findsOneWidget);
      expect(find.text('Opening balance'), findsOneWidget);
      expect(find.text('₹2,000'), findsWidgets);

      await pumpScreen(
        tester,
        WalletSummaryScreen(ledger: ledger, language: AppLanguage.bn),
      );
      expect(find.text(bn.text(AppString.walletSummary)), findsOneWidget);
      expect(find.text(bn.text(AppString.combinedRemaining)), findsOneWidget);
      expect(find.text(bn.entryCount(1)), findsOneWidget);
      expect(find.text(bn.text(AppString.openingBalance)), findsOneWidget);
      expect(find.text(bn.text(AppString.remaining)), findsOneWidget);
      expect(find.text(bn.acrossKhatas(1)), findsOneWidget);
      expect(
        find.text(bn.text(AppString.walletOpeningExplanation)),
        findsOneWidget,
      );
      expect(find.text(bn.money(200000)), findsWidgets);
      // The khata name is user data and stays exactly as stored.
      expect(find.text('Personal Khata'), findsOneWidget);

      await tester.runAsync(() => ledger.close());
    });

    testWidgets('320 dp Bengali wallet fits at 200% text scale', (
      WidgetTester tester,
    ) async {
      final LocalLedger ledger = LocalLedger(NativeDatabase.memory());
      await tester.runAsync(() => ledger.initialize());
      await tester.runAsync(
        () => ledger.addEntry(
          entryForm(
            kind: EntryFormKind.income,
            amountPaise: 200000,
            category: 'Income',
            occurredAt: DateTime(2026, 11, 2),
          ),
        ),
      );

      await pumpScreen(
        tester,
        WalletSummaryScreen(ledger: ledger, language: AppLanguage.bn),
        size: smallPhone,
        scale: 2,
      );
      expect(tester.takeException(), isNull);
      expect(find.text(bn.text(AppString.combinedRemaining)), findsOneWidget);
      expect(find.text('Personal Khata'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() => ledger.close());
    });

    testWidgets('the combined card is readable from Bengali semantics', (
      WidgetTester tester,
    ) async {
      final LocalLedger ledger = LocalLedger(NativeDatabase.memory());
      await tester.runAsync(() => ledger.initialize());
      await tester.runAsync(
        () => ledger.addEntry(
          entryForm(
            kind: EntryFormKind.income,
            amountPaise: 200000,
            category: 'Income',
            occurredAt: DateTime(2026, 11, 1),
          ),
        ),
      );

      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpScreen(
        tester,
        WalletSummaryScreen(ledger: ledger, language: AppLanguage.bn),
      );
      expect(
        find.bySemanticsLabel(bn.walletTotal(khatas: 1, paise: 200000)),
        findsOneWidget,
      );
      handle.dispose();
      await tester.runAsync(() => ledger.close());
    });
  });

  group('Manage Khatas', () {
    const LocalKhata personal = LocalKhata(
      id: 'personal',
      name: 'Personal',
      openingBalancePaise: 0,
    );
    const LocalKhata business = LocalKhata(
      id: 'biz',
      name: 'Business',
      openingBalancePaise: 50000,
    );

    Future<void> pumpManage(
      WidgetTester tester, {
      required List<LocalKhata> active,
      required List<LocalKhata> archived,
      Future<void> Function(String id, String name)? onRename,
      Future<void> Function(String id)? onArchive,
      Size size = tallPhone,
      double scale = 1,
    }) async {
      await pumpScreen(
        tester,
        KhataManageScreen(
          language: AppLanguage.bn,
          loadActive: () async => List<LocalKhata>.of(active),
          loadArchived: () async => List<LocalKhata>.of(archived),
          onRename: onRename ?? (_, _) async {},
          onArchive: onArchive ?? (_) async {},
          onUnarchive: (_) async {},
        ),
        size: size,
        scale: scale,
      );
    }

    testWidgets('labels the lists in Bengali and protects the default khata', (
      WidgetTester tester,
    ) async {
      await pumpManage(
        tester,
        active: <LocalKhata>[personal, business],
        archived: <LocalKhata>[],
      );

      expect(find.text(bn.text(AppString.manageKhatas)), findsOneWidget);
      expect(find.text(bn.text(AppString.activeKhatas)), findsOneWidget);
      expect(find.text(bn.text(AppString.archivedKhatas)), findsOneWidget);
      expect(find.text(bn.text(AppString.noArchivedKhatas)), findsOneWidget);
      expect(find.text(bn.text(AppString.defaultKhata)), findsOneWidget);
      // Khata names are user data, in either language.
      expect(find.text('Personal'), findsOneWidget);
      expect(find.text('Business'), findsOneWidget);
      // The personal khata can never be archived.
      expect(find.byKey(const Key('archive-khata-personal')), findsNothing);
    });

    testWidgets('the archive dialog cancels cleanly, then archives', (
      WidgetTester tester,
    ) async {
      final List<LocalKhata> active = <LocalKhata>[personal, business];
      final List<LocalKhata> archived = <LocalKhata>[];
      await pumpManage(
        tester,
        active: active,
        archived: archived,
        onArchive: (String id) async {
          final LocalKhata moved = active.firstWhere(
            (LocalKhata khata) => khata.id == id,
          );
          active.remove(moved);
          archived.add(moved);
        },
      );

      await tapKey(tester, 'archive-khata-biz');
      expect(find.text(bn.text(AppString.archiveQuestion)), findsOneWidget);
      expect(find.text(bn.archiveConfirmation('Business')), findsOneWidget);

      await tapKey(tester, 'cancel-archive');
      expect(find.text('Business'), findsOneWidget);
      expect(archived, isEmpty);

      await tapKey(tester, 'archive-khata-biz');
      expect(find.text(bn.text(AppString.archive)), findsOneWidget);
      await tapKey(tester, 'confirm-archive');

      expect(archived.map((LocalKhata khata) => khata.id), <String>['biz']);
      expect(find.byKey(const Key('active-khata-biz')), findsNothing);
      expect(find.byKey(const Key('archived-khata-biz')), findsOneWidget);
      expect(find.byKey(const Key('empty-archived-khatas')), findsNothing);
    });

    testWidgets('the rename dialog validates in Bengali, saves verbatim', (
      WidgetTester tester,
    ) async {
      String? renamed;
      await pumpManage(
        tester,
        active: <LocalKhata>[personal, business],
        archived: <LocalKhata>[],
        onRename: (String id, String name) async => renamed = name,
      );

      await tapKey(tester, 'rename-khata-biz');
      expect(find.text(bn.text(AppString.renameKhata)), findsOneWidget);
      expect(find.text(bn.text(AppString.khataName)), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('rename-khata-input')),
        '   ',
      );
      await tapKey(tester, 'save-rename');
      expect(find.text(bn.nameLength(40)), findsOneWidget);
      expect(renamed, isNull);

      await tester.enterText(
        find.byKey(const Key('rename-khata-input')),
        'সমিতির খাতা',
      );
      await tapKey(tester, 'save-rename');
      expect(renamed, 'সমিতির খাতা');
    });

    testWidgets('320 dp at 200% text scale fits in Bengali', (
      WidgetTester tester,
    ) async {
      await pumpManage(
        tester,
        active: <LocalKhata>[personal, business],
        archived: <LocalKhata>[],
        size: smallPhone,
        scale: 2,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Personal'), findsOneWidget);
    });
  });

  group('khata switcher', () {
    testWidgets('keeps the English copy when no language is passed', (
      WidgetTester tester,
    ) async {
      const List<LocalKhata> khatas = <LocalKhata>[
        LocalKhata(id: 'personal', name: 'Personal', openingBalancePaise: 0),
      ];
      final LocalLedger ledger = LocalLedger(NativeDatabase.memory());
      await tester.runAsync(() => ledger.initialize());

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  key: const Key('open-switcher-en'),
                  onPressed: () =>
                      showKhataSwitcher(context, ledger, khatas, 'personal'),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tapKey(tester, 'open-switcher-en');

      expect(find.text('Choose Khata'), findsOneWidget);
      expect(find.text('New Khata'), findsOneWidget);
      expect(find.text('Personal'), findsOneWidget);
      await tester.runAsync(() => ledger.close());
    });

    testWidgets('is labelled in Bengali and creates the typed name verbatim', (
      WidgetTester tester,
    ) async {
      const List<LocalKhata> khatas = <LocalKhata>[
        LocalKhata(id: 'personal', name: 'Personal', openingBalancePaise: 0),
        LocalKhata(id: 'biz', name: 'Business', openingBalancePaise: 0),
      ];
      final LocalLedger ledger = LocalLedger(NativeDatabase.memory());
      await tester.runAsync(() => ledger.initialize());

      LocalKhata? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  key: const Key('open-switcher'),
                  onPressed: () async {
                    opened = await showKhataSwitcher(
                      context,
                      ledger,
                      khatas,
                      'personal',
                      language: AppLanguage.bn,
                      onManage: () async {},
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tapKey(tester, 'open-switcher');

      expect(find.text(bn.text(AppString.chooseKhata)), findsOneWidget);
      expect(find.text(bn.text(AppString.newKhata)), findsOneWidget);
      expect(find.text(bn.text(AppString.manageKhatas)), findsOneWidget);
      expect(find.text('Personal'), findsOneWidget);
      expect(find.text('Business'), findsOneWidget);

      await tapKey(tester, 'new-khata');
      expect(find.text(bn.text(AppString.khataName)), findsOneWidget);
      expect(find.text(bn.text(AppString.openingBalanceInput)), findsOneWidget);
      expect(find.text(bn.text(AppString.cancel)), findsOneWidget);

      await tester.enterText(find.byKey(const Key('khata-name')), 'নতুন খাতা');
      await tapKey(tester, 'create-khata');

      expect(opened, isNotNull);
      expect(opened!.name, 'নতুন খাতা');
      await tester.runAsync(() => ledger.close());
    });
  });
}
