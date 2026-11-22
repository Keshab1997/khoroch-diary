// Flutter 3.50 deprecates this import; migrate to material_ui in a dedicated dependency update.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khoroch_diary/core/theme/app_colors.dart';
import 'package:khoroch_diary/core/theme/app_theme.dart';
import 'package:khoroch_diary/features/calculator/calculator_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The calculator is always exercised at a small phone width; the layout test
/// raises text scale to 200% on top of that.
Future<void> pumpCalculator(
  WidgetTester tester, {
  double scale = 1.0,
  Size size = const Size(320, 568),
  ValueChanged<int>? onUseInEntry,
  VoidCallback? onSettings,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      builder: (BuildContext context, Widget? child) {
        return MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: CalculatorScreen(
        onUseInEntry: onUseInEntry,
        onSettings: onSettings,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tapKeys(WidgetTester tester, Iterable<String> labels) async {
  for (final String label in labels) {
    final Finder key = find.byKey(Key('calc-key-$label'));
    await tester.ensureVisible(key);
    await tester.tap(key);
    await tester.pumpAndSettle();
  }
}

String resultText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('calculator-result'))).data ?? '';

String expressionText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('calculator-expression'))).data ??
    '';

void expectNoLayoutErrors(WidgetTester tester) {
  expect(
    tester.takeException(),
    isNull,
    reason: 'calculator must not overflow or throw at this size/scale',
  );
}

void main() {
  testWidgets('settings button invokes its callback', (tester) async {
    int taps = 0;
    await pumpCalculator(tester, onSettings: () => taps++);
    await tester.tap(find.byTooltip('Settings'));
    expect(taps, 1);
    expectNoLayoutErrors(tester);
  });

  group('expression evaluation', () {
    testWidgets('renders the preview expression with Indian grouping', (
      WidgetTester tester,
    ) async {
      await pumpCalculator(tester);
      await tapKeys(tester, <String>['2', '5', '0', '×', '4']);

      expect(expressionText(tester), '250 × 4');
      expect(resultText(tester), '1,000');

      await tester.tap(find.byKey(const Key('calc-key-=')));
      await tester.pumpAndSettle();
      expect(resultText(tester), '1,000');
      expect(expressionText(tester), '250 × 4');
      expectNoLayoutErrors(tester);
    });

    testWidgets('applies operator precedence, not left-to-right arithmetic', (
      WidgetTester tester,
    ) async {
      await pumpCalculator(tester);
      await tapKeys(tester, <String>['1', '0', '+', '2', '×', '3']);

      expect(expressionText(tester), '10 + 2 × 3');
      expect(resultText(tester), '16');
      expectNoLayoutErrors(tester);
    });

    testWidgets('percent divides only the current operand by 100', (
      WidgetTester tester,
    ) async {
      await pumpCalculator(tester);
      await tapKeys(tester, <String>['2', '0', '0', '%']);

      expect(expressionText(tester), '2');
      expect(resultText(tester), '2');

      await tapKeys(tester, <String>['×', '4']);
      expect(resultText(tester), '8');
      expectNoLayoutErrors(tester);
    });

    testWidgets('percent keeps full precision for later arithmetic', (
      WidgetTester tester,
    ) async {
      await pumpCalculator(tester);
      await tapKeys(tester, <String>['.', '1', '%', '×', '1', '0', '0', '0']);

      // 0.1 / 100 must stay 0.001 as an operand, not be rounded to 0.
      expect(expressionText(tester), '0.001 × 1000');
      expect(resultText(tester), '1');
      expectNoLayoutErrors(tester);
    });

    testWidgets('small percent operands stay decimal and arithmetic survives', (
      WidgetTester tester,
    ) async {
      await pumpCalculator(tester);
      await tapKeys(tester, <String>['1', '%', '%', '%', '%', '2']);

      // A digit after 1e-8 must extend the decimal, not the exponent.
      expect(expressionText(tester), '0.000000012');

      // Check the arithmetic, not just the display string.
      await tapKeys(tester, <String>[
        '×',
        '1',
        '0',
        '0',
        '0',
        '0',
        '0',
        '0',
        '0',
        '0',
      ]);
      expect(expressionText(tester), '0.000000012 × 100000000');
      expect(resultText(tester), '1.2');
      expectNoLayoutErrors(tester);
    });

    testWidgets('small percent operands accept decimal edits and backspace', (
      WidgetTester tester,
    ) async {
      await pumpCalculator(tester);
      await tapKeys(tester, <String>['1', '%', '%', '%', '%']);
      expect(expressionText(tester), '0.00000001');

      await tapKeys(tester, <String>['2', '5']);
      expect(expressionText(tester), '0.0000000125');

      await tester.tap(find.byTooltip('Backspace'));
      await tester.pumpAndSettle();
      expect(expressionText(tester), '0.000000012');

      // The operand already has a decimal point, so only the digit lands.
      await tapKeys(tester, <String>['.', '5']);
      expect(expressionText(tester), '0.0000000125');
      expectNoLayoutErrors(tester);
    });

    testWidgets(
      'repeated percent stops before expression bounds are exceeded',
      (WidgetTester tester) async {
        await pumpCalculator(tester);
        await tapKeys(tester, <String>[
          '1',
          ...List<String>.generate(20, (int index) => '%'),
        ]);

        expect(resultText(tester), 'Value too small');
        expect(expressionText(tester).length, lessThanOrEqualTo(64));
        expectNoLayoutErrors(tester);

        await tester.tap(find.byKey(const Key('calc-key-C')));
        await tester.pumpAndSettle();
        expect(resultText(tester), '0');
        expectNoLayoutErrors(tester);
      },
    );

    testWidgets('display groups whole numbers without cosmetic zeros', (
      WidgetTester tester,
    ) async {
      await pumpCalculator(tester);
      await tapKeys(tester, <String>['2', '5', '0', '×', '4', '+', '.', '5']);

      expect(resultText(tester), '1,000.5');

      await tester.tap(find.byKey(const Key('calc-key-C')));
      await tester.pumpAndSettle();
      await tapKeys(tester, <String>['2', '.', '5']);
      expect(resultText(tester), '2.5');
      expectNoLayoutErrors(tester);
    });
  });

  group('key surfaces', () {
    testWidgets('operators are solid green, equals orange, digits ivory', (
      WidgetTester tester,
    ) async {
      await pumpCalculator(tester);

      Color? capOf(String label) {
        final ElevatedButton button = tester.widget<ElevatedButton>(
          find.descendant(
            of: find.byKey(Key('calc-key-$label')),
            matching: find.byType(ElevatedButton),
          ),
        );
        return button.style?.backgroundColor?.resolve(const <WidgetState>{});
      }

      expect(capOf('+'), AppColors.primaryGreen);
      expect(capOf('×'), AppColors.primaryGreen);
      expect(capOf('='), AppColors.orange);
      expect(capOf('7'), AppColors.warmIvory);
      expectNoLayoutErrors(tester);
    });
  });

  group('keypad grid', () {
    testWidgets('every key is the same size on one grid', (
      WidgetTester tester,
    ) async {
      await pumpCalculator(tester);

      // One grid means one hit target: the five-key top row and the four-key
      // rows below it share the exact same key size.
      final Size reference = tester.getSize(
        find.byKey(const Key('calc-key-7')),
      );
      expect(reference.width, reference.height);
      for (final String label in <String>[
        'C',
        '%',
        '÷',
        '×',
        '−',
        '+',
        '=',
        '00',
        '.',
        'history',
        'backspace',
      ]) {
        final Size size = tester.getSize(find.byKey(Key('calc-key-$label')));
        expect(
          size.width,
          moreOrLessEquals(reference.width, epsilon: 0.01),
          reason: '$label must share the grid width',
        );
        expect(
          size.height,
          moreOrLessEquals(reference.height, epsilon: 0.01),
          reason: '$label must share the grid height',
        );
      }
      expectNoLayoutErrors(tester);
    });
  });

  group('editing keys', () {
    testWidgets('C resets expression and result to zero', (
      WidgetTester tester,
    ) async {
      await pumpCalculator(tester);
      await tapKeys(tester, <String>['2', '5', '0', '×', '4']);
      expect(resultText(tester), '1,000');

      await tester.tap(find.byKey(const Key('calc-key-C')));
      await tester.pumpAndSettle();
      // The redesigned display shows a hint while the expression is empty.
      expect(expressionText(tester), 'Enter an amount or expression');
      expect(resultText(tester), '0');

      await tapKeys(tester, <String>['7']);
      expect(expressionText(tester), '7');
      expect(resultText(tester), '7');
      expectNoLayoutErrors(tester);
    });

    testWidgets('backspace removes one character at a time', (
      WidgetTester tester,
    ) async {
      await pumpCalculator(tester);
      await tapKeys(tester, <String>['1', '2', '3', '+', '4']);
      expect(expressionText(tester), '123 + 4');
      expect(resultText(tester), '127');

      final Finder backspace = find.byTooltip('Backspace');
      await tester.tap(backspace);
      await tester.pumpAndSettle();
      expect(expressionText(tester), '123 +');
      expect(resultText(tester), '123');

      await tester.tap(backspace);
      await tester.pumpAndSettle();
      expect(expressionText(tester), '123');
      expect(resultText(tester), '123');
      expectNoLayoutErrors(tester);
    });

    testWidgets('decimal keys build fractional operands and results', (
      WidgetTester tester,
    ) async {
      await pumpCalculator(tester);
      await tapKeys(tester, <String>['1', '.', '2', '5', '+', '2', '.', '5']);

      expect(expressionText(tester), '1.25 + 2.5');
      expect(resultText(tester), '3.75');

      await tester.tap(find.byKey(const Key('calc-key-C')));
      await tester.pumpAndSettle();
      await tapKeys(tester, <String>['.', '5']);
      expect(expressionText(tester), '0.5');
      expect(resultText(tester), '0.5');
      expectNoLayoutErrors(tester);
    });

    testWidgets('divide by zero stays inline and the expression is editable', (
      WidgetTester tester,
    ) async {
      await pumpCalculator(tester);
      await tapKeys(tester, <String>['5', '÷', '0']);

      expect(resultText(tester), 'Cannot divide by zero');
      expect(expressionText(tester), '5 ÷ 0');
      expectNoLayoutErrors(tester);

      await tester.tap(find.byTooltip('Backspace'));
      await tester.pumpAndSettle();
      expect(resultText(tester), '5');
      expect(find.text('Cannot divide by zero'), findsNothing);

      await tapKeys(tester, <String>['2']);
      expect(resultText(tester), '2.5');
      expect(expressionText(tester), '5 ÷ 2');
      expectNoLayoutErrors(tester);
    });

    testWidgets('malformed and out-of-range input explains itself', (
      WidgetTester tester,
    ) async {
      await pumpCalculator(tester);
      // A leading operator, repeated decimals and an orphan `%` leave the
      // input editable but must not pass themselves off as a zero result.
      await tapKeys(tester, <String>['÷', '×', '+', '.', '.', '%', '=']);
      expect(resultText(tester), 'Invalid expression');
      expectNoLayoutErrors(tester);

      await tester.tap(find.byKey(const Key('calc-key-C')));
      await tester.pumpAndSettle();
      expect(resultText(tester), '0');

      for (int index = 0; index < 70; index++) {
        await tester.tap(find.byKey(const Key('calc-key-9')));
        await tester.pump();
      }
      expect(resultText(tester), 'Value too large');
      expectNoLayoutErrors(tester);
    });
  });

  group('accessible layout', () {
    testWidgets('all keys are present at 320 px and 200% text scale', (
      WidgetTester tester,
    ) async {
      await pumpCalculator(tester, scale: 2.0);
      expectNoLayoutErrors(tester);

      for (final String label in <String>[
        'C',
        '%',
        '÷',
        '7',
        '8',
        '9',
        '×',
        '4',
        '5',
        '6',
        '−',
        '1',
        '2',
        '3',
        '+',
        '00',
        '0',
        '.',
        '=',
      ]) {
        expect(
          find.byKey(Key('calc-key-$label')),
          findsOneWidget,
          reason: label,
        );
      }
      expect(find.byTooltip('Backspace'), findsOneWidget);

      await tapKeys(tester, <String>['2', '5', '0', '×', '4']);
      expect(resultText(tester), '1,000');
      final Rect resultRect = tester.getRect(
        find.byKey(const Key('calculator-result')),
      );
      expect(
        resultRect.right,
        lessThanOrEqualTo(320),
        reason: 'the display must scale inside a 320 px phone',
      );
      expectNoLayoutErrors(tester);
    });
  });

  group('use in entry', () {
    testWidgets('hidden without the callback', (WidgetTester tester) async {
      await pumpCalculator(tester);
      await tapKeys(tester, <String>['2', '5', '0', '×', '4']);

      expect(find.byKey(const Key('calculator-use-in-entry')), findsNothing);
      expect(resultText(tester), '1,000');
    });

    testWidgets('sends the current result as integer paise', (
      WidgetTester tester,
    ) async {
      int? captured;
      await pumpCalculator(
        tester,
        onUseInEntry: (int paise) => captured = paise,
      );
      await tapKeys(tester, <String>['2', '5', '0', '×', '4']);
      await tester.tap(find.byKey(const Key('calculator-use-in-entry')));
      await tester.pumpAndSettle();

      expect(captured, 100000);
    });

    testWidgets('sends fractional results rounded half away from zero', (
      WidgetTester tester,
    ) async {
      int? captured;
      await pumpCalculator(
        tester,
        onUseInEntry: (int paise) => captured = paise,
      );
      await tapKeys(tester, <String>['7', '÷', '2']); // 3.5
      await tester.tap(find.byKey(const Key('calculator-use-in-entry')));
      await tester.pumpAndSettle();
      expect(captured, 350);

      // 2.5 is an exactly representable half -> away from zero -> 250.
      captured = null;
      await tester.tap(find.byKey(const Key('calc-key-C')));
      await tester.pumpAndSettle();
      await tapKeys(tester, <String>['5', '÷', '2']); // 2.5
      await tester.tap(find.byKey(const Key('calculator-use-in-entry')));
      await tester.pumpAndSettle();
      expect(captured, 250);
    });

    testWidgets('disabled for an empty expression', (
      WidgetTester tester,
    ) async {
      int calls = 0;
      await pumpCalculator(tester, onUseInEntry: (int paise) => calls += 1);
      final OutlinedButton button = tester.widget<OutlinedButton>(
        find.byKey(const Key('calculator-use-in-entry')),
      );
      expect(button.onPressed, isNull);
      await tester.tap(
        find.byKey(const Key('calculator-use-in-entry')),
        warnIfMissed: false,
      );
      expect(calls, 0);
    });

    testWidgets('disabled on an evaluation error', (WidgetTester tester) async {
      int calls = 0;
      await pumpCalculator(tester, onUseInEntry: (int paise) => calls += 1);
      await tapKeys(tester, <String>['5', '÷', '0']);
      expect(resultText(tester), isNotEmpty);

      final OutlinedButton button = tester.widget<OutlinedButton>(
        find.byKey(const Key('calculator-use-in-entry')),
      );
      expect(button.onPressed, isNull);
      expect(calls, 0);
    });

    testWidgets('disabled for a zero result', (WidgetTester tester) async {
      int calls = 0;
      await pumpCalculator(tester, onUseInEntry: (int paise) => calls += 1);
      await tapKeys(tester, <String>['0', '×', '5']);

      final OutlinedButton button = tester.widget<OutlinedButton>(
        find.byKey(const Key('calculator-use-in-entry')),
      );
      expect(button.onPressed, isNull);
      expect(calls, 0);
    });

    testWidgets('disabled for a negative result', (WidgetTester tester) async {
      int calls = 0;
      await pumpCalculator(tester, onUseInEntry: (int paise) => calls += 1);
      await tapKeys(tester, <String>['−', '5']);

      final OutlinedButton button = tester.widget<OutlinedButton>(
        find.byKey(const Key('calculator-use-in-entry')),
      );
      expect(button.onPressed, isNull);
      expect(calls, 0);
    });

    testWidgets('existing behaviour stays identical', (
      WidgetTester tester,
    ) async {
      await pumpCalculator(tester);
      await tapKeys(tester, <String>['2', '5', '0', '×', '4']);
      expect(resultText(tester), '1,000');
      await tester.tap(find.byKey(const Key('calc-key-C')));
      await tester.pumpAndSettle();
      expect(resultText(tester), '0');
      expect(expressionText(tester), 'Enter an amount or expression');
    });
  });
}
