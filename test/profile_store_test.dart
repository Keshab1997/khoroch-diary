import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khoroch_diary/features/ledger/data/local_ledger.dart';
import 'package:khoroch_diary/features/profile/profile_store.dart';

Uint8List testPhoto() => base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGMQmOkO'
  'AAGtAPHeFsm4AAAAAElFTkSuQmCC',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('persists a Unicode name and immutable photo across reopen', () async {
    final dir = await Directory.systemTemp.createTemp('offline_profile_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/local.sqlite');
    final ledger = LocalLedger(NativeDatabase(file));
    final store = ProfileStore(ledger);
    try {
      expect((await store.load()).name, isEmpty);
      final bytes = testPhoto();
      final profile = LocalProfile(name: '  খাতা 🌱  ', avatarBytes: bytes);
      bytes[0] = 0;
      expect(() => profile.avatarBytes![0] = 0, throwsUnsupportedError);
      await store.save(profile);
    } finally {
      await ledger.close();
    }
    final reopened = LocalLedger(NativeDatabase(file));
    addTearDown(reopened.close);
    final persisted = ProfileStore(reopened);
    final profile = await persisted.load();
    expect(profile.name, 'খাতা 🌱');
    expect(profile.avatarBytes, testPhoto());
    await persisted.save(LocalProfile(name: '   '));
    final cleared = await persisted.load();
    expect(cleared.name, isEmpty);
    expect(cleared.avatarBytes, isNull);
  });

  test('invalid writes leave both previous fields intact', () async {
    final ledger = LocalLedger(NativeDatabase.memory());
    addTearDown(ledger.close);
    final store = ProfileStore(ledger);
    final name = List.filled(60, '🌱').join();
    final photo = testPhoto();
    await store.save(LocalProfile(name: name, avatarBytes: photo));
    final oversized = Uint8List(ProfileStore.maxAvatarBytes + 1)
      ..setAll(0, photo);
    for (final invalid in <LocalProfile>[
      LocalProfile(name: '$name🌱'),
      LocalProfile(name: 'empty', avatarBytes: Uint8List(0)),
      LocalProfile(name: 'wrong format', avatarBytes: Uint8List(20)),
      LocalProfile(name: 'oversized', avatarBytes: oversized),
    ]) {
      await expectLater(store.save(invalid), throwsFormatException);
      final saved = await store.load();
      expect(saved.name, name);
      expect(saved.avatarBytes, photo);
    }
  });
}
