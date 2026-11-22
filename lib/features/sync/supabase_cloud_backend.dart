/// Live Supabase implementation of [CloudBackend] for Khoroch Diary B5.
///
/// Always receives an injected [SupabaseClient] and never touches
/// `Supabase.instance`. Maps the `khatas` and `transactions` tables in
/// snake_case, keeps timestamps in UTC ISO-8601, omits `server_updated_at` on
/// outbound upserts so the database trigger stamps it, pages pulls via
/// `range()`, converts network/connectivity failures into
/// [CloudOfflineException], and strips secrets from rethrown errors.
library;

import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'cloud_backend.dart';

typedef OAuthLauncher = Future<bool> Function({
  required String? redirectTo,
  required LaunchMode launchMode,
});

/// Sanitized remote backend failure containing no tokens, API keys, or query
/// credentials.
final class CloudBackendException implements Exception {
  const CloudBackendException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SupabaseCloudBackend implements CloudBackend {
  SupabaseCloudBackend({
    required this.client,
    this.redirectTo,
    this.signInTimeout = const Duration(minutes: 3),
    this.requestTimeout = const Duration(seconds: 30),
    this.pageSize = 500,
    OAuthLauncher? oauthLauncher,
  }) : _customOAuthLauncher = oauthLauncher {
    if (signInTimeout <= Duration.zero) {
      throw ArgumentError.value(
        signInTimeout,
        'signInTimeout',
        'must be positive',
      );
    }
    if (requestTimeout <= Duration.zero) {
      throw ArgumentError.value(
        requestTimeout,
        'requestTimeout',
        'must be positive',
      );
    }
    if (pageSize <= 0) {
      throw ArgumentError.value(pageSize, 'pageSize', 'must be positive');
    }
  }

  final SupabaseClient client;
  final String? redirectTo;
  final Duration signInTimeout;
  final Duration requestTimeout;
  final int pageSize;
  final OAuthLauncher? _customOAuthLauncher;

  @override
  CloudUser? get currentUser => _mapUser(client.auth.currentUser);

  @override
  Stream<CloudUser?> get userChanges {
    return client.auth.onAuthStateChange
        .map((AuthState state) => _mapUser(state.session?.user))
        .handleError((Object _) {
          // Transient token-refresh errors on GoTrue's stream must not surface
          // as uncaught zone errors in UI/engine listeners.
        });
  }

  @override
  Future<CloudUser?> signInWithGoogle() async {
    final Completer<CloudUser?> completer = Completer<CloudUser?>();
    late final StreamSubscription<AuthState> subscription;
    subscription = client.auth.onAuthStateChange.listen(
      (AuthState state) {
        final CloudUser? signedIn = _mapUser(state.session?.user);
        if (signedIn != null && !completer.isCompleted) {
          completer.complete(signedIn);
        }
      },
      onError: (Object error) {
        if (!completer.isCompleted) {
          completer.completeError(_normalizeError(error));
        }
      },
    );

    Timer? timer;
    try {
      final OAuthLauncher? customLauncher = _customOAuthLauncher;
      final bool launched = customLauncher != null
          ? await customLauncher(
              redirectTo: redirectTo,
              launchMode: LaunchMode.externalApplication,
            ).timeout(requestTimeout)
          : await client.auth
                .signInWithOAuth(
                  OAuthProvider.google,
                  redirectTo: redirectTo,
                  authScreenLaunchMode: LaunchMode.externalApplication,
                )
                .timeout(requestTimeout);
      if (!launched) {
        return null;
      }

      final CloudUser? immediate = currentUser;
      if (immediate != null && !completer.isCompleted) {
        completer.complete(immediate);
      } else if (!completer.isCompleted) {
        timer = Timer(signInTimeout, () {
          if (!completer.isCompleted) {
            completer.complete(null);
          }
        });
      }

      return await completer.future;
    } catch (error) {
      throw _normalizeError(error);
    } finally {
      timer?.cancel();
      await subscription.cancel();
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await client.auth
          .signOut(scope: SignOutScope.local)
          .timeout(requestTimeout);
    } on CloudOfflineException {
      // SignOutScope.local clears the local session synchronously before any
      // best-effort token revocation call; if the device is offline, treat the
      // local sign-out as succeeded once the local session is gone.
      if (client.auth.currentUser != null) rethrow;
    } catch (error) {
      if (client.auth.currentUser == null && _isOfflineError(error)) {
        return;
      }
      throw _normalizeError(error);
    }
  }

  @override
  Future<void> deleteAccount() async {
    if (currentUser == null) {
      throw StateError('Cannot delete an account while signed out.');
    }

    try {
      final FunctionResponse response = await client.functions
          .invoke('delete-account')
          .timeout(requestTimeout);
      if (response.status < 200 || response.status >= 300) {
        throw const CloudBackendException(
          'Could not delete the cloud account. Please try again.',
        );
      }
      // The Edge Function has already deleted auth.users and cascading cloud
      // rows. Clear this device's session without making another network call.
      await client.auth.signOut(scope: SignOutScope.local);
    } catch (error) {
      throw _normalizeError(error);
    }
  }

  @override
  Future<List<CloudKhataRow>> upsertKhatas(List<CloudKhataRow> rows) async {
    final CloudUser user = _requireSignedInUser();
    if (rows.isEmpty) return const <CloudKhataRow>[];

    final List<Map<String, dynamic>> payload = rows
        .map((CloudKhataRow row) => _khataToJson(row, userId: user.id))
        .toList(growable: false);

    try {
      final List<Map<String, dynamic>> response = await client
          .from('khatas')
          .upsert(payload, onConflict: 'user_id,id')
          .select()
          .timeout(requestTimeout);
      return List<CloudKhataRow>.unmodifiable(response.map(_khataFromJson));
    } catch (error) {
      throw _normalizeError(error);
    }
  }

  @override
  Future<List<CloudTransactionRow>> upsertTransactions(
    List<CloudTransactionRow> rows,
  ) async {
    final CloudUser user = _requireSignedInUser();
    if (rows.isEmpty) return const <CloudTransactionRow>[];

    final List<Map<String, dynamic>> payload = rows
        .map(
          (CloudTransactionRow row) => _transactionToJson(row, userId: user.id),
        )
        .toList(growable: false);

    try {
      final List<Map<String, dynamic>> response = await client
          .from('transactions')
          .upsert(payload, onConflict: 'user_id,id')
          .select()
          .timeout(requestTimeout);
      return List<CloudTransactionRow>.unmodifiable(
        response.map(_transactionFromJson),
      );
    } catch (error) {
      throw _normalizeError(error);
    }
  }

  @override
  Future<CloudChangeSet> fetchChanges(DateTime? since) async {
    _requireSignedInUser();
    final DateTime? normalizedSince = since?.toUtc();
    final String? sinceIso = normalizedSince?.toIso8601String();

    try {
      final List<Map<String, dynamic>> rawKhatas = await _fetchPagedRows(
        table: 'khatas',
        sinceIso: sinceIso,
      );
      final List<Map<String, dynamic>> rawTransactions = await _fetchPagedRows(
        table: 'transactions',
        sinceIso: sinceIso,
      );

      final List<CloudKhataRow> khatas = rawKhatas
          .map(_khataFromJson)
          .toList(growable: false);
      final List<CloudTransactionRow> transactions = rawTransactions
          .map(_transactionFromJson)
          .toList(growable: false);

      DateTime? highest = normalizedSince;
      void observe(DateTime? ts) {
        if (ts == null) return;
        final DateTime utc = ts.toUtc();
        final DateTime? current = highest;
        if (current == null || utc.isAfter(current)) {
          highest = utc;
        }
      }

      for (final CloudKhataRow row in khatas) {
        observe(row.serverUpdatedAt);
      }
      for (final CloudTransactionRow row in transactions) {
        observe(row.serverUpdatedAt);
      }

      return CloudChangeSet(
        khatas: khatas,
        transactions: transactions,
        cursor: highest,
      );
    } catch (error) {
      throw _normalizeError(error);
    }
  }

  Future<List<Map<String, dynamic>>> _fetchPagedRows({
    required String table,
    required String? sinceIso,
  }) async {
    // Keep only the latest version if a row is updated after an earlier page
    // and reappears later. The server schema makes the timestamp non-null, but
    // the null branch also handles older or test servers defensively.
    final Map<String, Map<String, dynamic>> collected =
        <String, Map<String, dynamic>>{};
    String? cursorId;
    String? cursorTimestamp;

    while (true) {
      PostgrestFilterBuilder<List<Map<String, dynamic>>> filter = client
          .from(table)
          .select();
      if (sinceIso != null) {
        filter = filter.gt('server_updated_at', sinceIso);
      }
      if (cursorId != null) {
        if (cursorTimestamp == null) {
          filter = filter
              .isFilter('server_updated_at', null)
              .gt('id', cursorId);
        } else {
          final String timestamp = _postgrestQuoted(cursorTimestamp);
          final String id = _postgrestQuoted(cursorId);
          filter = filter.or(
            'server_updated_at.gt.$timestamp,'
            'and(server_updated_at.eq.$timestamp,id.gt.$id)'
            '${sinceIso == null ? ',server_updated_at.is.null' : ''}',
          );
        }
      }
      final List<Map<String, dynamic>> page = await filter
          .order('server_updated_at', ascending: true)
          .order('id', ascending: true)
          .limit(pageSize)
          .timeout(requestTimeout);

      for (final Map<String, dynamic> row in page) {
        final Object? id = row['id'];
        if (id is! String || id.isEmpty) {
          throw const FormatException('Pull row has no id');
        }
        collected[id] = row;
      }
      if (page.length < pageSize) break;

      final Map<String, dynamic> last = page.last;
      final String nextId = last['id'] as String;
      final String? nextTimestamp = last['server_updated_at'] as String?;
      // A broken server response must not turn sync into an infinite loop.
      if (cursorId == nextId && cursorTimestamp == nextTimestamp) {
        throw const FormatException('Pull cursor did not advance');
      }
      cursorId = nextId;
      cursorTimestamp = nextTimestamp;
    }

    return collected.values.toList(growable: false);
  }

  /// Quote PostgREST filter values so punctuation in server data cannot alter
  /// the cursor expression. URI encoding is handled by the client library.
  static String _postgrestQuoted(String value) {
    final String escaped = value
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"');
    return '"$escaped"';
  }

  CloudUser _requireSignedInUser() {
    final CloudUser? user = currentUser;
    if (user == null) {
      throw StateError('Cannot sync while signed out.');
    }
    return user;
  }

  static CloudUser? _mapUser(User? user) {
    if (user == null) return null;
    final String id = user.id.trim();
    final String? email = user.email?.trim();
    if (id.isEmpty || email == null || email.isEmpty) {
      return null;
    }
    return CloudUser(id: id, email: email);
  }

  static Map<String, dynamic> _khataToJson(
    CloudKhataRow row, {
    required String userId,
  }) {
    // Include every client-writable column from the migration in snake_case
    // with UTC ISO-8601 timestamps, and NEVER include `server_updated_at`.
    return <String, dynamic>{
      'user_id': userId,
      'id': row.id,
      'name': row.name,
      'opening_balance_paise': row.openingBalancePaise,
      'currency': row.currency,
      'sort_order': row.sortOrder,
      'created_at': row.createdAt.toUtc().toIso8601String(),
      'updated_at': row.updatedAt.toUtc().toIso8601String(),
      'deleted_at': row.deletedAt?.toUtc().toIso8601String(),
    };
  }

  static CloudKhataRow _khataFromJson(Map<String, dynamic> json) {
    return CloudKhataRow(
      userId: _readOptionalString(json['user_id']),
      id: _readRequiredString(json, 'id'),
      name: _readRequiredString(json, 'name'),
      openingBalancePaise: _readInt(json, 'opening_balance_paise'),
      currency: _readOptionalString(json['currency']) ?? 'INR',
      sortOrder: json['sort_order'] == null ? 0 : _readInt(json, 'sort_order'),
      createdAt: _readUtcDateTime(json, 'created_at'),
      updatedAt: _readUtcDateTime(json, 'updated_at'),
      deletedAt: _readOptionalUtcDateTime(json['deleted_at']),
      serverUpdatedAt: _readOptionalUtcDateTime(json['server_updated_at']),
    );
  }

  static Map<String, dynamic> _transactionToJson(
    CloudTransactionRow row, {
    required String userId,
  }) {
    // Include every client-writable column from the migration in snake_case
    // with UTC ISO-8601 timestamps, and NEVER include `server_updated_at`.
    return <String, dynamic>{
      'user_id': userId,
      'id': row.id,
      'khata_id': row.khataId,
      'type': row.type.wireValue,
      'amount_paise': row.amountPaise,
      'category_id': row.categoryId,
      'description': row.description,
      'occurred_at': row.occurredAt.toUtc().toIso8601String(),
      'note_session_id': row.noteSessionId,
      'created_at': row.createdAt.toUtc().toIso8601String(),
      'updated_at': row.updatedAt.toUtc().toIso8601String(),
      'deleted_at': row.deletedAt?.toUtc().toIso8601String(),
    };
  }

  static CloudTransactionRow _transactionFromJson(Map<String, dynamic> json) {
    return CloudTransactionRow(
      userId: _readOptionalString(json['user_id']),
      id: _readRequiredString(json, 'id'),
      khataId: _readRequiredString(json, 'khata_id'),
      type: CloudTransactionType.fromWire(_readRequiredString(json, 'type')),
      amountPaise: _readInt(json, 'amount_paise'),
      categoryId: _readRequiredString(json, 'category_id'),
      description: _readOptionalString(
        json['description'],
        preserveEmpty: true,
      ),
      occurredAt: _readUtcDateTime(json, 'occurred_at'),
      noteSessionId: _readOptionalString(json['note_session_id']),
      createdAt: _readUtcDateTime(json, 'created_at'),
      updatedAt: _readUtcDateTime(json, 'updated_at'),
      deletedAt: _readOptionalUtcDateTime(json['deleted_at']),
      serverUpdatedAt: _readOptionalUtcDateTime(json['server_updated_at']),
    );
  }

  static String _readRequiredString(Map<String, dynamic> json, String field) {
    final Object? value = json[field];
    if (value is String && value.trim().isNotEmpty) {
      return value;
    }
    throw FormatException('Missing or invalid string column "$field".');
  }

  static String? _readOptionalString(
    Object? value, {
    bool preserveEmpty = false,
  }) {
    if (value == null) return null;
    if (value is String) {
      if (preserveEmpty) return value;
      return value.trim().isEmpty ? null : value;
    }
    return value.toString();
  }

  static int _readInt(Map<String, dynamic> json, String field) {
    final Object? value = json[field];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final int? parsed = int.tryParse(value);
      if (parsed != null) return parsed;
    }
    throw FormatException('Missing or invalid integer column "$field".');
  }

  static DateTime _readUtcDateTime(Map<String, dynamic> json, String field) {
    final DateTime? parsed = _readOptionalUtcDateTime(json[field]);
    if (parsed == null) {
      throw FormatException('Missing or invalid timestamp column "$field".');
    }
    return parsed;
  }

  static DateTime? _readOptionalUtcDateTime(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value.toUtc();
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.parse(value).toUtc();
    }
    throw const FormatException('Invalid timestamp value.');
  }

  static bool _isOfflineError(Object error) {
    final String errorType = error.runtimeType.toString();
    if (error is CloudOfflineException ||
        errorType == 'SocketException' ||
        errorType == 'TlsException' ||
        errorType == 'HandshakeException' ||
        // `package:http`'s ClientException (and its private socket subclass,
        // whose toString also starts with "ClientException") matched without
        // a direct dependency on http — supabase_flutter owns that transport.
        errorType == 'ClientException' ||
        error.toString().startsWith('ClientException') ||
        error is TimeoutException) {
      return true;
    }
    if (error is AuthRetryableFetchException) {
      return true;
    }
    if (error is AuthUnknownException) {
      return _isOfflineError(error.originalError);
    }
    return false;
  }

  static Object _normalizeError(Object error) {
    if (error is CloudOfflineException || error is StateError) {
      return error;
    }
    if (_isOfflineError(error)) {
      return const CloudOfflineException('No internet connection.');
    }
    if (error is PostgrestException) {
      return CloudBackendException(
        _sanitizeMessage(error.message, fallback: 'Cloud sync request failed.'),
      );
    }
    if (error is AuthException) {
      return CloudBackendException(
        _sanitizeMessage(error.message, fallback: 'Authentication failed.'),
      );
    }
    if (error is CloudBackendException) {
      return error;
    }
    return CloudBackendException(
      _sanitizeMessage(
        error.toString(),
        fallback: 'Cloud sync failed. Please try again.',
      ),
    );
  }

  static String _sanitizeMessage(String raw, {required String fallback}) {
    String cleaned = raw
        .replaceFirst(
          RegExp(r'^(Exception|CloudBackendException|FormatException):\s*'),
          '',
        )
        .trim();
    // Redact Bearer tokens, JWT-shaped strings, Supabase key prefixes, and
    // URL query parameters that could carry tokens or codes.
    cleaned = cleaned.replaceAll(
      RegExp(r'Bearer\s+\S+', caseSensitive: false),
      'Bearer [redacted]',
    );
    cleaned = cleaned.replaceAll(
      RegExp(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+'),
      '[redacted]',
    );
    cleaned = cleaned.replaceAll(
      RegExp(r'\bsb_(?:publishable|secret)_[A-Za-z0-9_-]+'),
      '[redacted]',
    );
    cleaned = cleaned.replaceAll(
      RegExp(
        r'([?&](?:apikey|token|access_token|refresh_token|code)=)[^&\s]+',
        caseSensitive: false,
      ),
      r'$1[redacted]',
    );
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty) {
      return fallback;
    }
    if (cleaned.runes.length > 140) {
      return '${String.fromCharCodes(cleaned.runes.take(139))}…';
    }
    return cleaned;
  }
}
