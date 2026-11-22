import 'dart:io';

// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khoroch_diary/app.dart';
import 'package:khoroch_diary/features/ledger/data/local_ledger.dart';

void main() {
  testWidgets('selection survives shell restart and entries stay isolated', (
    tester,
  ) async {
    final Directory dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('khata_shell_restart_'),
    ))!;
    addTearDown(() => dir.delete(recursive: true));
    final File file = File('${dir.path}/ledger.sqlite');
    LocalLedger ledger = LocalLedger(NativeDatabase(file));
    await tester.runAsync(() => ledger.initialize());
    await tester.pumpWidget(KhorochDiaryApp(ledger: ledger));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('switch-khata')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('switch-khata')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('new-khata')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('new-khata')).hitTestable(), findsOneWidget);
    await tester.tap(find.byKey(const Key('new-khata')).hitTestable());
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('khata-name')), 'Business');
    await tester.enterText(find.byKey(const Key('khata-opening')), '100.50');
    await tester.tap(find.byKey(const Key('create-khata')));
    await tester.pumpAndSettle();
    expect(find.text('Business'), findsOneWidget);
    expect(find.text('₹100.50'), findsWidgets);
    await tester.ensureVisible(find.text('Add New Entry'));
    await tester.tap(find.text('Add New Entry'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('amount-field')), '20');
    await tester.tap(find.text('Food'));
    await tester.ensureVisible(find.byKey(const Key('description-field')));
    await tester.enterText(
      find.byKey(const Key('description-field')),
      'Business lunch',
    );
    await tester.ensureVisible(find.text('Save Entry'));
    await tester.pumpAndSettle();
    expect(find.text('Save Entry').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Save Entry').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('Business lunch'), findsOneWidget);
    expect(find.text('₹80.50'), findsWidgets);
    await tester.ensureVisible(find.byKey(const Key('switch-khata')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('switch-khata')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('khata-personal')));
    await tester.pumpAndSettle();
    expect(find.text('Business lunch'), findsNothing);
    expect(find.text('Personal Khata'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('switch-khata')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('switch-khata')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Business').last);
    await tester.pumpAndSettle();
    expect(find.text('Business lunch'), findsOneWidget);
    expect(find.text('₹80.50'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    ledger = LocalLedger(NativeDatabase(file));
    await tester.runAsync(() => ledger.initialize());
    await tester.pumpWidget(KhorochDiaryApp(ledger: ledger));
    await tester.pumpAndSettle();
    expect(find.text('Business'), findsOneWidget);
    expect(find.text('Business lunch'), findsOneWidget);
    expect(find.text('₹80.50'), findsWidgets);

    await tester.ensureVisible(find.text('Add New Entry'));
    await tester.tap(find.text('Add New Entry'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('amount-field')), '5');
    await tester.tap(find.text('Food'));
    await tester.ensureVisible(find.byKey(const Key('description-field')));
    await tester.enterText(
      find.byKey(const Key('description-field')),
      'After restart',
    );
    await tester.ensureVisible(find.text('Save Entry'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Entry').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('After restart'), findsOneWidget);
    expect(find.text('₹75.50'), findsWidgets);

    await tester.ensureVisible(find.byKey(const Key('switch-khata')));
    await tester.tap(find.byKey(const Key('switch-khata')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('khata-personal')));
    await tester.pumpAndSettle();
    expect(find.text('Personal Khata'), findsOneWidget);
    expect(find.text('After restart'), findsNothing);
    expect(find.text('₹0'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('shell shows an error instead of a missing ledger balance', (
    tester,
  ) async {
    final ledger = LocalLedger(NativeDatabase.memory());
    await tester.runAsync(() async {
      await ledger.initialize();
      await ledger.customStatement(
        'UPDATE khatas SET deleted_at = ? WHERE id = ?',
        <Object?>[DateTime.now().toUtc().toIso8601String(), 'personal'],
      );
    });
    await tester.pumpWidget(KhorochDiaryApp(ledger: ledger));
    await tester.pumpAndSettle();
    expect(find.text('Could not open local ledger.'), findsOneWidget);
    expect(find.text('₹0'), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Could not open local ledger.'), findsOneWidget);
    expect(find.text('₹0'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('invalid opening and empty name do not create a khata', (
    tester,
  ) async {
    final ledger = LocalLedger(NativeDatabase.memory());
    await tester.runAsync(() => ledger.initialize());
    await tester.pumpWidget(KhorochDiaryApp(ledger: ledger));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('switch-khata')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('switch-khata')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('new-khata')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('new-khata')).hitTestable(), findsOneWidget);
    await tester.tap(find.byKey(const Key('new-khata')).hitTestable());
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('khata-opening')), '-1');
    await tester.tap(find.byKey(const Key('create-khata')));
    await tester.pumpAndSettle();
    expect(find.text('Enter a name of up to 40 characters'), findsOneWidget);
    expect(find.text('Enter 0 to 999999999.99'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('switch-khata')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('khata-personal')), findsOneWidget);
    expect(find.text('New Khata'), findsOneWidget);
  });
  testWidgets('switcher and create form fit a small phone with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final ledger = LocalLedger(NativeDatabase.memory());
    await tester.runAsync(() => ledger.initialize());
    await tester.pumpWidget(KhorochDiaryApp(ledger: ledger));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('switch-khata')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('switch-khata')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(const Key('new-khata')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('new-khata')).hitTestable(), findsOneWidget);
    await tester.tap(find.byKey(const Key('new-khata')).hitTestable());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('khata-name')), findsOneWidget);
    expect(find.byKey(const Key('khata-opening')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('khata-name')), 'Shop');
    await tester.ensureVisible(find.byKey(const Key('create-khata')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('create-khata')).hitTestable(), findsOneWidget);
    await tester.tap(find.byKey(const Key('create-khata')).hitTestable());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Shop'), findsOneWidget);
  });
}
