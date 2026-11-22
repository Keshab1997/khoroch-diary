// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khoroch_diary/core/widgets/ledger_header_background.dart';
import 'package:khoroch_diary/features/calculator/calculator_screen.dart';
import 'package:khoroch_diary/features/counter/note_counter_screen.dart';
import 'package:khoroch_diary/features/home/home_screen.dart';

void main() {
  for (final entry in <String, Widget>{
    'Home': HomeScreen(khataName: 'Personal', onSwitchKhata: () {}),
    'Calculator': const CalculatorScreen(),
    'Counter': const NoteCounterScreen(),
  }.entries) {
    testWidgets('${entry.key} header fills the width and status inset', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              padding: const EdgeInsets.only(top: 24),
              viewPadding: const EdgeInsets.only(top: 24),
            ),
            child: child!,
          ),
          home: entry.value,
        ),
      );
      await tester.pumpAndSettle();
      final band = find.byKey(const Key('tab-header-status-background'));
      expect(tester.getTopLeft(band), Offset.zero);
      expect(tester.getSize(band).width, 390);
      expect(tester.getSize(band).height, greaterThanOrEqualTo(24));
      final wave = find.descendant(
        of: find.byType(FullWidthTabHeader),
        matching: find.byType(LedgerHeaderBackground),
      );
      expect(tester.getTopLeft(wave).dx, 0);
      expect(tester.getSize(wave).width, 390);
      expect(tester.takeException(), isNull);
    });
  }
}
