// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khoroch_diary/app.dart';
import 'package:khoroch_diary/features/entry/add_entry_screen.dart';
import 'package:khoroch_diary/features/ledger/data/local_ledger.dart';
import 'package:khoroch_diary/features/ledger/wallet_summary_screen.dart';
import 'package:khoroch_diary/features/ledger/all_transactions_screen.dart';
import 'package:khoroch_diary/features/profile/profile_screen.dart';

void main() {
  testWidgets('Home and Profile open real transaction and wallet data', (
    tester,
  ) async {
    final ledger = LocalLedger(NativeDatabase.memory());
    await tester.runAsync(() async {
      await ledger.initialize();
      await ledger.addEntry(
        EntryFormResult(
          kind: EntryFormKind.expense,
          amountPaise: 2050,
          category: 'Food',
          description: 'Lunch',
          occurredAt: DateTime(2026, 3, 1),
        ),
      );
      final shop = await ledger.createKhata(
        name: 'Shop',
        openingBalancePaise: 10000,
      );
      await ledger.addEntry(
        EntryFormResult(
          kind: EntryFormKind.income,
          amountPaise: 3000,
          category: 'Income',
          description: 'Sale',
          occurredAt: DateTime(2026, 3, 2),
        ),
        khataId: shop.id,
      );
    });
    await tester.pumpWidget(KhorochDiaryApp(ledger: ledger));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('View All'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View All'));
    await tester.pumpAndSettle();
    expect(find.byType(AllTransactionsScreen), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Lunch'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Lunch'), findsOneWidget);
    expect(find.text('Sale'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profile').last);
    await tester.pumpAndSettle();
    // The profile list is lazy; the wallet row is below what the default
    // surface builds, so scroll the profile list to it (ensureVisible needs
    // the finder to match, which lazy children don't until built).
    await tester.scrollUntilVisible(
      find.byKey(const Key('profile-wallet-row')),
      120,
      scrollable: find.descendant(
        of: find.byType(ProfileScreen),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('profile-wallet-row')).hitTestable(),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('profile-wallet-row')).hitTestable());
    await tester.pumpAndSettle();
    expect(find.byType(WalletSummaryScreen), findsOneWidget);
    expect(find.text('Shop'), findsOneWidget);
    expect(find.text('₹109.50'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
