// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khoroch_diary/core/l10n/app_strings.dart';
import 'package:khoroch_diary/core/theme/app_theme.dart';
import 'package:khoroch_diary/features/entry/add_entry_screen.dart';
import 'package:khoroch_diary/features/entry/transaction_editor_screen.dart';
import 'package:khoroch_diary/features/home/home_screen.dart';
import 'package:khoroch_diary/features/home/models.dart';

Future<void> _show(WidgetTester tester, Widget child, {double scale = 1}) =>
    tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: child,
      ),
    );

Future<void> _reveal(WidgetTester tester, Finder target) async {
  await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
  await tester.pumpAndSettle();
  expect(target.hitTestable(), findsOneWidget);
}

/// The English and Bengali empty-state instructions, spelled out rather than
/// derived: the bug was that Bengali silently fell back to the English one, so
/// a test that recomputed the expectation could not have caught it.
const String emptyInstructionEn =
    "Tap the big '+' button below to add your first expense or income.";
const String emptyInstructionBn =
    "শুরু করতে নিচের বড় '+' বাটনে চাপুন - প্রথম আয় বা খরচ যোগ করুন।";

void main() {
  testWidgets('the empty state instructs in the screen’s own language', (
    tester,
  ) async {
    const LedgerSummary empty = LedgerSummary(
      openingBalancePaise: 0,
      entries: <LedgerEntry>[],
    );
    for (final AppLanguage language in AppLanguage.values) {
      final AppStrings strings = AppStrings(language);
      await _show(tester, HomeScreen(language: language, summary: empty));

      expect(
        find.text(strings.text(AppString.homeEmpty)),
        findsOneWidget,
        reason: 'the empty headline is localized for $language',
      );
      final bool bengali = language == AppLanguage.bn;
      expect(
        find.text(bengali ? emptyInstructionBn : emptyInstructionEn),
        findsOneWidget,
        reason: 'the instruction must be written in $language',
      );
      expect(
        find.text(bengali ? emptyInstructionEn : emptyInstructionBn),
        findsNothing,
        reason: 'the other language must not leak through',
      );
      // A Bengali screen may not borrow the English instruction, which was the
      // actual defect: `_EmptyTransactions` compared `.name` with a display
      // name that can never match.
      expect(find.byKey(const Key('home-empty-instruction')), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('the settings control is named in the screen’s language', (
    tester,
  ) async {
    for (final AppLanguage language in AppLanguage.values) {
      final AppStrings strings = AppStrings(language);
      int taps = 0;
      await _show(
        tester,
        HomeScreen(
          language: language,
          khataName: 'Personal Khata',
          onSwitchKhata: () {},
          onSettings: () => taps++,
        ),
      );

      // The tooltip is the button's only accessible name, so a hard-coded
      // English string left Bengali users with an English control.
      final Finder tooltip = find.byTooltip(strings.text(AppString.settings));
      expect(
        tooltip,
        findsOneWidget,
        reason: 'tooltip localized for $language',
      );
      if (language == AppLanguage.bn) {
        expect(find.byTooltip('Settings'), findsNothing);
      }
      await tester.tap(tooltip);
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('the empty state reads cleanly at 320dp and 200% text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    for (final AppLanguage language in AppLanguage.values) {
      final AppStrings strings = AppStrings(language);
      await _show(
        tester,
        HomeScreen(
          language: language,
          summary: const LedgerSummary(
            openingBalancePaise: 0,
            entries: <LedgerEntry>[],
          ),
        ),
        scale: 2,
      );
      await _reveal(tester, find.text(strings.text(AppString.homeEmpty)));
      // At 200% the instruction can start below the headline's viewport;
      // verify that it too is reachable by scrolling, not that both fit at once.
      final Finder instruction = find.byKey(
        const Key('home-empty-instruction'),
      );
      await _reveal(tester, instruction);
      expect(instruction.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('a Bengali stored row is announced as editable in Bengali', (
    tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    final AppStrings strings = AppStrings(AppLanguage.bn);
    await _show(
      tester,
      HomeScreen(
        language: AppLanguage.bn,
        summary: LedgerSummary(
          openingBalancePaise: 0,
          entries: <LedgerEntry>[
            LedgerEntry(
              title: 'দুপুরের খাবার',
              category: 'Food',
              at: DateTime(2026, 11, 19, 13, 15),
              amountPaise: 58000,
              id: 'entry-bn-food',
            ),
          ],
        ),
        onRecentEntry: (_) {},
      ),
    );
    await _reveal(tester, find.text('দুপুরের খাবার'));

    final String label = tester
        .getSemantics(find.byKey(const Key('home-recent-দুপুরের খাবার')))
        .label;
    // Direction and the edit hint are both localized: the row reads as one
    // Bengali sentence, not a Bengali title followed by English controls.
    expect(label, contains(strings.text(AppString.expense)));
    expect(label, contains(strings.text(AppString.tapToEdit)));
    semantics.dispose();
  });

  testWidgets('Home defaults to English; Bengali scales and keeps user copy', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();
    await _show(tester, const HomeScreen());
    expect(find.text('Remaining Balance'), findsOneWidget);
    final summary = LedgerSummary(
      openingBalancePaise: kSeedOpeningBalancePaise,
      entries: [kSeedEntries.first],
    );
    await _show(
      tester,
      HomeScreen(
        language: AppLanguage.bn,
        summary: summary,
        khataName: 'Personal Khata',
        onSwitchKhata: () {},
      ),
      scale: 2,
    );
    expect(find.text('অবশিষ্ট টাকা'), findsOneWidget);
    expect(find.text('Personal Khata'), findsOneWidget);
    await _reveal(tester, find.text('Grocery Shopping'));
    // The translated category is still announced - now inside the row's own
    // label, because the avatar that used to carry it is decorative.
    expect(
      tester
          .getSemantics(find.byKey(const Key('home-recent-Grocery Shopping')))
          .label,
      contains('কেনাকাটা'),
    );
    expect(find.bySemanticsLabel(RegExp('বিভাগ: কেনাকাটা')), findsNothing);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('Bengali Add Entry validates and returns the English payload', (
    tester,
  ) async {
    final results = <EntryFormResult>[];
    const amount = Key('amount-field');
    const description = Key('description-field');
    const note = '  দুপুরের খাবার  ';
    final semantics = tester.ensureSemantics();
    for (final language in AppLanguage.values) {
      final strings = AppStrings(language);
      await _show(
        tester,
        AddEntryScreen(
          key: ValueKey(language),
          language: language,
          openingBalancePaise: 100000,
          onSave: results.add,
        ),
      );
      expect(find.text(strings.text(AppString.addEntry)), findsOneWidget);
      final save = find.byTooltip(strings.text(AppString.save));
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.text(strings.text(AppString.validAmount)), findsOneWidget);
      expect(find.text(strings.text(AppString.pickCategory)), findsOneWidget);
      await _reveal(tester, find.byKey(amount));
      await tester.enterText(
        find.byKey(amount),
        language == AppLanguage.bn ? '৫৮০.২৫' : '580.25',
      );
      await tester.pump();
      final food = find.text(strings.text(AppString.food));
      await _reveal(tester, food);
      expect(
        find.bySemanticsLabel(strings.text(AppString.food)),
        findsOneWidget,
      );
      await tester.tap(food);
      await tester.pumpAndSettle();
      await _reveal(tester, find.byKey(description));
      await tester.enterText(find.byKey(description), note);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(results.last.category, 'Food');
      expect(results.last.kind, EntryFormKind.expense);
      expect(results.last.amountPaise, 58025);
      expect(results.last.description, note);
    }
    expect(results, hasLength(2));
    semantics.dispose();
  });

  testWidgets('Bengali editor cancels delete and keeps canonical edit data', (
    tester,
  ) async {
    final when = DateTime(2025, 2, 3, 20, 45);
    EntryFormResult? updated;
    var deletes = 0;
    await _show(
      tester,
      TransactionEditorScreen(
        language: AppLanguage.bn,
        initial: EntryFormResult(
          kind: EntryFormKind.expense,
          amountPaise: 58025,
          category: 'Shopping',
          occurredAt: when,
          description: '  Tea  ',
        ),
        onUpdate: (result) async {
          updated = result;
          return false;
        },
        onDelete: () async {
          deletes++;
          return true;
        },
      ),
    );
    expect(find.text('লেনদেন সম্পাদনা করুন'), findsOneWidget);
    final delete = find.byKey(const Key('editor-delete-button'));
    await _reveal(tester, delete);
    await tester.tap(delete);
    await tester.pumpAndSettle();
    expect(find.text('এই লেনদেনটি মুছে ফেলবেন?'), findsOneWidget);
    await tester.tap(find.text('বাতিল করুন'));
    await tester.pumpAndSettle();
    expect(deletes, 0);
    final food = find.byKey(const Key('editor-category-Food'));
    await _reveal(tester, food);
    await tester.tap(food);
    await tester.pumpAndSettle();
    final update = find.byKey(const Key('editor-update-button'));
    await _reveal(tester, update);
    await tester.tap(update);
    await tester.pumpAndSettle();
    expect(updated?.category, 'Food');
    expect(updated?.occurredAt, when);
    expect(updated?.amountPaise, 58025);
    expect(updated?.description, '  Tea  ');
    expect(
      find.text('পরিবর্তন সংরক্ষণ করা যায়নি। আবার চেষ্টা করতে পারেন।'),
      findsOneWidget,
    );
  });

  testWidgets('Bengali entry forms lay out at 320dp and 200% text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final screens = <Widget>[
      AddEntryScreen(
        language: AppLanguage.bn,
        openingBalancePaise: 100000,
        onSave: (_) {},
      ),
      TransactionEditorScreen(
        language: AppLanguage.bn,
        initial: EntryFormResult(
          kind: EntryFormKind.expense,
          amountPaise: 58025,
          category: 'Food',
          description: 'দুপুরের খাবার',
          occurredAt: DateTime(2025, 2, 3),
        ),
        onUpdate: (_) async => false,
        onDelete: () async => false,
      ),
    ];
    final actions = <Finder>[
      find.text('লেনদেন সংরক্ষণ করুন'),
      find.byKey(const Key('editor-update-button')),
    ];
    for (var index = 0; index < screens.length; index++) {
      await _show(tester, screens[index], scale: 2);
      await _reveal(tester, actions[index]);
      expect(tester.takeException(), isNull);
    }
  });
}
