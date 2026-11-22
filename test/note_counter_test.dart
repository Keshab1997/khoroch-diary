import 'package:drift/native.dart';
import 'package:flutter/semantics.dart';
// Flutter 3.50 deprecates this import; migrate with the app's dependency update.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khoroch_diary/core/l10n/app_strings.dart';
import 'package:khoroch_diary/core/theme/app_colors.dart';
import 'package:khoroch_diary/core/theme/app_theme.dart';
import 'package:khoroch_diary/features/counter/note_counter_screen.dart';
import 'package:khoroch_diary/features/counter/note_counter_store.dart';
import 'package:khoroch_diary/features/home/models.dart' show LedgerSummary;
import 'package:khoroch_diary/features/ledger/data/local_ledger.dart';

/// A small phone (320 x 568 logical px) and a mid-range one (360 x 640).
const Size smallPhone = Size(320, 568);
const Size midPhone = Size(360, 640);

Future<void> pumpCounter(
  WidgetTester tester, {
  Size size = midPhone,
  double scale = 1.0,
  AppLanguage language = AppLanguage.en,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  // Deliberately NO `FlutterError.onError` override. flutter_test's binding
  // already captures framework errors (including "A RenderFlex overflowed")
  // and fails the test at teardown, so replacing the handler would hide real
  // failures and break the binding's own assertions.
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      builder: (BuildContext context, Widget? child) {
        final MediaQueryData media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(textScaler: TextScaler.linear(scale)),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: NoteCounterScreen(language: language),
    ),
  );
  await tester.pumpAndSettle();
}

/// Opens an in-memory ledger and closes it with the test. Opening and closing
/// run outside the fake-async zone (as in the other database widget tests);
/// otherwise the next test in this file can stall while opening its database.
Future<LocalLedger> openInMemoryLedger(WidgetTester tester) async {
  final LocalLedger ledger = LocalLedger(NativeDatabase.memory());
  await tester.runAsync(ledger.initialize);
  addTearDown(() => tester.runAsync(ledger.close));
  return ledger;
}

/// Pumps the per-khata counter over [store] for [khataId]. The load happens
/// asynchronously, so this waits for it to land.
Future<void> pumpPersistedCounter(
  WidgetTester tester, {
  required NoteCounterStore store,
  required String khataId,
  AppLanguage language = AppLanguage.en,
  Size size = midPhone,
  double scale = 1.0,
  void Function(int amountPaise, String note)? onAddToKhata,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      builder: (BuildContext context, Widget? child) {
        final MediaQueryData media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(textScaler: TextScaler.linear(scale)),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: NoteCounterScreen(
        language: language,
        store: store,
        khataId: khataId,
        onAddToKhata: onAddToKhata,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The platform clipboard, captured. Restores the handler on teardown.
class ClipboardCapture {
  String? text;

  Future<MethodCall?> handle(MethodCall call) async {
    if (call.method == 'Clipboard.setData') {
      text = (call.arguments as Map<Object?, Object?>)['text'] as String?;
    }
    return null;
  }
}

void mockClipboard(ClipboardCapture capture) {
  final TestDefaultBinaryMessenger messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, capture.handle);
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
}

/// Fails if the last frame raised a framework error.
///
/// `tester.takeException()` only *reads* the binding's pending error, so the
/// binding keeps ownership of failure reporting: an overflow reported at any
/// other point still fails the test through the normal binding path. The
/// unused return value is intentional - `expect` is the assertion.
void expectNoLayoutErrors(WidgetTester tester) {
  final Object? exception = tester.takeException();
  expect(
    exception,
    isNull,
    reason: 'the last frame raised a framework error: $exception',
  );
}

/// Types [value] straight into the field of [denominationPaise], replacing
/// what is there. Note rows take a quantity of notes; the ₹1-coin row takes
/// the **total value of the coins in rupees**.
Future<void> typeQuantity(
  WidgetTester tester,
  int denominationPaise,
  String value,
) async {
  final Finder field = find.byKey(Key('note-counter-field-$denominationPaise'));
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.enterText(field, value);
  await tester.pumpAndSettle();
}

/// Types [value] into the ₹500 row's field - the common case in these tests.
Future<void> typeFiveHundreds(WidgetTester tester, String value) =>
    typeQuantity(tester, 50000, value);

/// The quantity currently in [denominationPaise]'s field, read from its
/// controller.
///
/// Reading the controller avoids `find.text('0')`, which matches every zero
/// wearing text on the screen.
String fieldText(WidgetTester tester, int denominationPaise) {
  final EditableText editable = tester.widget<EditableText>(
    find.descendant(
      of: find.byKey(Key('note-counter-field-$denominationPaise')),
      matching: find.byType(EditableText),
    ),
  );
  return editable.controller.text;
}

/// Seeds a timestamped snapshot directly through the store. The screen is
/// autosave now - the Save button is gone - so this is how a test can create
/// the sessions the sheet lists.
Future<void> seedSession(
  WidgetTester tester,
  NoteCounterStore store,
  String khataId, {
  required int fiftyCount,
}) async {
  await tester.runAsync(() async {
    await store.saveSession(
      khataId,
      NoteCounterSnapshot(
        quantities: <int, int>{50000: fiftyCount},
        selectedDenominationPaise: kDefaultDenominationPaise,
        showTwoThousand: false,
      ),
    );
  });
}

/// The rendered amount of [denominationPaise]'s row total.
Finder rowTotalText(String formatted, int denominationPaise) => find.descendant(
  of: find.byKey(Key('note-counter-row-total-$denominationPaise')),
  matching: find.text(formatted),
);

/// Scrolls [finder] into view and asserts it can actually receive a tap.
Future<void> tapHittable(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expect(
    finder.hitTestable().evaluate().isNotEmpty,
    isTrue,
    reason: 'control is offscreen or covered and cannot be tapped',
  );
  await tester.tap(finder.hitTestable());
  await tester.pumpAndSettle();
}

/// The grand total card's rendered amount.
Finder grandTotalText(String formatted) => find.descendant(
  of: find.byKey(const Key('note-counter-grand-total')),
  matching: find.text(formatted),
);

void main() {
  group('row states', () {
    testWidgets('counted rows keep an ivory background and an accent border', (
      WidgetTester tester,
    ) async {
      await pumpCounter(tester);

      Color? rowColor(int denominationPaise) {
        final AnimatedContainer row = tester.widget<AnimatedContainer>(
          find.byKey(Key('note-counter-row-$denominationPaise')),
        );
        return (row.decoration! as BoxDecoration).color;
      }

      expect(rowColor(50000), AppColors.warmIvory);
      await typeFiveHundreds(tester, '2');
      expect(rowColor(50000), AppColors.warmIvory);
      final AnimatedContainer counted = tester.widget<AnimatedContainer>(
        find.byKey(const Key('note-counter-row-50000')),
      );
      final AnimatedContainer uncounted = tester.widget<AnimatedContainer>(
        find.byKey(const Key('note-counter-row-20000')),
      );
      expect(
        (counted.decoration! as BoxDecoration).border,
        isNot((uncounted.decoration! as BoxDecoration).border),
      );
      // Counting one denomination never tints the others.
      expect(rowColor(20000), AppColors.warmIvory);
      expectNoLayoutErrors(tester);
    });
  });

  group('row focus and total panel', () {
    testWidgets('the row being typed into shows a clear focus edge', (
      WidgetTester tester,
    ) async {
      await pumpCounter(tester);

      Border borderOf(int denominationPaise) {
        final AnimatedContainer row = tester.widget<AnimatedContainer>(
          find.byKey(Key('note-counter-row-$denominationPaise')),
        );
        return (row.decoration! as BoxDecoration).border! as Border;
      }

      // Idle rows carry the quiet accent edge, never the focus colour.
      expect(borderOf(50000).top.color, isNot(AppColors.primaryGreen));
      expect(borderOf(20000).top.color, isNot(AppColors.primaryGreen));

      await typeFiveHundreds(tester, '2');

      // Exactly one row is the one being counted, and it says so.
      expect(borderOf(50000).top.color, AppColors.primaryGreen);
      expect(borderOf(50000).top.width, greaterThan(borderOf(20000).top.width));
      expect(borderOf(20000).top.color, isNot(AppColors.primaryGreen));
      // The focused row still keeps the shared ivory fill.
      final AnimatedContainer focused = tester.widget<AnimatedContainer>(
        find.byKey(const Key('note-counter-row-50000')),
      );
      expect((focused.decoration! as BoxDecoration).color, AppColors.warmIvory);
      expectNoLayoutErrors(tester);
    });

    testWidgets('the Grand Total panel is one calm, flat card', (
      WidgetTester tester,
    ) async {
      await pumpCounter(tester);

      // A quiet light-green panel with no gradient: the amount is emphasised by
      // type, not by a loud background.
      final Container panel = tester.widget<Container>(
        find.byKey(const Key('note-counter-grand-total')),
      );
      final BoxDecoration decoration = panel.decoration! as BoxDecoration;
      expect(decoration.color, AppColors.lightGreen);
      expect(decoration.gradient, isNull);
      expect(decoration.borderRadius, BorderRadius.circular(20));
      expect((decoration.border! as Border).top.width, 1);
      expectNoLayoutErrors(tester);
    });
  });

  group('initial state', () {
    testWidgets('starts empty with a zero grand total', (
      WidgetTester tester,
    ) async {
      await pumpCounter(tester);

      expect(find.text('Grand Total'), findsOneWidget);
      expect(grandTotalText('₹0'), findsOneWidget);
      // The state is explicitly not persisted - say so on screen.
      expect(
        find.text('In-memory session - nothing is saved or added to a khata'),
        findsOneWidget,
      );
      // Every row starts at zero.
      for (final int denomination in <int>[
        50000,
        20000,
        10000,
        5000,
        2000,
        1000,
        100,
      ]) {
        expect(
          fieldText(tester, denomination),
          '0',
          reason: 'row $denomination must start at zero',
        );
      }
    });

    testWidgets('six note rows and one coins row are always on screen', (
      WidgetTester tester,
    ) async {
      await pumpCounter(tester);

      for (final int denomination in <int>[
        50000,
        20000,
        10000,
        5000,
        2000,
        1000,
      ]) {
        expect(
          find.byKey(Key('note-counter-row-$denomination')),
          findsOneWidget,
          reason: 'missing row for $denomination paise',
        );
        expect(
          find.byKey(Key('note-counter-field-$denomination')),
          findsOneWidget,
        );
      }
      // The coins row is present and typed as a total amount in rupees.
      expect(find.byKey(const Key('note-counter-row-100')), findsOneWidget);
      expect(find.byKey(const Key('note-counter-field-100')), findsOneWidget);
      expect(find.text('Coins'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (Widget widget) =>
              widget is Semantics &&
              widget.properties.label == 'Total value of coins (₹)',
        ),
        findsOneWidget,
      );
      expectNoLayoutErrors(tester);
    });

    testWidgets('the ₹2,000 note is gone from the screen', (
      WidgetTester tester,
    ) async {
      await pumpCounter(tester);

      expect(find.byKey(const Key('note-counter-row-200000')), findsNothing);
      expect(find.byKey(const Key('note-counter-field-200000')), findsNothing);
      expect(find.byKey(const Key('denomination-200000')), findsNothing);
      expect(find.byKey(const Key('note-counter-show-2000')), findsNothing);
      expect(find.text('Include ₹2,000 notes'), findsNothing);
      expect(find.text('₹2,000'), findsNothing);
    });
  });

  group('arithmetic', () {
    testWidgets('₹500 × 10 gives ₹5,000', (WidgetTester tester) async {
      await pumpCounter(tester);

      await typeFiveHundreds(tester, '10');

      expect(rowTotalText('₹5,000', 50000), findsOneWidget);
      expect(grandTotalText('₹5,000'), findsOneWidget);
      expectNoLayoutErrors(tester);
    });

    testWidgets('rows add up into one grand total', (
      WidgetTester tester,
    ) async {
      await pumpCounter(tester);

      await typeFiveHundreds(tester, '10'); // ₹5,000
      await typeQuantity(tester, 10000, '5'); // ₹500

      expect(rowTotalText('₹5,000', 50000), findsOneWidget);
      expect(rowTotalText('₹500', 10000), findsOneWidget);
      expect(grandTotalText('₹5,500'), findsOneWidget);
    });

    testWidgets('small denominations multiply exactly', (
      WidgetTester tester,
    ) async {
      await pumpCounter(tester);

      await typeQuantity(tester, 1000, '99999');
      // 1000 x 99999 = 99999000 paise = ₹9,99,990 with Indian grouping.
      expect(grandTotalText('₹9,99,990'), findsOneWidget);
      expectNoLayoutErrors(tester);
    });

    testWidgets('notes and coins combine into the grand total', (
      WidgetTester tester,
    ) async {
      await pumpCounter(tester);

      await typeFiveHundreds(tester, '2'); // ₹1,000
      await typeQuantity(tester, 100, '37'); // ₹37 of coins

      expect(rowTotalText('₹1,000', 50000), findsOneWidget);
      expect(rowTotalText('₹37', 100), findsOneWidget);
      expect(grandTotalText('₹1,037'), findsOneWidget);
    });
  });

  group('quantity limits', () {
    testWidgets('the maximum is 99,999 and cannot be exceeded', (
      WidgetTester tester,
    ) async {
      await pumpCounter(tester);

      await typeFiveHundreds(tester, '999999');
      // Clamped to the documented maximum, and the field shows the clamp.
      expect(fieldText(tester, 50000), '99999');
      expect(grandTotalText('₹4,99,99,500'), findsOneWidget); // 50000 x 99999
    });

    testWidgets('negative input is rejected with the generic message', (
      WidgetTester tester,
    ) async {
      await pumpCounter(tester);
      await typeFiveHundreds(tester, '7');
      expect(grandTotalText('₹3,500'), findsOneWidget);

      await typeFiveHundreds(tester, '-5');

      expect(
        find.textContaining('Enter a whole number of notes'),
        findsOneWidget,
      );
      // Nothing was counted, so the total is still the last valid one.
      expect(grandTotalText('₹3,500'), findsOneWidget);
      expectNoLayoutErrors(tester);
    });

    testWidgets('decimal input is rejected with the generic message', (
      WidgetTester tester,
    ) async {
      await pumpCounter(tester);
      await typeFiveHundreds(tester, '7');

      for (final String decimal in <String>['1.5', '0.5', '.5', '100.25']) {
        await typeFiveHundreds(tester, decimal);

        expect(
          find.textContaining('Enter a whole number of notes'),
          findsOneWidget,
          reason: '"$decimal" must show the whole-number message',
        );
        expect(
          grandTotalText('₹3,500'),
          findsOneWidget,
          reason: '"$decimal" must not alter the counted total',
        );
        expectNoLayoutErrors(tester);
      }
    });

    testWidgets('non-numeric input is rejected with the generic message', (
      WidgetTester tester,
    ) async {
      await pumpCounter(tester);
      await typeFiveHundreds(tester, '7');

      for (final String junk in <String>['abc', '0x10', '1e3']) {
        await typeFiveHundreds(tester, junk);

        expect(
          find.textContaining('Enter a whole number of notes'),
          findsOneWidget,
          reason: '"$junk" must show the whole-number message',
        );
        expect(
          grandTotalText('₹3,500'),
          findsOneWidget,
          reason: '"$junk" must not alter the counted total',
        );
        expectNoLayoutErrors(tester);
      }
    });

    testWidgets('whitespace is rejected, not treated as an empty field', (
      WidgetTester tester,
    ) async {
      await pumpCounter(tester);
      await typeFiveHundreds(tester, '7');
      expect(grandTotalText('₹3,500'), findsOneWidget);

      for (final String whitespace in <String>[' ', '   ', ' 5', '5 ', '5 0']) {
        await typeFiveHundreds(tester, whitespace);

        expect(
          find.textContaining('Enter a whole number of notes'),
          findsOneWidget,
          reason: '"$whitespace" must be rejected with an error',
        );
        expect(
          grandTotalText('₹3,500'),
          findsOneWidget,
          reason: '"$whitespace" must preserve the last valid count',
        );
        expectNoLayoutErrors(tester);
      }
    });

    testWidgets('only a genuinely empty field resets the count', (
      WidgetTester tester,
    ) async {
      await pumpCounter(tester);
      await typeFiveHundreds(tester, '7');
      expect(grandTotalText('₹3,500'), findsOneWidget);

      // Empty is not an error: it means "nothing counted right now".
      await typeFiveHundreds(tester, '');
      expect(find.textContaining('Enter a whole number'), findsNothing);
      expect(grandTotalText('₹0'), findsOneWidget);

      // A rejected value after that still shows an error and keeps the zero.
      await typeFiveHundreds(tester, ' ');
      expect(
        find.textContaining('Enter a whole number of notes'),
        findsOneWidget,
      );
      expect(grandTotalText('₹0'), findsOneWidget);
    });

    testWidgets('a valid value clears the error and counts normally', (
      WidgetTester tester,
    ) async {
      await pumpCounter(tester);

      await typeFiveHundreds(tester, '-5');
      expect(
        find.textContaining('Enter a whole number of notes'),
        findsOneWidget,
      );

      await typeFiveHundreds(tester, '2');
      expect(find.textContaining('Enter a whole number'), findsNothing);
      expect(grandTotalText('₹1,000'), findsOneWidget);
      expect(fieldText(tester, 50000), '2');
    });

    testWidgets(
      'an overflowing digit string clamps to 99,999 and rewrites the field',
      (WidgetTester tester) async {
        // `int.tryParse` returns null for a digit string longer than 64 bits.
        await pumpCounter(tester);

        final String overflowing = '9' * 30; // far beyond int64
        await typeFiveHundreds(tester, overflowing);

        expectNoLayoutErrors(tester);
        expect(
          fieldText(tester, 50000),
          '99999',
          reason: 'the field must show the same number that is counted',
        );
        // ₹500 x 99,999 = 49,99,95,000 paise -> ₹4,99,99,500
        expect(grandTotalText('₹4,99,99,500'), findsOneWidget);
        expect(
          find.textContaining('Enter a whole number'),
          findsNothing,
          reason: 'an over-long count clamps; it is not a validation error',
        );
      },
    );

    testWidgets('an empty field counts nothing rather than throwing', (
      WidgetTester tester,
    ) async {
      await pumpCounter(tester);
      await typeFiveHundreds(tester, '3');
      expect(grandTotalText('₹1,500'), findsOneWidget);

      await typeFiveHundreds(tester, '');
      expectNoLayoutErrors(tester);
      expect(grandTotalText('₹0'), findsOneWidget);
      expect(find.textContaining('Enter a whole number'), findsNothing);
    });
  });

  group('coins row', () {
    testWidgets('typing a coin total in rupees adds it to the grand total', (
      WidgetTester tester,
    ) async {
      await pumpCounter(tester);

      await typeQuantity(tester, 100, '37');

      expect(rowTotalText('₹37', 100), findsOneWidget);
      expect(grandTotalText('₹37'), findsOneWidget);
      expectNoLayoutErrors(tester);
    });

    testWidgets('the coin amount is capped at 99,999 and shows the clamp', (
      WidgetTester tester,
    ) async {
      await pumpCounter(tester);

      await typeQuantity(tester, 100, '100000');
      // 99,999 × ₹1 = ₹99,999 of coins.
      expect(fieldText(tester, 100), '99999');
      expect(rowTotalText('₹99,999', 100), findsOneWidget);
      expect(grandTotalText('₹99,999'), findsOneWidget);
    });

    testWidgets('an overflowing coin digit string clamps like a note row', (
      WidgetTester tester,
    ) async {
      await pumpCounter(tester);

      await typeQuantity(tester, 100, '9' * 30);
      expect(fieldText(tester, 100), '99999');
      expect(grandTotalText('₹99,999'), findsOneWidget);
    });

    testWidgets('non-numeric coin input is rejected and keeps the total', (
      WidgetTester tester,
    ) async {
      await pumpCounter(tester);
      await typeQuantity(tester, 100, '37');

      for (final String junk in <String>['abc', '3.5', '-2', ' ', '1e3']) {
        await typeQuantity(tester, 100, junk);

        expect(
          find.textContaining('Enter a whole number of notes'),
          findsOneWidget,
          reason: '"$junk" must show the whole-number message',
        );
        expect(
          grandTotalText('₹37'),
          findsOneWidget,
          reason: '"$junk" must not alter the counted total',
        );
        expectNoLayoutErrors(tester);
      }
    });

    testWidgets('the coin row is labelled as a total amount in ₹', (
      WidgetTester tester,
    ) async {
      await pumpCounter(tester);

      // The accessible field label explains that coins are a rupee total.
      expect(
        find.byWidgetPredicate(
          (Widget widget) =>
              widget is Semantics &&
              widget.properties.label == 'Total value of coins (₹)',
        ),
        findsOneWidget,
      );
      expect(find.text('Coins'), findsOneWidget);
    });
  });

  group('each row keeps its own count', () {
    testWidgets('every field keeps what was typed independently', (
      WidgetTester tester,
    ) async {
      await pumpCounter(tester);

      await typeFiveHundreds(tester, '4'); // ₹2,000
      await typeQuantity(tester, 10000, '2'); // ₹200

      expect(fieldText(tester, 50000), '4');
      expect(fieldText(tester, 10000), '2');
      expect(rowTotalText('₹2,000', 50000), findsOneWidget);
      expect(rowTotalText('₹200', 10000), findsOneWidget);
      expect(grandTotalText('₹2,200'), findsOneWidget);
    });
  });

  group('New count', () {
    testWidgets('clears every row, not just one', (WidgetTester tester) async {
      await pumpCounter(tester);

      await typeFiveHundreds(tester, '2'); // ₹1,000
      await typeQuantity(tester, 10000, '3'); // ₹300
      await typeQuantity(tester, 100, '15'); // ₹15 of coins
      expect(grandTotalText('₹1,315'), findsOneWidget);

      await tapHittable(
        tester,
        find.byKey(const Key('note-counter-new-count')),
      );
      // A non-empty count confirms first; the typed values are not lost by
      // accident.
      await tapHittable(
        tester,
        find.byKey(const Key('note-counter-new-count-confirm')),
      );

      expect(grandTotalText('₹0'), findsOneWidget);
      expect(fieldText(tester, 50000), '0');
      expect(fieldText(tester, 10000), '0');
      expect(fieldText(tester, 100), '0');
      expect(rowTotalText('₹0', 50000), findsOneWidget);
      expect(rowTotalText('₹0', 100), findsOneWidget);
    });

    testWidgets('cancelling keeps the current count', (
      WidgetTester tester,
    ) async {
      await pumpCounter(tester);

      await typeFiveHundreds(tester, '3'); // ₹1,500
      await tapHittable(
        tester,
        find.byKey(const Key('note-counter-new-count')),
      );
      expect(
        find.byKey(const Key('note-counter-new-count-confirm')),
        findsOneWidget,
      );
      await tapHittable(
        tester,
        find.byKey(const Key('note-counter-new-count-cancel')),
      );
      expect(grandTotalText('₹1,500'), findsOneWidget);
    });

    testWidgets('an empty count resets without asking', (
      WidgetTester tester,
    ) async {
      await pumpCounter(tester);

      await tapHittable(
        tester,
        find.byKey(const Key('note-counter-new-count')),
      );
      expect(
        find.byKey(const Key('note-counter-new-count-confirm')),
        findsNothing,
      );
      expect(grandTotalText('₹0'), findsOneWidget);
    });
  });

  group('accessibility and layout', () {
    testWidgets('every row field exposes a semantic label', (
      WidgetTester tester,
    ) async {
      // `ensureSemantics()` promotes the accessibility tree for the test.
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpCounter(tester);

      const Map<int, String> labels = <int, String>{
        50000: 'Quantity of ₹500 notes',
        20000: 'Quantity of ₹200 notes',
        10000: 'Quantity of ₹100 notes',
        5000: 'Quantity of ₹50 notes',
        2000: 'Quantity of ₹20 notes',
        1000: 'Quantity of ₹10 notes',
      };
      for (final MapEntry<int, String> entry in labels.entries) {
        final Finder field = find.bySemanticsLabel(entry.value);
        expect(field, findsOneWidget, reason: entry.value);
        final SemanticsNode node = tester.getSemantics(field);
        expect(node.flagsCollection.isTextField, isTrue);
      }
      // The coin field announces the total-value-in-rupees label. Both the
      // field and its helper text carry the same words, so this matches at
      // least the field node.
      expect(find.bySemanticsLabel('Total value of coins (₹)'), findsWidgets);
      handle.dispose();
    });

    testWidgets('fields are at least 44 dp tall for touch targets', (
      WidgetTester tester,
    ) async {
      await pumpCounter(tester);

      for (final int denomination in <int>[
        50000,
        20000,
        10000,
        5000,
        2000,
        1000,
        100,
      ]) {
        final Size field = tester.getSize(
          find.byKey(Key('note-counter-field-$denomination')),
        );
        expect(
          field.height,
          greaterThanOrEqualTo(44),
          reason: 'field $denomination must be a legal touch target',
        );
      }
    });

    testWidgets('layout survives a 320 dp phone at 200% text scale', (
      WidgetTester tester,
    ) async {
      await pumpCounter(tester, size: smallPhone, scale: 2.0);
      expectNoLayoutErrors(tester);

      await typeFiveHundreds(tester, '10');
      expect(grandTotalText('₹5,000'), findsOneWidget);
      expectNoLayoutErrors(tester);
    });

    testWidgets('rows stay inside the screen at 300% text scale', (
      WidgetTester tester,
    ) async {
      await pumpCounter(tester, size: smallPhone, scale: 3.0);
      expectNoLayoutErrors(tester);

      for (final int denomination in <int>[
        50000,
        20000,
        10000,
        5000,
        2000,
        1000,
        100,
      ]) {
        final Rect row = tester.getRect(
          find.byKey(Key('note-counter-row-$denomination')),
        );
        expect(row.left, greaterThanOrEqualTo(0));
        expect(row.right, lessThanOrEqualTo(smallPhone.width));
      }

      await typeQuantity(tester, 10000, '5');
      expect(grandTotalText('₹500'), findsOneWidget);
      expectNoLayoutErrors(tester);
    });

    testWidgets('large totals do not overflow at 200% text scale', (
      WidgetTester tester,
    ) async {
      await pumpCounter(tester, size: smallPhone, scale: 2.0);

      await typeFiveHundreds(tester, '99999');
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      expectNoLayoutErrors(tester);
      expect(grandTotalText('₹4,99,99,500'), findsOneWidget);
    });
  });

  group('per-khata persistence', () {
    testWidgets('a count survives closing and reopening the screen', (
      WidgetTester tester,
    ) async {
      final LocalLedger ledger = await openInMemoryLedger(tester);
      final NoteCounterStore store = NoteCounterStore(ledger);

      await pumpPersistedCounter(tester, store: store, khataId: 'personal');
      await typeFiveHundreds(tester, '10'); // ₹500 x 10
      await typeQuantity(tester, 10000, '5'); // ₹100 x 5
      expect(grandTotalText('₹5,500'), findsOneWidget);

      // Unmount and reopen: a brand-new state must reload from the store.
      await tester.pumpWidget(const SizedBox());
      await pumpPersistedCounter(tester, store: store, khataId: 'personal');

      expect(grandTotalText('₹5,500'), findsOneWidget);
      expect(rowTotalText('₹500', 10000), findsOneWidget);
      // The field shows each row's stored quantity.
      expect(fieldText(tester, 50000), '10');
      expect(fieldText(tester, 10000), '5');
      expectNoLayoutErrors(tester);
    });

    testWidgets('the coin amount survives a reopen', (
      WidgetTester tester,
    ) async {
      final LocalLedger ledger = await openInMemoryLedger(tester);
      final NoteCounterStore store = NoteCounterStore(ledger);

      await pumpPersistedCounter(tester, store: store, khataId: 'personal');
      await typeFiveHundreds(tester, '2'); // ₹1,000
      await typeQuantity(tester, 100, '37'); // ₹37 of coins
      expect(grandTotalText('₹1,037'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await pumpPersistedCounter(tester, store: store, khataId: 'personal');

      expect(grandTotalText('₹1,037'), findsOneWidget);
      expect(fieldText(tester, 100), '37');
      expect(rowTotalText('₹37', 100), findsOneWidget);
    });

    testWidgets('switching khata never carries quantities over', (
      WidgetTester tester,
    ) async {
      final LocalLedger ledger = await openInMemoryLedger(tester);
      final LocalKhata business = (await tester.runAsync(
        () => ledger.createKhata(name: 'Business', openingBalancePaise: 0),
      ))!;
      final NoteCounterStore store = NoteCounterStore(ledger);

      await pumpPersistedCounter(tester, store: store, khataId: 'personal');
      await typeFiveHundreds(tester, '4'); // ₹500 x 4 = ₹2,000
      expect(grandTotalText('₹2,000'), findsOneWidget);

      // A different khata, switched in place, starts empty.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: NoteCounterScreen(
            language: AppLanguage.en,
            store: store,
            khataId: business.id,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(grandTotalText('₹0'), findsOneWidget);
      expect(fieldText(tester, 50000), '0');

      // Count something there, then switch back: both keep their own count.
      await typeFiveHundreds(tester, '2'); // ₹500 x 2 = ₹1,000
      expect(grandTotalText('₹1,000'), findsOneWidget);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: NoteCounterScreen(
            language: AppLanguage.en,
            store: store,
            khataId: 'personal',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(grandTotalText('₹2,000'), findsOneWidget);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: NoteCounterScreen(
            language: AppLanguage.en,
            store: store,
            khataId: business.id,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(grandTotalText('₹1,000'), findsOneWidget);
    });
  });

  group('saved sessions', () {
    testWidgets('no Save button — the count persists itself', (
      WidgetTester tester,
    ) async {
      final LocalLedger ledger = await openInMemoryLedger(tester);
      final NoteCounterStore store = NoteCounterStore(ledger);

      await pumpPersistedCounter(tester, store: store, khataId: 'personal');
      expect(find.byKey(const Key('note-counter-save')), findsNothing);
      expect(find.text('No changes to save yet'), findsOneWidget);

      // Typing a value persists the count on its own.
      await typeFiveHundreds(tester, '2'); // ₹500 x 2 = ₹1,000
      await tester.pumpAndSettle();
      expect(grandTotalText('₹1,000'), findsOneWidget);
      expect(find.text('Saved on this device'), findsOneWidget);

      // And a reopen reads it back from storage.
      await tester.pumpWidget(const SizedBox());
      await pumpPersistedCounter(tester, store: store, khataId: 'personal');
      expect(grandTotalText('₹1,000'), findsOneWidget);
    });

    testWidgets(
      'restoring a seeded session from the sheet replaces the count',
      (WidgetTester tester) async {
        final LocalLedger ledger = await openInMemoryLedger(tester);
        final NoteCounterStore store = NoteCounterStore(ledger);

        await pumpPersistedCounter(tester, store: store, khataId: 'personal');
        await typeFiveHundreds(tester, '3'); // ₹500 x 3 = ₹1,500
        await seedSession(tester, store, 'personal', fiftyCount: 3);

        // Clear the screen (the count is not empty, so New count confirms
        // first), then restore the saved session. The current count is empty
        // at that point, so no restore confirmation is asked either.
        await tapHittable(
          tester,
          find.byKey(const Key('note-counter-new-count')),
        );
        await tapHittable(
          tester,
          find.byKey(const Key('note-counter-new-count-confirm')),
        );
        expect(grandTotalText('₹0'), findsOneWidget);

        await tapHittable(
          tester,
          find.byKey(const Key('note-counter-saved-sessions')),
        );
        expect(find.byKey(const Key('saved-sessions-list')), findsOneWidget);
        expect(find.textContaining('₹1,500'), findsWidgets);
        await tapHittable(
          tester,
          find
              .descendant(
                of: find.byKey(const Key('saved-sessions-list')),
                matching: find.byType(ListTile),
              )
              .first,
        );
        expect(
          find.byKey(const Key('saved-sessions-restore-confirm')),
          findsNothing,
        );
        expect(grandTotalText('₹1,500'), findsOneWidget);
        expectNoLayoutErrors(tester);
      },
    );

    testWidgets('restoring over a non-empty count asks for confirmation', (
      WidgetTester tester,
    ) async {
      final LocalLedger ledger = await openInMemoryLedger(tester);
      final NoteCounterStore store = NoteCounterStore(ledger);

      await pumpPersistedCounter(tester, store: store, khataId: 'personal');
      await typeFiveHundreds(tester, '3'); // ₹1,500
      await seedSession(tester, store, 'personal', fiftyCount: 3);
      await typeFiveHundreds(tester, '5'); // ₹2,500
      expect(grandTotalText('₹2,500'), findsOneWidget);

      await tapHittable(
        tester,
        find.byKey(const Key('note-counter-saved-sessions')),
      );
      await tapHittable(
        tester,
        find
            .descendant(
              of: find.byKey(const Key('saved-sessions-list')),
              matching: find.byType(ListTile),
            )
            .first,
      );
      expect(
        find.byKey(const Key('saved-sessions-restore-confirm')),
        findsOneWidget,
      );
      // Cancel keeps the current count untouched.
      await tapHittable(
        tester,
        find.byKey(const Key('saved-sessions-restore-cancel')),
      );
      expect(grandTotalText('₹2,500'), findsOneWidget);
      // Confirm replaces it with the saved snapshot.
      await tapHittable(
        tester,
        find
            .descendant(
              of: find.byKey(const Key('saved-sessions-list')),
              matching: find.byType(ListTile),
            )
            .first,
      );
      await tapHittable(
        tester,
        find.byKey(const Key('saved-sessions-restore-confirm')),
      );
      expect(grandTotalText('₹1,500'), findsOneWidget);
    });

    testWidgets('a saved session can be deleted from the sheet', (
      WidgetTester tester,
    ) async {
      final LocalLedger ledger = await openInMemoryLedger(tester);
      final NoteCounterStore store = NoteCounterStore(ledger);

      await pumpPersistedCounter(tester, store: store, khataId: 'personal');
      await typeFiveHundreds(tester, '2'); // ₹1,000
      await seedSession(tester, store, 'personal', fiftyCount: 2);
      expect(
        await tester.runAsync(() => store.listSessions('personal')),
        hasLength(1),
      );

      await tapHittable(
        tester,
        find.byKey(const Key('note-counter-saved-sessions')),
      );
      await tapHittable(
        tester,
        find.descendant(
          of: find.byKey(const Key('saved-sessions-list')),
          matching: find.byTooltip('Delete'),
        ),
      );
      await tapHittable(
        tester,
        find.byKey(const Key('saved-sessions-delete-confirm')),
      );
      expect(find.byKey(const Key('saved-sessions-empty')), findsOneWidget);
      expect(
        await tester.runAsync(() => store.listSessions('personal')),
        isEmpty,
      );
    });

    testWidgets('each khata lists its own saved sessions', (
      WidgetTester tester,
    ) async {
      final LocalLedger ledger = await openInMemoryLedger(tester);
      final LocalKhata business = (await tester.runAsync(
        () => ledger.createKhata(name: 'Business', openingBalancePaise: 0),
      ))!;
      final NoteCounterStore store = NoteCounterStore(ledger);

      await pumpPersistedCounter(tester, store: store, khataId: 'personal');
      await typeFiveHundreds(tester, '2'); // ₹1,000
      await seedSession(tester, store, 'personal', fiftyCount: 2);

      // The business khata has no sessions of its own.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: NoteCounterScreen(
            language: AppLanguage.en,
            store: store,
            khataId: business.id,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tapHittable(
        tester,
        find.byKey(const Key('note-counter-saved-sessions')),
      );
      expect(find.byKey(const Key('saved-sessions-empty')), findsOneWidget);
    });

    testWidgets('the screen says counter data travels in the backup', (
      WidgetTester tester,
    ) async {
      final LocalLedger ledger = await openInMemoryLedger(tester);
      final NoteCounterStore store = NoteCounterStore(ledger);

      await pumpPersistedCounter(tester, store: store, khataId: 'personal');
      expect(find.textContaining('travels in the backup file'), findsOneWidget);
      expect(
        find.text('In-memory session - nothing is saved or added to a khata'),
        findsNothing,
      );
    });

    testWidgets('Copy summary works for a zero count', (
      WidgetTester tester,
    ) async {
      final LocalLedger ledger = await openInMemoryLedger(tester);
      final NoteCounterStore store = NoteCounterStore(ledger);
      final ClipboardCapture clipboard = ClipboardCapture();
      mockClipboard(clipboard);
      await pumpPersistedCounter(tester, store: store, khataId: 'personal');
      await tapHittable(
        tester,
        find.byKey(const Key('note-counter-copy-summary')),
      );
      expect(clipboard.text, contains('Grand Total: ₹0'));
    });

    testWidgets('Copy summary puts readable text on the clipboard', (
      WidgetTester tester,
    ) async {
      final LocalLedger ledger = await openInMemoryLedger(tester);
      final NoteCounterStore store = NoteCounterStore(ledger);
      final ClipboardCapture clipboard = ClipboardCapture();
      mockClipboard(clipboard);

      await pumpPersistedCounter(tester, store: store, khataId: 'personal');
      await typeFiveHundreds(tester, '10'); // ₹500 x 10 = ₹5,000
      await typeQuantity(tester, 10000, '5'); // ₹100 x 5 = ₹500

      await tapHittable(
        tester,
        find.byKey(const Key('note-counter-copy-summary')),
      );
      expect(clipboard.text, isNotNull);
      expect(clipboard.text, contains('₹500 × 10 = ₹5,000'));
      expect(clipboard.text, contains('₹100 × 5 = ₹500'));
      expect(clipboard.text, contains('Grand Total: ₹5,500'));
    });

    testWidgets('Copy summary carries the coin row as a rupee total', (
      WidgetTester tester,
    ) async {
      final LocalLedger ledger = await openInMemoryLedger(tester);
      final NoteCounterStore store = NoteCounterStore(ledger);
      final ClipboardCapture clipboard = ClipboardCapture();
      mockClipboard(clipboard);

      await pumpPersistedCounter(tester, store: store, khataId: 'personal');
      await typeFiveHundreds(tester, '1'); // ₹500
      await typeQuantity(tester, 100, '37'); // ₹37 of coins

      await tapHittable(
        tester,
        find.byKey(const Key('note-counter-copy-summary')),
      );
      expect(clipboard.text, isNotNull);
      expect(clipboard.text, contains('Coins totalling ₹37'));
      expect(clipboard.text, contains('Grand Total: ₹537'));
    });
  });

  group('add to khata as income', () {
    testWidgets('hidden at zero, shown above zero, hands paise and a note', (
      WidgetTester tester,
    ) async {
      final LocalLedger ledger = await openInMemoryLedger(tester);
      final NoteCounterStore store = NoteCounterStore(ledger);
      int? capturedPaise;
      String? capturedNote;

      await pumpPersistedCounter(
        tester,
        store: store,
        khataId: 'personal',
        onAddToKhata: (int amountPaise, String note) {
          capturedPaise = amountPaise;
          capturedNote = note;
        },
      );
      expect(find.byKey(const Key('note-counter-add-to-khata')), findsNothing);

      await typeFiveHundreds(tester, '10'); // ₹500 x 10 = ₹5,000
      expect(
        find.byKey(const Key('note-counter-add-to-khata')),
        findsOneWidget,
      );
      await tapHittable(
        tester,
        find.byKey(const Key('note-counter-add-to-khata')),
      );
      expect(capturedPaise, 500000);
      expect(capturedNote, isNotNull);
      expect(capturedNote!.trim(), isNotEmpty);
      // The screen never writes a ledger entry itself.
      final LedgerSummary summary = (await tester.runAsync(
        ledger.readSummary,
      ))!;
      expect(summary.entries, isEmpty);
      expect(summary.remainingPaise, 0);
    });

    testWidgets('the button stays hidden without the callback', (
      WidgetTester tester,
    ) async {
      final LocalLedger ledger = await openInMemoryLedger(tester);
      final NoteCounterStore store = NoteCounterStore(ledger);

      await pumpPersistedCounter(tester, store: store, khataId: 'personal');
      await typeFiveHundreds(tester, '2');
      expect(find.byKey(const Key('note-counter-add-to-khata')), findsNothing);
    });
  });

  group('Bengali', () {
    testWidgets('visible counter strings follow the language', (
      WidgetTester tester,
    ) async {
      await pumpCounter(tester, language: AppLanguage.bn);

      expect(find.text('সর্বমোট'), findsOneWidget);
      expect(find.text('কয়েন'), findsOneWidget);
      expect(find.byTooltip('নতুন গণনা'), findsOneWidget);
      expect(
        find.text(
          'শুধু এই সেশনের জন্য — কিছুই সংরক্ষণ করা হয় না বা খাতায় যোগ হয় না',
        ),
        findsOneWidget,
      );

      final SemanticsHandle handle = tester.ensureSemantics();
      // Every note field announces "quantity of <money> notes" in Bengali.
      expect(find.bySemanticsLabel(RegExp('নোটের সংখ্যা')), findsWidgets);
      handle.dispose();

      await typeFiveHundreds(tester, '10');
      expect(grandTotalText('₹৫,০০০'), findsOneWidget);
      expectNoLayoutErrors(tester);
    });
  });

  testWidgets('normal phone fits the persisted counted screen actions', (
    tester,
  ) async {
    final ledger = await openInMemoryLedger(tester);
    final store = NoteCounterStore(ledger);
    await pumpPersistedCounter(
      tester,
      store: store,
      khataId: 'personal',
      size: const Size(390, 770),
      onAddToKhata: (_, _) {},
    );
    await typeFiveHundreds(tester, '2');
    for (final key in <String>[
      'note-counter-add-to-khata',
      'note-counter-saved-sessions',
      'note-counter-copy-summary',
    ]) {
      expect(find.byKey(Key(key)).hitTestable(), findsOneWidget, reason: key);
    }
    expect(
      find.byKey(const Key('note-counter-new-count')).hitTestable(),
      findsOneWidget,
    );
    expect(
      find.textContaining('travels in the backup file').hitTestable(),
      findsOneWidget,
    );
    expectNoLayoutErrors(tester);
  });

  group('layout matrix', () {
    const List<Size> sizes = <Size>[
      Size(320, 568),
      Size(360, 640),
      Size(800, 600),
    ];
    for (final Size size in sizes) {
      for (final double scale in <double>[1.0, 1.3]) {
        testWidgets(
          'persisted counter at ${size.width}x${size.height} text scale $scale',
          (WidgetTester tester) async {
            final LocalLedger ledger = await openInMemoryLedger(tester);
            final NoteCounterStore store = NoteCounterStore(ledger);
            await pumpPersistedCounter(
              tester,
              store: store,
              khataId: 'personal',
              size: size,
              scale: scale,
              onAddToKhata: (_, _) {},
            );
            await typeFiveHundreds(tester, '2'); // ₹1,000
            await seedSession(tester, store, 'personal', fiftyCount: 2);
            await tapHittable(
              tester,
              find.byKey(const Key('note-counter-saved-sessions')),
            );
            expect(
              find.byKey(const Key('saved-sessions-list')),
              findsOneWidget,
            );
            expectNoLayoutErrors(tester);
          },
        );
      }
    }
  });
}
