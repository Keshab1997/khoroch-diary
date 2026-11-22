/// In-memory [CloudBackend] test double mirroring the live Supabase Postgres
/// trigger (`khatabook_sync_write`) and per-user RLS isolation.
///
/// Server rules simulated here:
/// * Primary key is `(user_id, id)`, isolated per signed-in user.
/// * On upsert, the server keeps the row with the newer `updatedAt`. On an
///   exact `updatedAt` tie, a tombstone (`deletedAt != null`) beats a live row
///   (`deletedAt == null`).
/// * Every accepted write stamps an advancing UTC `serverUpdatedAt`. When the
///   server keeps its existing row unchanged, its existing `serverUpdatedAt` is
///   preserved.
/// * [fetchChanges] returns rows for the current user whose `serverUpdatedAt`
///   is strictly after `since` (or all rows when `since == null`), plus the
///   newest cursor.
library;

import 'dart:async';

import 'package:khoroch_diary/features/sync/cloud_backend.dart';

class FakeCloudBackend implements CloudBackend {
  FakeCloudBackend({CloudUser? initialUser, DateTime? initialServerTime})
    : _currentUser = initialUser,
      _serverClock = (initialServerTime ?? DateTime.utc(2026, 11, 20, 9, 0, 0))
          .toUtc();

  CloudUser? _currentUser;
  DateTime _serverClock;

  final StreamController<CloudUser?> _userController =
      StreamController<CloudUser?>.broadcast();

  /// Per-user remote tables: `userId -> (id -> row)`.
  final Map<String, Map<String, CloudKhataRow>> _khatasByUser =
      <String, Map<String, CloudKhataRow>>{};
  final Map<String, Map<String, CloudTransactionRow>> _transactionsByUser =
      <String, Map<String, CloudTransactionRow>>{};

  /// Configurable Google sign-in handler; defaults to returning [nextSignInUser].
  Future<CloudUser?> Function()? onSignInWithGoogle;
  CloudUser? nextSignInUser;

  /// Optional hooks and fault injection for testing batches, races and retries.
  Object? nextError;
  bool offline = false;
  Future<void> Function(List<CloudKhataRow> batch)? beforeUpsertKhatas;
  Future<void> Function(List<CloudTransactionRow> batch)?
  beforeUpsertTransactions;
  Future<void> Function(DateTime? since)? beforeFetchChanges;

  /// Audit logs for test assertions.
  final List<String> callOrder = <String>[];
  final List<List<CloudKhataRow>> pushedKhataBatches = <List<CloudKhataRow>>[];
  final List<List<CloudTransactionRow>> pushedTransactionBatches =
      <List<CloudTransactionRow>>[];
  final List<DateTime?> fetchSinceArgs = <DateTime?>[];

  /// How many times [fetchChanges] has run.
  int get fetchCalls => fetchSinceArgs.length;
  int signOutCalls = 0;

  @override
  CloudUser? get currentUser => _currentUser;

  @override
  Stream<CloudUser?> get userChanges => _userController.stream;

  /// Programmatically signs in or switches [user] and emits on [userChanges].
  void setSignedInUser(CloudUser? user) {
    _currentUser = user;
    if (!_userController.isClosed) {
      _userController.add(user);
    }
  }

  /// Read-only snapshot helper for asserting data remaining in the fake server.
  List<CloudKhataRow> remoteKhatasFor(String userId) =>
      List<CloudKhataRow>.unmodifiable(
        _khatasByUser[userId]?.values ?? const <CloudKhataRow>[],
      );

  /// Read-only snapshot helper for asserting data remaining in the fake server.
  List<CloudTransactionRow> remoteTransactionsFor(String userId) =>
      List<CloudTransactionRow>.unmodifiable(
        _transactionsByUser[userId]?.values ?? const <CloudTransactionRow>[],
      );

  /// Seeds a khata row directly on the server for [userId] (simulating a write
  /// from another device).
  CloudKhataRow seedRemoteKhata(String userId, CloudKhataRow row) {
    final DateTime stampedAt = row.serverUpdatedAt ?? _tickServerClock();
    final CloudKhataRow stored = row.copyWith(
      userId: userId,
      serverUpdatedAt: stampedAt,
    );
    _khatasFor(userId)[stored.id] = stored;
    if (stampedAt.isAfter(_serverClock)) {
      _serverClock = stampedAt;
    }
    return stored;
  }

  /// Seeds a transaction row directly on the server for [userId] (simulating a
  /// write from another device).
  CloudTransactionRow seedRemoteTransaction(
    String userId,
    CloudTransactionRow row,
  ) {
    final DateTime stampedAt = row.serverUpdatedAt ?? _tickServerClock();
    final CloudTransactionRow stored = row.copyWith(
      userId: userId,
      serverUpdatedAt: stampedAt,
    );
    _transactionsFor(userId)[stored.id] = stored;
    if (stampedAt.isAfter(_serverClock)) {
      _serverClock = stampedAt;
    }
    return stored;
  }

  /// Snapshot of stored khatas for [userId].
  List<CloudKhataRow> storedKhatasFor(String userId) =>
      List<CloudKhataRow>.unmodifiable(_khatasFor(userId).values);

  /// Snapshot of stored transactions for [userId].
  List<CloudTransactionRow> storedTransactionsFor(String userId) =>
      List<CloudTransactionRow>.unmodifiable(_transactionsFor(userId).values);

  @override
  Future<CloudUser?> signInWithGoogle() async {
    callOrder.add('signInWithGoogle');
    _throwIfFaultInjected();
    final CloudUser? result = onSignInWithGoogle != null
        ? await onSignInWithGoogle!()
        : nextSignInUser;
    if (result != null) {
      setSignedInUser(result);
    }
    return result;
  }

  @override
  Future<void> signOut() async {
    callOrder.add('signOut');
    signOutCalls++;
    setSignedInUser(null);
  }

  @override
  Future<void> deleteAccount() async {
    callOrder.add('deleteAccount');
    _throwIfFaultInjected();
    final String userId = _requireSignedIn().id;
    _khatasByUser.remove(userId);
    _transactionsByUser.remove(userId);
    setSignedInUser(null);
  }

  @override
  Future<List<CloudKhataRow>> upsertKhatas(List<CloudKhataRow> rows) async {
    callOrder.add('upsertKhatas:${rows.length}');
    if (beforeUpsertKhatas != null) {
      await beforeUpsertKhatas!(rows);
    }
    _throwIfFaultInjected();
    final CloudUser user = _requireSignedIn();
    pushedKhataBatches.add(List<CloudKhataRow>.unmodifiable(rows));

    final Map<String, CloudKhataRow> table = _khatasFor(user.id);
    final List<CloudKhataRow> out = <CloudKhataRow>[];
    for (final CloudKhataRow incoming in rows) {
      final CloudKhataRow? existing = table[incoming.id];
      if (existing != null && _keepExistingKhata(existing, incoming)) {
        out.add(existing);
        continue;
      }
      final CloudKhataRow stored = incoming.copyWith(
        userId: user.id,
        serverUpdatedAt: _tickServerClock(),
      );
      table[stored.id] = stored;
      out.add(stored);
    }
    return List<CloudKhataRow>.unmodifiable(out);
  }

  @override
  Future<List<CloudTransactionRow>> upsertTransactions(
    List<CloudTransactionRow> rows,
  ) async {
    callOrder.add('upsertTransactions:${rows.length}');
    if (beforeUpsertTransactions != null) {
      await beforeUpsertTransactions!(rows);
    }
    _throwIfFaultInjected();
    final CloudUser user = _requireSignedIn();
    pushedTransactionBatches.add(List<CloudTransactionRow>.unmodifiable(rows));

    final Map<String, CloudKhataRow> khataTable = _khatasFor(user.id);
    final Map<String, CloudTransactionRow> txTable = _transactionsFor(user.id);
    final List<CloudTransactionRow> out = <CloudTransactionRow>[];

    for (final CloudTransactionRow incoming in rows) {
      if (!khataTable.containsKey(incoming.khataId)) {
        throw StateError(
          'Foreign key violation: khata ${incoming.khataId} missing on server',
        );
      }
      final CloudTransactionRow? existing = txTable[incoming.id];
      if (existing != null && _keepExistingTransaction(existing, incoming)) {
        out.add(existing);
        continue;
      }
      final CloudTransactionRow stored = incoming.copyWith(
        userId: user.id,
        serverUpdatedAt: _tickServerClock(),
      );
      txTable[stored.id] = stored;
      out.add(stored);
    }
    return List<CloudTransactionRow>.unmodifiable(out);
  }

  @override
  Future<CloudChangeSet> fetchChanges(DateTime? since) async {
    final DateTime? normalizedSince = since?.toUtc();
    callOrder.add(
      'fetchChanges:${normalizedSince?.toIso8601String() ?? 'null'}',
    );
    fetchSinceArgs.add(normalizedSince);
    if (beforeFetchChanges != null) {
      await beforeFetchChanges!(normalizedSince);
    }
    _throwIfFaultInjected();
    final CloudUser user = _requireSignedIn();

    final List<CloudKhataRow> khatas = _khatasFor(user.id).values
        .where(
          (CloudKhataRow r) =>
              normalizedSince == null ||
              r.serverUpdatedAt!.isAfter(normalizedSince),
        )
        .toList(growable: false);
    final List<CloudTransactionRow> transactions = _transactionsFor(user.id)
        .values
        .where(
          (CloudTransactionRow r) =>
              normalizedSince == null ||
              r.serverUpdatedAt!.isAfter(normalizedSince),
        )
        .toList(growable: false);

    DateTime? cursor = normalizedSince;
    for (final CloudKhataRow r in _khatasFor(user.id).values) {
      final DateTime ts = r.serverUpdatedAt!;
      if (cursor == null || ts.isAfter(cursor)) {
        cursor = ts;
      }
    }
    for (final CloudTransactionRow r in _transactionsFor(user.id).values) {
      final DateTime ts = r.serverUpdatedAt!;
      if (cursor == null || ts.isAfter(cursor)) {
        cursor = ts;
      }
    }
    cursor ??= _serverClock;

    return CloudChangeSet(
      khatas: khatas,
      transactions: transactions,
      cursor: cursor,
    );
  }

  Future<void> dispose() async {
    await _userController.close();
  }

  DateTime _tickServerClock() {
    _serverClock = _serverClock.add(const Duration(seconds: 1));
    return _serverClock;
  }

  void _throwIfFaultInjected() {
    if (offline) {
      throw const CloudOfflineException();
    }
    final Object? err = nextError;
    if (err != null) {
      nextError = null;
      if (err is Exception) throw err;
      if (err is Error) throw err;
      throw Exception(err.toString());
    }
  }

  CloudUser _requireSignedIn() {
    final CloudUser? user = _currentUser;
    if (user == null) {
      throw StateError('Not signed in');
    }
    return user;
  }

  Map<String, CloudKhataRow> _khatasFor(String userId) =>
      _khatasByUser.putIfAbsent(userId, () => <String, CloudKhataRow>{});

  Map<String, CloudTransactionRow> _transactionsFor(String userId) =>
      _transactionsByUser.putIfAbsent(
        userId,
        () => <String, CloudTransactionRow>{},
      );

  static bool _keepExistingKhata(CloudKhataRow oldRow, CloudKhataRow newRow) {
    if (newRow.updatedAt.isBefore(oldRow.updatedAt)) return true;
    if (newRow.updatedAt.isAtSameMomentAs(oldRow.updatedAt) &&
        oldRow.deletedAt != null &&
        newRow.deletedAt == null) {
      return true;
    }
    return false;
  }

  static bool _keepExistingTransaction(
    CloudTransactionRow oldRow,
    CloudTransactionRow newRow,
  ) {
    if (newRow.updatedAt.isBefore(oldRow.updatedAt)) return true;
    if (newRow.updatedAt.isAtSameMomentAs(oldRow.updatedAt) &&
        oldRow.deletedAt != null &&
        newRow.deletedAt == null) {
      return true;
    }
    return false;
  }
}
