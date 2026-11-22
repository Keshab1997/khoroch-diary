// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khoroch_diary/app.dart';
import 'package:khoroch_diary/features/ledger/data/local_ledger.dart';

void main() {
  testWidgets(
    'rename and archive selected khata refresh the shell and preserve its data',
    (tester) async {
      final ledger = LocalLedger(NativeDatabase.memory());
      await ledger.initialize();
      final shop = await ledger.createKhata(
        name: 'Shop',
        openingBalancePaise: 12345,
      );
      await ledger.setActiveKhataId(shop.id);
      await tester.pumpWidget(KhorochDiaryApp(ledger: ledger));
      await tester.pumpAndSettle();
      expect(find.text('Shop'), findsOneWidget);
      await tester.tap(find.byKey(const Key('switch-khata')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('manage-khatas')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('rename-khata-${shop.id}')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('rename-khata-input')),
        'New Shop',
      );
      await tester.tap(find.byKey(const Key('save-rename')));
      await tester.pumpAndSettle();
      expect(find.text('New Shop'), findsOneWidget);
      await tester.tap(find.byKey(Key('archive-khata-${shop.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-archive')));
      await tester.pumpAndSettle();
      expect(
        (await ledger.listArchivedKhatas()).single.openingBalancePaise,
        12345,
      );
      await tester.tap(find.byKey(const Key('manage-khatas-back')));
      await tester.pumpAndSettle();
      expect(find.text('Personal Khata'), findsOneWidget);
      expect(await ledger.readActiveKhataId(), 'personal');
      await tester.tap(find.byKey(const Key('switch-khata')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('manage-khatas')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(Key('unarchive-khata-${shop.id}')));
      await tester.tap(find.byKey(Key('unarchive-khata-${shop.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-unarchive')));
      await tester.pumpAndSettle();
      expect((await ledger.listKhatas()).last.name, 'New Shop');
      expect(
        (await ledger.readSummary(khataId: shop.id)).openingBalancePaise,
        12345,
      );
    },
  );
}
