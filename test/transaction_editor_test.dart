import 'dart:async';

// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khoroch_diary/core/l10n/app_strings.dart';
import 'package:khoroch_diary/core/theme/app_theme.dart';
import 'package:khoroch_diary/features/entry/add_entry_screen.dart';
import 'package:khoroch_diary/features/entry/transaction_editor_screen.dart';

const Size smallPhone = Size(320, 568);
const Size midPhone = Size(360, 640);

/// A representative entry: a custom category Add Entry would never create, an
/// amount with paise, and a timestamp with a time component to protect.
EntryFormResult sampleInitial({
  EntryFormKind kind = EntryFormKind.expense,
  int amountPaise = 123456,
  String category = 'Chai Stall',
  String description = 'Evening tea',
  DateTime? occurredAt,
}) => EntryFormResult(
  kind: kind,
  amountPaise: amountPaise,
  category: category,
  description: description,
  occurredAt: occurredAt ?? DateTime(2026, 11, 19, 20, 30),
);

/// Pushes the editor above a host screen so pops really return a result.
Future<void> pumpEditor(
  WidgetTester tester, {
  required EntryFormResult initial,
  required Future<bool> Function(EntryFormResult) onUpdate,
  required Future<bool> Function() onDelete,
  void Function(TransactionEditResult?)? onPopped,
  Size size = midPhone,
  double scale = 1.0,
  AppLanguage language = AppLanguage.en,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      key: UniqueKey(),
      theme: AppTheme.light(),
      builder: (BuildContext context, Widget? child) {
        final MediaQueryData media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(textScaler: TextScaler.linear(scale)),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => Center(
            child: TextButton(
              onPressed: () async {
                final TransactionEditResult? result =
                    await Navigator.of(context).push<TransactionEditResult>(
                      MaterialPageRoute<TransactionEditResult>(
                        builder: (BuildContext routeContext) =>
                            TransactionEditorScreen(
                              language: language,
                              initial: initial,
                              onUpdate: onUpdate,
                              onDelete: onDelete,
                            ),
                      ),
                    );
                onPopped?.call(result);
              },
              child: const Text('Open editor'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open editor'));
  await tester.pumpAndSettle();
}

/// The text currently in a field, read from its controller (not from a
/// possibly duplicated `find.text`).
String fieldText(WidgetTester tester, String key) {
  final EditableText editable = tester.widget<EditableText>(
    find.descendant(
      of: find.byKey(Key(key)),
      matching: find.byType(EditableText),
    ),
  );
  return editable.controller.text;
}

/// Scrolls a control into view and taps it only if it can receive the tap.
Future<void> tapControl(WidgetTester tester, Key key) async {
  final Finder target = find.byKey(key);
  await tester.scrollUntilVisible(
    target,
    120,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  expect(
    target.hitTestable().evaluate().isNotEmpty,
    isTrue,
    reason: '$key is offscreen or covered and cannot be tapped',
  );
  await tester.tap(target.hitTestable());
  await tester.pumpAndSettle();
}

/// The selected marker shown inside a category chip.
Finder chipCheck(String category) => find.descendant(
  of: find.byKey(Key('editor-category-$category')),
  matching: find.byIcon(Icons.check),
);

/// Whether the Expense/Income segment reports itself as selected.
bool kindSelected(WidgetTester tester, String key) {
  final Semantics semantics = tester.widget<Semantics>(find.byKey(Key(key)));
  return semantics.properties.selected ?? false;
}

void main() {
  group('prefill', () {
    testWidgets('shows the original values, empty description and all', (
      WidgetTester tester,
    ) async {
      await pumpEditor(
        tester,
        initial: sampleInitial(
          category: 'Chai Stall',
          description: '',
          amountPaise: 123456,
        ),
        onUpdate: (EntryFormResult entry) async => true,
        onDelete: () async => true,
      );

      expect(find.text('Edit Transaction'), findsOneWidget);
      expect(fieldText(tester, 'editor-amount-field'), '1234.56');
      expect(fieldText(tester, 'editor-description-field'), '');

      // A category Add Entry would never offer is kept, selected, and visible.
      expect(
        find.byKey(const Key('editor-category-Chai Stall')),
        findsOneWidget,
      );
      expect(chipCheck('Chai Stall'), findsOneWidget);
      expect(chipCheck('Food'), findsNothing);
      // ...alongside the standard ones, so it can still be changed.
      for (final String category in <String>[
        'Shopping',
        'Food',
        'Travel',
        'Bills',
        'Gifts',
      ]) {
        expect(find.byKey(Key('editor-category-$category')), findsOneWidget);
      }

      expect(kindSelected(tester, 'editor-kind-expense'), isTrue);
      expect(kindSelected(tester, 'editor-kind-income'), isFalse);

      final String dateText = const DefaultMaterialLocalizations()
          .formatMediumDate(DateTime(2026, 11, 19));
      expect(find.text(dateText), findsOneWidget);
    });

    testWidgets('prefills an income entry with its own category and paise', (
      WidgetTester tester,
    ) async {
      await pumpEditor(
        tester,
        initial: sampleInitial(
          kind: EntryFormKind.income,
          category: 'Income',
          amountPaise: 500001,
        ),
        onUpdate: (EntryFormResult entry) async => true,
        onDelete: () async => true,
      );

      expect(fieldText(tester, 'editor-amount-field'), '5000.01');
      expect(chipCheck('Income'), findsOneWidget);
      expect(kindSelected(tester, 'editor-kind-income'), isTrue);
      expect(kindSelected(tester, 'editor-kind-expense'), isFalse);
    });
  });

  group('update', () {
    testWidgets('unchanged submit preserves the exact paise and timestamp', (
      WidgetTester tester,
    ) async {
      final DateTime original = DateTime(2026, 11, 19, 20, 30, 45, 123);
      EntryFormResult? sent;
      TransactionEditResult? popped;
      await pumpEditor(
        tester,
        initial: sampleInitial(
          amountPaise: 123456,
          description: '',
          category: 'Chai Stall',
          occurredAt: original,
        ),
        onUpdate: (EntryFormResult entry) async {
          sent = entry;
          return true;
        },
        onDelete: () async => true,
        onPopped: (TransactionEditResult? result) => popped = result,
      );

      await tapControl(tester, const Key('editor-update-button'));

      expect(sent, isNotNull);
      expect(sent!.amountPaise, 123456);
      expect(sent!.category, 'Chai Stall');
      expect(sent!.description, '');
      expect(sent!.kind, EntryFormKind.expense);
      // Not just the day: the untouched time and milliseconds survive too.
      expect(sent!.occurredAt, original);
      expect(sent!.occurredAt.millisecond, 123);
      expect(popped, TransactionEditResult.updated);
      expect(find.byType(TransactionEditorScreen), findsNothing);
    });

    testWidgets('valid edits reach the callback exactly', (
      WidgetTester tester,
    ) async {
      EntryFormResult? sent;
      TransactionEditResult? popped;
      await pumpEditor(
        tester,
        initial: sampleInitial(occurredAt: DateTime(2026, 11, 19, 20, 30)),
        onUpdate: (EntryFormResult entry) async {
          sent = entry;
          return true;
        },
        onDelete: () async => true,
        onPopped: (TransactionEditResult? result) => popped = result,
      );

      await tester.enterText(
        find.byKey(const Key('editor-amount-field')),
        '999.99',
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('editor-description-field')),
        'Dinner with family',
      );
      await tester.pumpAndSettle();
      await tapControl(tester, const Key('editor-kind-income'));
      await tapControl(tester, const Key('editor-category-Food'));

      await tapControl(tester, const Key('editor-update-button'));

      expect(sent, isNotNull);
      expect(sent!.kind, EntryFormKind.income);
      expect(sent!.amountPaise, 99999);
      expect(sent!.category, 'Food');
      expect(sent!.description, 'Dinner with family');
      // The date was never touched, so the original instant is kept.
      expect(sent!.occurredAt, DateTime(2026, 11, 19, 20, 30));
      expect(popped, TransactionEditResult.updated);
    });

    testWidgets('a picked date becomes that local day at midnight', (
      WidgetTester tester,
    ) async {
      EntryFormResult? sent;
      await pumpEditor(
        tester,
        initial: sampleInitial(occurredAt: DateTime(2026, 11, 19, 20, 30, 45)),
        onUpdate: (EntryFormResult entry) async {
          sent = entry;
          return true;
        },
        onDelete: () async => true,
      );

      await tapControl(tester, const Key('editor-date-field'));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);

      await tester.tap(
        find
            .descendant(
              of: find.byType(DatePickerDialog),
              matching: find.text('15'),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      final String expected = const DefaultMaterialLocalizations()
          .formatMediumDate(DateTime(2026, 11, 15));
      expect(find.text(expected), findsOneWidget);

      await tapControl(tester, const Key('editor-update-button'));

      expect(sent, isNotNull);
      expect(sent!.occurredAt, DateTime(2026, 11, 15));
      expect(sent!.occurredAt.hour, 0);
      expect(sent!.occurredAt.minute, 0);
    });
  });

  group('validation', () {
    testWidgets('bad amounts are rejected, never truncated', (
      WidgetTester tester,
    ) async {
      int calls = 0;
      await pumpEditor(
        tester,
        initial: sampleInitial(),
        onUpdate: (EntryFormResult entry) async {
          calls++;
          return true;
        },
        onDelete: () async => true,
      );

      for (final String bad in <String>[
        'abc',
        '',
        '0',
        '0.00',
        '12.345',
        '1234567890',
        '1,200',
      ]) {
        await tester.enterText(
          find.byKey(const Key('editor-amount-field')),
          bad,
        );
        await tester.pumpAndSettle();
        await tapControl(tester, const Key('editor-update-button'));
        expect(calls, 0, reason: '"$bad" must not reach the callback');
        expect(
          find.byType(TransactionEditorScreen),
          findsOneWidget,
          reason: 'the editor must stay open for "$bad"',
        );
      }

      // Zero gets its own, specific message rather than "invalid format".
      await tester.enterText(find.byKey(const Key('editor-amount-field')), '0');
      await tester.pumpAndSettle();
      await tapControl(tester, const Key('editor-update-button'));
      expect(find.text('Amount must be more than zero'), findsOneWidget);
    });

    testWidgets('description longer than 120 characters is rejected', (
      WidgetTester tester,
    ) async {
      int calls = 0;
      await pumpEditor(
        tester,
        initial: sampleInitial(description: ''),
        onUpdate: (EntryFormResult entry) async {
          calls++;
          return true;
        },
        onDelete: () async => true,
      );

      // 121 rupee signs: 121 grapheme clusters, not 121 code units.
      await tester.enterText(
        find.byKey(const Key('editor-description-field')),
        '₹' * 121,
      );
      await tester.pumpAndSettle();
      await tapControl(tester, const Key('editor-update-button'));
      expect(calls, 0);
      expect(
        find.text('Description must be 120 characters or fewer'),
        findsOneWidget,
      );
      expect(find.byType(TransactionEditorScreen), findsOneWidget);

      // Exactly 120 is fine, so the limit is not off by one.
      await tester.enterText(
        find.byKey(const Key('editor-description-field')),
        '₹' * 120,
      );
      await tester.pumpAndSettle();
      await tapControl(tester, const Key('editor-update-button'));
      expect(calls, 1);
    });

    testWidgets('a blank category blocks the update until one is picked', (
      WidgetTester tester,
    ) async {
      int calls = 0;
      await pumpEditor(
        tester,
        initial: sampleInitial(category: ''),
        onUpdate: (EntryFormResult entry) async {
          calls++;
          return true;
        },
        onDelete: () async => true,
      );

      expect(chipCheck('Food'), findsNothing);
      await tapControl(tester, const Key('editor-update-button'));
      expect(calls, 0);
      expect(find.text('Pick a category'), findsOneWidget);
      expect(find.byType(TransactionEditorScreen), findsOneWidget);

      await tapControl(tester, const Key('editor-category-Food'));
      expect(find.text('Pick a category'), findsNothing);
      await tapControl(tester, const Key('editor-update-button'));
      expect(calls, 1);
    });
  });

  group('delete', () {
    testWidgets('cancelling the confirmation calls nothing and stays put', (
      WidgetTester tester,
    ) async {
      int deletes = 0;
      TransactionEditResult? popped;
      await pumpEditor(
        tester,
        initial: sampleInitial(),
        onUpdate: (EntryFormResult entry) async => true,
        onDelete: () async {
          deletes++;
          return true;
        },
        onPopped: (TransactionEditResult? result) => popped = result,
      );

      await tapControl(tester, const Key('editor-delete-button'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('delete-confirm-dialog')), findsOneWidget);

      await tester.tap(find.byKey(const Key('cancel-delete-button')));
      await tester.pumpAndSettle();

      expect(deletes, 0);
      expect(popped, isNull);
      expect(find.byType(TransactionEditorScreen), findsOneWidget);
      expect(find.byKey(const Key('delete-confirm-dialog')), findsNothing);
    });

    testWidgets('confirming delete calls onDelete and pops with deleted', (
      WidgetTester tester,
    ) async {
      int deletes = 0;
      TransactionEditResult? popped;
      await pumpEditor(
        tester,
        initial: sampleInitial(),
        onUpdate: (EntryFormResult entry) async => true,
        onDelete: () async {
          deletes++;
          return true;
        },
        onPopped: (TransactionEditResult? result) => popped = result,
      );

      await tapControl(tester, const Key('editor-delete-button'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-delete-button')));
      await tester.pumpAndSettle();

      expect(deletes, 1);
      expect(popped, TransactionEditResult.deleted);
      expect(find.byType(TransactionEditorScreen), findsNothing);
    });

    testWidgets('a refused or failed delete keeps the entry and says so', (
      WidgetTester tester,
    ) async {
      for (final bool shouldThrow in <bool>[false, true]) {
        int deletes = 0;
        TransactionEditResult? popped;
        await pumpEditor(
          tester,
          initial: sampleInitial(),
          onUpdate: (EntryFormResult entry) async => true,
          onDelete: () async {
            deletes++;
            if (shouldThrow) {
              throw StateError('delete failed');
            }
            return false;
          },
          onPopped: (TransactionEditResult? result) => popped = result,
        );

        await tapControl(tester, const Key('editor-delete-button'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('confirm-delete-button')));
        await tester.pumpAndSettle();

        expect(deletes, 1);
        expect(popped, isNull);
        expect(find.byType(TransactionEditorScreen), findsOneWidget);
        expect(find.byKey(const Key('editor-error')), findsOneWidget);
        expect(
          find.textContaining('Could not delete this transaction'),
          findsOneWidget,
        );
        // The buttons are usable again, so the user can retry.
        final OutlinedButton delete = tester.widget<OutlinedButton>(
          find.byKey(const Key('editor-delete-button')),
        );
        expect(delete.onPressed, isNotNull);
      }
    });
  });

  group('failure handling and pending state', () {
    testWidgets('a refused or failed update stays put with an honest error', (
      WidgetTester tester,
    ) async {
      for (final bool shouldThrow in <bool>[false, true]) {
        int calls = 0;
        TransactionEditResult? popped;
        await pumpEditor(
          tester,
          initial: sampleInitial(),
          onUpdate: (EntryFormResult entry) async {
            calls++;
            if (shouldThrow) {
              throw StateError('update failed');
            }
            return false;
          },
          onDelete: () async => true,
          onPopped: (TransactionEditResult? result) => popped = result,
        );

        await tapControl(tester, const Key('editor-update-button'));

        expect(calls, 1);
        expect(popped, isNull);
        expect(find.byType(TransactionEditorScreen), findsOneWidget);
        expect(find.byKey(const Key('editor-error')), findsOneWidget);
        expect(
          find.textContaining('Could not save your changes'),
          findsOneWidget,
        );
        final FilledButton update = tester.widget<FilledButton>(
          find.byKey(const Key('editor-update-button')),
        );
        expect(update.onPressed, isNotNull);
        // Nothing was submitted twice by the failure path.
        expect(calls, 1);
      }
    });

    testWidgets('a pending update disables both actions and ignores repeats', (
      WidgetTester tester,
    ) async {
      final Completer<bool> pending = Completer<bool>();
      int updates = 0;
      int deletes = 0;
      TransactionEditResult? popped;
      await pumpEditor(
        tester,
        initial: sampleInitial(),
        onUpdate: (EntryFormResult entry) {
          updates++;
          return pending.future;
        },
        onDelete: () async {
          deletes++;
          return true;
        },
        onPopped: (TransactionEditResult? result) => popped = result,
      );

      await tapControl(tester, const Key('editor-update-button'));
      expect(updates, 1);
      expect(find.byKey(const Key('editor-busy')), findsOneWidget);

      final FilledButton update = tester.widget<FilledButton>(
        find.byKey(const Key('editor-update-button')),
      );
      final OutlinedButton delete = tester.widget<OutlinedButton>(
        find.byKey(const Key('editor-delete-button')),
      );
      expect(update.onPressed, isNull);
      expect(delete.onPressed, isNull);

      // Repeat taps while the first call is still in flight do nothing.
      await tester.tap(
        find.byKey(const Key('editor-update-button')),
        warnIfMissed: false,
      );
      await tester.tap(
        find.byKey(const Key('editor-delete-button')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(updates, 1);
      expect(deletes, 0);
      expect(find.byKey(const Key('delete-confirm-dialog')), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(TransactionEditorScreen), findsOneWidget);

      pending.complete(true);
      await tester.pumpAndSettle();
      expect(popped, TransactionEditResult.updated);
    });

    testWidgets(
      'a callback that settles after the screen is gone is harmless',
      (WidgetTester tester) async {
        final Completer<bool> pending = Completer<bool>();
        await pumpEditor(
          tester,
          initial: sampleInitial(),
          onUpdate: (EntryFormResult entry) => pending.future,
          onDelete: () async => true,
        );

        await tapControl(tester, const Key('editor-update-button'));
        // The whole app goes away before the callback answers.
        await tester.pumpWidget(const SizedBox.shrink());
        pending.complete(true);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      },
    );
  });

  group('layout and accessibility', () {
    testWidgets('controls are 44 dp+ and selection is announced', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();

      await pumpEditor(
        tester,
        initial: sampleInitial(),
        onUpdate: (EntryFormResult entry) async => true,
        onDelete: () async => true,
      );

      for (final String key in <String>[
        'editor-kind-expense',
        'editor-kind-income',
        'editor-date-field',
        'editor-category-Food',
        'editor-update-button',
        'editor-delete-button',
      ]) {
        expect(
          tester.getSize(find.byKey(Key(key))).height,
          greaterThanOrEqualTo(44),
          reason: '$key must be at least 44 dp tall',
        );
      }

      expect(find.bySemanticsLabel('Category Chai Stall'), findsWidgets);
      expect(find.bySemanticsLabel('Category Food'), findsWidgets);
      expect(find.bySemanticsLabel('Expense'), findsWidgets);
      handle.dispose();
    });

    testWidgets('fits 320 dp at 200% text scale and can still submit', (
      WidgetTester tester,
    ) async {
      TransactionEditResult? popped;
      await pumpEditor(
        tester,
        initial: sampleInitial(),
        onUpdate: (EntryFormResult entry) async => true,
        onDelete: () async => true,
        size: smallPhone,
        scale: 2.0,
        onPopped: (TransactionEditResult? result) => popped = result,
      );
      expect(tester.takeException(), isNull);

      await tapControl(tester, const Key('editor-update-button'));
      expect(tester.takeException(), isNull);
      expect(popped, TransactionEditResult.updated);
    });

    testWidgets('fits a 360 dp phone at 100%', (WidgetTester tester) async {
      await pumpEditor(
        tester,
        initial: sampleInitial(),
        onUpdate: (EntryFormResult entry) async => true,
        onDelete: () async => true,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Update transaction'), findsOneWidget);
      expect(find.text('Delete transaction'), findsOneWidget);
    });
  });

  group('live preview, empty-zero grammar and the shared grid', () {
    testWidgets('the preview names kind, amount and the balance delta', (
      WidgetTester tester,
    ) async {
      await pumpEditor(
        tester,
        initial: sampleInitial(),
        onUpdate: (EntryFormResult entry) async => true,
        onDelete: () async => true,
      );
      // The stored entry unchanged: the delta is zero, so the line is the
      // kind and the amount about to be written.
      expect(find.text('Expense ₹1,234.56'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('editor-amount-field')),
        '999.99',
      );
      await tester.pumpAndSettle();
      expect(find.text('Expense ₹999.99 → remaining +₹234.57'), findsOneWidget);

      await tapControl(tester, const Key('editor-kind-income'));
      expect(
        find.text('Income ₹999.99 → remaining +₹2,234.55'),
        findsOneWidget,
      );

      await tester.enterText(find.byKey(const Key('editor-amount-field')), '');
      await tester.pumpAndSettle();
      expect(find.text('After saving: —'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the amount field carries a rupee prefix, never a 0.00 hint', (
      WidgetTester tester,
    ) async {
      await pumpEditor(
        tester,
        initial: sampleInitial(amountPaise: 50),
        onUpdate: (EntryFormResult entry) async => true,
        onDelete: () async => true,
      );
      final TextField field = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('editor-amount-field')),
          matching: find.byType(TextField),
        ),
      );
      expect(field.controller!.text, '0.50');
      expect(field.decoration!.hintText ?? '', isEmpty);
      expect(field.decoration!.prefixText, '₹ ');
      expect(find.text('0.00'), findsNothing);
    });

    testWidgets('leading zeros are rejected like any bad amount', (
      WidgetTester tester,
    ) async {
      int calls = 0;
      await pumpEditor(
        tester,
        initial: sampleInitial(),
        onUpdate: (EntryFormResult entry) async {
          calls++;
          return true;
        },
        onDelete: () async => true,
      );
      for (final String bad in <String>['007', '00.5']) {
        await tester.enterText(
          find.byKey(const Key('editor-amount-field')),
          bad,
        );
        await tester.pumpAndSettle();
        await tapControl(tester, const Key('editor-update-button'));
        expect(calls, 0, reason: '"$bad" must not reach the callback');
      }
      expect(
        find.text('Enter an amount with up to 9 digits and 2 decimals'),
        findsOneWidget,
      );
      // A disabled update is the gate: the button only wakes for a positive
      // amount.
      final FilledButton update = tester.widget<FilledButton>(
        find.byKey(const Key('editor-update-button')),
      );
      expect(update.onPressed, isNull);
      await tester.enterText(
        find.byKey(const Key('editor-amount-field')),
        '12',
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('editor-update-button')))
            .onPressed,
        isNotNull,
      );
    });

    group('unsaved changes', () {
      const Key amountField = Key('editor-amount-field');
      const Key descriptionField = Key('editor-description-field');
      const Key discardDialog = Key('discard-confirm-dialog');
      const Key keepEditing = Key('keep-editing-button');
      const Key discardChanges = Key('discard-changes-button');

      Future<void> editField(WidgetTester tester, Key key, String value) async {
        final Finder field = find.byKey(key);
        await tester.scrollUntilVisible(
          field,
          120,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.enterText(field, value);
        await tester.pumpAndSettle();
      }

      testWidgets('an unchanged editor exits at once on either back path', (
        WidgetTester tester,
      ) async {
        final List<TransactionEditResult?> results = <TransactionEditResult?>[];
        await pumpEditor(
          tester,
          initial: sampleInitial(),
          onUpdate: (EntryFormResult entry) async => true,
          onDelete: () async => true,
          onPopped: results.add,
        );
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byKey(discardDialog), findsNothing);
        expect(find.byType(TransactionEditorScreen), findsNothing);
        expect(results, <TransactionEditResult?>[null]);

        results.clear();
        await pumpEditor(
          tester,
          initial: sampleInitial(),
          onUpdate: (EntryFormResult entry) async => true,
          onDelete: () async => true,
          onPopped: results.add,
        );
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.byKey(discardDialog), findsNothing);
        expect(find.byType(TransactionEditorScreen), findsNothing);
        expect(results, <TransactionEditResult?>[null]);
        expect(tester.takeException(), isNull);
      });

      testWidgets('system back asks; keep preserves, discard exits unwritten', (
        WidgetTester tester,
      ) async {
        int updates = 0;
        int deletes = 0;
        final List<TransactionEditResult?> results = <TransactionEditResult?>[];
        await pumpEditor(
          tester,
          initial: sampleInitial(),
          onUpdate: (EntryFormResult entry) async {
            updates++;
            return true;
          },
          onDelete: () async {
            deletes++;
            return true;
          },
          onPopped: results.add,
        );

        await editField(tester, descriptionField, 'Changed note');
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byKey(discardDialog), findsOneWidget);
        expect(find.byType(TransactionEditorScreen), findsOneWidget);
        expect(results, isEmpty);

        // Keeping the draft preserves every field and calls nothing.
        await tester.tap(find.byKey(keepEditing));
        await tester.pumpAndSettle();
        expect(find.byKey(discardDialog), findsNothing);
        expect(fieldText(tester, 'editor-description-field'), 'Changed note');
        expect(fieldText(tester, 'editor-amount-field'), '1234.56');
        expect(updates, 0);
        expect(deletes, 0);
        expect(results, isEmpty);

        // Asking again and discarding leaves without writing anything.
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byKey(discardDialog), findsOneWidget);
        await tester.tap(find.byKey(discardChanges));
        await tester.pumpAndSettle();
        expect(find.byType(TransactionEditorScreen), findsNothing);
        expect(results, <TransactionEditResult?>[null]);
        expect(updates, 0);
        expect(deletes, 0);
        expect(tester.takeException(), isNull);
      });

      testWidgets('the header back control asks before discarding too', (
        WidgetTester tester,
      ) async {
        int updates = 0;
        await pumpEditor(
          tester,
          initial: sampleInitial(),
          onUpdate: (EntryFormResult entry) async {
            updates++;
            return true;
          },
          onDelete: () async => true,
        );
        await editField(tester, amountField, '777.00');
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.byKey(discardDialog), findsOneWidget);
        // Dismissing the dialog (back while it is open) keeps the draft too.
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byKey(discardDialog), findsNothing);
        expect(find.byType(TransactionEditorScreen), findsOneWidget);
        expect(fieldText(tester, 'editor-amount-field'), '777.00');
        expect(updates, 0);
        expect(tester.takeException(), isNull);
      });

      testWidgets('reverting every edit removes the prompt', (
        WidgetTester tester,
      ) async {
        final List<TransactionEditResult?> results = <TransactionEditResult?>[];
        await pumpEditor(
          tester,
          initial: sampleInitial(),
          onUpdate: (EntryFormResult entry) async => true,
          onDelete: () async => true,
          onPopped: results.add,
        );
        await editField(tester, amountField, '999.99');
        await editField(tester, amountField, '1234.56');
        await tapControl(tester, const Key('editor-kind-income'));
        await tapControl(tester, const Key('editor-kind-expense'));
        await tapControl(tester, const Key('editor-category-Food'));
        await tapControl(tester, const Key('editor-category-Chai Stall'));
        await editField(tester, descriptionField, 'Something else');
        await editField(tester, descriptionField, 'Evening tea');

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byKey(discardDialog), findsNothing);
        expect(find.byType(TransactionEditorScreen), findsNothing);
        expect(results, <TransactionEditResult?>[null]);
        expect(tester.takeException(), isNull);
      });

      testWidgets('changing amount, kind, category or date each asks', (
        WidgetTester tester,
      ) async {
        await pumpEditor(
          tester,
          initial: sampleInitial(),
          onUpdate: (EntryFormResult entry) async => true,
          onDelete: () async => true,
        );

        Future<void> expectPrompt() async {
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(find.byKey(discardDialog), findsOneWidget);
          await tester.tap(find.byKey(keepEditing));
          await tester.pumpAndSettle();
          expect(find.byType(TransactionEditorScreen), findsOneWidget);
        }

        await editField(tester, amountField, '1.00');
        await expectPrompt();
        await editField(tester, amountField, '1234.56');

        await tapControl(tester, const Key('editor-kind-income'));
        await expectPrompt();
        await tapControl(tester, const Key('editor-kind-expense'));

        await tapControl(tester, const Key('editor-category-Food'));
        await expectPrompt();
        await tapControl(tester, const Key('editor-category-Chai Stall'));

        // Pick a different day in the date picker.
        await tapControl(tester, const Key('editor-date-field'));
        await tester.tap(
          find.descendant(
            of: find.byType(DatePickerDialog),
            matching: find.text('20'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        await expectPrompt();
        expect(tester.takeException(), isNull);
      });

      testWidgets('a failed update keeps the draft and the back guard', (
        WidgetTester tester,
      ) async {
        int updates = 0;
        await pumpEditor(
          tester,
          initial: sampleInitial(),
          onUpdate: (EntryFormResult entry) async {
            updates++;
            return false;
          },
          onDelete: () async => true,
        );
        await editField(tester, descriptionField, 'Unsaved note');
        await tapControl(tester, const Key('editor-update-button'));
        expect(updates, 1);
        expect(find.byKey(const Key('editor-error')), findsOneWidget);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byKey(discardDialog), findsOneWidget);
        await tester.tap(find.byKey(keepEditing));
        await tester.pumpAndSettle();
        expect(fieldText(tester, 'editor-description-field'), 'Unsaved note');
        expect(updates, 1);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a saved edit exits at once with no discard prompt', (
        WidgetTester tester,
      ) async {
        final List<TransactionEditResult?> results = <TransactionEditResult?>[];
        await pumpEditor(
          tester,
          initial: sampleInitial(),
          onUpdate: (EntryFormResult entry) async => true,
          onDelete: () async => true,
          onPopped: results.add,
        );
        await editField(tester, descriptionField, 'Saved note');
        await tapControl(tester, const Key('editor-update-button'));
        expect(find.byKey(discardDialog), findsNothing);
        expect(results, <TransactionEditResult?>[
          TransactionEditResult.updated,
        ]);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a pending delete still blocks back without prompting', (
        WidgetTester tester,
      ) async {
        final Completer<bool> pending = Completer<bool>();
        final List<TransactionEditResult?> results = <TransactionEditResult?>[];
        await pumpEditor(
          tester,
          initial: sampleInitial(),
          onUpdate: (EntryFormResult entry) async => true,
          onDelete: () => pending.future,
          onPopped: results.add,
        );
        await editField(tester, descriptionField, 'About to delete');
        await tapControl(tester, const Key('editor-delete-button'));
        await tester.tap(find.byKey(const Key('confirm-delete-button')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('editor-busy')), findsOneWidget);

        await tester.binding.handlePopRoute();
        await tester.pump();
        expect(find.byKey(discardDialog), findsNothing);
        expect(find.byType(TransactionEditorScreen), findsOneWidget);

        pending.complete(true);
        await tester.pumpAndSettle();
        expect(results, <TransactionEditResult?>[
          TransactionEditResult.deleted,
        ]);
        expect(tester.takeException(), isNull);
      });

      testWidgets('the discard prompt speaks Bengali in the BN editor', (
        WidgetTester tester,
      ) async {
        final AppStrings bn = AppStrings(AppLanguage.bn);
        int updates = 0;
        await pumpEditor(
          tester,
          initial: sampleInitial(),
          language: AppLanguage.bn,
          onUpdate: (EntryFormResult entry) async {
            updates++;
            return true;
          },
          onDelete: () async => true,
        );
        await editField(tester, descriptionField, 'Changed note');
        await tester.tap(find.byTooltip(bn.text(AppString.back)));
        await tester.pumpAndSettle();
        expect(find.byKey(discardDialog), findsOneWidget);
        expect(find.text('পরিবর্তন বাতিল করবেন?'), findsOneWidget);
        expect(find.text('সম্পাদনা চালিয়ে যান'), findsOneWidget);
        expect(find.text('বাতিল করুন'), findsOneWidget);
        await tester.tap(find.byKey(keepEditing));
        await tester.pumpAndSettle();
        expect(fieldText(tester, 'editor-description-field'), 'Changed note');
        expect(updates, 0);
        expect(tester.takeException(), isNull);
      });

      testWidgets('the discard prompt fits 320 dp at 200% text', (
        WidgetTester tester,
      ) async {
        await pumpEditor(
          tester,
          initial: sampleInitial(),
          onUpdate: (EntryFormResult entry) async => true,
          onDelete: () async => true,
          size: smallPhone,
          scale: 2.0,
        );
        await editField(tester, descriptionField, 'Changed note');
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byKey(discardDialog), findsOneWidget);
        for (final Key action in <Key>[keepEditing, discardChanges]) {
          expect(
            tester.getSize(find.byKey(action)).height,
            greaterThanOrEqualTo(44),
            reason: '$action must stay a 44 dp+ target',
          );
        }
        await tester.tap(find.byKey(keepEditing));
        await tester.pumpAndSettle();
        expect(find.byType(TransactionEditorScreen), findsOneWidget);
        expect(fieldText(tester, 'editor-description-field'), 'Changed note');
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('categories lay out as one wrapping grid of even cells', (
      WidgetTester tester,
    ) async {
      await pumpEditor(
        tester,
        initial: sampleInitial(),
        onUpdate: (EntryFormResult entry) async => true,
        onDelete: () async => true,
        size: smallPhone,
      );
      double widthOf(String category) =>
          tester.getSize(find.byKey(Key('editor-category-$category'))).width;
      double topOf(String category) =>
          tester.getTopLeft(find.byKey(Key('editor-category-$category'))).dy;
      // One grid: every cell in a row shares the row's top and width. The
      // original category keeps its place at the head of the set.
      expect(widthOf('Shopping'), widthOf('Food'));
      expect(topOf('Chai Stall'), topOf('Bills'));
      expect(topOf('Gifts'), greaterThan(topOf('Bills')));
      expect(tester.takeException(), isNull);
    });
  });
}
