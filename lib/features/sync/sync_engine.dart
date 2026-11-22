/// Offline-first cloud sync engine for khatas and transactions (B5).
///
/// Orchestrates [LocalLedger], [CloudBackend] and an optional [SyncScheduler]:
/// * Pushes pending khatas first (in batches), then pending transactions (in
///   batches), applying any server-returned row that differs from what was sent
///   and marking unchanged local rows `synced`.
/// * Pulls remote changes from `cursor - 60s` (or `null` on the first pull),
///   idempotently applies remote khatas before remote transactions, and stores
///   the new cursor, `last_synced_at` and `last_synced_account_id`.
/// * Never throws network or backend failures to callers of [syncNow]: signed
///   out and offline states are clean no-ops, account switches wait for
///   explicit user confirmation before pushing, and backend failures leave
///   local data untouched, persist `last_error`, emit [SyncStatus.error] and
///   schedule exponential backoff through [scheduler].
library;

import 'dart:async';

import '../ledger/data/local_ledger.dart';
import 'cloud_backend.dart';
import 'sync_scheduler.dart';
import 'sync_status.dart';

typedef OnlineCheck = FutureOr<bool> Function();
typedef ClockReader = DateTime Function();

/// Outcome of a single [SyncEngine.syncNow] call.
enum SyncOutcome {
  synced,
  signedOut,
  offline,
  accountSwitchConfirmationRequired,
  alreadySyncing,
  failed,
}

class SyncEngine {
  SyncEngine({
    required this.ledger,
    required this.backend,
    this.batchSize = 100,
    this.pullOverlap = const Duration(seconds: 60),
    OnlineCheck? isOnline,
    ClockReader? now,
    Duration debounce = const Duration(milliseconds: 800),
    Duration baseBackoff = const Duration(seconds: 2),
    Duration maxBackoff = const Duration(minutes: 5),
    TimerFactory? timerFactory,
  }) : _onlineCheck = isOnline,
       _now = now ?? _utcNow {
    if (batchSize <= 0) {
      throw ArgumentError.value(batchSize, 'batchSize', 'must be positive');
    }
    if (pullOverlap.isNegative) {
      throw ArgumentError.value(
        pullOverlap,
        'pullOverlap',
        'must not be negative',
      );
    }
    scheduler = SyncScheduler(
      runSync: _runFromScheduler,
      debounce: debounce,
      baseBackoff: baseBackoff,
      maxBackoff: maxBackoff,
      timerFactory: timerFactory,
    );
    _userSubscription = backend.userChanges.listen(_onUserChanged);
    unawaited(refreshStatus());
  }

  final LocalLedger ledger;
  final CloudBackend backend;
  final int batchSize;
  final Duration pullOverlap;
  final OnlineCheck? _onlineCheck;
  final ClockReader _now;

  late final SyncScheduler scheduler;

  final StreamController<SyncStatus> _statusController =
      StreamController<SyncStatus>.broadcast();
  StreamSubscription<CloudUser?>? _userSubscription;

  SyncStatus _currentStatus = const SyncStatus.signedOut();
  bool _syncing = false;
  bool _disposed = false;
  String? _confirmedSwitchAccountId;

  static DateTime _utcNow() => DateTime.now().toUtc();

  /// Latest emitted [SyncStatus].
  SyncStatus get currentStatus => _currentStatus;

  /// Broadcast stream of [SyncStatus] updates. New listeners receive
  /// [currentStatus] immediately followed by every subsequent transition.
  Stream<SyncStatus> get statusStream async* {
    yield _currentStatus;
    yield* _statusController.stream;
  }

  /// Debounced trigger for use after local writes.
  void kick() {
    if (_disposed) return;
    unawaited(refreshStatus());
    if (backend.currentUser != null) {
      scheduler.kick();
    }
  }

  /// Recomputes and emits [SyncStatus] from local ledger metadata and
  /// [CloudBackend.currentUser] without hitting the network.
  Future<SyncStatus> refreshStatus() async {
    if (_disposed) return _currentStatus;
    if (_syncing) return _currentStatus;

    final int pendingCount = await ledger.readPendingSyncCount();
    final CloudUser? user = backend.currentUser;
    if (user == null) {
      final SyncStatus next = SyncStatus.signedOut(pendingCount: pendingCount);
      _emitStatus(next);
      return next;
    }

    final LocalSyncMetadata meta = await ledger.readSyncMetadata();
    final bool needsConfirm = _requiresSwitchConfirmation(
      user: user,
      meta: meta,
    );
    if (needsConfirm) {
      final SyncStatus next = SyncStatus.idle(
        userEmail: user.email,
        lastSyncedAt: meta.lastSyncedAt,
        pendingCount: pendingCount,
        requiresAccountSwitchConfirmation: true,
        previousAccountId: meta.lastSyncedAccountId,
      );
      _emitStatus(next);
      return next;
    }

    final String? lastError = meta.lastError;
    if (lastError != null && lastError.trim().isNotEmpty) {
      final SyncStatus next = SyncStatus.error(
        reason: lastError,
        userEmail: user.email,
        lastSyncedAt: meta.lastSyncedAt,
        pendingCount: pendingCount,
      );
      _emitStatus(next);
      return next;
    }

    final SyncStatus next = SyncStatus.idle(
      userEmail: user.email,
      lastSyncedAt: meta.lastSyncedAt,
      pendingCount: pendingCount,
    );
    _emitStatus(next);
    return next;
  }

  /// Explicitly confirms syncing this device's local ledger with the currently
  /// signed-in account when a different account previously synced on this
  /// device, then runs [syncNow].
  Future<SyncOutcome> confirmAccountSwitchAndSync() async {
    final CloudUser? user = backend.currentUser;
    if (user == null) {
      await refreshStatus();
      return SyncOutcome.signedOut;
    }
    await ledger.prepareForAccountSwitch(user.id);
    _confirmedSwitchAccountId = user.id;
    return syncNow(confirmAccountSwitch: true);
  }

  /// Signs out through [CloudBackend.signOut] without touching local khata or
  /// transaction rows, cancels scheduled retries, and emits
  /// [SyncStatus.signedOut].
  Future<void> signOut() async {
    scheduler.reset();
    _confirmedSwitchAccountId = null;
    await backend.signOut();
    await refreshStatus();
  }

  /// Deletes the signed-in cloud account and remote copies, but preserves the
  /// local ledger. A failed remote deletion leaves the session intact to retry.
  Future<void> deleteAccount() async {
    if (_disposed) return;
    scheduler.reset();
    _confirmedSwitchAccountId = null;
    await backend.deleteAccount();
    await refreshStatus();
  }

  /// Runs one push-then-pull sync pass now. Never throws network or backend
  /// errors to the caller.
  Future<SyncOutcome> syncNow({bool confirmAccountSwitch = false}) async {
    if (_disposed) return SyncOutcome.signedOut;
    if (_syncing) return SyncOutcome.alreadySyncing;

    final CloudUser? user = backend.currentUser;
    final int initialPending = await ledger.readPendingSyncCount();
    if (user == null) {
      scheduler.reset();
      _emitStatus(SyncStatus.signedOut(pendingCount: initialPending));
      return SyncOutcome.signedOut;
    }

    LocalSyncMetadata meta = await ledger.readSyncMetadata();
    if (_requiresSwitchConfirmation(user: user, meta: meta)) {
      if (!confirmAccountSwitch) {
        _emitStatus(
          SyncStatus.idle(
            userEmail: user.email,
            lastSyncedAt: meta.lastSyncedAt,
            pendingCount: initialPending,
            requiresAccountSwitchConfirmation: true,
            previousAccountId: meta.lastSyncedAccountId,
          ),
        );
        return SyncOutcome.accountSwitchConfirmationRequired;
      }
      await ledger.prepareForAccountSwitch(user.id);
      _confirmedSwitchAccountId = user.id;
      meta = await ledger.readSyncMetadata();
    }

    if (!await _checkOnline()) {
      final int pending = await ledger.readPendingSyncCount();
      _emitStatus(
        SyncStatus.idle(
          userEmail: user.email,
          lastSyncedAt: meta.lastSyncedAt,
          pendingCount: pending,
          isOffline: true,
        ),
      );
      return SyncOutcome.offline;
    }

    // Cancel any pending debounce or retry timer while preserving consecutive
    // failure count until the attempt succeeds.
    scheduler.cancelPendingTimers();
    final SyncOutcome outcome = await _performSync(
      user: user,
      meta: meta,
      manageBackoffOnDirectCall: true,
    );
    return outcome;
  }

  Future<bool> _runFromScheduler() async {
    if (_disposed || _syncing) return true;
    final CloudUser? user = backend.currentUser;
    if (user == null) {
      await refreshStatus();
      return true;
    }
    final LocalSyncMetadata meta = await ledger.readSyncMetadata();
    if (_requiresSwitchConfirmation(user: user, meta: meta)) {
      final int pending = await ledger.readPendingSyncCount();
      _emitStatus(
        SyncStatus.idle(
          userEmail: user.email,
          lastSyncedAt: meta.lastSyncedAt,
          pendingCount: pending,
          requiresAccountSwitchConfirmation: true,
          previousAccountId: meta.lastSyncedAccountId,
        ),
      );
      return true;
    }
    if (!await _checkOnline()) {
      final int pending = await ledger.readPendingSyncCount();
      _emitStatus(
        SyncStatus.idle(
          userEmail: user.email,
          lastSyncedAt: meta.lastSyncedAt,
          pendingCount: pending,
          isOffline: true,
        ),
      );
      return true;
    }

    final SyncOutcome outcome = await _performSync(
      user: user,
      meta: meta,
      manageBackoffOnDirectCall: false,
    );
    return outcome != SyncOutcome.failed;
  }

  Future<SyncOutcome> _performSync({
    required CloudUser user,
    required LocalSyncMetadata meta,
    required bool manageBackoffOnDirectCall,
  }) async {
    _syncing = true;
    final int startingPending = await ledger.readPendingSyncCount();
    _emitStatus(
      SyncStatus.syncing(
        userEmail: user.email,
        lastSyncedAt: meta.lastSyncedAt,
        pendingCount: startingPending,
      ),
    );

    try {
      await _pushKhatas(user.id);
      await _pushTransactions(user.id);

      final DateTime? pullSince = meta.cursor?.subtract(pullOverlap).toUtc();
      final CloudChangeSet changes = await backend.fetchChanges(pullSince);

      if (changes.khatas.isNotEmpty) {
        await ledger.applyRemoteKhatas(changes.khatas);
      }
      if (changes.transactions.isNotEmpty) {
        await ledger.applyRemoteTransactions(changes.transactions);
      }

      final DateTime syncedAt = _now().toUtc();
      final DateTime? nextCursor = _advanceCursor(
        previous: meta.cursor,
        reported: changes.cursor,
        khatas: changes.khatas,
        transactions: changes.transactions,
      );

      await ledger.writeSyncMetadata(
        cursor: nextCursor,
        lastSyncedAt: syncedAt,
        lastError: null,
        lastSyncedAccountId: user.id,
      );
      _confirmedSwitchAccountId = user.id;

      if (manageBackoffOnDirectCall) {
        scheduler.reset();
      }

      final int remainingPending = await ledger.readPendingSyncCount();
      _emitStatus(
        SyncStatus.idle(
          userEmail: user.email,
          lastSyncedAt: syncedAt,
          pendingCount: remainingPending,
        ),
      );
      return SyncOutcome.synced;
    } on CloudOfflineException {
      _syncing = false;
      final int pending = await ledger.readPendingSyncCount();
      final LocalSyncMetadata latest = await ledger.readSyncMetadata();
      _emitStatus(
        SyncStatus.idle(
          userEmail: user.email,
          lastSyncedAt: latest.lastSyncedAt,
          pendingCount: pending,
          isOffline: true,
        ),
      );
      return SyncOutcome.offline;
    } catch (error) {
      _syncing = false;
      final String reason = _formatErrorReason(error);
      await ledger.writeSyncMetadata(lastError: reason);
      final int pending = await ledger.readPendingSyncCount();
      final LocalSyncMetadata latest = await ledger.readSyncMetadata();
      _emitStatus(
        SyncStatus.error(
          reason: reason,
          userEmail: user.email,
          lastSyncedAt: latest.lastSyncedAt,
          pendingCount: pending,
        ),
      );
      if (manageBackoffOnDirectCall) {
        await _armSchedulerFailureFromDirectCall();
      }
      return SyncOutcome.failed;
    } finally {
      _syncing = false;
    }
  }

  Future<void> _armSchedulerFailureFromDirectCall() async {
    // Delegate backoff arming to a lightweight scheduler failure pass when
    // `syncNow()` was invoked directly rather than via `scheduler.triggerNow()`.
    // To avoid running a duplicate network request right now, only arm through
    // the scheduler's own state if nothing is scheduled yet.
    if (!scheduler.hasScheduledRetry) {
      scheduler.scheduleFailureRetry();
    }
  }

  Future<void> _pushKhatas(String userId) async {
    String? afterId;
    while (true) {
      final List<CloudKhataRow> batch = await ledger.readPendingKhatas(
        limit: batchSize,
        afterId: afterId,
      );
      if (batch.isEmpty) break;
      // An edited-in-flight row remains pending, but is retried next sync
      // rather than blocking other rows or being pushed twice this time.
      afterId = batch.last.id;

      final List<CloudKhataRow> payload = batch
          .map((CloudKhataRow row) => row.copyWith(userId: userId))
          .toList(growable: false);
      final List<CloudKhataRow> stored = await backend.upsertKhatas(payload);

      final Map<String, CloudKhataRow> sentById = <String, CloudKhataRow>{
        for (final CloudKhataRow row in payload) row.id: row,
      };
      final List<CloudKhataRow> unchanged = <CloudKhataRow>[];
      final List<CloudKhataRow> differed = <CloudKhataRow>[];

      final Set<String> returnedIds = <String>{};
      for (final CloudKhataRow serverRow in stored) {
        returnedIds.add(serverRow.id);
        final CloudKhataRow? sent = sentById[serverRow.id];
        if (sent != null && serverRow.sameContentAs(sent)) {
          unchanged.add(sent);
        } else {
          differed.add(serverRow);
        }
      }
      for (final CloudKhataRow sent in payload) {
        if (!returnedIds.contains(sent.id)) {
          unchanged.add(sent);
        }
      }

      if (differed.isNotEmpty) {
        await ledger.applyRemoteKhatas(differed);
      }
      if (unchanged.isNotEmpty) {
        await ledger.markKhatasSyncedIfUnchanged(unchanged);
      }
    }
  }

  Future<void> _pushTransactions(String userId) async {
    String? afterId;
    while (true) {
      final List<CloudTransactionRow> batch = await ledger
          .readPendingTransactions(limit: batchSize, afterId: afterId);
      if (batch.isEmpty) break;
      afterId = batch.last.id;

      final List<CloudTransactionRow> payload = batch
          .map((CloudTransactionRow row) => row.copyWith(userId: userId))
          .toList(growable: false);
      final List<CloudTransactionRow> stored = await backend.upsertTransactions(
        payload,
      );

      final Map<String, CloudTransactionRow> sentById =
          <String, CloudTransactionRow>{
            for (final CloudTransactionRow row in payload) row.id: row,
          };
      final List<CloudTransactionRow> unchanged = <CloudTransactionRow>[];
      final List<CloudTransactionRow> differed = <CloudTransactionRow>[];

      final Set<String> returnedIds = <String>{};
      for (final CloudTransactionRow serverRow in stored) {
        returnedIds.add(serverRow.id);
        final CloudTransactionRow? sent = sentById[serverRow.id];
        if (sent != null && serverRow.sameContentAs(sent)) {
          unchanged.add(sent);
        } else {
          differed.add(serverRow);
        }
      }
      for (final CloudTransactionRow sent in payload) {
        if (!returnedIds.contains(sent.id)) {
          unchanged.add(sent);
        }
      }

      if (differed.isNotEmpty) {
        await ledger.applyRemoteTransactions(differed);
      }
      if (unchanged.isNotEmpty) {
        await ledger.markTransactionsSyncedIfUnchanged(unchanged);
      }
    }
  }

  bool _requiresSwitchConfirmation({
    required CloudUser user,
    required LocalSyncMetadata meta,
  }) {
    final String? previousAccount = meta.lastSyncedAccountId;
    if (previousAccount == null || previousAccount.trim().isEmpty) {
      return false;
    }
    if (previousAccount == user.id) {
      return false;
    }
    return _confirmedSwitchAccountId != user.id;
  }

  Future<bool> _checkOnline() async {
    final OnlineCheck? check = _onlineCheck;
    if (check == null) return true;
    try {
      return await check();
    } catch (_) {
      return false;
    }
  }

  DateTime? _advanceCursor({
    required DateTime? previous,
    required DateTime? reported,
    required List<CloudKhataRow> khatas,
    required List<CloudTransactionRow> transactions,
  }) {
    DateTime? best = previous?.toUtc();
    void consider(DateTime? candidate) {
      if (candidate == null) return;
      final DateTime utc = candidate.toUtc();
      final DateTime? currentBest = best;
      if (currentBest == null || utc.isAfter(currentBest)) {
        best = utc;
      }
    }

    consider(reported);
    for (final CloudKhataRow row in khatas) {
      consider(row.serverUpdatedAt);
    }
    for (final CloudTransactionRow row in transactions) {
      consider(row.serverUpdatedAt);
    }
    return best;
  }

  static String _formatErrorReason(Object error) {
    final String raw = error.toString().trim();
    const List<String> prefixes = <String>[
      'Exception: ',
      'StateError: ',
      'Bad state: ',
    ];
    String cleaned = raw;
    for (final String prefix in prefixes) {
      if (cleaned.startsWith(prefix)) {
        cleaned = cleaned.substring(prefix.length).trim();
      }
    }
    if (cleaned.isEmpty) {
      return 'Cloud sync failed. Please try again.';
    }
    if (cleaned.runes.length > 160) {
      return '${String.fromCharCodes(cleaned.runes.take(159))}…';
    }
    return cleaned;
  }

  void _onUserChanged(CloudUser? user) {
    if (_disposed) return;
    if (user == null) {
      scheduler.reset();
      _confirmedSwitchAccountId = null;
      unawaited(refreshStatus());
      return;
    }
    unawaited(_handleSignedInUser(user));
  }

  Future<void> _handleSignedInUser(CloudUser user) async {
    if (_disposed) return;
    final LocalSyncMetadata meta = await ledger.readSyncMetadata();
    if (_requiresSwitchConfirmation(user: user, meta: meta)) {
      await refreshStatus();
      return;
    }
    await refreshStatus();
    scheduler.kick();
  }

  void _emitStatus(SyncStatus next) {
    _currentStatus = next;
    if (!_disposed && !_statusController.isClosed) {
      _statusController.add(next);
    }
  }

  /// Cancels subscriptions, stops timers and closes [statusStream].
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    scheduler.dispose();
    await _userSubscription?.cancel();
    await _statusController.close();
  }
}
