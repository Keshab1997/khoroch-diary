/// App-level cloud backup & sync service for Khoroch Diary B5.
///
/// Owns one [CloudBackend], one [SyncEngine] (and its [SyncScheduler]), and an
/// [AppLifecycleListener] so cloud sync runs:
/// * once on start-up when a user is already signed in;
/// * automatically after a user signs in;
/// * after local ledger writes via debounced [notifyLocalChange];
/// * when the app resumes to the foreground.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../ledger/data/local_ledger.dart';
import 'cloud_backend.dart';
import 'cloud_config.dart';
import 'supabase_cloud_backend.dart';
import 'sync_engine.dart';
import 'sync_scheduler.dart';
import 'sync_status.dart';

class CloudSync {
  /// Testable constructor taking any [CloudBackend] (such as `FakeCloudBackend`
  /// or a custom [SupabaseCloudBackend]).
  CloudSync({
    required LocalLedger ledger,
    required this.backend,
    OnlineCheck? isOnline,
    ClockReader? now,
    Duration debounce = const Duration(milliseconds: 800),
    Duration baseBackoff = const Duration(seconds: 2),
    Duration maxBackoff = const Duration(minutes: 5),
    TimerFactory? timerFactory,
    bool observeAppLifecycle = true,
  }) : _engine = SyncEngine(
         ledger: ledger,
         backend: backend,
         isOnline: isOnline,
         now: now,
         debounce: debounce,
         baseBackoff: baseBackoff,
         maxBackoff: maxBackoff,
         timerFactory: timerFactory,
       ) {
    _previousUser = backend.currentUser;
    _userSubscription = backend.userChanges.listen(_onUserChanged);
    if (observeAppLifecycle) {
      WidgetsFlutterBinding.ensureInitialized();
      _lifecycleListener = AppLifecycleListener(onResume: _onAppResumed);
    }
    if (_previousUser != null) {
      unawaited(_engine.syncNow());
    }
  }

  static Future<Supabase>? _initialization;

  final CloudBackend backend;
  final SyncEngine _engine;
  StreamSubscription<CloudUser?>? _userSubscription;
  AppLifecycleListener? _lifecycleListener;
  CloudUser? _previousUser;
  bool _disposed = false;

  /// Starts live cloud sync when [config] is configured, or returns `null` when
  /// `SUPABASE_URL` / `SUPABASE_PUBLISHABLE_KEY` are absent so the app stays
  /// purely local-only.
  static Future<CloudSync?> start({
    required LocalLedger ledger,
    CloudConfig config = const CloudConfig.fromEnvironment(),
    OnlineCheck? isOnline,
  }) async {
    if (!config.isConfigured) {
      return null;
    }

    final Future<Supabase> init = _initialization ??= Supabase.initialize(
      url: config.url.trim(),
      publishableKey: config.publishableKey.trim(),
    );
    await init;

    final SupabaseCloudBackend backend = SupabaseCloudBackend(
      client: Supabase.instance.client,
      redirectTo: config.redirectTo,
    );
    return CloudSync(ledger: ledger, backend: backend, isOnline: isOnline);
  }

  /// Broadcast stream of [SyncStatus] updates.
  Stream<SyncStatus> get statusStream => _engine.statusStream;

  /// Latest [SyncStatus] snapshot.
  SyncStatus get currentStatus => _engine.currentStatus;

  /// Runs an immediate sync pass (`Back up now` / `Retry`).
  Future<SyncOutcome> backupNow() => _engine.syncNow();

  /// Confirms syncing local data with a newly signed-in Google account when a
  /// different account previously synced on this phone, then runs a sync pass.
  Future<SyncOutcome> confirmAccountSwitch() =>
      _engine.confirmAccountSwitchAndSync();

  /// Signs out locally without deleting any local khatas or transactions.
  Future<void> signOut() => _engine.signOut();

  /// Debounced trigger called after local ledger writes.
  void notifyLocalChange() {
    if (_disposed) return;
    _engine.kick();
  }

  void _onUserChanged(CloudUser? nextUser) {
    if (_disposed) return;
    final CloudUser? previous = _previousUser;
    _previousUser = nextUser;
    if (nextUser != null && previous?.id != nextUser.id) {
      unawaited(_engine.syncNow());
    }
  }

  void _onAppResumed() {
    if (_disposed) return;
    if (backend.currentUser != null) {
      unawaited(_engine.syncNow());
    }
  }

  /// Releases lifecycle listeners, auth subscriptions, and scheduler timers.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _lifecycleListener?.dispose();
    _lifecycleListener = null;
    await _userSubscription?.cancel();
    _userSubscription = null;
    await _engine.dispose();
  }
}
