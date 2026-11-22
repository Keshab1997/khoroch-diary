// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khoroch_diary/app.dart';
import 'package:khoroch_diary/features/entry/add_entry_screen.dart';
import 'package:khoroch_diary/features/ledger/data/local_ledger.dart';

Future<void> revealTap(WidgetTester tester, Finder finder) async {
  // Let any in-flight scroll finish first. A focused text field keeps itself
  // and its caret on screen with a scroll request that lands a frame after
  // the field gains focus - if that lands after the jump below, it scrolls
  // the target straight back off screen and the tap is dropped.
  await tester.pumpAndSettle();
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      120,
      scrollable: find.byType(Scrollable).first,
    );
  } else {
    await tester.ensureVisible(finder);
  }
  await tester.pumpAndSettle();
  if (finder.hitTestable().evaluate().isEmpty) {
    // A snackbar from the previous action may cover the control; let it
    // animate out (fake time) and settle before tapping.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder.hitTestable());
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('edit, cancel delete, delete and undo refresh the real ledger', (
    tester,
  ) async {
    final ledger = LocalLedger(NativeDatabase.memory());
    await tester.runAsync(() async {
      await ledger.initialize();
      await ledger.addEntry(
        EntryFormResult(
          kind: EntryFormKind.expense,
          amountPaise: 2000,
          category: 'Food',
          description: 'Lunch',
          occurredAt: DateTime(2026, 1, 2, 18, 30),
        ),
      );
    });
    await tester.pumpWidget(KhorochDiaryApp(ledger: ledger));
    await tester.pumpAndSettle();
    await revealTap(tester, find.text('View All'));
    await revealTap(tester, find.text('Lunch'));
    await tester.enterText(
      find.byKey(const Key('editor-amount-field')),
      '35.50',
    );
    await revealTap(tester, find.byKey(const Key('editor-update-button')));
    expect(find.text('-₹35.50'), findsOneWidget);
    await revealTap(tester, find.text('Lunch'));
    await revealTap(tester, find.byKey(const Key('editor-delete-button')));
    await tester.tap(find.byKey(const Key('cancel-delete-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('transaction-editor-screen')), findsOneWidget);
    await revealTap(tester, find.byKey(const Key('editor-delete-button')));
    await tester.tap(find.byKey(const Key('confirm-delete-button')));
    await tester.pumpAndSettle();
    expect(find.text('Lunch'), findsNothing);
    expect(find.text('Transaction deleted'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Lunch'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Lunch'), findsOneWidget);
    expect(find.text('-₹35.50'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Lunch'), findsOneWidget);
    expect(find.text('-₹35.50'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final summary = await tester.runAsync(() => ledger.readSummary());
    expect(summary!.remainingPaise, -3550);
    expect(summary.entries.single.at.hour, 18);
  });
  testWidgets('undo after returning Home restores the deleted entry', (
    tester,
  ) async {
    final ledger = LocalLedger(NativeDatabase.memory());
    await tester.runAsync(() async {
      await ledger.initialize();
      await ledger.addEntry(
        EntryFormResult(
          kind: EntryFormKind.expense,
          amountPaise: 1000,
          category: 'Food',
          description: 'Tea',
          occurredAt: DateTime(2026, 1, 2),
        ),
      );
    });
    await tester.pumpWidget(KhorochDiaryApp(ledger: ledger));
    await tester.pumpAndSettle();
    await revealTap(tester, find.text('View All'));
    await revealTap(tester, find.text('Tea'));
    await revealTap(tester, find.byKey(const Key('editor-delete-button')));
    await tester.tap(find.byKey(const Key('confirm-delete-button')));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Tea'), findsNothing);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Tea'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
