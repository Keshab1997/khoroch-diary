import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khoroch_diary/features/counter/note_counter_store.dart';
import 'package:khoroch_diary/features/home/models.dart' show LedgerSummary;
import 'package:khoroch_diary/features/ledger/data/local_ledger.dart';

/// A snapshot with every denomination defaulted to zero.
NoteCounterSnapshot _snapshot({
  Map<int, int> quantities = const <int, int>{},
  int selected = kDefaultDenominationPaise,
  bool showTwoThousand = false,
}) => NoteCounterSnapshot(
  quantities: quantities,
  selectedDenominationPaise: selected,
  showTwoThousand: showTwoThousand,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late File file;

  LocalLedger open() => LocalLedger(NativeDatabase(file));

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('note_counter_store_');
    file = File('${dir.path}/ledger.sqlite');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test('ensureTables creates the counter tables on a fresh database', () async {
    final LocalLedger ledger = open();
    await ledger.initialize();
    // No store call has happened yet: the tables do not exist.
    for (final String table in <String>[
      'note_counter_quantities',
      'note_counter_state',
      'note_counter_saved_sessions',
    ]) {
      final List<QueryRow> rows = await ledger
          .customSelect(
            'SELECT name FROM sqlite_master '
            "WHERE type = 'table' AND name = ?",
            variables: <Variable<Object>>[Variable<String>(table)],
          )
          .get();
      expect(rows, isEmpty, reason: '$table should not exist yet');
    }
    final NoteCounterStore store = NoteCounterStore(ledger);
    await store.ensureTables();
    await store.ensureTables();
    for (final String table in <String>[
      'note_counter_quantities',
      'note_counter_state',
      'note_counter_saved_sessions',
    ]) {
      final List<QueryRow> rows = await ledger
          .customSelect(
            'SELECT name FROM sqlite_master '
            "WHERE type = 'table' AND name = ?",
            variables: <Variable<Object>>[Variable<String>(table)],
          )
          .get();
      expect(rows.length, 1, reason: '$table should exist now');
    }
    await ledger.close();
  });

  group('snapshot', () {
    test('fills in every denomination and stays immutable', () {
      final NoteCounterSnapshot snapshot = _snapshot(
        quantities: <int, int>{50000: 4},
      );

      expect(snapshot.quantities.length, kAllDenominationsPaise.length);
      expect(snapshot.quantityFor(50000), 4);
      expect(snapshot.quantityFor(1000), 0);
      expect(snapshot.totalPaise, 200000);
      expect(() => snapshot.quantities[50000] = 9, throwsUnsupportedError);
    });

    test(
      'rejects unknown denominations, bad quantities and bad selections',
      () {
        expect(
          () => _snapshot(quantities: <int, int>{1500: 1}),
          throwsArgumentError,
        );
        expect(
          () => _snapshot(quantities: <int, int>{50000: -1}),
          throwsArgumentError,
        );
        expect(
          () => _snapshot(quantities: <int, int>{50000: kMaxNoteQuantity + 1}),
          throwsArgumentError,
        );
        expect(() => _snapshot(selected: 1234), throwsArgumentError);
      },
    );

    test('equality compares values, not map identity', () {
      final NoteCounterSnapshot first = _snapshot(
        quantities: <int, int>{50000: 2},
      );
      final NoteCounterSnapshot second = _snapshot(
        quantities: <int, int>{50000: 2},
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(first.withQuantity(50000, 3), isNot(second));
      expect(first.hasUnreadableRows, isFalse);
    });
  });

  group('persistence', () {
    test('a saved count survives closing and reopening the database', () async {
      LocalLedger ledger = open();
      await ledger.initialize();
      await NoteCounterStore(ledger).save(
        'personal',
        _snapshot(quantities: <int, int>{50000: 4, 10000: 2}, selected: 10000),
      );
      await ledger.close();

      ledger = open();
      await ledger.initialize();
      final NoteCounterSnapshot loaded = await NoteCounterStore(ledger)
          .load('personal');

      expect(loaded.quantityFor(50000), 4);
      expect(loaded.quantityFor(10000), 2);
      expect(loaded.quantityFor(2000), 0);
      expect(loaded.selectedDenominationPaise, 10000);
      expect(loaded.showTwoThousand, isFalse);
      expect(loaded.hasUnreadableRows, isFalse);
      await ledger.close();
    });

    test('two khatas keep separate counts and selections', () async {
      final LocalLedger ledger = open();
      await ledger.initialize();
      final LocalKhata business = await ledger.createKhata(
        name: 'Business',
        openingBalancePaise: 0,
      );
      final NoteCounterStore store = NoteCounterStore(ledger);

      await store.save('personal', _snapshot(quantities: <int, int>{50000: 3}));
      await store.save(
        business.id,
        _snapshot(quantities: <int, int>{50000: 7, 20000: 1}, selected: 20000),
      );

      final NoteCounterSnapshot personal = await store.load('personal');
      expect(personal.quantityFor(50000), 3);
      expect(personal.quantityFor(200000), 0);
      expect(personal.selectedDenominationPaise, kDefaultDenominationPaise);
      expect(personal.showTwoThousand, isFalse);

      final NoteCounterSnapshot saved = await store.load(business.id);
      expect(saved.quantityFor(50000), 7);
      expect(saved.quantityFor(20000), 1);
      expect(saved.selectedDenominationPaise, 20000);
      expect(saved.showTwoThousand, isFalse);
      await ledger.close();
    });

    test(
      'a new count persists zeros instead of deleting the saved rows',
      () async {
        final LocalLedger ledger = open();
        await ledger.initialize();
        final NoteCounterStore store = NoteCounterStore(ledger);

        await store.save(
          'personal',
          _snapshot(quantities: <int, int>{50000: 3}),
        );
        await store.save('personal', NoteCounterSnapshot.empty());

        expect((await store.load('personal')).totalPaise, 0);
        final List<QueryRow> rows = await ledger
            .customSelect(
              'SELECT COUNT(*) AS saved FROM note_counter_quantities '
              'WHERE khata_id = ?',
              variables: <Variable<Object>>[Variable<String>('personal')],
            )
            .get();
        expect(rows.single.read<int>('saved'), kAllDenominationsPaise.length);
        await ledger.close();
      },
    );

    test('a saved count never touches the ledger or its balance', () async {
      final LocalLedger ledger = open();
      await ledger.initialize();
      await NoteCounterStore(
        ledger,
      ).save('personal', _snapshot(quantities: <int, int>{50000: 10, 2000: 2}));

      final LedgerSummary summary = await ledger.readSummary();
      expect(summary.entries, isEmpty);
      expect(summary.totalIncomePaise, 0);
      expect(summary.totalExpensePaise, 0);
      expect(summary.remainingPaise, 0);
      await ledger.close();
    });

    test(
      'the counter tables are additive and the schema version is unchanged',
      () async {
        final LocalLedger ledger = open();
        await ledger.initialize();
        final int schemaVersion = ledger.schemaVersion;

        await NoteCounterStore(ledger)
            .save('personal', NoteCounterSnapshot.empty());

        final List<QueryRow> version = await ledger
            .customSelect('PRAGMA user_version')
            .get();
        expect(version.single.read<int>('user_version'), schemaVersion);

        final List<QueryRow> tables = await ledger
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'table' "
              "AND name LIKE 'note_counter%' ORDER BY name",
            )
            .get();
        expect(
          tables.map((QueryRow row) => row.read<String>('name')).toList(),
          <String>[
            'note_counter_quantities',
            'note_counter_saved_sessions',
            'note_counter_state',
          ],
        );

        final List<QueryRow> foreignKeys = await ledger
            .customSelect('PRAGMA foreign_key_list(note_counter_quantities)')
            .get();
        expect(foreignKeys.single.read<String>('table'), 'khatas');
        expect(foreignKeys.single.read<String>('on_delete'), 'CASCADE');

        expect((await ledger.listKhatas()).length, 1);
        await ledger.close();
      },
    );
  });

  group('khata rules', () {
    test(
      'a blank or unknown khata is rejected, never filed under personal',
      () async {
        final LocalLedger ledger = open();
        await ledger.initialize();
        final NoteCounterStore store = NoteCounterStore(ledger);

        await expectLater(
          store.load('missing'),
          throwsA(isA<KhataNotFoundException>()),
        );
        await expectLater(
          store.save('missing', _snapshot(quantities: <int, int>{50000: 9})),
          throwsA(isA<KhataNotFoundException>()),
        );
        await expectLater(
          store.save('   ', _snapshot(quantities: <int, int>{50000: 9})),
          throwsA(isA<KhataNotFoundException>()),
        );

        expect((await store.load('personal')).totalPaise, 0);
        final List<QueryRow> rows = await ledger
            .customSelect(
              'SELECT COUNT(*) AS saved FROM note_counter_quantities',
            )
            .get();
        expect(rows.single.read<int>('saved'), 0);
        await ledger.close();
      },
    );

    test(
      'archiving keeps the count and unarchiving lets it be written again',
      () async {
        final LocalLedger ledger = open();
        await ledger.initialize();
        final LocalKhata business = await ledger.createKhata(
          name: 'Business',
          openingBalancePaise: 0,
        );
        final NoteCounterStore store = NoteCounterStore(ledger);
        await store.save(
          business.id,
          _snapshot(quantities: <int, int>{50000: 5}),
        );

        await ledger.archiveKhata(khataId: business.id);

        // Archive does not delete counts: the saved session is still readable.
        expect((await store.load(business.id)).quantityFor(50000), 5);
        // But an archived khata cannot be written, and nothing falls back to
        // the personal khata.
        await expectLater(
          store.save(business.id, _snapshot(quantities: <int, int>{50000: 9})),
          throwsA(isA<KhataNotFoundException>()),
        );
        expect((await store.load(business.id)).quantityFor(50000), 5);
        expect((await store.load('personal')).totalPaise, 0);

        await ledger.unarchiveKhata(khataId: business.id);
        await store.save(
          business.id,
          _snapshot(quantities: <int, int>{50000: 9}),
        );
        expect((await store.load(business.id)).quantityFor(50000), 9);
        await ledger.close();
      },
    );
  });

  group('unreadable rows', () {
    test('bad rows are reported, bounded, and repaired by the next save', () async {
      final LocalLedger ledger = open();
      await ledger.initialize();
      final NoteCounterStore store = NoteCounterStore(ledger);
      // The store creates its tables lazily; let it, then seed the bad rows.
      await store.load('personal');
      final String now = DateTime.now().toUtc().toIso8601String();

      // A row this version has no chip for, and a quantity outside the
      // documented range. The CHECK constraints are switched off only for this
      // setup, to stand in for a hand-edited or foreign database.
      await ledger.customStatement(
        'INSERT INTO note_counter_quantities '
        '(khata_id, denomination_paise, quantity, updated_at) '
        'VALUES (?, ?, ?, ?)',
        <Object>['personal', 1500, 7, now],
      );
      await ledger.customStatement('PRAGMA ignore_check_constraints = ON');
      await ledger.customStatement(
        'INSERT INTO note_counter_quantities '
        '(khata_id, denomination_paise, quantity, updated_at) '
        'VALUES (?, ?, ?, ?)',
        <Object>['personal', 50000, 200000, now],
      );
      await ledger.customStatement(
        'INSERT INTO note_counter_state '
        '(khata_id, selected_denomination_paise, show_two_thousand, updated_at) '
        'VALUES (?, ?, ?, ?)',
        <Object>['personal', 1234, 2, now],
      );
      await ledger.customStatement('PRAGMA ignore_check_constraints = OFF');

      final NoteCounterSnapshot loaded = await store.load('personal');
      expect(loaded.hasUnreadableRows, isTrue);
      expect(loaded.quantityFor(50000), kMaxNoteQuantity);
      expect(loaded.quantities.containsKey(1500), isFalse);
      expect(loaded.selectedDenominationPaise, kDefaultDenominationPaise);
      expect(loaded.showTwoThousand, isFalse);

      // Saving the sanitized snapshot rewrites every known denomination and
      // drops the row this version can never display; the warning clears.
      await store.save('personal', loaded);
      final NoteCounterSnapshot repaired = await store.load('personal');
      expect(repaired.hasUnreadableRows, isFalse);
      expect(repaired.quantityFor(50000), kMaxNoteQuantity);
      expect(repaired.totalPaise, kMaxNoteQuantity * 50000);
      await ledger.close();
    });

    test(
      'a stored ₹2,000 selection and flag are repaired away on load',
      () async {
        final LocalLedger ledger = open();
        await ledger.initialize();
        // The store creates its tables lazily; let it, then seed the row.
        await NoteCounterStore(ledger).load('personal');
        final String now = DateTime.now().toUtc().toIso8601String();
        await ledger.customStatement(
          'INSERT INTO note_counter_state '
          '(khata_id, selected_denomination_paise, show_two_thousand, updated_at) '
          'VALUES (?, ?, ?, ?)',
          <Object>['personal', 200000, 1, now],
        );

        final NoteCounterSnapshot loaded = await NoteCounterStore(ledger)
            .load('personal');
        expect(loaded.showTwoThousand, isFalse);
        expect(loaded.selectedDenominationPaise, kDefaultDenominationPaise);
        expect(loaded.hasUnreadableRows, isTrue);
        // Gone from the database, not merely ignored on screen.
        final List<QueryRow> rows = await ledger
            .customSelect(
              'SELECT selected_denomination_paise, show_two_thousand '
              'FROM note_counter_state WHERE khata_id = ?',
              variables: <Variable<Object>>[Variable<String>('personal')],
            )
            .get();
        expect(
          rows.single.read<int>('selected_denomination_paise'),
          kDefaultDenominationPaise,
        );
        expect(rows.single.read<int>('show_two_thousand'), 0);
        await ledger.close();
      },
    );

    test(
      'stored ₹2,000 quantities and sessions are repaired away on load',
      () async {
        final LocalLedger ledger = open();
        await ledger.initialize();
        final NoteCounterStore store = NoteCounterStore(ledger);
        // The store creates its tables lazily; let it, then seed the rows a
        // pre-withdrawal phone could hold.
        await store.load('personal');
        final String now = DateTime.now().toUtc().toIso8601String();
        await ledger.customStatement(
          'INSERT INTO note_counter_quantities '
          '(khata_id, denomination_paise, quantity, updated_at) '
          'VALUES (?, ?, ?, ?), (?, ?, ?, ?)',
          <Object>['personal', 50000, 3, now, 'personal', 200000, 2, now],
        );
        await ledger.customStatement(
          'INSERT INTO note_counter_state '
          '(khata_id, selected_denomination_paise, show_two_thousand, updated_at) '
          'VALUES (?, ?, ?, ?)',
          <Object>['personal', 200000, 1, now],
        );
        await ledger.customStatement(
          'INSERT INTO note_counter_saved_sessions '
          '(id, khata_id, saved_at, quantities_json, '
          'selected_denomination_paise, show_two_thousand) '
          'VALUES (?, ?, ?, ?, ?, ?)',
          <Object>[
            'session-1',
            'personal',
            now,
            '{"50000":4,"200000":1}',
            200000,
            1,
          ],
        );

        final NoteCounterSnapshot loaded = await store.load('personal');
        expect(loaded.hasUnreadableRows, isTrue);
        expect(loaded.quantityFor(50000), 3);
        expect(loaded.quantities.containsKey(200000), isFalse);
        expect(loaded.totalPaise, 3 * 50000);
        expect(loaded.selectedDenominationPaise, kDefaultDenominationPaise);
        expect(loaded.showTwoThousand, isFalse);

        // The stored quantity is gone, not merely hidden.
        final List<QueryRow> quantities = await ledger
            .customSelect(
              'SELECT denomination_paise FROM note_counter_quantities '
              'WHERE khata_id = ?',
              variables: <Variable<Object>>[Variable<String>('personal')],
            )
            .get();
        expect(
          quantities.map((QueryRow row) => row.read<int>('denomination_paise')),
          <int>[50000],
        );

        // The saved session no longer carries the retired note either, so
        // it is not silently hidden from the sheet.
        final List<SavedNoteCount> sessions = await store.listSessions(
          'personal',
        );
        expect(sessions, hasLength(1));
        expect(
          sessions.single.snapshot.quantities.containsKey(200000),
          isFalse,
        );
        expect(sessions.single.snapshot.quantityFor(50000), 4);
        expect(
          sessions.single.snapshot.selectedDenominationPaise,
          kDefaultDenominationPaise,
        );
        expect(sessions.single.snapshot.showTwoThousand, isFalse);
        expect(sessions.single.totalPaise, 4 * 50000);

        // Repair is idempotent: the next load is clean.
        expect((await store.load('personal')).hasUnreadableRows, isFalse);
        await ledger.close();
      },
    );
  });

  group('write queue', () {
    test(
      'rapid saves settle, keep the newest value and never reorder',
      () async {
        final LocalLedger ledger = open();
        await ledger.initialize();
        final NoteCounterStore store = NoteCounterStore(ledger);

        final List<Future<void>> writes = <Future<void>>[
          for (int quantity = 1; quantity <= 20; quantity++)
            store.save(
              'personal',
              _snapshot(quantities: <int, int>{50000: quantity}),
            ),
        ];
        await Future.wait(writes);

        expect((await store.load('personal')).quantityFor(50000), 20);
        await ledger.close();
      },
    );

    test('a load settles a save that has not been awaited yet', () async {
      final LocalLedger ledger = open();
      await ledger.initialize();
      final NoteCounterStore store = NoteCounterStore(ledger);

      final Future<void> queued = store.save(
        'personal',
        _snapshot(quantities: <int, int>{50000: 6}),
      );
      // Nothing between save() and load(): the load must wait for the queue
      // rather than read the value before the write.
      final NoteCounterSnapshot loaded = await store.load('personal');
      expect(loaded.quantityFor(50000), 6);
      await queued;
      await ledger.close();
    });

    test(
      'a failed write fails its caller and leaves the stored count intact',
      () async {
        final LocalLedger ledger = open();
        await ledger.initialize();
        final LocalKhata business = await ledger.createKhata(
          name: 'Business',
          openingBalancePaise: 0,
        );
        final NoteCounterStore store = NoteCounterStore(ledger);
        await store.save(
          business.id,
          _snapshot(quantities: <int, int>{50000: 2}),
        );
        await ledger.archiveKhata(khataId: business.id);

        await expectLater(
          store.save(business.id, _snapshot(quantities: <int, int>{50000: 8})),
          throwsA(isA<KhataNotFoundException>()),
        );
        expect((await store.load(business.id)).quantityFor(50000), 2);
        await ledger.close();
      },
    );
  });

  group('saved sessions', () {
    test(
      'a saved session round-trips with its snapshot and timestamp',
      () async {
        final LocalLedger ledger = open();
        await ledger.initialize();
        final NoteCounterStore store = NoteCounterStore(ledger);

        final SavedNoteCount session = await store.saveSession(
          'personal',
          _snapshot(
            quantities: <int, int>{50000: 4, 10000: 2},
            selected: 10000,
          ),
        );

        expect(session.id, isNotEmpty);
        expect(session.khataId, 'personal');
        expect(session.snapshot.quantityFor(50000), 4);
        expect(session.snapshot.selectedDenominationPaise, 10000);
        expect(session.snapshot.showTwoThousand, isFalse);
        expect(session.totalPaise, 4 * 50000 + 2 * 10000);
        expect(session.savedAt.isUtc, isTrue);

        final List<SavedNoteCount> sessions = await store.listSessions(
          'personal',
        );
        expect(sessions, hasLength(1));
        expect(sessions.single.id, session.id);
        expect(sessions.single.savedAt, session.savedAt);
        expect(sessions.single.snapshot.quantityFor(10000), 2);
        await ledger.close();
      },
    );

    test('sessions list newest first, even in the same millisecond', () async {
      final LocalLedger ledger = open();
      await ledger.initialize();
      final NoteCounterStore store = NoteCounterStore(ledger);

      final SavedNoteCount first = await store.saveSession(
        'personal',
        _snapshot(quantities: <int, int>{50000: 1}),
      );
      final SavedNoteCount second = await store.saveSession(
        'personal',
        _snapshot(quantities: <int, int>{50000: 2}),
      );

      final List<SavedNoteCount> sessions = await store.listSessions(
        'personal',
      );
      expect(sessions.map((SavedNoteCount s) => s.id), <String>[
        second.id,
        first.id,
      ]);
      await ledger.close();
    });

    test('an empty count cannot be saved as a session', () async {
      final LocalLedger ledger = open();
      await ledger.initialize();
      final NoteCounterStore store = NoteCounterStore(ledger);

      await expectLater(
        store.saveSession('personal', NoteCounterSnapshot.empty()),
        throwsArgumentError,
      );
      expect(await store.listSessions('personal'), isEmpty);
      await ledger.close();
    });

    test('a blank, unknown or archived khata is rejected', () async {
      final LocalLedger ledger = open();
      await ledger.initialize();
      final LocalKhata business = await ledger.createKhata(
        name: 'Business',
        openingBalancePaise: 0,
      );
      final NoteCounterStore store = NoteCounterStore(ledger);

      await expectLater(
        store.saveSession('   ', _snapshot(quantities: <int, int>{50000: 1})),
        throwsA(isA<KhataNotFoundException>()),
      );
      await expectLater(
        store.saveSession(
          'missing',
          _snapshot(quantities: <int, int>{50000: 1}),
        ),
        throwsA(isA<KhataNotFoundException>()),
      );
      await ledger.archiveKhata(khataId: business.id);
      await expectLater(
        store.saveSession(
          business.id,
          _snapshot(quantities: <int, int>{50000: 1}),
        ),
        throwsA(isA<KhataNotFoundException>()),
      );
      await expectLater(
        store.listSessions('missing'),
        throwsA(isA<KhataNotFoundException>()),
      );
      await ledger.close();
    });

    test('saving a session never rewrites the current count', () async {
      final LocalLedger ledger = open();
      await ledger.initialize();
      final NoteCounterStore store = NoteCounterStore(ledger);

      await store.save('personal', _snapshot(quantities: <int, int>{50000: 3}));
      await store.saveSession(
        'personal',
        _snapshot(quantities: <int, int>{50000: 9}),
      );

      expect((await store.load('personal')).quantityFor(50000), 3);
      final List<SavedNoteCount> sessions = await store.listSessions(
        'personal',
      );
      expect(sessions.single.snapshot.quantityFor(50000), 9);
      await ledger.close();
    });

    test('sessions are isolated per khata and deletes are scoped', () async {
      final LocalLedger ledger = open();
      await ledger.initialize();
      final LocalKhata business = await ledger.createKhata(
        name: 'Business',
        openingBalancePaise: 0,
      );
      final NoteCounterStore store = NoteCounterStore(ledger);

      final SavedNoteCount personal = await store.saveSession(
        'personal',
        _snapshot(quantities: <int, int>{50000: 1}),
      );
      final SavedNoteCount shop = await store.saveSession(
        business.id,
        _snapshot(quantities: <int, int>{50000: 2}),
      );

      expect(
        (await store.listSessions('personal')).map((SavedNoteCount s) => s.id),
        <String>[personal.id],
      );
      expect(
        (await store.listSessions(business.id)).map((SavedNoteCount s) => s.id),
        <String>[shop.id],
      );

      // One khata cannot delete the other's session.
      await store.deleteSession('personal', shop.id);
      expect(await store.listSessions(business.id), hasLength(1));
      // Deleting an already-deleted session is a no-op, not an error.
      await store.deleteSession(business.id, shop.id);
      await store.deleteSession(business.id, shop.id);
      expect(await store.listSessions(business.id), isEmpty);
      expect(await store.listSessions('personal'), hasLength(1));
      await ledger.close();
    });

    test(
      'a saved session survives closing and reopening the database',
      () async {
        LocalLedger ledger = open();
        await ledger.initialize();
        final String id = (await NoteCounterStore(ledger).saveSession(
          'personal',
          _snapshot(quantities: <int, int>{20000: 3}, selected: 20000),
        )).id;
        await ledger.close();

        ledger = open();
        await ledger.initialize();
        final List<SavedNoteCount> sessions = await NoteCounterStore(ledger)
            .listSessions('personal');
        expect(sessions.single.id, id);
        expect(sessions.single.snapshot.quantityFor(20000), 3);
        expect(sessions.single.snapshot.selectedDenominationPaise, 20000);
        await ledger.close();
      },
    );

    test('a saved session never touches the ledger or its balance', () async {
      final LocalLedger ledger = open();
      await ledger.initialize();
      await NoteCounterStore(
        ledger,
      ).saveSession('personal', _snapshot(quantities: <int, int>{50000: 10}));

      final LedgerSummary summary = await ledger.readSummary();
      expect(summary.entries, isEmpty);
      expect(summary.remainingPaise, 0);
      await ledger.close();
    });
  });
}
