import 'package:drift/native.dart';
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:khoroch_diary/app.dart';
import 'package:khoroch_diary/features/entry/add_entry_screen.dart';
import 'package:khoroch_diary/features/entry/category_store.dart';
import 'package:khoroch_diary/features/entry/transaction_editor_screen.dart';
import 'package:khoroch_diary/features/home/home_screen.dart';
import 'package:khoroch_diary/features/home/models.dart';
import 'package:khoroch_diary/features/ledger/data/local_ledger.dart';
import 'package:khoroch_diary/features/sync/cloud_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_cloud_backend.dart';

// Give each in-memory database migration its own asset Future rather than
// reusing one from a previous widget test's fake-async zone.
const String _schemaAsset = 'lib/features/ledger/data/schema.sql';

/// Records the shell's successful-write notifications without scheduling a
/// cloud operation. The actual sync engine is covered by cloud_sync_test.dart.
class _RecordingCloudSync extends CloudSync {
  _RecordingCloudSync(LocalLedger ledger, FakeCloudBackend backend)
    : super(ledger: ledger, backend: backend, observeAppLifecycle: false);

  int notifications = 0;

  @override
  void notifyLocalChange() => notifications++;
}

class _RejectingLedger extends LocalLedger {
  _RejectingLedger() : super(NativeDatabase.memory());

  @override
  Future<bool> updateEntry({
    required String khataId,
    required String entryId,
    required EntryFormResult entry,
  }) async => false;

  @override
  Future<bool> softDeleteEntry({
    required String khataId,
    required String entryId,
  }) async => false;
}

/// Yield to real database I/O as well as advancing the widget clock. A fixed
/// number of pumps is not evidence that a read or write has finished.
Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  final DateTime deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  fail('Timed out waiting for $finder');
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  if (finder.hitTestable().evaluate().isEmpty) {
    // A previous snackbar can temporarily cover a control.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder.hitTestable());
  await tester.pump();
}

List<ScrollableState> _ancestorScrollables(WidgetTester tester, Finder finder) {
  return tester
      .stateList<ScrollableState>(
        find.ancestor(of: finder, matching: find.byType(Scrollable)),
      )
      .toList();
}

/// A focused field may schedule a scroll a frame after it gains focus. Wait
/// for stable ancestor positions before moving to the desired control. The
/// bounded loop also yields to real database I/O between frames.
Future<void> _waitForScrollIdle(WidgetTester tester, Finder finder) async {
  String? previous;
  int stableFrames = 0;
  for (int frame = 0; frame < 50; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
    final List<ScrollableState> scrollables = _ancestorScrollables(
      tester,
      finder,
    );
    final String current = scrollables
        .map((state) => state.position.pixels.toStringAsFixed(1))
        .join(',');
    final bool idle = scrollables.every(
      (state) => !state.position.isScrollingNotifier.value,
    );
    stableFrames = idle && current == previous ? stableFrames + 1 : 0;
    previous = current;
    if (stableFrames >= 4) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  fail('Timed out waiting for scrolling to settle for $finder');
}

Future<void> _tapWhenStable(WidgetTester tester, Finder finder) async {
  expect(finder, findsOneWidget);
  await _waitForScrollIdle(tester, finder);
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await _waitFor(tester, finder.hitTestable());
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder.hitTestable());
  await tester.pump();
}

void main() {
  testWidgets('Home edit, cancel, delete and undo update the correct khata', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    rootBundle.evict(_schemaAsset);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final LocalLedger ledger = LocalLedger(NativeDatabase.memory());
    final FakeCloudBackend backend = FakeCloudBackend();

    late LocalKhata business;
    late CustomCategory category;
    late LedgerEntry original;
    await tester.runAsync(() async {
      await ledger.initialize().timeout(const Duration(seconds: 10));
      final CategoryStore seed = CategoryStore(ledger);
      category = await seed.add('Tea');
      seed.dispose();
      business = await ledger.createKhata(
        name: 'Business',
        openingBalancePaise: 10000,
      );
      await ledger.addEntry(
        EntryFormResult(
          kind: EntryFormKind.expense,
          amountPaise: 2000,
          category: category.id,
          description: 'Business tea',
          occurredAt: DateTime(2026, 1, 2, 18, 30),
        ),
        khataId: business.id,
      );
      await ledger.addEntry(
        EntryFormResult(
          kind: EntryFormKind.expense,
          amountPaise: 700,
          category: 'Travel',
          description: 'Personal fare',
          occurredAt: DateTime(2026, 1, 1),
        ),
      );
      original = (await ledger.readSummary(khataId: business.id))
          .entries
          .single;
      await ledger.setActiveKhataId(business.id);
    });
    // CloudSync starts a status read in its constructor; seed the ledger first.
    final _RecordingCloudSync sync = _RecordingCloudSync(ledger, backend);
    addTearDown(() async {
      await sync.dispose();
      await backend.dispose();
    });

    await tester.pumpWidget(KhorochDiaryApp(ledger: ledger, cloudSync: sync));
    final Finder row = find.byKey(const Key('home-recent-Business tea'));
    await _waitFor(tester, row);
    final HomeScreen home = tester.widget(find.byType(HomeScreen));
    expect(home.onRecentEntry, isNotNull);
    await _tapVisible(tester, row);
    await _waitFor(tester, find.byType(TransactionEditorScreen));
    final TransactionEditorScreen editor = tester.widget(
      find.byType(TransactionEditorScreen),
    );
    expect(identical(editor.categoryStore, home.categoryStore), isTrue);
    expect(editor.initial.category, category.id);
    expect(editor.initial.description, 'Business tea');
    expect(editor.initial.amountPaise, 2000);
    expect(editor.initial.occurredAt.isAtSameMomentAs(original.at), isTrue);

    await tester.enterText(
      find.byKey(const Key('editor-amount-field')),
      '35.50',
    );
    await tester.pump();
    await tester.binding.handlePopRoute();
    await _waitFor(tester, find.byKey(const Key('discard-confirm-dialog')));
    await _tapVisible(tester, find.byKey(const Key('keep-editing-button')));
    await _tapVisible(tester, find.byKey(const Key('editor-update-button')));
    await _waitFor(tester, find.text('₹35.50'));
    LedgerSummary businessSummary = (await tester.runAsync(
      () => ledger.readSummary(khataId: business.id),
    ))!;
    expect(businessSummary.entries.single.id, original.id);
    expect(businessSummary.entries.single.amountPaise, 3550);
    expect(businessSummary.entries.single.category, category.id);
    expect(
      businessSummary.entries.single.at.isAtSameMomentAs(original.at),
      isTrue,
    );
    expect(businessSummary.remainingPaise, 6450);
    expect(sync.notifications, 1);

    await _tapVisible(tester, row);
    await _waitFor(tester, find.byType(TransactionEditorScreen));
    await _tapVisible(tester, find.byKey(const Key('editor-delete-button')));
    await _waitFor(tester, find.byKey(const Key('cancel-delete-button')));
    await _tapVisible(tester, find.byKey(const Key('cancel-delete-button')));
    expect(find.byType(TransactionEditorScreen), findsOneWidget);
    expect(sync.notifications, 1);
    await _tapVisible(tester, find.byKey(const Key('editor-delete-button')));
    await _waitFor(tester, find.byKey(const Key('confirm-delete-button')));
    await _tapVisible(tester, find.byKey(const Key('confirm-delete-button')));
    await _waitFor(tester, find.text('Undo'));
    expect(row, findsNothing);
    businessSummary = (await tester.runAsync(
      () => ledger.readSummary(khataId: business.id),
    ))!;
    expect(businessSummary.entries, isEmpty);
    expect(sync.notifications, 2);

    // The outgoing editor and Home can briefly both contain the snackbar
    // during the route transition; tap the single visible, hit-testable action.
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.text('Undo').hitTestable());
    await _waitFor(tester, row);
    businessSummary = (await tester.runAsync(
      () => ledger.readSummary(khataId: business.id),
    ))!;
    expect(businessSummary.entries.single.id, original.id);
    expect(businessSummary.entries.single.amountPaise, 3550);
    expect(businessSummary.entries.single.category, category.id);
    expect(businessSummary.remainingPaise, 6450);
    expect(sync.notifications, 3);
    final LedgerSummary personal = (await tester.runAsync(
      () => ledger.readSummary(khataId: 'personal'),
    ))!;
    expect(personal.entries.single.title, 'Personal fare');
    expect(personal.entries.single.amountPaise, 700);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('rejected writes stay in editor and never notify cloud', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    rootBundle.evict(_schemaAsset);
    final _RejectingLedger ledger = _RejectingLedger();
    final FakeCloudBackend backend = FakeCloudBackend();
    final bool? seeded = await tester.runAsync(() async {
      await ledger.initialize().timeout(const Duration(seconds: 10));
      await ledger
          .addEntry(
            EntryFormResult(
              kind: EntryFormKind.expense,
              amountPaise: 1200,
              category: 'Food',
              description: 'Rejected tea',
              occurredAt: DateTime(2026, 1, 2),
            ),
          )
          .timeout(const Duration(seconds: 10));
      return true;
    });
    expect(seeded, isTrue, reason: 'ledger setup must finish');
    // As in the successful-write case, do not start sync until seed completes.
    final _RecordingCloudSync sync = _RecordingCloudSync(ledger, backend);
    addTearDown(() async {
      await sync.dispose();
      await backend.dispose();
    });
    await tester.pumpWidget(KhorochDiaryApp(ledger: ledger, cloudSync: sync));
    await _waitFor(tester, find.text('Rejected tea'));
    await _tapWhenStable(tester, find.text('Rejected tea'));
    await _waitFor(tester, find.byType(TransactionEditorScreen));
    await tester.enterText(find.byKey(const Key('editor-amount-field')), '99');
    await _tapWhenStable(tester, find.byKey(const Key('editor-update-button')));
    await _waitFor(
      tester,
      find.text('Could not save your changes. You can try again.'),
    );
    expect(find.byType(TransactionEditorScreen), findsOneWidget);
    expect(sync.notifications, 0);

    await _tapWhenStable(tester, find.byKey(const Key('editor-delete-button')));
    await _waitFor(tester, find.byKey(const Key('confirm-delete-button')));
    await _tapWhenStable(
      tester,
      find.byKey(const Key('confirm-delete-button')),
    );
    await _waitFor(
      tester,
      find.text(
        'Could not delete this transaction. It has not been removed, so you can try again.',
      ),
    );
    expect(find.byType(TransactionEditorScreen), findsOneWidget);
    expect(sync.notifications, 0);
    final LedgerSummary saved = (await tester.runAsync(
      () => ledger.readSummary(),
    ))!;
    expect(saved.entries.single.amountPaise, 1200);
    expect(saved.entries.single.description, 'Rejected tea');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('undo after a khata switch restores only the original khata', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    rootBundle.evict(_schemaAsset);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final LocalLedger ledger = LocalLedger(NativeDatabase.memory());
    late LocalKhata business;
    await tester.runAsync(() async {
      await ledger.initialize().timeout(const Duration(seconds: 10));
      business = await ledger.createKhata(
        name: 'Business',
        openingBalancePaise: 0,
      );
      await ledger.addEntry(
        EntryFormResult(
          kind: EntryFormKind.expense,
          amountPaise: 1000,
          category: 'Food',
          description: 'Business tea',
          occurredAt: DateTime(2026, 1, 2),
        ),
        khataId: business.id,
      );
      await ledger.addEntry(
        EntryFormResult(
          kind: EntryFormKind.expense,
          amountPaise: 700,
          category: 'Travel',
          description: 'Personal fare',
          occurredAt: DateTime(2026, 1, 1),
        ),
      );
      await ledger.setActiveKhataId(business.id);
    });
    await tester.pumpWidget(KhorochDiaryApp(ledger: ledger));
    await _waitFor(tester, find.text('Business tea'));
    await _tapVisible(tester, find.text('Business tea'));
    await _waitFor(tester, find.byType(TransactionEditorScreen));
    await _tapVisible(tester, find.byKey(const Key('editor-delete-button')));
    await _waitFor(tester, find.byKey(const Key('confirm-delete-button')));
    await _tapVisible(tester, find.byKey(const Key('confirm-delete-button')));
    await _waitFor(tester, find.text('Undo'));
    await _tapVisible(tester, find.byKey(const Key('switch-khata')));
    await _waitFor(tester, find.byKey(const Key('khata-personal')));
    await _tapVisible(tester, find.byKey(const Key('khata-personal')));
    await _waitFor(tester, find.text('Personal fare'));
    await tester.pumpAndSettle();
    expect(find.text('Undo').hitTestable(), findsOneWidget);
    await _tapVisible(tester, find.text('Undo').hitTestable());
    await _waitFor(tester, find.text('Transaction restored'));
    final LedgerSummary personal = (await tester.runAsync(
      () => ledger.readSummary(),
    ))!;
    final LedgerSummary businessSummary = (await tester.runAsync(
      () => ledger.readSummary(khataId: business.id),
    ))!;
    expect(personal.entries.single.title, 'Personal fare');
    expect(businessSummary.entries.single.title, 'Business tea');
    expect(find.text('Personal fare'), findsOneWidget);
    expect(find.text('Business tea'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
