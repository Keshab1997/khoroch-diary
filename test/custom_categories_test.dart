import 'package:drift/native.dart';
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khoroch_diary/features/entry/category_store.dart';
import 'package:khoroch_diary/features/entry/add_entry_screen.dart';
import 'package:khoroch_diary/features/entry/transaction_editor_screen.dart';
import 'package:khoroch_diary/features/home/home_screen.dart';
import 'package:khoroch_diary/features/home/models.dart';
import 'package:khoroch_diary/features/ledger/all_transactions_screen.dart';
import 'package:khoroch_diary/features/ledger/data/local_ledger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('custom category keeps its id through rename and archive', () async {
    final ledger = LocalLedger(NativeDatabase.memory());
    addTearDown(ledger.close);
    final store = CategoryStore(ledger);
    final category = await store.add('  Tea  ', iconIndex: 1, colorIndex: 1);
    expect(category.id, startsWith('custom:'));
    expect((await store.load()).single.name, 'Tea');
    await store.rename(category.id, 'Coffee');
    expect((await store.load()).single.id, category.id);
    expect((await store.load()).single.name, 'Coffee');
    await store.archive(category.id);
    expect(await store.load(), isEmpty);
    expect((await store.load(includeArchived: true)).single.archived, isTrue);
    await expectLater(store.add(''), throwsFormatException);
  });

  testWidgets('both entry pickers offer active custom categories', (
    tester,
  ) async {
    final ledger = LocalLedger(NativeDatabase.memory());
    addTearDown(ledger.close);
    final store = CategoryStore(ledger);
    final category = (await tester.runAsync(() => store.add('Tea')))!;
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: AddEntryScreen(
          categoryStore: store,
          openingBalancePaise: 0,
          onSave: (_) {},
        ),
      ),
    );
    await waitFor(tester, find.byKey(Key('custom-category-${category.id}')));
    expect(find.text('Tea'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        home: TransactionEditorScreen(
          categoryStore: store,
          initial: EntryFormResult(
            kind: EntryFormKind.expense,
            amountPaise: 100,
            category: 'Food',
            description: '',
            occurredAt: DateTime(2026),
          ),
          onUpdate: (_) async => true,
          onDelete: () async => true,
        ),
      ),
    );
    await waitFor(tester, find.byKey(Key('custom-category-${category.id}')));
    expect(find.text('Tea'), findsOneWidget);
  });

  testWidgets('More creates and selects, renames, then archives a category', (
    tester,
  ) async {
    final ledger = LocalLedger(NativeDatabase.memory());
    addTearDown(ledger.close);
    final store = CategoryStore(ledger);
    await tester.runAsync(() => store.load());
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final saved = <EntryFormResult>[];
    await tester.pumpWidget(
      MaterialApp(
        home: AddEntryScreen(
          categoryStore: store,
          openingBalancePaise: 0,
          initialAmountPaise: 100,
          onSave: saved.add,
        ),
      ),
    );
    await waitFor(tester, find.byKey(const Key('category-more')));
    await tester.tap(find.byKey(const Key('category-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new-category')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('category-name')), 'Tea');
    await tester.tap(find.byKey(const Key('save-category')));
    await waitFor(tester, find.text('Tea'));
    await tester.ensureVisible(find.text('Save Entry'));
    await tester.tap(find.text('Save Entry'));
    await tester.pumpAndSettle();
    expect(saved.single.category, startsWith('custom:'));
    await tester.ensureVisible(find.byKey(const Key('category-more')));
    await tester.tap(find.byKey(const Key('category-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('category-name')), 'Coffee');
    await tester.tap(find.byKey(const Key('save-category')));
    // The sheet's CategoryCatalog rebuilds after the rename; the sheet itself
    // stays open, so the rename shows in place. The selected chip in the
    // AddEntry row also shows the new name, so "Coffee" appears twice.
    await tester.pumpAndSettle();
    expect(find.text('Coffee'), findsNWidgets(2));
    await tester.tap(find.byTooltip('Archive'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-archive-category')));
    await tester.pumpAndSettle();
    final all = (await tester.runAsync(
      () => store.load(includeArchived: true),
    ))!;
    expect(all.single.name, 'Coffee');
    expect(all.single.archived, isTrue);
  });

  testWidgets(
    'home and transactions display archived names and unknown fallback',
    (tester) async {
      final ledger = LocalLedger(NativeDatabase.memory());
      addTearDown(ledger.close);
      final store = CategoryStore(ledger);
      final category = (await tester.runAsync(() async {
        final item = await store.add('Tea', iconIndex: 1, colorIndex: 1);
        await store.archive(item.id);
        return item;
      }))!;
      final summary = LedgerSummary(
        openingBalancePaise: 0,
        entries: [
          LedgerEntry(
            title: category.id,
            category: category.id,
            at: DateTime(2026),
            amountPaise: 100,
          ),
          LedgerEntry(
            title: 'custom:missing',
            category: 'custom:missing',
            at: DateTime(2026),
            amountPaise: 200,
          ),
        ],
      );
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(summary: summary, categoryStore: store),
        ),
      );
      await waitFor(tester, find.text('Tea'));
      expect(find.text('Other'), findsWidgets);
      expect(find.text('custom:missing'), findsNothing);
      await tester.pumpWidget(
        MaterialApp(
          home: AllTransactionsScreen(summary: summary, categoryStore: store),
        ),
      );
      await waitFor(tester, find.text('Tea'));
      expect(find.text('Other'), findsWidgets);
      expect(find.text('custom:missing'), findsNothing);
      // The filter panels start collapsed; only open them before looking for
      // chips, which live inside them.
      await openFilters(tester);
      expect(find.byKey(Key('category-filter-${category.id}')), findsOneWidget);
      expect(find.byIcon(Icons.restaurant), findsWidgets);
    },
  );
}

/// Opens the filter panels, which start collapsed: the list is the first
/// screenful now, not the blank filter area. The summary card's search
/// button is the way in; the tune cap only exists once the panels are open.
Future<void> openFilters(WidgetTester tester) async {
  if (find.byKey(const Key('date-filter-from')).evaluate().isNotEmpty) {
    return;
  }
  await tester.tap(find.byKey(const Key('transactions-search')));
  await tester.pumpAndSettle();
}

Future<void> waitFor(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100; i++) {
    await tester.pumpAndSettle();
    if (finder.evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  expect(finder, findsWidgets);
}
