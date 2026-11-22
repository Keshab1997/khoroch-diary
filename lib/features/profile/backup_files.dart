import 'dart:convert';

import 'package:flutter/services.dart';

import '../ledger/data/ledger_backup.dart';

/// Android Storage Access Framework bridge. Null means user cancellation.
class BackupFiles {
  const BackupFiles();
  static const MethodChannel _channel = MethodChannel(
    'com.keshabstudios.khorochdiary/backup_files',
  );

  Future<bool> save(String json) async {
    final bytes = Uint8List.fromList(utf8.encode(json));
    if (bytes.length > kLedgerBackupMaxBytes) {
      throw const FormatException('Backup too large');
    }
    final result = await _channel.invokeMethod<bool>('save', {'bytes': bytes});
    return result ?? false;
  }

  Future<String?> pick() async {
    final bytes = await _channel.invokeMethod<Uint8List>('pick');
    if (bytes == null) return null;
    if (bytes.length > kLedgerBackupMaxBytes) {
      throw const FormatException('Backup too large');
    }
    return utf8.decode(bytes, allowMalformed: false);
  }
}
