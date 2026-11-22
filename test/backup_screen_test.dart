// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:khoroch_diary/core/theme/app_colors.dart';
import 'package:khoroch_diary/features/profile/backup_screen.dart';

const preview = BackupPreview(
  payload: 'SECRET_PAYLOAD',
  khataCount: 2,
  transactionCount: 3,
  deletedTransactionCount: 1,
  profileIncluded: true,
  customCategoryCount: 2,
  khatasWithSavedCount: 1,
  savedSessionCount: 4,
);

const previewWithoutSideFacts = BackupPreview(
  payload: 'SECRET_PAYLOAD',
  khataCount: 2,
  transactionCount: 3,
  deletedTransactionCount: 1,
);
Future<void> open(WidgetTester t, BackupScreen screen) async {
  await t.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              final result = await Navigator.of(context)
                  .push<bool>(MaterialPageRoute(builder: (_) => screen));
              if (context.mounted && result == true) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('RESTORED')));
              }
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('Open'));
  await t.pumpAndSettle();
}

Future<void> export(WidgetTester t) async {
  // Same reason as pick(): the export card can sit below the fold.
  await t.ensureVisible(find.text('Export Backup'));
  await t.pumpAndSettle();
  await t.tap(find.text('Export Backup'));
  await t.pumpAndSettle();
}

Future<void> pick(WidgetTester t) async {
  // The screen is two step cards tall after the polish; bring the pick control
  // into view before tapping so the test never depends on the viewport height.
  await t.ensureVisible(find.text('Pick Backup to Restore'));
  await t.pumpAndSettle();
  await t.tap(find.text('Pick Backup to Restore'));
  await t.pumpAndSettle();
}

Future<void> confirm(WidgetTester t) async {
  await t.ensureVisible(find.text('Confirm Restore (Replace ALL Data)'));
  await t.tap(find.text('Confirm Restore (Replace ALL Data)'));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('export results are honest and errors do not leak', (t) async {
    var result = BackupExportResult.cancelled;
    await open(
      t,
      BackupScreen(
        onExport: () async => result,
        onPickBackup: () async => null,
        onRestore: (_) async => false,
      ),
    );
    expect(find.text('A backup file contains:'), findsOneWidget);
    expect(find.textContaining('custom categories'), findsWidgets);
    await export(t);
    expect(find.text('Export cancelled.'), findsOneWidget);
    result = BackupExportResult.saved;
    await export(t);
    expect(find.text('Export saved successfully.'), findsOneWidget);
    result = BackupExportResult.failed;
    await export(t);
    expect(find.text('Export failed.'), findsOneWidget);
  });
  testWidgets('a preview without the side facts hides the details line', (
    t,
  ) async {
    await open(
      t,
      BackupScreen(
        onExport: () async => BackupExportResult.saved,
        onPickBackup: () async => previewWithoutSideFacts,
        onRestore: (_) async => false,
      ),
    );
    await pick(t);
    expect(
      find.text('Preview: 2 khatas, 3 transactions, 1 deleted.'),
      findsOneWidget,
    );
    expect(find.textContaining('Includes:'), findsNothing);
  });
  testWidgets('pick cancel and exception with sensitive text', (t) async {
    var fail = false;
    await open(
      t,
      BackupScreen(
        onExport: () async => BackupExportResult.saved,
        onPickBackup: () async {
          if (fail) throw Exception('SECRET_PAYLOAD');
          return null;
        },
        onRestore: (_) async => false,
      ),
    );
    await pick(t);
    expect(find.text('Pick cancelled.'), findsOneWidget);
    fail = true;
    await pick(t);
    expect(find.text('Could not read or validate the backup.'), findsOneWidget);
    expect(find.textContaining('SECRET_PAYLOAD'), findsNothing);
  });
  testWidgets(
    'restore requires confirmation, cancellation writes nothing, success returns true',
    (t) async {
      var restores = 0;
      await open(
        t,
        BackupScreen(
          onExport: () async => BackupExportResult.saved,
          onPickBackup: () async => preview,
          onRestore: (p) async {
            restores++;
            expect(p.payload, 'SECRET_PAYLOAD');
            return true;
          },
        ),
      );
      await pick(t);
      expect(
        find.text('Preview: 2 khatas, 3 transactions, 1 deleted.'),
        findsOneWidget,
      );
      // The version 2 side areas are reported with the counts.
      expect(
        find.text(
          'Includes: profile, 2 custom categories, 1 khata with a saved '
          'count, 4 saved sessions.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('SECRET_PAYLOAD'), findsNothing);
      await confirm(t);
      expect(
        find.text(
          'WARNING: ALL current khatas and transactions on device will be replaced. This action is irreversible.',
        ),
        findsOneWidget,
      );
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(restores, 0);
      await confirm(t);
      await t.tap(find.text('Confirm Restore'));
      await t.pumpAndSettle();
      expect(restores, 1);
      expect(find.text('RESTORED'), findsOneWidget);
    },
  );
  for (final throws in [false, true]) {
    testWidgets('restore failure remains on screen, throws=$throws', (t) async {
      await open(
        t,
        BackupScreen(
          onExport: () async => BackupExportResult.saved,
          onPickBackup: () async => preview,
          onRestore: (_) async {
            if (throws) throw Exception('SECRET_PAYLOAD');
            return false;
          },
        ),
      );
      await pick(t);
      await confirm(t);
      await t.tap(find.text('Confirm Restore'));
      await t.pumpAndSettle();
      expect(
        find.text('Restore failed. Your current data was not replaced.'),
        findsOneWidget,
      );
      expect(find.textContaining('SECRET_PAYLOAD'), findsNothing);
      expect(find.text('RESTORED'), findsNothing);
    });
  }
  testWidgets('pending operation blocks repeat and system back', (t) async {
    final completer = Completer<BackupExportResult>();
    var calls = 0;
    await open(
      t,
      BackupScreen(
        onExport: () {
          calls++;
          return completer.future;
        },
        onPickBackup: () async => null,
        onRestore: (_) async => false,
      ),
    );
    await t.ensureVisible(find.text('Export Backup'));
    await t.pumpAndSettle();
    await t.tap(find.text('Export Backup'));
    await t.pump();
    await t.ensureVisible(find.text('Export Backup'));
    // The pending state is a static working panel: it names what is running
    // and never turns the screen into a spinner.
    await t.pump();
    expect(find.byKey(const Key('backup-working-panel')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      t
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Export Backup'),
          )
          .onPressed,
      isNull,
    );
    await t.binding.handlePopRoute();
    await t.pump();
    expect(find.byType(BackupScreen), findsOneWidget);
    expect(calls, 1);
    completer.complete(BackupExportResult.cancelled);
    await t.pumpAndSettle();
    expect(find.text('Export cancelled.'), findsOneWidget);
  });
  testWidgets('dispose while pending is safe', (t) async {
    final completer = Completer<BackupExportResult>();
    await open(
      t,
      BackupScreen(
        onExport: () => completer.future,
        onPickBackup: () async => null,
        onRestore: (_) async => false,
      ),
    );
    await t.ensureVisible(find.text('Export Backup'));
    await t.pumpAndSettle();
    await t.tap(find.text('Export Backup'));
    await t.pump();
    await t.pumpWidget(const SizedBox());
    completer.complete(BackupExportResult.saved);
    await t.pump();
    expect(t.takeException(), isNull);
  });
  testWidgets('320dp 200 percent text including confirmation', (t) async {
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: BackupScreen(
          onExport: () async => BackupExportResult.saved,
          onPickBackup: () async => preview,
          onRestore: (_) async => false,
        ),
      ),
    );
    await t.ensureVisible(find.text('Pick Backup to Restore'));
    await pick(t);
    await confirm(t);
    expect(t.takeException(), isNull);
  });

  testWidgets('the screen is two green steps with one red restore action', (
    t,
  ) async {
    await open(
      t,
      BackupScreen(
        onExport: () async => BackupExportResult.saved,
        onPickBackup: () async => preview,
        onRestore: (_) async => false,
      ),
    );

    // The step headings are real text, not a numbered decoration.
    expect(find.text('Save a copy'), findsOneWidget);
    expect(find.text('Restore from a file'), findsOneWidget);
    expect(find.byKey(const Key('backup-export-button')), findsOneWidget);
    expect(find.byKey(const Key('backup-pick-button')), findsOneWidget);
    // No restore action until a backup is picked.
    expect(find.byKey(const Key('backup-restore-button')), findsNothing);

    await pick(t);

    // The destructive action is red, full width and clearly labelled.
    final FilledButton restore = t.widget<FilledButton>(
      find.byKey(const Key('backup-restore-button')),
    );
    expect(
      restore.style?.backgroundColor?.resolve(<WidgetState>{}),
      AppColors.expenseRed,
    );
    expect(restore.onPressed, isNotNull);
    expect(t.takeException(), isNull);
  });
}
