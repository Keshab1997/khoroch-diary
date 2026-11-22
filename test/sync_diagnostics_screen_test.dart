// Widget tests for the Diagnostics screen (S: sync_metadata viewer) and the
// quiet row on the Cloud Backup screen that opens it. Together they prove a
// recorded failure — including the `CloudSync.start` startup failure that
// main.dart now persists — is actually readable in the UI instead of dying
// in the dark.

// Flutter 3.50 deprecates this import; migrate with the app's dependency update.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khoroch_diary/core/l10n/app_strings.dart' show AppLanguage;
import 'package:khoroch_diary/core/theme/app_theme.dart';
import 'package:khoroch_diary/features/ledger/data/local_ledger.dart';
import 'package:khoroch_diary/features/sync/cloud_backup_screen.dart';
import 'package:khoroch_diary/features/sync/sync_diagnostics_screen.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget screen, {
  Size size = const Size(400, 840),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: screen));
  // Let the readSyncMetadata future complete.
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pumpAndSettle();
}

Future<LocalLedger> _openLedger(WidgetTester tester) async {
  late LocalLedger ledger;
  await tester.runAsync(() async {
    ledger = LocalLedger(NativeDatabase.memory());
    await ledger.initialize();
  });
  addTearDown(() => ledger.close());
  return ledger;
}

void main() {
  testWidgets('shows the recorded last_error prominently', (
    WidgetTester tester,
  ) async {
    final LocalLedger ledger = await _openLedger(tester);
    await tester.runAsync(
      () => ledger.writeSyncMetadata(
        lastError: 'Cloud sync failed to start: bad config',
        lastSyncedAt: DateTime.utc(2026, 11, 20, 6, 30),
        lastSyncedAccountId: 'user-1',
      ),
    );

    await _pump(tester, SyncDiagnosticsScreen(ledger: ledger));

    expect(find.byKey(const Key('sync-diagnostics-screen')), findsOneWidget);
    expect(find.text('Cloud sync failed to start: bad config'), findsOneWidget);
    expect(find.textContaining('2026-11-20T06:30:00'), findsOneWidget);
    expect(find.text('user-1'), findsOneWidget);
  });

  testWidgets('shows a quiet all-clear when nothing was recorded', (
    WidgetTester tester,
  ) async {
    final LocalLedger ledger = await _openLedger(tester);

    await _pump(tester, SyncDiagnosticsScreen(ledger: ledger));

    expect(find.text('No sync errors recorded on this phone.'), findsOneWidget);
    expect(find.text('Never'), findsOneWidget);
  });

  testWidgets('renders in Bengali', (WidgetTester tester) async {
    final LocalLedger ledger = await _openLedger(tester);

    await _pump(
      tester,
      SyncDiagnosticsScreen(ledger: ledger, language: AppLanguage.bn),
    );

    expect(find.text('ডায়াগনস্টিকস'), findsOneWidget);
    expect(
      find.text('এই ফোনে কোনো সিঙ্ক ত্রুটি রেকর্ড হয়নি।'),
      findsOneWidget,
    );
  });

  testWidgets(
    'Cloud Backup screen opens Diagnostics even when cloud sync never started',
    (WidgetTester tester) async {
      final LocalLedger ledger = await _openLedger(tester);
      await tester.runAsync(
        () => ledger.writeSyncMetadata(lastError: 'startup boom'),
      );

      // cloudSync: null is exactly the state after a CloudSync.start failure.
      await _pump(tester, CloudBackupScreen(cloudSync: null, ledger: ledger));

      final Finder row = find.byKey(const Key('cloud-backup-diagnostics-row'));
      await tester.scrollUntilVisible(row, 120);
      await tester.tap(row);
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sync-diagnostics-screen')), findsOneWidget);
      expect(find.text('startup boom'), findsOneWidget);
    },
  );

  testWidgets('Cloud Backup screen hides the row without a ledger', (
    WidgetTester tester,
  ) async {
    await _pump(tester, const CloudBackupScreen(cloudSync: null));

    expect(find.byKey(const Key('cloud-backup-diagnostics-row')), findsNothing);
  });
}
