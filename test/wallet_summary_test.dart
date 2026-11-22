// Flutter 3.50 deprecates this import; migrate to material_ui in a dedicated dependency update.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khoroch_diary/features/entry/add_entry_screen.dart';
import 'package:khoroch_diary/core/theme/app_colors.dart';
import 'package:khoroch_diary/features/home/models.dart';
import 'package:khoroch_diary/features/ledger/data/local_ledger.dart';
import 'package:khoroch_diary/features/ledger/wallet_summary_screen.dart';

EntryFormResult _entry({
  required EntryFormKind kind,
  required int amountPaise,
  required String category,
  String description = '',
  required DateTime occurredAt,
}) {
  return EntryFormResult(
    kind: kind,
    amountPaise: amountPaise,
    category: category,
    description: description,
    occurredAt: occurredAt,
  );
}

Widget _host(LocalLedger ledger) {
  return MaterialApp(
    theme: ThemeData(useMaterial3: true),
    home: WalletSummaryScreen(ledger: ledger),
  );
}

/// A ledger double: delegates the reads this screen uses and records them, so a
/// test can prove the screen only reads and never closes a ledger it did not
/// create.
class _RecordingLedger extends LocalLedger {
  _RecordingLedger(super.executor);

  int listCalls = 0;
  final List<String> readIds = <String>[];
  int closeCalls = 0;

  @override
  Future<List<LocalKhata>> listKhatas() {
    listCalls++;
    return super.listKhatas();
  }

  @override
  Future<LedgerSummary> readSummary({String khataId = 'personal'}) {
    readIds.add(khataId);
    return super.readSummary(khataId: khataId);
  }

  @override
  Future<void> close() {
    closeCalls++;
    return super.close();
  }
}

void main() {
  group('with seeded data (two khatas)', () {
    late LocalLedger ledger;
    late LocalKhata business;

    setUp(() async {
      ledger = LocalLedger(NativeDatabase.memory());
      await ledger.initialize();
      business = await ledger.createKhata(
        name: 'Business Khata',
        openingBalancePaise: 250000,
      );
      // Personal: opening ₹0, one income of ₹7,000.
      await ledger.addEntry(
        _entry(
          kind: EntryFormKind.income,
          amountPaise: 700000,
          category: 'Income',
          occurredAt: DateTime(2026, 3, 1),
        ),
      );
      // Business: opening ₹2,500, income ₹3,000, expense ₹450.
      await ledger.addEntry(
        _entry(
          kind: EntryFormKind.income,
          amountPaise: 300000,
          category: 'Income',
          description: 'Client payment',
          occurredAt: DateTime(2026, 3, 2),
        ),
        khataId: business.id,
      );
      await ledger.addEntry(
        _entry(
          kind: EntryFormKind.expense,
          amountPaise: 45000,
          category: 'Bills',
          description: 'Electricity',
          occurredAt: DateTime(2026, 3, 3),
        ),
        khataId: business.id,
      );
    });

    tearDown(() async {
      await ledger.close();
    });

    testWidgets('the combined card sits above every khata card', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(ledger));
      await tester.pumpAndSettle();

      final Finder combinedCard = find.text('Combined remaining');
      final Finder personalCard = find.text('Personal Khata');
      final Finder businessCard = find.text('Business Khata');

      final double combinedTop = tester.getTopLeft(combinedCard).dy;
      final double personalTop = tester.getTopLeft(personalCard).dy;
      final double businessTop = tester.getTopLeft(businessCard).dy;

      expect(combinedTop, lessThan(personalTop));
      expect(personalTop, lessThan(businessTop));
    });

    testWidgets('shows every per-khata figure and the combined remaining', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(ledger));
      await tester.pumpAndSettle();

      // Both khata names and their entry counts.
      expect(find.text('Personal Khata'), findsOneWidget);
      expect(find.text('Business Khata'), findsOneWidget);
      expect(find.text('1 entry'), findsOneWidget); // personal
      expect(find.text('2 entries'), findsOneWidget); // business

      // Personal: opening 0, income 7,000, expense 0, remaining 7,000.
      expect(find.text('Opening balance'), findsNWidgets(2));
      expect(find.text('₹0'), findsNWidgets(2));
      expect(find.text('₹7,000'), findsNWidgets(2));

      // Business: opening 2,500, income 5,500 incl. opening,
      // expense 450, remaining 5,050.
      expect(find.text('₹2,500'), findsOneWidget);
      expect(find.text('₹5,500'), findsOneWidget);
      expect(find.text('₹450'), findsOneWidget);
      expect(find.text('₹5,050'), findsOneWidget);

      // Combined remaining = 7,000 + 5,050: openings are not added twice.
      expect(find.text('Combined remaining'), findsOneWidget);
      expect(find.text('₹12,050'), findsOneWidget);
      expect(find.text('Across 2 khatas'), findsOneWidget);
      expect(find.text('Income (incl. opening)'), findsNWidgets(2));
      await tester.scrollUntilVisible(
        find.textContaining('never added twice'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('never added twice'), findsOneWidget);
    });

    testWidgets('reload reflects a new entry', (WidgetTester tester) async {
      await tester.pumpWidget(_host(ledger));
      await tester.pumpAndSettle();
      expect(find.text('2 entries'), findsOneWidget);

      await tester.runAsync(
        () => ledger.addEntry(
          _entry(
            kind: EntryFormKind.expense,
            amountPaise: 1000,
            category: 'Food',
            occurredAt: DateTime(2026, 3, 4),
          ),
          khataId: business.id,
        ),
      );
      await tester.tap(find.byTooltip('Reload summary'));
      await tester.pumpAndSettle();

      expect(find.text('3 entries'), findsOneWidget);
      // Business remaining drops to 5,040; combined becomes 12,040.
      expect(find.text('₹5,040'), findsOneWidget);
      expect(find.text('₹12,040'), findsOneWidget);
      expect(find.text('₹5,050'), findsNothing);
    });

    testWidgets('the combined card and every khata card share one radius', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(ledger));
      await tester.pumpAndSettle();

      BoxDecoration boxOf(Finder finder) =>
          tester.widget<Container>(finder).decoration! as BoxDecoration;
      final Finder combined = find.byKey(const Key('wallet-combined-card'));
      final Finder personal = find.byKey(const Key('wallet-khata-personal'));
      final Finder shop = find.byKey(Key('wallet-khata-${business.id}'));

      final Set<BorderRadiusGeometry> radii = <BorderRadiusGeometry>{
        boxOf(combined).borderRadius!,
        boxOf(personal).borderRadius!,
        boxOf(shop).borderRadius!,
      };
      // One card radius for the hero and for every khata, as on Home.
      expect(radii, <BorderRadiusGeometry>{BorderRadius.circular(20)});

      // One gap between cards, and the same 16 dp page grid.
      expect(
        tester.getRect(personal).top - tester.getRect(combined).bottom,
        12,
      );
      expect(tester.getRect(combined).left, 16);
    });

    testWidgets('a khata card reads label, then figure, in tabular figures', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(ledger));
      await tester.pumpAndSettle();

      // Personal holds one income of ₹7,000 on an opening of ₹0, so the
      // figure shows twice: once as an input, once as the result.
      final Iterable<Text> figures = tester.widgetList<Text>(
        find.descendant(
          of: find.byKey(const Key('wallet-khata-personal')),
          matching: find.text('₹7,000'),
        ),
      );
      expect(figures, hasLength(2));
      for (final Text figure in figures) {
        expect(figure.textAlign, TextAlign.right);
        expect(
          figure.style?.fontFeatures,
          contains(FontFeature.tabularFigures()),
          reason: 'figures in a card must line up in a column',
        );
      }
      // One size for an input, one step up for the figure that matters.
      expect(
        figures.map((Text figure) => figure.style!.fontSize).toSet(),
        <double?>{14, 20},
      );

      // Card title and caption follow the same steps as every other card.
      final Text title = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('wallet-khata-personal')),
          matching: find.text('Personal Khata'),
        ),
      );
      expect(title.style?.fontSize, 16);
    });
  });

  testWidgets('only reads: never closes the caller-owned ledger', (
    WidgetTester tester,
  ) async {
    final _RecordingLedger recording = _RecordingLedger(
      NativeDatabase.memory(),
    );
    await tester.runAsync(() => recording.initialize());
    await tester.runAsync(
      () => recording.addEntry(
        _entry(
          kind: EntryFormKind.expense,
          amountPaise: 1234,
          category: 'Food',
          occurredAt: DateTime(2026, 6, 1),
        ),
      ),
    );

    await tester.pumpWidget(_host(recording));
    await tester.pumpAndSettle();
    expect(recording.listCalls, 1);
    expect(recording.readIds, <String>['personal']);
    expect(find.text('₹12.34'), findsOneWidget);

    // Unmounting the screen must not close a ledger it does not own.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();
    expect(recording.closeCalls, 0);

    // The ledger is still usable after the screen is gone.
    expect(
      (await tester.runAsync(() => recording.readSummary()))!.totalExpensePaise,
      1234,
    );
    await tester.runAsync(() => recording.close());
  });

  testWidgets('empty ledger with zero balances totals zero', (
    WidgetTester tester,
  ) async {
    final LocalLedger ledger = LocalLedger(NativeDatabase.memory());
    await tester.runAsync(() => ledger.initialize());

    await tester.pumpWidget(_host(ledger));
    await tester.pumpAndSettle();

    expect(find.text('Personal Khata'), findsOneWidget);
    expect(find.text('0 entries'), findsOneWidget);
    // opening, income, expense, remaining, combined.
    expect(find.text('₹0'), findsNWidgets(5));
    expect(find.text('Combined remaining'), findsOneWidget);
    expect(find.text('Across 1 khata'), findsOneWidget);
    // No design-preview seed figures leak into a real screen.
    expect(find.text('₹10,000'), findsNothing);
    expect(find.text('₹6,420'), findsNothing);

    await tester.runAsync(() => ledger.close());
  });

  testWidgets('a database with no khatas says so instead of inventing one', (
    WidgetTester tester,
  ) async {
    // Open the database without seeding the default khata.
    final LocalLedger ledger = LocalLedger(NativeDatabase.memory());
    await tester.runAsync(() => ledger.listKhatas());

    await tester.pumpWidget(_host(ledger));
    await tester.pumpAndSettle();

    expect(find.text('No khatas on this device yet.'), findsOneWidget);
    expect(find.text('Combined remaining'), findsNothing);
    expect(find.text('Personal Khata'), findsNothing);
    await tester.runAsync(() => ledger.close());
  });

  testWidgets('negative remaining is shown, not hidden or clamped', (
    WidgetTester tester,
  ) async {
    final LocalLedger ledger = LocalLedger(NativeDatabase.memory());
    await tester.runAsync(() => ledger.initialize());
    final LocalKhata loans = (await tester.runAsync(
      () => ledger.createKhata(name: 'Loans', openingBalancePaise: 10000),
    ))!;
    await tester.runAsync(
      () => ledger.addEntry(
        _entry(
          kind: EntryFormKind.expense,
          amountPaise: 35000,
          category: 'Bills',
          occurredAt: DateTime(2026, 7, 1),
        ),
        khataId: loans.id,
      ),
    );

    await tester.pumpWidget(_host(ledger));
    await tester.pumpAndSettle();

    // Loans: 100 - 350 = -250 paise-words; personal is 0; combined is -250.
    expect(find.text('-₹250'), findsNWidgets(2));
    expect(find.text('₹350'), findsOneWidget);
    // Opening balance and income (incl. opening) both read ₹100.
    expect(find.text('₹100'), findsNWidgets(2));
    expect(find.text('₹0'), findsNWidgets(4)); // the zero personal card

    await tester.runAsync(() => ledger.close());
  });

  testWidgets('failure shows the real reason and retry is honest', (
    WidgetTester tester,
  ) async {
    final LocalLedger ledger = LocalLedger(NativeDatabase.memory());
    await tester.runAsync(() => ledger.initialize());
    await tester.runAsync(
      () => ledger.addEntry(
        _entry(
          kind: EntryFormKind.income,
          amountPaise: 50000,
          category: 'Income',
          occurredAt: DateTime(2026, 8, 1),
        ),
      ),
    );
    // A closed database makes every read throw: a real failure, not a mock.
    await tester.runAsync(() => ledger.close());

    await tester.pumpWidget(_host(ledger));
    await tester.pumpAndSettle();

    expect(find.text('Could not read your khatas'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    // No stale or invented totals while the read fails.
    expect(find.text('Combined remaining'), findsNothing);
    expect(find.text('₹500'), findsNothing);

    // Retry re-attempts the read; on a closed database it stays an honest
    // failure rather than showing invented figures.
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Could not read your khatas'), findsOneWidget);
    expect(find.text('Combined remaining'), findsNothing);
  });

  testWidgets('reload picks up figures written after the first load', (
    WidgetTester tester,
  ) async {
    final LocalLedger ledger = LocalLedger(NativeDatabase.memory());
    await tester.runAsync(() => ledger.initialize());
    await tester.pumpWidget(_host(ledger));
    await tester.pumpAndSettle();
    expect(find.text('0 entries'), findsOneWidget);

    await tester.runAsync(
      () => ledger.addEntry(
        _entry(
          kind: EntryFormKind.income,
          amountPaise: 125000,
          category: 'Income',
          occurredAt: DateTime(2026, 9, 1),
        ),
      ),
    );
    expect(find.text('0 entries'), findsOneWidget); // not refreshed yet

    await tester.tap(find.byTooltip('Reload summary'));
    await tester.pumpAndSettle();

    expect(find.text('1 entry'), findsOneWidget);
    // income, remaining and combined.
    expect(find.text('₹1,250'), findsNWidgets(3));
    await tester.runAsync(() => ledger.close());
  });

  for (final double textScale in <double>[1, 2]) {
    testWidgets(
      'no overflow at 320dp width and ${(textScale * 100).round()}% text',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final LocalLedger ledger = LocalLedger(NativeDatabase.memory());
        await tester.runAsync(() => ledger.initialize());
        final LocalKhata longName = (await tester.runAsync(
          () => ledger.createKhata(
            name: 'Very Long Family Business Khata Name',
            openingBalancePaise: 987654321,
          ),
        ))!;
        await tester.runAsync(
          () => ledger.addEntry(
            _entry(
              kind: EntryFormKind.expense,
              amountPaise: 12345678,
              category: 'Shopping',
              description: 'Big purchase',
              occurredAt: DateTime(2026, 10, 1),
            ),
            khataId: longName.id,
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(useMaterial3: true),
            home: Builder(
              builder: (BuildContext context) {
                return MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(textScale)),
                  child: WalletSummaryScreen(ledger: ledger),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Any RenderFlex overflow is reported as a test exception.
        expect(tester.takeException(), isNull);
        expect(find.text('Combined remaining'), findsOneWidget);

        // Scroll through every card at the narrow width.
        await tester.scrollUntilVisible(
          find.textContaining('never added twice'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.textContaining('never added twice'), findsOneWidget);
        await tester.runAsync(() => ledger.close());
      },
    );
  }

  testWidgets('the combined figure is readable from semantics alone', (
    WidgetTester tester,
  ) async {
    final LocalLedger ledger = LocalLedger(NativeDatabase.memory());
    await tester.runAsync(() => ledger.initialize());
    await tester.runAsync(
      () => ledger.addEntry(
        _entry(
          kind: EntryFormKind.income,
          amountPaise: 200000,
          category: 'Income',
          occurredAt: DateTime(2026, 11, 1),
        ),
      ),
    );

    final SemanticsHandle handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(ledger));
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel(RegExp('Combined remaining, Across 1 khata')),
      findsOneWidget,
    );
    // The label carries the amount and the opening-balance caveat as text, so
    // it does not rely on colour or layout.
    expect(find.bySemanticsLabel(RegExp('₹2,000')), findsWidgets);
    expect(
      find.bySemanticsLabel(RegExp('Income already includes each khata')),
      findsWidgets,
    );
    handle.dispose();
    await tester.runAsync(() => ledger.close());
  });

  testWidgets('app bar and back navigation come from Navigator', (
    WidgetTester tester,
  ) async {
    final LocalLedger ledger = LocalLedger(NativeDatabase.memory());
    await tester.runAsync(() => ledger.initialize());

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            return Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (BuildContext _) =>
                            WalletSummaryScreen(ledger: ledger),
                      ),
                    );
                  },
                  child: const Text('Open wallet'),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Open wallet'));
    await tester.pumpAndSettle();
    expect(find.text('Wallet Summary'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Open wallet'), findsOneWidget);
    expect(find.byType(WalletSummaryScreen), findsNothing);
    await tester.runAsync(() => ledger.close());
  });

  testWidgets('the reload control meets the 44dp touch target', (
    WidgetTester tester,
  ) async {
    final LocalLedger ledger = LocalLedger(NativeDatabase.memory());
    await tester.runAsync(() => ledger.initialize());
    await tester.pumpWidget(_host(ledger));
    await tester.pumpAndSettle();

    final Size refresh = tester.getSize(find.byType(IconButton));
    expect(refresh.width, greaterThanOrEqualTo(44));
    expect(refresh.height, greaterThanOrEqualTo(44));
    await tester.runAsync(() => ledger.close());
  });
  testWidgets('an empty device gets the same quiet card', (
    WidgetTester tester,
  ) async {
    // Opened without seeding, so there is no khata to show at all.
    final LocalLedger empty = LocalLedger(NativeDatabase.memory());
    await tester.runAsync(() => empty.listKhatas());

    await tester.pumpWidget(_host(empty));
    await tester.pumpAndSettle();

    final Container card = tester.widget<Container>(
      find
          .ancestor(
            of: find.text('No khatas on this device yet.'),
            matching: find.byType(Container),
          )
          .first,
    );
    final BoxDecoration box = card.decoration! as BoxDecoration;
    expect(box.borderRadius, BorderRadius.circular(20));
    expect(box.color, AppColors.surface);
    // A placeholder with no figures asks for less attention: a softer edge
    // than a card of balances, and no shadow.
    expect(box.border!.top.color, AppColors.outline.withValues(alpha: 0.6));
    expect(box.boxShadow, isNull);

    await tester.runAsync(() => empty.close());
  });
}
