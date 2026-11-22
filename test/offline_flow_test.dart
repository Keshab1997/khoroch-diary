// Flutter 3.50 deprecates this import; migrate in a dedicated dependency update.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khoroch_diary/app.dart';
import 'package:khoroch_diary/features/ledger/data/local_ledger.dart';

void main() {
  testWidgets('save expense updates offline Home and all transactions', (
    tester,
  ) async {
    final ledger = LocalLedger(NativeDatabase.memory());
    await ledger.initialize();
    await tester.pumpWidget(KhorochDiaryApp(ledger: ledger));
    await tester.pumpAndSettle();
    expect(
      find.text('No transactions yet. Add an entry to see it here.'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Add New Entry'));
    await tester.tap(find.text('Add New Entry'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('amount-field')), '580.05');
    await tester.pump();
    await tester.tap(find.text('Food'));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('description-field')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('description-field')), 'Lunch');
    await tester.ensureVisible(find.text('Save Entry'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Entry'));
    await tester.pumpAndSettle();
    expect(find.text('Lunch'), findsOneWidget);
    expect(find.text('-₹580.05'), findsOneWidget);
    expect(find.text('₹580.05'), findsNWidgets(2));
    await tester.ensureVisible(find.text('View All'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View All'));
    await tester.pumpAndSettle();
    expect(find.text('All Transactions'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Lunch'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Lunch'), findsOneWidget);
  });
}
