import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khoroch_diary/features/ledger/data/ledger_backup.dart';
import 'package:khoroch_diary/features/profile/backup_files.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.keshabstudios.khorochdiary/backup_files');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  test('save passes UTF-8 and distinguishes cancellation', () async {
    bool cancelled = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'save');
      expect(
        utf8.decode((call.arguments as Map)['bytes'] as Uint8List),
        'বাংলা',
      );
      return cancelled ? null : true;
    });
    const files = BackupFiles();
    expect(await files.save('বাংলা'), isTrue);
    cancelled = true;
    expect(await files.save('বাংলা'), isFalse);
  });
  test('pick handles cancellation, strict UTF-8, and size limit', () async {
    Uint8List? input;
    messenger.setMockMethodCallHandler(channel, (_) async => input);
    const files = BackupFiles();
    expect(await files.pick(), isNull);
    input = Uint8List.fromList(utf8.encode('বাংলা'));
    expect(await files.pick(), 'বাংলা');
    input = Uint8List.fromList([0xff]);
    await expectLater(files.pick(), throwsFormatException);
    input = Uint8List(kLedgerBackupMaxBytes + 1);
    await expectLater(files.pick(), throwsFormatException);
  });
  test('oversized export is rejected before invoking native picker', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      calls++;
      return true;
    });
    await expectLater(
      const BackupFiles().save('a' * (kLedgerBackupMaxBytes + 1)),
      throwsFormatException,
    );
    expect(calls, 0);
  });
}
