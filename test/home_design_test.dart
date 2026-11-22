// Flutter 3.50 deprecates this import; migrate to material_ui in a dedicated dependency update.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khoroch_diary/core/format/money.dart';
import 'package:khoroch_diary/core/theme/app_colors.dart';
import 'package:khoroch_diary/core/theme/app_theme.dart';
import 'package:khoroch_diary/features/home/home_screen.dart';
import 'package:khoroch_diary/features/home/models.dart';

/// Sizes used by the layout tests: a small phone (320 x 568 logical px) and a
/// common mid-range device (360 x 640).
const Size smallPhone = Size(320, 568);
const Size midPhone = Size(360, 640);

/// Pumps the Home screen alone, with the real app theme, at [scale] text size.
Future<void> pumpHome(
  WidgetTester tester, {
  Size size = midPhone,
  double scale = 1.0,
  VoidCallback? onAddEntry,
  VoidCallback? onViewAll,
  ValueChanged<LedgerEntry>? onRecentEntry,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      // The builder override is how a test can change the text scale without
      // touching the ambient MediaQuery that MaterialApp installs.
      builder: (BuildContext context, Widget? child) {
        final MediaQueryData media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(textScaler: TextScaler.linear(scale)),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: HomeScreen(
        onAddEntry: onAddEntry,
        onViewAll: onViewAll,
        onRecentEntry: onRecentEntry,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Fails with the recorded exception when a layout overflows or throws.
void expectNoLayoutErrors(WidgetTester tester) {
  final Object? exception = tester.takeException();
  expect(
    exception,
    isNull,
    reason: 'layout must not overflow at this size/scale: $exception',
  );
}

void main() {
  group('seeded balance and totals', () {
    testWidgets('shows the seeded remaining, income and expense amounts', (
      WidgetTester tester,
    ) async {
      await pumpHome(tester);

      expect(find.text('Remaining Balance'), findsOneWidget);
      expect(find.text('₹6,420'), findsOneWidget);
      expect(find.text('Total Income'), findsOneWidget);
      expect(find.text('₹10,000'), findsOneWidget);
      expect(find.text('Total Expense'), findsOneWidget);
      expect(find.text('₹3,580'), findsOneWidget);
      expectNoLayoutErrors(tester);
    });

    testWidgets('keeps the seeded numbers identical to the model', (
      WidgetTester tester,
    ) async {
      final LedgerSummary summary = LedgerSummary(
        openingBalancePaise: kSeedOpeningBalancePaise,
        entries: kSeedEntries,
      );
      await pumpHome(tester);

      // The screen must not invent its own arithmetic: these are the same
      // strings the formatter produces for the model values.
      expect(find.text(formatPaise(summary.remainingPaise)), findsOneWidget);
      expect(find.text(formatPaise(summary.totalIncomePaise)), findsOneWidget);
      expect(find.text(formatPaise(summary.totalExpensePaise)), findsOneWidget);
    });

    testWidgets('shows Home content without a full-width brand header', (
      WidgetTester tester,
    ) async {
      await pumpHome(tester);

      expect(find.text('Khoroch Diary'), findsNothing);
      expect(find.text('Plan · Track · Save'), findsNothing);
      expect(find.byIcon(Icons.settings), findsNothing);
      expect(find.text('Recent Transactions'), findsOneWidget);
      expect(find.text('View All'), findsOneWidget);
      expect(find.text('Add New Entry'), findsOneWidget);
      expect(find.text('Sample ledger · preview data only'), findsOneWidget);
    });

    testWidgets('the Add New Entry CTA remains tappable without a header', (
      WidgetTester tester,
    ) async {
      int addTaps = 0;
      await pumpHome(tester, onAddEntry: () => addTaps++);

      expect(find.byIcon(Icons.settings), findsNothing);
      expect(find.byIcon(Icons.add), findsOneWidget);
      final Finder cta = find.text('Add New Entry');
      await tester.ensureVisible(cta);
      await tester.pumpAndSettle();
      await tester.tap(cta);
      await tester.pumpAndSettle();
      expect(addTaps, 1);
      expectNoLayoutErrors(tester);
    });
  });

  testWidgets('active khata and settings controls invoke their callbacks', (
    tester,
  ) async {
    int switches = 0;
    int settings = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: HomeScreen(
          khataName: 'Personal Khata',
          onSwitchKhata: () => switches++,
          onSettings: () => settings++,
        ),
      ),
    );
    await tester.tap(find.byTooltip('Settings'));
    await tester.tap(find.byKey(const Key('switch-khata')));
    expect(settings, 1);
    expect(switches, 1);
  });

  group('visual hierarchy', () {
    testWidgets('hero, totals, section header and rows read top-down', (
      WidgetTester tester,
    ) async {
      await pumpHome(tester);

      final List<double> tops = <double>[
        tester.getTopLeft(find.text('Remaining Balance')).dy,
        tester.getTopLeft(find.text('Total Income')).dy,
        tester.getTopLeft(find.text('Recent Transactions')).dy,
        tester.getTopLeft(find.text('Grocery Shopping')).dy,
      ];
      for (int index = 1; index < tops.length; index++) {
        expect(
          tops[index],
          greaterThan(tops[index - 1]),
          reason: 'block $index must sit below block ${index - 1}',
        );
      }
      expectNoLayoutErrors(tester);
    });

    testWidgets('the pinned CTA stays reachable below every recent row', (
      WidgetTester tester,
    ) async {
      await pumpHome(tester);

      final Finder cta = find.text('Add New Entry');
      await tester.ensureVisible(find.text('Gift for Mom'));
      await tester.pumpAndSettle();

      expect(cta.hitTestable(), findsOneWidget);
      expect(tester.getRect(cta).bottom, lessThanOrEqualTo(midPhone.height));
      expectNoLayoutErrors(tester);
    });
  });

  group('recent transactions', () {
    testWidgets('renders exactly the four newest seeded entries', (
      WidgetTester tester,
    ) async {
      await pumpHome(tester);

      for (final String title in <String>[
        'Grocery Shopping',
        'Lunch with Friends',
        'Mobile Recharge',
        'Gift for Mom',
      ]) {
        expect(find.text(title), findsOneWidget, reason: title);
      }

      // Older entries exist in the model but must not reach the preview list.
      expect(find.text('Bus Fare'), findsNothing);
      expect(find.text('Tea with Team'), findsNothing);
    });

    testWidgets('shows the formatted timestamp and amount for a row', (
      WidgetTester tester,
    ) async {
      await pumpHome(tester);

      expect(find.text('19 Nov 2026, 8:30 PM'), findsOneWidget);
      expect(find.text('19 Nov 2026, 1:15 PM'), findsOneWidget);
      expect(find.text('19 Nov 2026, 10:20 AM'), findsOneWidget);
      expect(find.text('18 Nov 2026, 7:40 PM'), findsOneWidget);

      expect(find.text('₹1,200'), findsOneWidget);
      expect(find.text('₹580'), findsOneWidget);
      expect(find.text('₹199'), findsOneWidget);
      expect(find.text('₹1,000'), findsOneWidget);
    });

    testWidgets('orders rows newest first, top to bottom', (
      WidgetTester tester,
    ) async {
      await pumpHome(tester);

      final List<String> titles = <String>[
        'Grocery Shopping',
        'Lunch with Friends',
        'Mobile Recharge',
        'Gift for Mom',
      ];
      final List<double> tops = <double>[
        for (final String title in titles)
          tester.getTopLeft(find.text(title)).dy,
      ];

      for (int index = 1; index < tops.length; index++) {
        expect(
          tops[index],
          greaterThan(tops[index - 1]),
          reason: '${titles[index]} must sit below ${titles[index - 1]}',
        );
      }
    });

    testWidgets('every visible row shows its category icon', (
      WidgetTester tester,
    ) async {
      await pumpHome(tester);

      expect(
        find.byKey(const Key('category-artwork-Shopping')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('category-artwork-Food')), findsOneWidget);
      expect(find.byKey(const Key('category-artwork-Bills')), findsOneWidget);
      expect(find.byKey(const Key('category-artwork-Gifts')), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Image &&
              widget.image is AssetImage &&
              (widget.image as AssetImage).assetName ==
                  'assets/illustrations/home_balance_wallet.png',
        ),
        findsOneWidget,
      );
    });
  });

  group('accessibility and responsive layout', () {
    testWidgets('layout is clean at the default scale on a small phone', (
      WidgetTester tester,
    ) async {
      await pumpHome(tester, size: smallPhone);
      expectNoLayoutErrors(tester);
      expect(find.text('₹6,420'), findsOneWidget);
    });

    testWidgets('200% text scale does not overflow on a small phone', (
      WidgetTester tester,
    ) async {
      await pumpHome(tester, size: smallPhone, scale: 2.0);

      expectNoLayoutErrors(tester);
      // Numbers stay present (they scale down inside their own boxes).
      expect(find.text('₹6,420'), findsOneWidget);
      expect(find.text('₹10,000'), findsOneWidget);
      expect(find.text('₹3,580'), findsOneWidget);
    });

    testWidgets('200% text scale does not overflow on a mid-range phone', (
      WidgetTester tester,
    ) async {
      await pumpHome(tester, size: midPhone, scale: 2.0);
      expectNoLayoutErrors(tester);
    });

    testWidgets('200% text scale keeps the four recent rows visible', (
      WidgetTester tester,
    ) async {
      await pumpHome(tester, size: smallPhone, scale: 2.0);

      for (final String title in <String>[
        'Grocery Shopping',
        'Lunch with Friends',
        'Mobile Recharge',
        'Gift for Mom',
      ]) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
      expect(find.text('Add New Entry'), findsOneWidget);
    });

    testWidgets('the primary CTA stays visible while content scrolls at 200%', (
      WidgetTester tester,
    ) async {
      await pumpHome(tester, size: smallPhone, scale: 2.0);

      final Finder cta = find.text('Add New Entry');
      expect(tester.getRect(cta).top, greaterThan(0));
      expect(
        tester.getRect(cta).bottom,
        lessThanOrEqualTo(smallPhone.height),
        reason: 'the primary action stays pinned above the device edge',
      );
      expect(cta.hitTestable(), findsOneWidget);

      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();
      expect(cta.hitTestable(), findsOneWidget);
      expectNoLayoutErrors(tester);
    });

    testWidgets('summary tiles expose direction in their semantics', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpHome(tester);

      // The tile announces label, direction and amount as one node.
      expect(
        find.bySemanticsLabel(RegExp(r'Total Income, income, ₹10,000')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'Total Expense, expense, ₹3,580')),
        findsOneWidget,
      );
      // The category is no longer a node of its own: it is spoken inside the
      // row's single label, so a reader hears one row rather than a row plus
      // a floating "Category Shopping" from its decorative avatar.
      expect(
        tester
            .getSemantics(find.byKey(const Key('home-recent-Grocery Shopping')))
            .label,
        contains('Shopping'),
      );
      expect(find.byTooltip('Settings'), findsNothing);
      handle.dispose();
    });
  });

  group('actionable activity rows', () {
    /// A live, fully stored ledger: the only state in which a Home row may be
    /// edited. Two rows, long names and large amounts, so the layout checks
    /// below are the pessimistic ones from the brief.
    LedgerSummary storedSummary() => LedgerSummary(
      openingBalancePaise: 0,
      entries: <LedgerEntry>[
        LedgerEntry(
          title:
              'Freelance invoice settled by the client for the festival '
              'campaign and the extra revisions',
          category: 'Income',
          at: DateTime(2026, 11, 19, 18, 30),
          amountPaise: 876543210,
          type: EntryType.income,
          id: 'entry-design-income',
        ),
        LedgerEntry(
          title: 'Monthly grocery and household supplies for the whole family',
          category: 'Shopping',
          at: DateTime(2026, 11, 19, 17),
          amountPaise: 123456789,
          id: 'entry-design-expense',
        ),
      ],
    );

    Finder rowOf(String title) => find.byKey(Key('home-recent-$title'));

    testWidgets('a row announces direction, title and amount as one node', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      final LedgerSummary summary = storedSummary();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: HomeScreen(summary: summary, onRecentEntry: (_) {}),
        ),
      );
      await tester.pumpAndSettle();

      final String incomeTitle = summary.entries.first.title;
      await tester.ensureVisible(rowOf(incomeTitle));
      await tester.pumpAndSettle();

      final SemanticsNode node = tester.getSemantics(rowOf(incomeTitle));
      // Direction is in words, so the green/red amount is never the only
      // carrier of the meaning; the figure is spoken with its sign.
      expect(node.label, contains('Income +'));
      expect(node.label, contains('+₹87,65,432.10'));
      expect(node.label, contains(incomeTitle));
      // A stored row with a handler announces the edit affordance.
      expect(node.label, contains('Tap to edit'));
      // The decorative avatar is not announced a second time.
      expect(
        find.descendant(
          of: rowOf(incomeTitle),
          matching: find.bySemanticsLabel(RegExp('Category')),
        ),
        findsNothing,
        reason: 'the row speaks once, not once per decorative part',
      );
      handle.dispose();
    });

    testWidgets('an expense row is signed and coloured differently', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      final LedgerSummary summary = storedSummary();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: HomeScreen(summary: summary, onRecentEntry: (_) {}),
        ),
      );
      await tester.pumpAndSettle();

      final String expenseTitle = summary.entries.last.title;
      await tester.ensureVisible(rowOf(expenseTitle));
      await tester.pumpAndSettle();

      final SemanticsNode node = tester.getSemantics(rowOf(expenseTitle));
      expect(node.label, contains('Expense -'));
      expect(node.label, contains('-₹12,34,567.89'));

      final Text amount = tester.widget<Text>(
        find.descendant(
          of: rowOf(expenseTitle),
          matching: find.text('₹12,34,567.89'),
        ),
      );
      expect(amount.style?.color, AppColors.expenseRed);
      final Text incomeAmount = tester.widget<Text>(
        find.descendant(
          of: rowOf(summary.entries.first.title),
          matching: find.text('+₹87,65,432.10'),
        ),
      );
      expect(incomeAmount.style?.color, AppColors.incomeGreen);
      handle.dispose();
    });

    testWidgets('the edit affordance appears only where a tap edits', (
      WidgetTester tester,
    ) async {
      // Seed data has no ids: a preview row may not offer an edit icon, even
      // when the parent supplies the callback.
      await pumpHome(tester, onRecentEntry: (_) {});
      await tester.ensureVisible(find.text('Gift for Mom'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.edit_outlined), findsNothing);

      // Stored rows with the same callback do offer it, once per row.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: HomeScreen(summary: storedSummary(), onRecentEntry: (_) {}),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(rowOf(storedSummary().entries.last.title));
      expect(find.byIcon(Icons.edit_outlined), findsNWidgets(2));
      expectNoLayoutErrors(tester);
    });

    testWidgets('every actionable row is at least 44 dp tall', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: HomeScreen(summary: storedSummary(), onRecentEntry: (_) {}),
        ),
      );
      await tester.pumpAndSettle();

      for (final LedgerEntry entry in storedSummary().entries) {
        await tester.ensureVisible(rowOf(entry.title));
        await tester.pumpAndSettle();
        expect(
          tester.getSize(rowOf(entry.title)).height,
          greaterThanOrEqualTo(44),
          reason: '${entry.title} must be a full-size tap target',
        );
        // The width is the sheet's own: the row is the full sheet width, so
        // the target is never a sliver beside the amount.
        expect(
          tester.getSize(rowOf(entry.title)).width,
          greaterThanOrEqualTo(44),
        );
      }
    });

    testWidgets('a 320 dp phone at 200% still lays out the edit target', (
      WidgetTester tester,
    ) async {
      addTearDown(tester.view.reset);
      for (final Size size in <Size>[smallPhone, midPhone]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            builder: (BuildContext context, Widget? child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child ?? const SizedBox.shrink(),
            ),
            home: HomeScreen(summary: storedSummary(), onRecentEntry: (_) {}),
          ),
        );
        await tester.pumpAndSettle();

        expectNoLayoutErrors(tester);
        final Finder row = rowOf(storedSummary().entries.last.title);
        await tester.ensureVisible(row);
        await tester.pumpAndSettle();
        expect(tester.getSize(row).height, greaterThanOrEqualTo(44));
        expect(row.hitTestable(), findsOneWidget);
        // The rows stay inside the page grid: nothing is clipped at the edge.
        expect(tester.getRect(row).left, greaterThanOrEqualTo(0));
        expect(tester.getRect(row).right, lessThanOrEqualTo(size.width));
        expectNoLayoutErrors(tester);
      }
    });
  });

  group('polish contract: one grid, one scale, one row language', () {
    /// The three amounts the hero and the two tiles show, plus a row's amount.
    void expectTabular(WidgetTester tester, String amount) {
      final Text figure = tester.widget<Text>(find.text(amount));
      expect(
        figure.style?.fontFeatures,
        contains(FontFeature.tabularFigures()),
        reason: '$amount must use tabular figures so digits line up',
      );
    }

    testWidgets('cards and the CTA sit on the same 16 dp page grid', (
      tester,
    ) async {
      await pumpHome(tester);
      // The CTA is the deepest thing in the list, so reveal it first: every
      // assertion below is a left edge or a gap, and neither moves when the
      // list scrolls.
      await tester.ensureVisible(find.byKey(const Key('home-add-entry')));

      final Rect hero = tester.getRect(
        find.byKey(const Key('home-balance-card')),
      );
      final Rect tiles = tester.getRect(
        find.byKey(const Key('home-summary-row')),
      );
      final Rect list = tester.getRect(
        find.byKey(const Key('recent-transactions-card')),
      );
      final Rect cta = tester.getRect(find.byKey(const Key('home-add-entry')));

      expect(hero.left, 16);
      expect(tiles.left, 16);
      expect(list.left, 16);
      expect(cta.left, 16);
      expect(hero.right, midPhone.width - 16);
      expect(cta.right, midPhone.width - 16);
      // One inter-card gap, everywhere: 12 dp between the hero and the tiles.
      expect(tiles.top - hero.bottom, 12);
      // The section header sits on the page column, one card inset (12 dp)
      // further in than the card edges above it - so it lines up with the
      // card *interiors*, not with their outer frames. `Remaining Balance` is
      // not part of that column at all: it is the caption inside the balance
      // card, set right of the card's gold bar.
      expect(
        tester.getTopLeft(find.text('Recent Transactions')).dx,
        hero.left + 12,
      );
    });

    testWidgets('the recent rows share one sheet with a rule between them', (
      tester,
    ) async {
      await pumpHome(tester);

      final Finder sheet = find.byKey(const Key('recent-transactions-card'));
      expect(sheet, findsOneWidget);
      // Reveal the last row so all three rules are laid out on a 640 dp phone.
      await tester.ensureVisible(find.text('Gift for Mom'));
      // Four rows, so three rules - one between each pair, none after the last.
      expect(
        find.descendant(
          of: sheet,
          matching: find.byWidgetPredicate(
            (Widget widget) =>
                widget is ColoredBox && widget.color == AppColors.beige,
          ),
        ),
        findsNWidgets(3),
      );
      // The sheet carries the surface; nothing inside it casts a shadow, which
      // is what "boxed rows" used to mean.
      final Iterable<DecoratedBox> boxes = tester
          .widgetList<DecoratedBox>(
            find.descendant(of: sheet, matching: find.byType(DecoratedBox)),
          )
          .where((DecoratedBox box) => box.decoration is BoxDecoration);
      expect(
        boxes.where(
          (DecoratedBox box) =>
              (box.decoration as BoxDecoration).boxShadow?.isNotEmpty ?? false,
        ),
        isEmpty,
      );
      final BoxDecoration sheetBox =
          tester.widget<Container>(sheet).decoration! as BoxDecoration;
      expect(sheetBox.color, AppColors.surface);
      expect(sheetBox.borderRadius, BorderRadius.circular(20));
    });

    testWidgets('the summary pair is one block split by one rule', (
      WidgetTester tester,
    ) async {
      await pumpHome(tester);

      final Finder row = find.byKey(const Key('home-summary-row'));
      final BoxDecoration box =
          tester.widget<Container>(row).decoration! as BoxDecoration;
      // One frame for income and expense, framed like every other card.
      expect(box.color, AppColors.surface);
      expect(box.borderRadius, BorderRadius.circular(20));
      // One rule between the halves - and neither half is a box of its own
      // any more, so nothing inside carries a border or a shadow.
      expect(
        find.descendant(
          of: row,
          matching: find.byWidgetPredicate(
            (Widget widget) =>
                widget is ColoredBox && widget.color == AppColors.beige,
          ),
        ),
        findsOneWidget,
      );
      // The frame above is the only boxed thing here: neither half may carry
      // its own border or shadow (the row's own decoration is skipped, since
      // that is the frame the check is made against).
      // The row's own Container decoration is the frame itself, so it is not
      // one of the halves under test: everything else that paints a
      // BoxDecoration must be flat (an icon chip), never bordered or lifted.
      final BoxDecoration frame = box;
      final Iterable<DecoratedBox> halves = tester
          .widgetList<DecoratedBox>(
            find.descendant(of: row, matching: find.byType(DecoratedBox)),
          )
          .where(
            (DecoratedBox decorated) =>
                decorated.decoration is BoxDecoration &&
                !identical(decorated.decoration, frame),
          );
      expect(
        halves.where(
          (DecoratedBox decorated) =>
              (decorated.decoration as BoxDecoration).border != null ||
              ((decorated.decoration as BoxDecoration).boxShadow?.isNotEmpty ??
                  false),
        ),
        isEmpty,
      );
    });

    testWidgets('every amount is drawn with tabular figures', (tester) async {
      await pumpHome(tester);
      // The fourth row's amount is the lowest figure, so revealing it brings
      // every amount in this loop into the tree.
      await tester.ensureVisible(find.text('₹1,000'));

      for (final String amount in <String>[
        '₹6,420',
        '₹10,000',
        '₹3,580',
        '₹1,200',
        '₹580',
        '₹199',
        '₹1,000',
      ]) {
        expectTabular(tester, amount);
      }
    });

    testWidgets('labels, figures, titles and dates come from one scale', (
      tester,
    ) async {
      await pumpHome(tester);

      double sizeOf(String text) =>
          tester.widget<Text>(find.text(text)).style!.fontSize!;

      // Caption, then figure, then row title, then date - the same four steps
      // on every card, at the same sizes.
      expect(sizeOf('Remaining Balance'), 12);
      expect(sizeOf('Total Income'), 12);
      expect(sizeOf('Total Expense'), 12);
      expect(sizeOf('19 Nov 2026, 8:30 PM'), 12);
      expect(sizeOf('Grocery Shopping'), 15);
      expect(sizeOf('Recent Transactions'), 16);
      expect(sizeOf('₹6,420'), 38);
      expect(sizeOf('₹10,000'), 24);
    });
  });
}
