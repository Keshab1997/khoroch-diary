import 'dart:convert';

// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khoroch_diary/app.dart';
import 'package:khoroch_diary/features/counter/note_counter_store.dart';
import 'package:khoroch_diary/features/ledger/data/ledger_backup.dart';
import 'package:khoroch_diary/features/ledger/data/local_ledger.dart';
import 'package:khoroch_diary/features/profile/backup_screen.dart';
import 'package:khoroch_diary/features/profile/profile_screen.dart';

void main() {
  testWidgets(
    'Android backup export and confirmed restore refresh the selected khata',
    (t) async {
      const channel = MethodChannel(
        'com.keshabstudios.khorochdiary/backup_files',
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final original = LocalLedger(NativeDatabase.memory());
      await original.initialize();
      // Seed the version 2 side areas: a profile with an avatar, one custom
      // category and a note count with a saved session.
      await original.customStatement('''
CREATE TABLE IF NOT EXISTS local_profile (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  name TEXT NOT NULL,
  avatar BLOB
)
''');
      await original.customStatement(
        'INSERT INTO local_profile (id, name, avatar) VALUES (1, ?, ?)',
        <Object?>[
          'Integration Profile',
          Uint8List.fromList(<int>[137, 80, 78, 71, 13, 10, 26, 10]),
        ],
      );
      await original.customStatement('''
CREATE TABLE IF NOT EXISTS custom_categories (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  icon_index INTEGER NOT NULL,
  color_index INTEGER NOT NULL,
  archived INTEGER NOT NULL DEFAULT 0
)
''');
      await original.customStatement(
        'INSERT INTO custom_categories '
        '(id, name, icon_index, color_index, archived) VALUES (?, ?, ?, ?, ?)',
        <Object?>['custom:integration', 'Integration Category', 1, 2, 0],
      );
      final NoteCounterStore store = NoteCounterStore(original);
      final snapshot = NoteCounterSnapshot(
        quantities: <int, int>{50000: 7},
        selectedDenominationPaise: 50000,
        showTwoThousand: false,
      );
      await store.save('personal', snapshot);
      await store.saveSession('personal', snapshot);
      final json = await LedgerBackup(original).exportJson();
      expect(json, contains('"version": 2'));
      expect(json, contains('"profile"'));
      expect(json, contains('Integration Profile'));
      expect(json, contains('Integration Category'));
      expect(json, contains('"noteCounter"'));
      await original.close();
      final ledger = LocalLedger(NativeDatabase.memory());
      await ledger.initialize();
      final old = await ledger.createKhata(
        name: 'Old Shop',
        openingBalancePaise: 5000,
      );
      await ledger.setActiveKhataId(old.id);
      int saves = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'pick') return Uint8List.fromList(utf8.encode(json));
        if (call.method == 'save') {
          saves++;
          final bytes = (call.arguments as Map)['bytes'] as Uint8List;
          expect(utf8.decode(bytes), contains('Old Shop'));
          return true;
        }
        throw PlatformException(code: 'unknown');
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await t.pumpWidget(KhorochDiaryApp(ledger: ledger));
      await t.pumpAndSettle();
      expect(find.text('Old Shop'), findsOneWidget);
      await t.tap(find.text('Profile').last);
      await t.pumpAndSettle();
      // Scroll the Profile list until the backup row is really on screen. A
      // fixed drag is not enough on the 800x600 test surface: the row lands
      // under the NavigationBar, the tap is swallowed by the shell and the
      // "Export Backup" lookups below then fail on a screen that never opened.
      await t.scrollUntilVisible(
        find.byKey(const Key('profile-backup-row')),
        120,
        scrollable: find.descendant(
          of: find.byType(ProfileScreen),
          matching: find.byType(Scrollable),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('profile-backup-row')));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('Export Backup'),
        120,
        scrollable: find.descendant(
          of: find.byType(BackupScreen),
          matching: find.byType(Scrollable),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Export Backup'));
      await t.pumpAndSettle();
      expect(saves, 1);
      expect(find.text('Export saved successfully.'), findsOneWidget);
      // The backup list is lazy and grew past the default viewport; scroll
      // until the targets are built/visible instead of tapping blind.
      await t.scrollUntilVisible(
        find.text('Pick Backup to Restore'),
        120,
        scrollable: find.descendant(
          of: find.byType(BackupScreen),
          matching: find.byType(Scrollable),
        ),
      );
      await t.tap(find.text('Pick Backup to Restore'));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('Confirm Restore (Replace ALL Data)'),
        120,
        scrollable: find.descendant(
          of: find.byType(BackupScreen),
          matching: find.byType(Scrollable),
        ),
      );
      await t.tap(find.text('Confirm Restore (Replace ALL Data)'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.text('Confirm Restore'));
      await t.pumpAndSettle();
      await t.tap(find.text('Home').last);
      await t.pumpAndSettle();
      expect(find.text('Personal Khata'), findsOneWidget);
      expect(find.text('Old Shop'), findsNothing);
      expect(await ledger.readActiveKhataId(), 'personal');
      // The version 2 restore carried the side areas into the app ledger.
      final profiles = await ledger
          .customSelect('SELECT name FROM local_profile')
          .get();
      expect(profiles.single.read<String>('name'), 'Integration Profile');
      final categories = await ledger
          .customSelect('SELECT id FROM custom_categories')
          .get();
      expect(categories.single.read<String>('id'), 'custom:integration');
      final sessions = await ledger
          .customSelect('SELECT id FROM note_counter_saved_sessions')
          .get();
      expect(sessions.length, 1);
    },
  );
}
