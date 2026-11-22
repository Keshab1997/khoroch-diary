import 'package:drift/native.dart';
// Flutter 3.50 deprecates this import; migrate with the app's dependency update.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khoroch_diary/app.dart';
import 'package:khoroch_diary/features/counter/note_counter_screen.dart';
import 'package:khoroch_diary/features/counter/note_counter_store.dart';
import 'package:khoroch_diary/features/entry/add_entry_screen.dart';
import 'package:khoroch_diary/features/ledger/data/local_ledger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Opens the app over an in-memory ledger, as the other shell tests do: the
/// database opens outside fake async and the app closes it when unmounted.
Future<LocalLedger> pumpApp(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  tester.view.physicalSize = const Size(400, 860);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final LocalLedger ledger = LocalLedger(NativeDatabase.memory());
  await tester.runAsync(() => ledger.initialize());
  await tester.pumpWidget(KhorochDiaryApp(ledger: ledger));
  await tester.pumpAndSettle();
  return ledger;
}

Future<void> openTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

Future<void> tapKey(WidgetTester tester, String key) async {
  final Finder finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the calculator result opens a prefilled entry form', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);
    await openTab(tester, 'Calculator');
    for (final String key in <String>['2', '5', '0']) {
      await tapKey(tester, 'calc-key-$key');
    }
    await tapKey(tester, 'calculator-use-in-entry');

    final AddEntryScreen form = tester.widget(find.byType(AddEntryScreen));
    expect(form.initialAmountPaise, 25000);
    expect(form.initialKind, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'the note counter saves per khata and hands its total to an income entry',
    (WidgetTester tester) async {
      final LocalLedger ledger = await pumpApp(tester);
      await openTab(tester, 'Counter');

      final NoteCounterScreen counter = tester.widget(
        find.byType(NoteCounterScreen),
      );
      expect(counter.store, isNotNull);
      expect(counter.khataId, 'personal');

      final Finder fiveHundredField = find.byKey(
        const Key('note-counter-field-50000'),
      );
      await tester.ensureVisible(fiveHundredField);
      await tester.tap(fiveHundredField);
      await tester.pump();
      await tester.enterText(fiveHundredField, '2'); // ₹500 × 2
      await tester.pumpAndSettle();
      final NoteCounterSnapshot saved = (await tester.runAsync(
        () => NoteCounterStore(ledger).load('personal'),
      ))!;
      expect(saved.quantityFor(50000), 2);

      await tapKey(tester, 'note-counter-add-to-khata');
      final AddEntryScreen form = tester.widget(find.byType(AddEntryScreen));
      expect(form.initialAmountPaise, 100000);
      expect(form.initialKind, EntryFormKind.income);
      expect(form.initialDescription, isNotEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
