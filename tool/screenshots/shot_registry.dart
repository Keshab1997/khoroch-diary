// This file belongs to THIS project (the installer never replaces it).
// It lists the screens the local screenshot harness renders, dressed in the
// app's real theme. Run: python3 tool/local_screenshots.py --shot home
import 'dart:io';

import 'package:drift/native.dart';
// Flutter 3.50 keeps this compatibility import for the current app.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:khoroch_diary/core/theme/app_theme.dart';
import 'package:khoroch_diary/features/calculator/calculator_screen.dart';
import 'package:khoroch_diary/features/counter/note_counter_screen.dart';
import 'package:khoroch_diary/features/counter/note_counter_store.dart';
import 'package:khoroch_diary/features/entry/add_entry_screen.dart';
import 'package:khoroch_diary/features/home/home_screen.dart';
import 'package:khoroch_diary/features/home/models.dart';
import 'package:khoroch_diary/features/ledger/all_transactions_screen.dart';
import 'package:khoroch_diary/features/ledger/data/local_ledger.dart';
import 'package:khoroch_diary/features/profile/profile_screen.dart';
import 'package:khoroch_diary/features/profile/settings_screen.dart';
import 'package:khoroch_diary/features/sync/cloud_backend.dart';
import 'package:khoroch_diary/features/sync/cloud_backup_screen.dart';
import 'package:khoroch_diary/features/sync/sign_in_screen.dart';

import 'shot_framework.dart';

// The per-khata counter shot reads and writes a real (in-memory) ledger, so it
// renders the same saved-count chrome as the live app: the autosave status
// line, the Saved sessions and Copy summary buttons and the device-save hint.
NoteCounterStore? _perKhataStore;

Future<void> _loadPerKhataCounter() async {
  final LocalLedger ledger = LocalLedger(NativeDatabase.memory());
  await ledger.initialize();
  _perKhataStore = NoteCounterStore(ledger);
}

/// Widget tests otherwise use the Ahem test font, where every glyph is a
/// square: text becomes boxes and a normal Row looks like an overflow bug.
/// These two files ship with the repo (Apache-2.0, see assets/fonts/) and are
/// loaded only by the screenshot runner - the app itself uses platform fonts.
Future<void> _loadRoboto() async {
  final FontLoader loader = FontLoader('Roboto');
  for (final String path in <String>[
    'assets/fonts/Roboto-Regular.ttf',
    'assets/fonts/Roboto-Bold.ttf',
  ]) {
    final Uint8List bytes = await File(path).readAsBytes();
    loader.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

/// The same light theme and phone size the design preview was drawn for.
/// Tab shots include bottom navigation. Detail shots get a real route below
/// them, so their back buttons appear exactly as they do after navigation.
final ShotEnv env = ShotEnv(
  app: (Shot shot, Widget home) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    // A route factory enables the Navigator for the initial stack below.
    onGenerateRoute: (_) =>
        MaterialPageRoute<void>(builder: (_) => const SizedBox.shrink()),
    onGenerateInitialRoutes: (_) => <Route<void>>[
      if (_isDetailShot(shot.name))
        MaterialPageRoute<void>(builder: (_) => const SizedBox.shrink()),
      MaterialPageRoute<void>(
        builder: (_) => _isDetailShot(shot.name)
            ? home
            : _TabShotShell(index: _tabIndex(shot.name), child: home),
      ),
    ],
  ),
  setUpAll: () async {
    await _loadRoboto();
    await _loadPerKhataCounter();
  },
);

bool _isDetailShot(String name) =>
    name.startsWith('add_entry') ||
    name.startsWith('settings') ||
    name.startsWith('sign_in') ||
    name.startsWith('cloud_backup') ||
    name.startsWith('all_transactions');

int _tabIndex(String name) {
  if (name.startsWith('profile')) return 3;
  if (name.startsWith('counter')) return 2;
  switch (name) {
    case 'calculator':
      return 1;
    case 'profile':
      return 3;
    default:
      return 0;
  }
}

class _TabShotShell extends StatelessWidget {
  const _TabShotShell({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (_) {},
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.calculate_outlined),
            selectedIcon: Icon(Icons.calculate),
            label: 'Calculator',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: 'Counter',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

final List<Shot> shots = <Shot>[
  Shot(
    name: 'home',
    build: () => HomeScreen(
      summary: LedgerSummary(
        openingBalancePaise: kSeedOpeningBalancePaise,
        entries: kSeedEntries,
      ),
      khataName: 'Personal Khata',
      onSwitchKhata: () {},
      onAddEntry: () {},
      onViewAll: () {},
    ),
    dark: false,
  ),
  Shot(name: 'calculator', build: () => const CalculatorScreen(), dark: false),
  Shot(name: 'counter', build: () => const NoteCounterScreen(), dark: false),
  // The per-khata variant: the standalone counter above shows only the
  // in-memory hint, while this one shows the autosave status line and the
  // two-action button row the real app renders.
  Shot(
    name: 'counter_khata',
    build: () => NoteCounterScreen(
      store: _perKhataStore!,
      khataId: 'personal',
      onSettings: () {},
    ),
    dark: false,
  ),
  Shot(name: 'profile', build: () => const ProfileScreen(), dark: false),
  // Honest signed-out/unconfigured states: no live auth, storage or network.
  Shot(name: 'settings', build: () => const SettingsScreen(), dark: false),
  Shot(
    name: 'sign_in',
    build: () => const SignInScreen(backend: _ScreenshotBackend()),
    dark: false,
  ),
  Shot(
    name: 'cloud_backup',
    build: () => const CloudBackupScreen(),
    dark: false,
  ),
  Shot(
    name: 'profile_small_large_text',
    build: () => const ProfileScreen(),
    logicalSize: const Size(320, 568),
    textScale: 2,
    dark: false,
  ),
  Shot(
    name: 'settings_small_large_text',
    build: () => const SettingsScreen(),
    logicalSize: const Size(320, 568),
    textScale: 2,
    dark: false,
  ),
  Shot(
    name: 'sign_in_small_large_text',
    build: () => const SignInScreen(backend: _ScreenshotBackend()),
    logicalSize: const Size(320, 568),
    textScale: 2,
    dark: false,
  ),
  Shot(
    name: 'cloud_backup_small_large_text',
    build: () => const CloudBackupScreen(),
    logicalSize: const Size(320, 568),
    textScale: 2,
    dark: false,
  ),
  Shot(
    name: 'all_transactions',
    build: () => AllTransactionsScreen(summary: _referenceTransactions()),
    dark: false,
  ),
  Shot(
    name: 'all_transactions_small_large_text',
    build: () => AllTransactionsScreen(summary: _referenceTransactions()),
    logicalSize: const Size(320, 568),
    textScale: 2,
    dark: false,
  ),
  Shot(
    name: 'all_transactions_empty',
    build: () => AllTransactionsScreen(
      summary: LedgerSummary(openingBalancePaise: 0, entries: <LedgerEntry>[]),
    ),
    dark: false,
  ),
  Shot(
    name: 'add_entry_compact',
    build: () => AddEntryScreen(openingBalancePaise: 642000, onSave: (_) {}),
    logicalSize: const Size(360, 780),
    dark: false,
  ),
  Shot(
    name: 'add_entry',
    build: () => AddEntryScreen(openingBalancePaise: 642000, onSave: (_) {}),
    dark: false,
  ),
];

/// A presentation-only, signed-out backend. Screenshot builds never contact
/// Google/Supabase and cannot silently upload or mutate a local ledger.
class _ScreenshotBackend implements CloudBackend {
  const _ScreenshotBackend();

  @override
  CloudUser? get currentUser => null;

  @override
  Stream<CloudUser?> get userChanges => const Stream<CloudUser?>.empty();

  @override
  Future<CloudUser?> signInWithGoogle() async => null;

  @override
  Future<void> signOut() async {}

  @override
  Future<List<CloudKhataRow>> upsertKhatas(List<CloudKhataRow> rows) =>
      Future<List<CloudKhataRow>>.error(UnsupportedError('Screenshot only'));

  @override
  Future<List<CloudTransactionRow>> upsertTransactions(
    List<CloudTransactionRow> rows,
  ) => Future<List<CloudTransactionRow>>.error(
    UnsupportedError('Screenshot only'),
  );

  @override
  Future<CloudChangeSet> fetchChanges(DateTime? since) =>
      Future<CloudChangeSet>.error(UnsupportedError('Screenshot only'));
}

/// Screenshot-only data matching the user's visual reference. Never injected
/// into the running application or used as the source of production totals.
LedgerSummary _referenceTransactions() => LedgerSummary(
  openingBalancePaise: 250000,
  entries: <LedgerEntry>[
    LedgerEntry(
      title: 'Income from Business',
      category: 'Income',
      at: DateTime(2026, 11, 19, 10, 15),
      amountPaise: 100000,
      type: EntryType.income,
    ),
    LedgerEntry(
      title: 'Shopping at Mart',
      category: 'Shopping',
      at: DateTime(2026, 11, 19, 9, 30),
      amountPaise: 50000,
    ),
  ],
);
