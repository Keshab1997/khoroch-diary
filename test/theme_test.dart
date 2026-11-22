// Flutter 3.50 deprecates this import; migrate to material_ui in a dedicated dependency update.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:khoroch_diary/features/ledger/data/local_ledger.dart';
import 'package:khoroch_diary/app.dart';
import 'package:khoroch_diary/core/format/money.dart';
import 'package:khoroch_diary/core/theme/app_colors.dart';
import 'package:khoroch_diary/features/home/models.dart';

void main() {
  group('palette tokens match the style guide', () {
    test('all sixteen colours are transcribed exactly', () {
      expect(AppColors.primaryGreen, const Color(0xFF0B6623));
      expect(AppColors.headerGreen, const Color(0xFF1B5E20));
      expect(AppColors.secondaryGreen, const Color(0xFF2E7D32));
      expect(AppColors.accentGreen, const Color(0xFF4CAF50));
      expect(AppColors.lightGreen, const Color(0xFFE8F5E9));
      expect(AppColors.creamBackground, const Color(0xFFFFF8E1));
      expect(AppColors.warmIvory, const Color(0xFFFDF6E3));
      expect(AppColors.beige, const Color(0xFFEAD7B7));
      expect(AppColors.golden, const Color(0xFFF4B400));
      expect(AppColors.orange, const Color(0xFFFB8C00));
      expect(AppColors.darkText, const Color(0xFF1B1B1B));
      expect(AppColors.softText, const Color(0xFF555555));
      expect(AppColors.expenseRed, const Color(0xFFE53935));
      expect(AppColors.incomeGreen, const Color(0xFF388E3C));
      expect(AppColors.navigationGrey, const Color(0xFF9E9E9E));
      expect(AppColors.onPrimary, const Color(0xFFFFFFFF));
    });
  });

  group('money formatting (integer paise, Indian grouping)', () {
    test('formats whole rupees, fractions, large values and negatives', () {
      expect(formatPaise(58000), '₹580');
      expect(formatPaise(642000), '₹6,420');
      expect(formatPaise(1000000), '₹10,000');
      expect(formatPaise(10000000), '₹1,00,000');
      expect(formatPaise(58050), '₹580.50');
      expect(formatPaise(5), '₹0.05');
      expect(formatPaise(-19900), '-₹199');
    });
  });

  group('ledger seed reproduces the design preview', () {
    test('₹10,000 income, ₹3,580 expense, ₹6,420 remaining', () {
      final LedgerSummary summary = LedgerSummary(
        openingBalancePaise: kSeedOpeningBalancePaise,
        entries: kSeedEntries,
      );
      expect(summary.totalIncomePaise, 1000000);
      expect(summary.totalExpensePaise, 358000);
      expect(summary.remainingPaise, 642000);
      expect(formatPaise(summary.remainingPaise), '₹6,420');
      expect(summary.recent().length, 4);
    });
  });

  testWidgets('shell shows four tabs and the remaining balance', (
    WidgetTester tester,
  ) async {
    final LocalLedger ledger = LocalLedger(NativeDatabase.memory());
    await ledger.initialize();
    await tester.pumpWidget(KhorochDiaryApp(ledger: ledger));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    for (final String label in <String>[
      'Home',
      'Calculator',
      'Counter',
      'Profile',
    ]) {
      expect(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        ),
        findsOneWidget,
      );
    }
    expect(find.text('Remaining Balance'), findsOneWidget);
    expect(find.text('₹0'), findsNWidgets(3));
    expect(
      find.text('No transactions yet. Add an entry to see it here.'),
      findsOneWidget,
    );
  });
}
