// Flutter 3.50 deprecates this import; migrate to material_ui in a dedicated dependency update.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khoroch_diary/core/l10n/app_strings.dart';
import 'package:khoroch_diary/core/theme/app_colors.dart';
import 'package:khoroch_diary/core/theme/app_theme.dart';
import 'package:khoroch_diary/features/entry/add_entry_screen.dart';

/// The card colour around [field] - the closest [AnimatedContainer] above it,
/// which is the frame the screen paints for that input.
Color? frameColorOf(WidgetTester tester, Finder field) {
  final Finder frame = find
      .ancestor(of: field, matching: find.byType(AnimatedContainer))
      .first;
  final AnimatedContainer card = tester.widget<AnimatedContainer>(frame);
  return (card.decoration! as BoxDecoration).color;
}

void main() {
  // The redesign puts a bold caption above each framed input instead of a
  // floating `labelText`, so the fields are addressed by key.
  const Key amountField = Key('amount-field');
  const Key descriptionField = Key('description-field');
  const Key saveEntry = Key('save-entry-button');
  const Key dateField = Key('date-field');

  Future<void> showForm(
    WidgetTester tester,
    List<EntryFormResult> saved, {
    int balance = 100000,
    double textScale = 1,
    Size? size,
    EdgeInsets? systemInsets,
    EdgeInsets? viewInsets,
    AppLanguage language = AppLanguage.en,
  }) async {
    if (size != null) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            padding: systemInsets,
            viewPadding: systemInsets,
            viewInsets: viewInsets,
          ),
          child: child ?? const SizedBox.shrink(),
        ),
        home: AddEntryScreen(
          language: language,
          openingBalancePaise: balance,
          onSave: saved.add,
        ),
      ),
    );
  }

  /// Scrolls [finder] to the middle of the scroll view and lets that layout
  /// settle. `WidgetController.ensureVisible` jumps the scroll offset without
  /// laying out, so anything tapped straight afterwards is hit-tested against
  /// the pre-scroll geometry - which is how the Food tile ended up under the
  /// app bar and the category stayed unselected.
  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester, Key key, String value) async {
    await scrollTo(tester, find.byKey(key));
    await tester.enterText(find.byKey(key), value);
    await tester.pump();
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    expect(finder, findsOneWidget);
    await scrollTo(tester, finder);
    // A tap that misses only prints a warning, so assert hit testing rather
    // than silencing it: the target must be the top-most widget at its centre.
    expect(
      finder.hitTestable(),
      findsOneWidget,
      reason: '$finder is not hittable after scrolling it into view.',
    );
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  String labelOf(WidgetTester tester, Finder finder) =>
      tester.getSemantics(finder).getSemanticsData().label;

  testWidgets('validates amount, category and description inline', (
    tester,
  ) async {
    final List<EntryFormResult> saved = <EntryFormResult>[];
    await showForm(tester, saved);
    // Save is live while the form is idle: pressing it on an empty form is
    // how the form names what it is missing, and it writes nothing.
    expect(
      tester.widget<FilledButton>(find.byKey(saveEntry)).onPressed,
      isNotNull,
    );
    await tapVisible(tester, find.text('Save Entry'));
    expect(find.text('Enter a valid amount'), findsOneWidget);
    expect(find.text('Pick a category'), findsOneWidget);
    expect(saved, isEmpty);

    for (final String invalid in <String>[
      '0',
      '0.00',
      '-1',
      '1.234',
      '1000000000',
      '1.',
      'abc',
      '007',
    ]) {
      await enter(tester, amountField, invalid);
      expect(
        tester.widget<FilledButton>(find.byKey(saveEntry)).onPressed,
        isNotNull,
        reason: 'Save must stay available for amount: $invalid',
      );
      await tapVisible(tester, find.text('Save Entry'));
      expect(
        find.text('Enter a valid amount'),
        findsOneWidget,
        reason: 'Rejected amount must explain itself: $invalid',
      );
      expect(saved, isEmpty, reason: 'Rejected amount: $invalid');
    }

    // Picking a category clears its error; leaving an invalid amount
    // behind then flags it under its own frame alone.
    await tapVisible(tester, find.text('Food'));
    expect(find.text('Pick a category'), findsNothing);
    await enter(tester, descriptionField, '');
    expect(find.text('Enter a valid amount'), findsOneWidget);
    expect(find.text('Pick a category'), findsNothing);

    await enter(tester, amountField, '1.25');
    expect(find.text('Enter a valid amount'), findsNothing);
    await tapVisible(tester, find.text('Food'));
    await enter(tester, descriptionField, 'x' * 121);
    await tapVisible(tester, find.text('Save Entry'));
    expect(
      find.text('Description must be 120 characters or fewer'),
      findsOneWidget,
    );
    expect(saved, isEmpty);
    await enter(tester, descriptionField, 'x' * 120);
    await tapVisible(tester, find.text('Save Entry'));
    expect(saved, hasLength(1));
    expect(saved.single.description, 'x' * 120);
  });

  testWidgets('expense callback uses exact paise and selected category', (
    tester,
  ) async {
    final List<EntryFormResult> saved = <EntryFormResult>[];
    await showForm(tester, saved);
    await enter(tester, amountField, '999999999.99');
    await enter(tester, amountField, '12.05');
    // 12.05 against a ₹1,000 balance: the preview is the real projection and
    // the old "findsNothing" guard would have hidden a wrong number.
    expect(find.text('Expense ₹12.05 → remaining ₹987.95'), findsOneWidget);
    await tapVisible(tester, find.text('Gifts'));
    await enter(tester, descriptionField, 'A gift');
    await tapVisible(tester, find.text('Save Entry'));
    expect(saved, hasLength(1));
    expect(saved.single.kind, EntryFormKind.expense);
    expect(saved.single.amountPaise, 1205);
    expect(saved.single.category, 'Gifts');
    expect(saved.single.description, 'A gift');
    final DateTime now = DateTime.now();
    expect(saved.single.occurredAt, DateTime(now.year, now.month, now.day));
    // The host pops this route once the write lands; a directly pumped screen
    // disposes the saving look on the next frame, so a second save is possible.
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Save Entry'));
    expect(saved, hasLength(2));
  });

  testWidgets('income needs no category and saves exact amount', (
    tester,
  ) async {
    final List<EntryFormResult> saved = <EntryFormResult>[];
    await showForm(tester, saved, balance: -100);
    await enter(tester, amountField, '0.5');
    await tapVisible(tester, find.text('Income'));
    expect(find.text('Category: Income'), findsOneWidget);
    expect(find.text('Income ₹0.50 → remaining -₹0.50'), findsOneWidget);
    await tapVisible(tester, find.text('Save Entry'));
    expect(saved, hasLength(1));
    expect(saved.single.kind, EntryFormKind.income);
    expect(saved.single.amountPaise, 50);
    expect(saved.single.category, 'Income');
    expect(saved.single.description, isEmpty);
  });

  testWidgets('a future date is warned about but can be saved', (tester) async {
    final List<EntryFormResult> saved = <EntryFormResult>[];
    await showForm(tester, saved);
    await enter(tester, amountField, '1');
    await tapVisible(tester, find.text('Food'));
    await tapVisible(tester, find.byIcon(Icons.calendar_today));
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('15').last);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('This date is in the future.'), findsOneWidget);
    await tapVisible(tester, find.text('Save Entry'));
    expect(saved, hasLength(1));
    final DateTime now = DateTime.now();
    final DateTime expected = DateTime(now.year, now.month + 1, 15);
    expect(saved.single.occurredAt, expected);
    // Proves the Food tap registered: a missed tap leaves the category unset
    // and save returns no result at all.
    expect(saved.single.category, 'Food');
    expect(saved.single.amountPaise, 100);
  });

  testWidgets('exposes field labels and selected state', (tester) async {
    // Semantics has to be enabled for the tree to be inspectable; the handle
    // is disposed when the test ends.
    final SemanticsHandle semantics = tester.ensureSemantics();
    final List<EntryFormResult> saved = <EntryFormResult>[];
    await showForm(tester, saved);

    // The captions above the frames are their own Texts, so each field also
    // names itself for a screen reader.
    expect(labelOf(tester, find.byKey(amountField)), contains('Amount'));
    expect(
      labelOf(tester, find.byKey(descriptionField)),
      contains('Description'),
    );

    // Expense is the default; both segments are buttons that report selection.
    expect(
      tester.getSemantics(find.text('Expense')),
      isSemantics(label: 'Expense', isButton: true, isSelected: true),
    );
    expect(
      tester.getSemantics(find.text('Income')),
      isSemantics(label: 'Income', isButton: true, isSelected: false),
    );

    // Category tiles expose the same state.
    expect(
      tester.getSemantics(find.text('Shopping')),
      isSemantics(label: 'Shopping', isSelected: false),
    );
    await tapVisible(tester, find.text('Food'));
    expect(
      tester.getSemantics(find.text('Food')),
      isSemantics(label: 'Food', isButton: true, isSelected: true),
    );
    expect(
      tester.getSemantics(find.text('Shopping')),
      isSemantics(label: 'Shopping', isSelected: false),
    );

    await tapVisible(tester, find.text('Income'));
    expect(
      tester.getSemantics(find.text('Income')),
      isSemantics(label: 'Income', isSelected: true),
    );
    expect(
      tester.getSemantics(find.text('Expense')),
      isSemantics(label: 'Expense', isSelected: false),
    );
    semantics.dispose();
  });

  testWidgets('the active field frame turns green', (tester) async {
    final List<EntryFormResult> saved = <EntryFormResult>[];
    await showForm(tester, saved);

    expect(frameColorOf(tester, find.byKey(amountField)), AppColors.warmIvory);

    await enter(tester, amountField, '12');
    await tester.pumpAndSettle();
    expect(frameColorOf(tester, find.byKey(amountField)), AppColors.lightGreen);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ends at Save Entry without the old footer', (tester) async {
    final List<EntryFormResult> saved = <EntryFormResult>[];
    await showForm(tester, saved, size: const Size(390, 844));
    expect(find.text('Add Entry'), findsOneWidget);
    expect(find.text('Amount'), findsOneWidget);
    expect(find.text('Date'), findsOneWidget);
    expect(find.text('Category'), findsOneWidget);
    expect(find.text('Description'), findsOneWidget);
    expect(find.byKey(const Key('add-entry-notebook-image')), findsNothing);
    expect(find.text('Save Entry'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                'assets/illustrations/entry_footer_leaves.png',
      ),
      findsOneWidget,
    );
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final Size size in <Size>[
    const Size(360, 780),
    const Size(390, 844),
    const Size(430, 932),
  ]) {
    testWidgets('fills available height without a blank footer at $size', (
      tester,
    ) async {
      await showForm(
        tester,
        <EntryFormResult>[],
        size: size,
        systemInsets: const EdgeInsets.only(top: 24, bottom: 24),
      );
      await tester.pumpAndSettle();
      final ScrollPosition position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      final Finder footer = find.byKey(const Key('entry-footer-artwork'));
      final double bottom = tester.getBottomLeft(footer).dy;
      expect(
        bottom,
        closeTo(size.height - 24 - (size.height - 48 < 800 ? 6 : 8), 1),
        reason:
            'The form should use its viewport, not leave a blank lower third',
      );
      expect(find.byKey(saveEntry).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('renders consistent rounded icons for each expense category', (
    tester,
  ) async {
    final List<EntryFormResult> saved = <EntryFormResult>[];
    await showForm(tester, saved, size: const Size(390, 844));

    for (final String category in <String>[
      'Shopping',
      'Food',
      'Travel',
      'Bills',
      'Gifts',
    ]) {
      expect(
        find.byKey(Key('category-artwork-$category')),
        findsOneWidget,
        reason: '$category artwork should be visible',
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('category badges share one style and selection changes the ink', (
    tester,
  ) async {
    await showForm(tester, <EntryFormResult>[], size: const Size(360, 780));
    const Map<String, IconData> icons = <String, IconData>{
      'Shopping': Icons.shopping_bag_rounded,
      'Food': Icons.restaurant_rounded,
      'Travel': Icons.flight_rounded,
      'Bills': Icons.receipt_long_rounded,
      'Gifts': Icons.card_giftcard_rounded,
    };
    for (final MapEntry<String, IconData> entry in icons.entries) {
      final Finder badge = find.byKey(Key('category-artwork-${entry.key}'));
      expect(tester.getSize(badge), const Size(32, 32));
      final Container frame = tester.widget<Container>(badge);
      final BoxDecoration decoration = frame.decoration! as BoxDecoration;
      expect(decoration.color, AppColors.lightGreen);
      expect(decoration.borderRadius, BorderRadius.circular(10));
      final Icon icon = tester.widget<Icon>(
        find.descendant(of: badge, matching: find.byType(Icon)),
      );
      expect(icon.icon, entry.value);
      expect(icon.size, 20);
      expect(icon.color, AppColors.primaryGreen);
      expect(
        find.descendant(of: badge, matching: find.byType(Image)),
        findsNothing,
      );
    }
    await tapVisible(tester, find.text('Food'));
    final Finder selected = find.byKey(const Key('category-artwork-Food'));
    expect(
      (tester.widget<Container>(selected).decoration! as BoxDecoration).color,
      AppColors.primaryGreen,
    );
    expect(
      tester
          .widget<Icon>(
            find.descendant(of: selected, matching: find.byType(Icon)),
          )
          .color,
      AppColors.onPrimary,
    );
    expect(find.byKey(const Key('category-check-Food')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stays usable at 200% text scale', (tester) async {
    final List<EntryFormResult> saved = <EntryFormResult>[];
    await showForm(tester, saved, textScale: 2, size: const Size(390, 844));
    expect(find.text('Save Entry'), findsOneWidget);
    await enter(tester, amountField, '12.05');
    await tapVisible(tester, find.text('Food'));
    expect(find.text('Expense ₹12.05 → remaining ₹987.95'), findsOneWidget);
    await tapVisible(tester, find.text('Save Entry'));
    expect(saved, hasLength(1));
    expect(saved.single.amountPaise, 1205);
    expect(saved.single.category, 'Food');
    expect(tester.takeException(), isNull);
  });

  testWidgets('save entry is visible without scrolling on a standard phone', (
    tester,
  ) async {
    final saved = <EntryFormResult>[];
    await showForm(
      tester,
      saved,
      size: const Size(360, 640),
      systemInsets: const EdgeInsets.only(top: 24, bottom: 24),
    );
    await tester.pumpAndSettle();
    expect(find.text('Save Entry').hitTestable(), findsOneWidget);
    final scrollable = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView).first,
    );
    final position = tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byWidget(scrollable),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
    expect(position.pixels, 0);
    expect(position.maxScrollExtent, 0);
    final dateTapTarget = find
        .ancestor(
          of: find.byIcon(Icons.calendar_today),
          matching: find.byType(InkWell),
        )
        .first;
    expect(tester.getSize(dateTapTarget).height, greaterThanOrEqualTo(44));
    expect(tester.takeException(), isNull);
  });

  testWidgets('lays out on a 320px wide screen without overflow', (
    tester,
  ) async {
    final List<EntryFormResult> saved = <EntryFormResult>[];
    await showForm(tester, saved, size: const Size(320, 640));
    expect(find.text('Shopping'), findsOneWidget);
    expect(find.text('Save Entry'), findsOneWidget);
    await enter(tester, amountField, '0.5');
    await tapVisible(tester, find.text('Income'));
    expect(find.text('Category: Income'), findsOneWidget);
    await tapVisible(tester, find.text('Save Entry'));
    expect(saved, hasLength(1));
    expect(saved.single.amountPaise, 50);
    expect(tester.takeException(), isNull);
  });

  // ----- The visual contract this task sets ---------------------------------

  testWidgets('amount is loudest: 40 sp tabular, ₹ before the first digit', (
    tester,
  ) async {
    final List<EntryFormResult> saved = <EntryFormResult>[];
    await showForm(tester, saved, size: const Size(390, 844));
    final TextField field = tester.widget<TextField>(find.byKey(amountField));
    final TextStyle style = field.style!;
    expect(style.fontSize, 40);
    expect(style.fontWeight, FontWeight.w800);
    expect(style.fontFeatures, contains(const FontFeature.tabularFigures()));

    // The ₹ is the field's own prefix - painted inside the input on the
    // amount's first line, not floated above it as a label - and it is
    // weightier than body copy so it reads as part of the number.
    final TextField amountWidget = tester.widget<TextField>(
      find.byKey(amountField),
    );
    final Widget? prefix = amountWidget.decoration!.prefixIcon;
    expect(prefix, isNotNull);
    expect(
      (prefix! as Padding).child,
      isA<Text>().having((Text t) => t.data, 'text', '₹'),
    );
    final Text rupee = (prefix as Padding).child! as Text;
    expect(rupee.style!.fontSize, greaterThanOrEqualTo(20));

    // One calm helper line names what the field expects.
    expect(
      find.text('Enter an amount with up to 9 digits and 2 decimals'),
      findsOneWidget,
    );

    // ...and no other field's text is as large.
    for (final Text text in tester.widgetList<Text>(
      find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.byType(Text),
      ),
    )) {
      final double? size = text.style?.fontSize;
      if (size != null && text.data != '₹') {
        expect(size, lessThanOrEqualTo(40), reason: text.data);
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('section order descends from the amount to the save area', (
    tester,
  ) async {
    final List<EntryFormResult> saved = <EntryFormResult>[];
    await showForm(tester, saved, size: const Size(390, 2000));
    double top(Finder finder) => tester.getTopLeft(finder).dy;
    expect(top(find.byKey(amountField)), lessThan(top(find.text('Expense'))));
    expect(top(find.text('Expense')), lessThan(top(find.text('Date'))));
    expect(top(find.text('Date')), lessThan(top(find.byKey(dateField))));
    expect(top(find.byKey(dateField)), lessThan(top(find.text('Category'))));
    expect(top(find.text('Category')), lessThan(top(find.text('Description'))));
    expect(
      top(find.text('Description')),
      lessThan(top(find.byKey(const Key('after-saving-preview')))),
    );
    expect(
      top(find.byKey(const Key('after-saving-preview'))),
      lessThan(top(find.byKey(saveEntry))),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('card radius family stays between 16 and 20 dp', (tester) async {
    final List<EntryFormResult> saved = <EntryFormResult>[];
    await showForm(tester, saved, size: const Size(390, 844));
    // The date row's keyed frame *is* the AnimatedContainer (so it is not
    // found as an ancestor of itself).
    final BoxDecoration frame =
        tester.widget<AnimatedContainer>(find.byKey(dateField)).decoration!
            as BoxDecoration;
    final double frameRadius = (frame.borderRadius! as BorderRadius).topLeft.x;
    expect(frameRadius, inInclusiveRange(16, 20));

    final Finder amountCard = find
        .ancestor(
          of: find.byKey(amountField),
          matching: find.byType(AnimatedContainer),
        )
        .first;
    final BoxDecoration amountDecoration =
        tester.widget<AnimatedContainer>(amountCard).decoration!
            as BoxDecoration;
    expect(
      (amountDecoration.borderRadius! as BorderRadius).topLeft.x,
      inInclusiveRange(16, 20),
    );
    // The save button matches the input family rather than the old stadium.
    final FilledButton button = tester.widget<FilledButton>(
      find.byKey(saveEntry),
    );
    final RoundedRectangleBorder shape =
        button.style!.shape!.resolve(<WidgetState>{})!
            as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(frameRadius));
    expect(tester.takeException(), isNull);
  });

  testWidgets('every colour comes from AppColors', (tester) async {
    final List<EntryFormResult> saved = <EntryFormResult>[];
    await showForm(tester, saved, size: const Size(390, 844));
    final Set<Color> tokens = <Color>{
      AppColors.primaryGreen,
      AppColors.headerGreen,
      AppColors.secondaryGreen,
      AppColors.accentGreen,
      AppColors.lightGreen,
      AppColors.creamBackground,
      AppColors.warmIvory,
      AppColors.beige,
      AppColors.golden,
      AppColors.orange,
      AppColors.darkText,
      AppColors.softText,
      AppColors.expenseRed,
      AppColors.incomeGreen,
      AppColors.navigationGrey,
      AppColors.onPrimary,
      Colors.transparent,
    };
    bool known(Color? color) {
      if (color == null) return true;
      return tokens.any((Color token) => token.toARGB32() == color.toARGB32());
    }

    for (final Text text in tester.widgetList<Text>(find.byType(Text))) {
      expect(known(text.style?.color), isTrue, reason: text.data);
    }
    for (final Icon icon in tester.widgetList<Icon>(find.byType(Icon))) {
      expect(known(icon.color), isTrue, reason: '${icon.icon}');
    }
    // TextField text styles carry the amount/value ink too.
    for (final EditableText field in tester.widgetList<EditableText>(
      find.byType(EditableText),
    )) {
      expect(known(field.style.color), isTrue);
    }
  });

  testWidgets('a category tile shows a check and a border, not just tint', (
    tester,
  ) async {
    final List<EntryFormResult> saved = <EntryFormResult>[];
    await showForm(tester, saved, size: const Size(390, 844));
    // Nothing is selected yet: no tile paints a check.
    expect(find.byKey(const Key('category-check-Food')), findsNothing);
    await tapVisible(tester, find.text('Food'));
    // The chosen tile gains a check badge in the on-primary ink...
    final Icon checkIcon = tester.widget<Icon>(
      find.byKey(const Key('category-check-Food')),
    );
    expect(checkIcon.icon, Icons.check);
    expect(checkIcon.color, AppColors.onPrimary);
    // ...and a heavier border than an unselected tile.
    double borderWidthOf(String category) {
      final Finder frame = find
          .ancestor(
            of: find.byKey(Key('category-artwork-$category')),
            matching: find.byType(AnimatedContainer),
          )
          .first;
      final BoxDecoration decoration =
          tester.widget<AnimatedContainer>(frame).decoration! as BoxDecoration;
      return (decoration.border! as Border).top.width;
    }

    expect(borderWidthOf('Food'), 2);
    expect(borderWidthOf('Shopping'), lessThan(2));
    expect(
      tester.widget<Text>(find.text('Food')).style!.fontWeight,
      FontWeight.w800,
    );
    // Every starter tile in a row keeps the same width, so it wraps evenly.
    final double foodWidth = tester
        .getSize(
          find
              .ancestor(
                of: find.byKey(const Key('category-artwork-Food')),
                matching: find.byType(AnimatedContainer),
              )
              .first,
        )
        .width;
    final double shoppingWidth = tester
        .getSize(
          find
              .ancestor(
                of: find.byKey(const Key('category-artwork-Shopping')),
                matching: find.byType(AnimatedContainer),
              )
              .first,
        )
        .width;
    expect(foodWidth, shoppingWidth);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid amount shows one aligned inline error, not a stack', (
    tester,
  ) async {
    final List<EntryFormResult> saved = <EntryFormResult>[];
    await showForm(tester, saved, size: const Size(390, 844));
    await enter(tester, amountField, '1.234');
    await enter(tester, descriptionField, '');
    // Exactly one message: the field's own hidden error slot and the visible
    // row never both paint.
    expect(find.text('Enter a valid amount'), findsOneWidget);
    // It sits directly under the amount field, above the Expense/Income pill.
    final double errorTop = tester
        .getTopLeft(find.text('Enter a valid amount'))
        .dy;
    final double fieldBottom = tester.getBottomLeft(find.byKey(amountField)).dy;
    expect(errorTop, greaterThan(fieldBottom));
    expect(errorTop, lessThan(tester.getTopLeft(find.text('Expense')).dy));
    // A positive amount clears the flag and unlocks save; saving without a
    // category then names exactly what is missing.
    await enter(tester, amountField, '5');
    expect(find.text('Enter a valid amount'), findsNothing);
    await tapVisible(tester, find.text('Save Entry'));
    expect(find.text('Pick a category'), findsOneWidget);
    expect(saved, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saving state is distinct and clears after the first frame', (
    tester,
  ) async {
    final List<EntryFormResult> saved = <EntryFormResult>[];
    await showForm(tester, saved, size: const Size(390, 844));
    await enter(tester, amountField, '10');
    await tapVisible(tester, find.text('Food'));
    await scrollTo(tester, find.byKey(saveEntry));
    await tester.tap(find.byKey(saveEntry));
    await tester.pump();
    expect(saved, hasLength(1));
    // Everything the user could press is disabled while the write is in
    // flight, and the button says so.
    expect(
      find.descendant(
        of: find.byKey(saveEntry),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<FilledButton>(find.byKey(saveEntry)).onPressed,
      isNull,
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byKey(saveEntry)).onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('projected balance preview follows kind and amount', (
    tester,
  ) async {
    final List<EntryFormResult> saved = <EntryFormResult>[];
    await showForm(tester, saved, balance: 50000, size: const Size(390, 844));
    expect(find.text('After saving: —'), findsOneWidget);
    await enter(tester, amountField, '125.50');
    await scrollTo(tester, find.byKey(const Key('after-saving-preview')));
    expect(find.text('Expense ₹125.50 → remaining ₹374.50'), findsOneWidget);
    await tapVisible(tester, find.text('Income'));
    await scrollTo(tester, find.byKey(const Key('after-saving-preview')));
    expect(find.text('Income ₹125.50 → remaining ₹625.50'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('with the keyboard up, preview and save stay reachable', (
    tester,
  ) async {
    final List<EntryFormResult> saved = <EntryFormResult>[];
    await showForm(
      tester,
      saved,
      size: const Size(320, 568),
      systemInsets: const EdgeInsets.only(top: 24, bottom: 0),
      // A 320x568 phone with the numeric keypad open: 256 dp of keyboard.
      viewInsets: const EdgeInsets.only(bottom: 256),
    );
    await enter(tester, amountField, '20');
    await tapVisible(tester, find.text('Food'));
    // Scroll to the very end of the form: the save button must be fully on
    // screen and nothing decorative may sit on top of it.
    await Scrollable.ensureVisible(
      tester.element(find.byKey(saveEntry)),
      alignment: 1,
    );
    await tester.pumpAndSettle();
    final Rect button = tester.getRect(find.byKey(saveEntry));
    final double keyboardTop = 568 - 256;
    expect(button.bottom, lessThanOrEqualTo(keyboardTop));
    expect(find.byKey(saveEntry).hitTestable(), findsOneWidget);

    // The preview is directly above it and is still readable.
    final Rect preview = tester.getRect(
      find.byKey(const Key('after-saving-preview')),
    );
    expect(preview.bottom, lessThanOrEqualTo(button.top));
    expect(
      find.byKey(const Key('after-saving-preview')).hitTestable(),
      findsOneWidget,
    );
    // The leaves artwork never covers either: it is last in the scroll
    // content, below the button.
    final Rect artwork = tester.getRect(
      find.byKey(const Key('entry-footer-artwork')),
    );
    expect(artwork.top, greaterThanOrEqualTo(button.bottom));
    await tester.tap(find.byKey(saveEntry));
    await tester.pumpAndSettle();
    expect(saved, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('short labels never clip at 320 dp', (tester) async {
    final List<EntryFormResult> saved = <EntryFormResult>[];
    await showForm(tester, saved, size: const Size(320, 640));
    for (final String label in <String>[
      'Shopping',
      'Food',
      'Travel',
      'Bills',
      'Gifts',
    ]) {
      final Finder text = find.text(label);
      expect(text, findsOneWidget);
      final Finder tile = find
          .ancestor(of: text, matching: find.byType(AnimatedContainer))
          .first;
      // The label is laid out at its intrinsic width inside a scale-down box
      // that paints it into the tile, so the box that must fit is the one that
      // actually paints - the `FittedBox`, not the raw `Text` (whose un-scaled
      // width is what a clipped tile would have to swallow).
      final Finder painted = find
          .ancestor(of: text, matching: find.byType(FittedBox))
          .first;
      expect(
        tester.getSize(painted).width,
        lessThanOrEqualTo(tester.getSize(tile).width),
        reason: '$label must fit its tile',
      );
    }
    expect(tester.takeException(), isNull);
  });

  // ----- The visual contract this polish round sets -----------------------

  testWidgets('amount starts empty with a rupee placeholder, no dead zero', (
    tester,
  ) async {
    await showForm(tester, <EntryFormResult>[], size: const Size(390, 844));
    final TextField field = tester.widget<TextField>(find.byKey(amountField));
    expect(field.controller!.text, isEmpty);
    // The ₹ prefix is the placeholder: no `0.00` ghost value anywhere.
    expect(field.decoration!.hintText ?? '', isEmpty);
    expect(find.text('0.00'), findsNothing);
    expect(find.text('₹'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('save stays available while idle, whatever the amount', (
    tester,
  ) async {
    await showForm(tester, <EntryFormResult>[]);
    bool saveEnabled() =>
        tester.widget<FilledButton>(find.byKey(saveEntry)).onPressed != null;
    // Empty, zero and malformed amounts all keep the action live so a press
    // can explain the problem; nothing about the amount gates it any more.
    expect(saveEnabled(), isTrue);
    await enter(tester, amountField, '0');
    expect(saveEnabled(), isTrue);
    await enter(tester, amountField, '0.5');
    expect(saveEnabled(), isTrue);
    await enter(tester, amountField, '');
    expect(saveEnabled(), isTrue);
    await enter(tester, amountField, '7');
    expect(saveEnabled(), isTrue);
  });

  testWidgets('the header save action names what an empty form misses', (
    tester,
  ) async {
    final List<EntryFormResult> saved = <EntryFormResult>[];
    await showForm(tester, saved);
    // The header action and the main Save Entry button run the same
    // validation: both are live on an empty form and reveal every inline
    // error at once.
    expect(
      tester.widget<FilledButton>(find.byKey(saveEntry)).onPressed,
      isNotNull,
    );
    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid amount'), findsOneWidget);
    expect(find.text('Pick a category'), findsOneWidget);
    expect(saved, isEmpty);
    expect(
      tester.widget<FilledButton>(find.byKey(saveEntry)).onPressed,
      isNotNull,
    );
  });

  testWidgets('a failed save focuses the first invalid field', (tester) async {
    final List<EntryFormResult> saved = <EntryFormResult>[];
    await showForm(tester, saved);
    await tapVisible(tester, find.text('Save Entry'));
    // The amount is the first invalid input: the form scrolls it back into
    // view, focuses it, and keeps its error readable while it has focus.
    expect(find.text('Enter a valid amount'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byKey(amountField)).focusNode!.hasFocus,
      isTrue,
    );
    expect(find.byKey(amountField).hitTestable(), findsOneWidget);
    expect(saved, isEmpty);

    // With a valid amount the missing category is next: its error is shown
    // and the category grid is brought into view.
    await enter(tester, amountField, '42');
    await tapVisible(tester, find.text('Save Entry'));
    expect(find.text('Enter a valid amount'), findsNothing);
    expect(find.text('Pick a category'), findsOneWidget);
    expect(find.text('Food').hitTestable(), findsOneWidget);
    expect(saved, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('leading zeros never parse as an amount', (tester) async {
    await showForm(tester, <EntryFormResult>[]);
    for (final String mess in <String>['007', '00.50', '01']) {
      await enter(tester, amountField, mess);
      await enter(tester, descriptionField, '');
      expect(
        find.text('Enter a valid amount'),
        findsOneWidget,
        reason: '$mess must not read as an amount',
      );
    }
    await enter(tester, amountField, '0.50');
    expect(find.text('Enter a valid amount'), findsNothing);
  });

  testWidgets('the preview reads kind, amount and the remaining balance', (
    tester,
  ) async {
    await showForm(
      tester,
      <EntryFormResult>[],
      balance: 642000,
      size: const Size(390, 844),
    );
    expect(find.text('After saving: —'), findsOneWidget);
    await enter(tester, amountField, '500');
    expect(find.text('Expense ₹500 → remaining ₹5,920'), findsOneWidget);
    await tapVisible(tester, find.text('Income'));
    expect(find.text('Income ₹500 → remaining ₹6,920'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('category grid: four columns at 390, five across at 360', (
    tester,
  ) async {
    double tileWidthOf(WidgetTester tester, String id) => tester
        .getSize(
          find
              .ancestor(
                of: find.byKey(Key('category-artwork-$id')),
                matching: find.byType(AnimatedContainer),
              )
              .first,
        )
        .width;

    double topOf(String id) =>
        tester.getTopLeft(find.byKey(Key('category-artwork-$id'))).dy;

    // 390 dp: four even columns, the fifth starter tile wraps to row two.
    await showForm(tester, <EntryFormResult>[], size: const Size(390, 844));
    expect(topOf('Shopping'), topOf('Bills'));
    expect(topOf('Gifts'), greaterThan(topOf('Bills')));
    expect(tileWidthOf(tester, 'Shopping'), closeTo((390 - 32 - 30) / 4, 0.01));

    // 360 dp at 200% text: all five stay on one row, labels scale down
    // inside their cells instead of overflowing or scrolling sideways.
    await showForm(
      tester,
      <EntryFormResult>[],
      size: const Size(360, 780),
      textScale: 2,
    );
    final double row = topOf('Shopping');
    for (final String id in <String>['Food', 'Travel', 'Bills', 'Gifts']) {
      expect(topOf(id), row, reason: '$id must stay on the first grid row');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('nothing overflows at 320x568 with 200% text', (tester) async {
    await showForm(
      tester,
      <EntryFormResult>[],
      size: const Size(320, 568),
      textScale: 2,
      systemInsets: const EdgeInsets.only(top: 24, bottom: 24),
    );
    expect(tester.takeException(), isNull);
    // The save action stays reachable: the form scrolls internally and the
    // last section is never clipped, even with the preview row above it.
    await scrollTo(tester, find.byKey(saveEntry));
    expect(find.byKey(saveEntry).hitTestable(), findsOneWidget);
    expect(
      find.byKey(const Key('after-saving-preview')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Bengali validation, 320 dp, 200% text and the keyboard up', (
    tester,
  ) async {
    final AppStrings bn = AppStrings(AppLanguage.bn);
    final List<EntryFormResult> saved = <EntryFormResult>[];
    await showForm(
      tester,
      saved,
      language: AppLanguage.bn,
      size: const Size(320, 568),
      textScale: 2,
      systemInsets: const EdgeInsets.only(top: 24, bottom: 0),
      viewInsets: const EdgeInsets.only(bottom: 256),
    );
    expect(tester.takeException(), isNull);

    // The main save explains an empty form in Bengali and writes nothing.
    await tapVisible(tester, find.byKey(saveEntry));
    expect(find.text(bn.text(AppString.validAmount)), findsOneWidget);
    expect(find.text(bn.text(AppString.pickCategory)), findsOneWidget);
    expect(saved, isEmpty);
    expect(tester.takeException(), isNull);

    // Bengali digits parse as before and a valid income saves exactly once.
    await enter(tester, amountField, '৫০');
    await tapVisible(tester, find.text(bn.text(AppString.income)));
    await scrollTo(tester, find.byKey(saveEntry));
    await tester.tap(find.byKey(saveEntry));
    await tester.pumpAndSettle();
    expect(saved, hasLength(1));
    expect(saved.single.kind, EntryFormKind.income);
    expect(saved.single.amountPaise, 5000);
    expect(tester.takeException(), isNull);
  });

  for (final Size size in <Size>[const Size(390, 844), const Size(360, 780)]) {
    testWidgets('first viewport carries the whole form grammar at $size', (
      tester,
    ) async {
      await showForm(
        tester,
        <EntryFormResult>[],
        size: size,
        systemInsets: const EdgeInsets.only(top: 24, bottom: 24),
      );
      for (final Finder finder in <Finder>[
        find.byKey(amountField),
        find.text('Expense'),
        find.byKey(dateField),
        find.text('Category'),
        find.byKey(descriptionField),
      ]) {
        expect(
          tester.getRect(finder).bottom,
          lessThanOrEqualTo(size.height),
          reason: 'the first viewport must show this section',
        );
      }
      expect(tester.takeException(), isNull);
    });
  }
}
