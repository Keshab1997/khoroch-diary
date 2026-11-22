import 'dart:async';

// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khoroch_diary/core/theme/app_colors.dart';
import 'package:khoroch_diary/features/ledger/data/local_ledger.dart';
import 'package:khoroch_diary/features/ledger/khata_manage_screen.dart';

void main() {
  const LocalKhata personal = LocalKhata(
    id: 'personal',
    name: 'Personal',
    openingBalancePaise: 0,
  );
  const LocalKhata business = LocalKhata(
    id: 'biz',
    name: 'Business',
    openingBalancePaise: 50000,
  );
  const LocalKhata archivedTrip = LocalKhata(
    id: 'trip',
    name: 'Goa Trip',
    openingBalancePaise: 10000,
  );

  Future<bool?> pumpManageScreen(
    WidgetTester tester, {
    required Future<List<LocalKhata>> Function() loadActive,
    required Future<List<LocalKhata>> Function() loadArchived,
    Future<void> Function(String id, String name)? onRename,
    Future<void> Function(String id)? onArchive,
    Future<void> Function(String id)? onUnarchive,
    Size surfaceSize = const Size(412, 892),
    double textScale = 1.0,
  }) async {
    bool? popResult;
    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const Key('open-manage'),
                onPressed: () async {
                  popResult = await Navigator.of(context).push<bool>(
                    MaterialPageRoute<bool>(
                      builder: (_) => KhataManageScreen(
                        loadActive: loadActive,
                        loadArchived: loadArchived,
                        onRename: onRename ?? (_, _) async {},
                        onArchive: onArchive ?? (_) async {},
                        onUnarchive: onUnarchive ?? (_) async {},
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open-manage')));
    await tester.pumpAndSettle();
    return popResult;
  }

  testWidgets('shows active khatas, empty archive, and personal protection', (
    tester,
  ) async {
    await pumpManageScreen(
      tester,
      loadActive: () async => <LocalKhata>[personal, business],
      loadArchived: () async => <LocalKhata>[],
    );

    expect(find.text('Personal'), findsOneWidget);
    expect(find.text('Business'), findsOneWidget);
    expect(find.byKey(const Key('empty-archived-khatas')), findsOneWidget);
    expect(find.byKey(const Key('archive-khata-personal')), findsNothing);
    expect(find.byKey(const Key('archive-khata-biz')), findsOneWidget);
  });

  testWidgets('rename validates 1-40 runes, trims, and reloads', (
    tester,
  ) async {
    List<LocalKhata> active = <LocalKhata>[personal, business];
    String? renamedId;
    String? renamedTo;

    await pumpManageScreen(
      tester,
      loadActive: () async => active,
      loadArchived: () async => <LocalKhata>[],
      onRename: (String id, String name) async {
        renamedId = id;
        renamedTo = name;
        active = <LocalKhata>[
          personal,
          LocalKhata(id: id, name: name, openingBalancePaise: 50000),
        ];
      },
    );

    await tester.tap(find.byKey(const Key('rename-khata-biz')));
    await tester.pumpAndSettle();

    final EditableText input = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const Key('rename-khata-input')),
        matching: find.byType(EditableText),
      ),
    );
    expect(input.controller.text, 'Business');

    // Empty / whitespace-only rejected
    await tester.enterText(find.byKey(const Key('rename-khata-input')), '   ');
    await tester.tap(find.byKey(const Key('save-rename')));
    await tester.pumpAndSettle();
    expect(renamedId, isNull);

    // > 40 runes rejected
    await tester.enterText(
      find.byKey(const Key('rename-khata-input')),
      'a' * 41,
    );
    await tester.tap(find.byKey(const Key('save-rename')));
    await tester.pumpAndSettle();
    expect(renamedId, isNull);

    // Cancel does not mutate
    await tester.tap(find.byKey(const Key('cancel-rename')));
    await tester.pumpAndSettle();
    expect(renamedId, isNull);

    // Valid trimmed rename
    await tester.tap(find.byKey(const Key('rename-khata-biz')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('rename-khata-input')),
      '  Shop Ledger  ',
    );
    await tester.tap(find.byKey(const Key('save-rename')));
    await tester.pumpAndSettle();

    expect(renamedId, 'biz');
    expect(renamedTo, 'Shop Ledger');
    expect(find.text('Shop Ledger'), findsOneWidget);
  });

  testWidgets('archive confirmation, cancel, and unarchive reload both lists', (
    tester,
  ) async {
    List<LocalKhata> active = <LocalKhata>[personal, business];
    List<LocalKhata> archived = <LocalKhata>[archivedTrip];
    final List<String> actions = <String>[];

    await pumpManageScreen(
      tester,
      loadActive: () async => active,
      loadArchived: () async => archived,
      onArchive: (String id) async {
        actions.add('archive:$id');
        active = <LocalKhata>[personal];
        archived = <LocalKhata>[archivedTrip, business];
      },
      onUnarchive: (String id) async {
        actions.add('unarchive:$id');
        archived = <LocalKhata>[business];
        active = <LocalKhata>[personal, archivedTrip];
      },
    );

    // Cancel archive
    await tester.tap(find.byKey(const Key('archive-khata-biz')));
    await tester.pumpAndSettle();
    expect(find.textContaining('entries will be retained'), findsOneWidget);
    await tester.tap(find.byKey(const Key('cancel-archive')));
    await tester.pumpAndSettle();
    expect(actions, isEmpty);

    // Confirm archive
    await tester.tap(find.byKey(const Key('archive-khata-biz')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-archive')));
    await tester.pumpAndSettle();
    expect(actions, <String>['archive:biz']);
    expect(find.byKey(const Key('archived-khata-biz')), findsOneWidget);

    // Cancel unarchive
    await tester.tap(find.byKey(const Key('unarchive-khata-trip')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cancel-unarchive')));
    await tester.pumpAndSettle();
    expect(actions, <String>['archive:biz']);

    // Confirm unarchive
    await tester.tap(find.byKey(const Key('unarchive-khata-trip')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-unarchive')));
    await tester.pumpAndSettle();
    expect(actions, <String>['archive:biz', 'unarchive:trip']);
    expect(find.byKey(const Key('active-khata-trip')), findsOneWidget);
  });

  testWidgets('load error shows retry and recovers on retry', (tester) async {
    bool shouldFail = true;
    await pumpManageScreen(
      tester,
      loadActive: () async {
        if (shouldFail) throw Exception('db error');
        return <LocalKhata>[personal];
      },
      loadArchived: () async => <LocalKhata>[],
    );

    expect(find.byKey(const Key('manage-khatas-retry')), findsOneWidget);
    shouldFail = false;
    await tester.tap(find.byKey(const Key('manage-khatas-retry')));
    await tester.pumpAndSettle();
    expect(find.text('Personal'), findsOneWidget);
  });

  testWidgets('callback error shows banner without false success', (
    tester,
  ) async {
    await pumpManageScreen(
      tester,
      loadActive: () async => <LocalKhata>[personal, business],
      loadArchived: () async => <LocalKhata>[],
      onArchive: (_) async => throw Exception('failed'),
    );

    await tester.tap(find.byKey(const Key('archive-khata-biz')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-archive')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('manage-khatas-action-error')), findsOneWidget);
    expect(find.byKey(const Key('active-khata-biz')), findsOneWidget);
  });

  testWidgets('pending mutation blocks duplicate actions and back navigation', (
    tester,
  ) async {
    final Completer<void> completer = Completer<void>();
    int archiveCalls = 0;

    await pumpManageScreen(
      tester,
      loadActive: () async => <LocalKhata>[personal, business],
      loadArchived: () async => <LocalKhata>[],
      onArchive: (_) {
        archiveCalls++;
        return completer.future;
      },
    );

    await tester.tap(find.byKey(const Key('archive-khata-biz')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-archive')));
    await tester.pump();

    // Back button is disabled while mutating
    await tester.tap(find.byKey(const Key('manage-khatas-back')));
    await tester.pump();
    expect(find.byType(KhataManageScreen), findsOneWidget);
    expect(archiveCalls, 1);

    completer.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('pops false when unchanged and true when changed', (
    tester,
  ) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: ElevatedButton(
              key: const Key('open'),
              onPressed: () async {
                result = await Navigator.of(context).push<bool>(
                  MaterialPageRoute<bool>(
                    builder: (_) => KhataManageScreen(
                      loadActive: () async => <LocalKhata>[personal, business],
                      loadArchived: () async => <LocalKhata>[],
                      onRename: (_, _) async {},
                      onArchive: (_) async {},
                      onUnarchive: (_) async {},
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    // Unchanged -> false
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('manage-khatas-back')));
    await tester.pumpAndSettle();
    expect(result, isFalse);

    // Changed -> true
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('archive-khata-biz')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-archive')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('manage-khatas-back')));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('each section heading sits above its own cards', (tester) async {
    await pumpManageScreen(
      tester,
      loadActive: () async => <LocalKhata>[personal, business],
      loadArchived: () async => <LocalKhata>[],
    );

    final Finder activeHeading = find.text('Active Khatas');
    final Finder personalCard = find.text('Personal');
    final Finder archivedHeading = find.text('Archived Khatas');
    final Finder emptyArchive = find.byKey(const Key('empty-archived-khatas'));

    final double activeTop = tester.getTopLeft(activeHeading).dy;
    final double personalTop = tester.getTopLeft(personalCard).dy;
    final double archivedTop = tester.getTopLeft(archivedHeading).dy;
    final double emptyTop = tester.getTopLeft(emptyArchive).dy;

    expect(activeTop, lessThan(personalTop));
    expect(personalTop, lessThan(archivedTop));
    expect(archivedTop, lessThan(emptyTop));
  });

  testWidgets('renders cleanly at 320dp width and 200% text scale', (
    tester,
  ) async {
    await pumpManageScreen(
      tester,
      loadActive: () async => <LocalKhata>[personal, business],
      loadArchived: () async => <LocalKhata>[archivedTrip],
      surfaceSize: const Size(320, 640),
      textScale: 2.0,
    );

    expect(find.text('Personal'), findsOneWidget);
    expect(find.text('Business'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('card language', () {
    testWidgets('a khata row and an empty placeholder are the same card', (
      tester,
    ) async {
      await pumpManageScreen(
        tester,
        loadActive: () async => <LocalKhata>[personal, business],
        loadArchived: () async => <LocalKhata>[],
      );

      // One radius for a row and for the placeholder that stands in for an
      // empty group, so the two read as the same kind of object.
      final Card row = tester.widget<Card>(
        find.ancestor(of: find.text('Business'), matching: find.byType(Card)),
      );
      final RoundedRectangleBorder rowShape =
          row.shape! as RoundedRectangleBorder;
      expect(row.color, AppColors.surface);
      expect(rowShape.borderRadius, BorderRadius.circular(20));

      final Container empty = tester.widget<Container>(
        find
            .descendant(
              of: find.byKey(const Key('empty-archived-khatas')),
              matching: find.byType(Container),
            )
            .first,
      );
      final BoxDecoration emptyBox = empty.decoration! as BoxDecoration;
      expect(emptyBox.borderRadius, BorderRadius.circular(20));
      expect(emptyBox.color, AppColors.surface);
      // A placeholder that holds nothing asks for less attention: a softer
      // edge than a row that carries a khata.
      expect(
        emptyBox.border!.top.color,
        AppColors.outline.withValues(alpha: 0.6),
      );
      expect(rowShape.side.color, AppColors.outline.withValues(alpha: 0.85));

      // One gap between rows, matching every other ledger surface. A Card's
      // margin is its gap, so the contract is the margin itself.
      expect(row.margin, const EdgeInsets.only(bottom: 12));
    });

    testWidgets('headings, row titles and meta lines use the shared scale', (
      tester,
    ) async {
      await pumpManageScreen(
        tester,
        loadActive: () async => <LocalKhata>[personal, business],
        loadArchived: () async => <LocalKhata>[],
      );

      double sizeOf(String text) =>
          tester.widget<Text>(find.text(text)).style!.fontSize!;
      FontWeight weightOf(String text) =>
          tester.widget<Text>(find.text(text)).style!.fontWeight!;

      // Group heading: a caption, not a competing title.
      expect(sizeOf('Active Khatas'), 12);
      expect(sizeOf('Archived Khatas'), 12);
      expect(weightOf('Active Khatas'), FontWeight.w800);
      // Row title and its meta line, the same two steps a transaction row uses.
      expect(sizeOf('Personal'), 15);
      expect(sizeOf('Default'), 12);
    });
  });
}
