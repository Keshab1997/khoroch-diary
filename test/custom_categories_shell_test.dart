import 'package:drift/native.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khoroch_diary/app.dart';
import 'package:khoroch_diary/core/l10n/app_strings.dart';
import 'package:khoroch_diary/features/entry/add_entry_screen.dart';
import 'package:khoroch_diary/features/entry/category_picker.dart';
import 'package:khoroch_diary/features/entry/category_store.dart';
import 'package:khoroch_diary/features/entry/transaction_editor_screen.dart';
import 'package:khoroch_diary/features/home/home_screen.dart';
import 'package:khoroch_diary/features/ledger/all_transactions_screen.dart';
import 'package:khoroch_diary/features/ledger/data/ledger_backup.dart';
import 'package:khoroch_diary/features/ledger/data/local_ledger.dart';
import 'package:khoroch_diary/features/profile/backup_screen.dart';
import 'package:khoroch_diary/features/profile/profile_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wait for a real UI condition while native database work runs outside the
/// test clock. This is bounded and never treats a fixed number of pumps as a
/// successful database read.
Future<void> waitFor(WidgetTester tester, Finder finder) async {
  final DateTime deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  fail('Timed out waiting for $finder');
}

Future<void> revealTap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder.hitTestable());
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a custom category flows through the real shell and editor', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final LocalLedger ledger = LocalLedger(NativeDatabase.memory());
    await tester.runAsync(() => ledger.initialize());
    await tester.pumpWidget(KhorochDiaryApp(ledger: ledger));
    await waitFor(tester, find.byType(HomeScreen));
    final CategoryStore store = tester
        .widget<HomeScreen>(find.byType(HomeScreen))
        .categoryStore!;

    await revealTap(tester, find.byKey(const Key('home-add-entry')));
    final AddEntryScreen entry = tester.widget(find.byType(AddEntryScreen));
    expect(identical(entry.categoryStore, store), isTrue);
    await revealTap(tester, find.byKey(const Key('category-more')));
    expect(
      find.byKey(const Key('custom-category-local-notice')),
      findsOneWidget,
    );
    expect(
      find.text(
        'Custom category names and icons stay on this device; they are not synced to the cloud.',
      ),
      findsOneWidget,
    );
    await revealTap(tester, find.byKey(const Key('new-category')));
    await tester.enterText(find.byKey(const Key('category-name')), 'Tea');
    await revealTap(tester, find.byKey(const Key('save-category')));
    await waitFor(tester, find.text('Tea'));
    final List<CustomCategory> categories = (await tester.runAsync(
      () => store.load(),
    ))!;
    final String id = categories.single.id;

    await tester.enterText(find.byKey(const Key('amount-field')), '12.50');
    await tester.enterText(
      find.byKey(const Key('description-field')),
      'Morning bus',
    );
    await revealTap(tester, find.byKey(const Key('save-entry-button')));
    await waitFor(tester, find.byType(HomeScreen));
    await waitFor(tester, find.text('Morning bus'));
    await waitFor(tester, find.text('Tea'));
    expect(find.text(id), findsNothing);
    final summary = (await tester.runAsync(() => ledger.readSummary()))!;
    expect(summary.entries.single.category, id);
    expect(summary.entries.single.amountPaise, 1250);

    await revealTap(tester, find.text('View All'));
    final AllTransactionsScreen transactions = tester.widget(
      find.byType(AllTransactionsScreen),
    );
    expect(identical(transactions.categoryStore, store), isTrue);
    // The filter panels start collapsed; only open them before looking for
    // chips, which live inside them. The summary card's search button is
    // the way in now.
    await revealTap(tester, find.byKey(const Key('transactions-search')));
    await waitFor(tester, find.byKey(Key('category-filter-$id')));
    await tester.scrollUntilVisible(
      find.text('Morning bus'),
      120,
      scrollable: find
          .descendant(
            of: find.byType(AllTransactionsScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await revealTap(tester, find.text('Morning bus'));
    final TransactionEditorScreen editor = tester.widget(
      find.byType(TransactionEditorScreen),
    );
    expect(identical(editor.categoryStore, store), isTrue);
    expect(editor.initial.category, id);
    await waitFor(tester, find.byKey(Key('custom-category-$id')));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the local-only category notice is Bengali and wraps at 200%', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final LocalLedger ledger = LocalLedger(NativeDatabase.memory());
    final CategoryStore store = CategoryStore(ledger);
    await tester.runAsync(() => ledger.initialize());
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: Center(
            child: CustomCategoryChoices(
              store: store,
              language: AppLanguage.bn,
              selected: null,
              onSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    await revealTap(tester, find.byKey(const Key('category-more')));
    expect(
      find.text(
        'নিজের বিভাগের নাম ও আইকন এই ডিভাইসেই থাকে; ক্লাউডে সিঙ্ক হয় না।',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
    await tester.runAsync(() => ledger.close());
  });

  testWidgets('offline restore refreshes mounted category names', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final TargetPlatform? previous = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = previous);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final LocalLedger ledger = LocalLedger(NativeDatabase.memory());
    late final CustomCategory category;
    late final String backupJson;
    await tester.runAsync(() async {
      await ledger.initialize();
      final CategoryStore seed = CategoryStore(ledger);
      category = await seed.add('Tea');
      await ledger.addEntry(
        EntryFormResult(
          kind: EntryFormKind.expense,
          amountPaise: 100,
          category: category.id,
          description: '',
          occurredAt: DateTime(2026, 1, 2),
        ),
      );
      backupJson = await LedgerBackup(ledger).exportJson();
      seed.dispose();
    });
    await tester.pumpWidget(KhorochDiaryApp(ledger: ledger));
    await waitFor(tester, find.text('Tea'));
    final CategoryStore store = tester
        .widget<HomeScreen>(find.byType(HomeScreen))
        .categoryStore!;
    await tester.runAsync(() => store.rename(category.id, 'Coffee'));
    await waitFor(tester, find.text('Coffee'));

    final ProfileScreen profile = tester.widget(
      find.byType(ProfileScreen, skipOffstage: false),
    );
    expect(profile.onBackup, isNotNull);
    profile.onBackup!();
    await tester.pumpAndSettle();
    final BackupScreen screen = tester.widget(find.byType(BackupScreen));
    final bool? restored = await tester.runAsync(
      () => screen.onRestore(
        BackupPreview(
          payload: backupJson,
          khataCount: 1,
          transactionCount: 1,
          deletedTransactionCount: 0,
        ),
      ),
    );
    expect(restored, isTrue);
    Navigator.of(tester.element(find.byType(BackupScreen))).pop(true);
    // The shell reloads SQLite after a restore and shows an animated loading
    // indicator. Wait for the actual restored content while yielding to I/O;
    // pumpAndSettle cannot settle while that indicator is still running.
    await waitFor(tester, find.text('Tea'));
    expect(find.text('Coffee'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
