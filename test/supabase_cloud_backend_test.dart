import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:khoroch_diary/features/sync/cloud_backend.dart';
import 'package:khoroch_diary/features/sync/supabase_cloud_backend.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MemoryGotrueStorage extends GotrueAsyncStorage {
  _MemoryGotrueStorage(this.store);

  final Map<String, String> store;

  @override
  Future<String?> getItem({required String key}) async => store[key];

  @override
  Future<void> setItem({required String key, required String value}) async {
    store[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    store.remove(key);
  }
}

String _jwt({required String sub, String? email, int? expSeconds}) {
  String b64(Map<String, dynamic> map) =>
      base64Url.encode(utf8.encode(jsonEncode(map))).replaceAll('=', '');

  final String header = b64(<String, dynamic>{'alg': 'HS256', 'typ': 'JWT'});
  final int exp =
      expSeconds ??
      (DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000) + 3600;
  final String payload = b64(<String, dynamic>{
    'sub': sub,
    'email': ?email,
    'role': 'authenticated',
    'exp': exp,
  });
  return '$header.$payload.testsignature';
}

Map<String, dynamic> _sessionPayload({required String userId, String? email}) {
  return <String, dynamic>{
    'access_token': _jwt(sub: userId, email: email),
    'token_type': 'bearer',
    'expires_in': 3600,
    'refresh_token': 'refresh-$userId',
    'user': <String, dynamic>{
      'id': userId,
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': email,
      'created_at': '2026-11-20T08:00:00Z',
      'app_metadata': const <String, dynamic>{'provider': 'google'},
      'user_metadata': const <String, dynamic>{},
    },
  };
}

SupabaseClient _buildClient(
  Future<http.Response> Function(http.Request request) handler,
) {
  return SupabaseClient(
    'https://example.supabase.co',
    'test-key',
    httpClient: MockClient((http.Request req) async {
      // postgrest parses `response.request!`, which a hand-built response
      // lacks; re-wrap the mock's answer with the request attached.
      final http.Response res = await handler(req);
      return http.Response.bytes(
        res.bodyBytes,
        res.statusCode,
        request: req,
        headers: res.headers,
        isRedirect: res.isRedirect,
        persistentConnection: res.persistentConnection,
        reasonPhrase: res.reasonPhrase,
      );
    }),
    authOptions: AuthClientOptions(
      autoRefreshToken: false,
      pkceAsyncStorage: _MemoryGotrueStorage(<String, String>{}),
    ),
    postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
  );
}

http.Response _jsonResponse(Object body, {int statusCode = 200}) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: const <String, String>{'content-type': 'application/json'},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SupabaseCloudBackend auth & session mapping', () {
    test('maps currentUser and userChanges, treats missing email as signed out, and signs out locally', () async {
      Map<String, dynamic> nextTokenPayload = _sessionPayload(
        userId: 'user-111',
        email: 'alice@example.com',
      );

      final SupabaseClient client = _buildClient((http.Request req) async {
        if (req.url.path.endsWith('/auth/v1/token')) {
          return _jsonResponse(nextTokenPayload);
        }
        if (req.url.path.endsWith('/auth/v1/logout')) {
          return http.Response('', 204);
        }
        return _jsonResponse(<Object>[]);
      });
      addTearDown(client.dispose);

      final SupabaseCloudBackend backend = SupabaseCloudBackend(
        client: client,
        redirectTo: 'com.keshabstudios.khorochdiary://login-callback',
      );

      final List<CloudUser?> observed = <CloudUser?>[];
      final StreamSubscription<CloudUser?> sub = backend.userChanges.listen(
        observed.add,
      );
      addTearDown(sub.cancel);

      expect(backend.currentUser, isNull);

      await client.auth.signInWithPassword(
        email: 'alice@example.com',
        password: 'pw',
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        backend.currentUser,
        CloudUser(id: 'user-111', email: 'alice@example.com'),
      );

      // A session whose user has no email is treated as signed out.
      nextTokenPayload = _sessionPayload(userId: 'user-no-email');
      await client.auth.signInWithPassword(
        email: 'placeholder@example.com',
        password: 'pw',
      );
      await Future<void>.delayed(Duration.zero);
      expect(backend.currentUser, isNull);

      // Sign back in with an email, then signOut() clears session locally.
      nextTokenPayload = _sessionPayload(
        userId: 'user-111',
        email: 'alice@example.com',
      );
      await client.auth.signInWithPassword(
        email: 'alice@example.com',
        password: 'pw',
      );
      await Future<void>.delayed(Duration.zero);
      expect(backend.currentUser?.email, 'alice@example.com');

      await backend.signOut();
      await Future<void>.delayed(Duration.zero);
      expect(backend.currentUser, isNull);
      expect(
        observed,
        containsAllInOrder(<CloudUser?>[
          CloudUser(id: 'user-111', email: 'alice@example.com'),
          null,
          CloudUser(id: 'user-111', email: 'alice@example.com'),
          null,
        ]),
      );
    });

    test('deleteAccount calls the authenticated deletion function and clears local session', () async {
      bool sawDeletion = false;
      String? bearer;
      final SupabaseClient client = _buildClient((http.Request request) async {
        if (request.url.path.endsWith('/auth/v1/token')) {
          return _jsonResponse(
            _sessionPayload(userId: 'delete-user', email: 'delete@example.com'),
          );
        }
        if (request.url.path.endsWith('/functions/v1/delete-account')) {
          sawDeletion = true;
          bearer = request.headers['authorization'];
          return _jsonResponse(<String, dynamic>{'deleted': true});
        }
        return _jsonResponse(<Object>[]);
      });
      addTearDown(client.dispose);
      await client.auth.signInWithPassword(
        email: 'delete@example.com',
        password: 'pw',
      );
      final SupabaseCloudBackend backend = SupabaseCloudBackend(client: client);

      await backend.deleteAccount();

      expect(sawDeletion, isTrue);
      expect(bearer, startsWith('Bearer '));
      expect(backend.currentUser, isNull);
    });

    test('signInWithGoogle launches OAuth with redirectTo & externalApplication, resolves on session, and returns null on timeout', () async {
      const MethodChannel urlLauncherChannel = MethodChannel(
        'plugins.flutter.io/url_launcher',
      );
      final List<MethodCall> launcherCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(urlLauncherChannel, (
            MethodCall call,
          ) async {
            launcherCalls.add(call);
            return true;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(urlLauncherChannel, null);
      });

      final SupabaseClient client = _buildClient((http.Request req) async {
        if (req.url.path.endsWith('/auth/v1/token')) {
          return _jsonResponse(
            _sessionPayload(userId: 'google-uid', email: 'g@example.com'),
          );
        }
        return http.Response('', 204);
      });
      addTearDown(client.dispose);

      // 1. Timeout when no OAuth callback arrives -> returns null (cancelled).
      final SupabaseCloudBackend timeoutBackend = SupabaseCloudBackend(
        client: client,
        redirectTo: 'com.keshabstudios.khorochdiary://login-callback',
        signInTimeout: const Duration(milliseconds: 40),
      );
      final CloudUser? cancelled = await timeoutBackend.signInWithGoogle();
      expect(cancelled, isNull);
      expect(launcherCalls, isNotEmpty);
      final String launchedUrl =
          (launcherCalls.last.arguments as Map<Object?, Object?>)['url']!
              as String;
      final Uri parsedLaunch = Uri.parse(launchedUrl);
      expect(parsedLaunch.path, '/auth/v1/authorize');
      expect(parsedLaunch.queryParameters['provider'], 'google');
      expect(
        parsedLaunch.queryParameters['redirect_to'],
        'com.keshabstudios.khorochdiary://login-callback',
      );

      // 2. Session arrives over onAuthStateChange -> resolves with CloudUser.
      final SupabaseCloudBackend liveBackend = SupabaseCloudBackend(
        client: client,
        redirectTo: 'com.keshabstudios.khorochdiary://login-callback',
        signInTimeout: const Duration(seconds: 5),
      );
      final Future<CloudUser?> signInFuture = liveBackend.signInWithGoogle();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await client.auth.signInWithPassword(
        email: 'g@example.com',
        password: 'pw',
      );
      final CloudUser? resolved = await signInFuture;
      expect(resolved, CloudUser(id: 'google-uid', email: 'g@example.com'));
    });

    test('calls made while signed out throw StateError', () async {
      final SupabaseClient client = _buildClient(
        (http.Request _) async => _jsonResponse(<Object>[]),
      );
      addTearDown(client.dispose);
      final SupabaseCloudBackend backend = SupabaseCloudBackend(client: client);

      await expectLater(
        backend.upsertKhatas(<CloudKhataRow>[]),
        throwsStateError,
      );
      await expectLater(
        backend.upsertTransactions(<CloudTransactionRow>[]),
        throwsStateError,
      );
      await expectLater(backend.fetchChanges(null), throwsStateError);
    });
  });

  group('SupabaseCloudBackend REST push & pull requests', () {
    test('upsertKhatas and upsertTransactions send exact snake_case columns without server_updated_at and map server-returned rows', () async {
      final List<http.Request> restRequests = <http.Request>[];
      final DateTime serverTime1 = DateTime.utc(2026, 11, 20, 10, 5);
      final DateTime serverTime2 = DateTime.utc(2026, 11, 20, 10, 6);

      final SupabaseClient client = _buildClient((http.Request req) async {
        if (req.url.path.endsWith('/auth/v1/token')) {
          return _jsonResponse(
            _sessionPayload(userId: 'uid-42', email: 'sync@example.com'),
          );
        }
        restRequests.add(req);
        if (req.url.path == '/rest/v1/khatas') {
          final List<dynamic> decoded = jsonDecode(req.body) as List<dynamic>;
          final Map<String, dynamic> sent = Map<String, dynamic>.from(
            decoded.single as Map,
          );
          // Simulate trigger keeping a newer server copy on upsert!
          return _jsonResponse(<Map<String, dynamic>>[
            <String, dynamic>{
              ...sent,
              'name': 'Server Kept Newer Name',
              'updated_at': '2026-11-20T10:04:00.000Z',
              'server_updated_at': serverTime1.toIso8601String(),
            },
          ]);
        }
        if (req.url.path == '/rest/v1/transactions') {
          final List<dynamic> decoded = jsonDecode(req.body) as List<dynamic>;
          final Map<String, dynamic> sent = Map<String, dynamic>.from(
            decoded.single as Map,
          );
          return _jsonResponse(<Map<String, dynamic>>[
            <String, dynamic>{
              ...sent,
              'server_updated_at': serverTime2.toIso8601String(),
            },
          ]);
        }
        return _jsonResponse(<Object>[]);
      });
      addTearDown(client.dispose);

      await client.auth.signInWithPassword(
        email: 'sync@example.com',
        password: 'pw',
      );
      final SupabaseCloudBackend backend = SupabaseCloudBackend(client: client);

      final List<CloudKhataRow> storedKhatas = await backend.upsertKhatas(
        <CloudKhataRow>[
          CloudKhataRow(
            id: 'personal',
            name: 'Local Name',
            openingBalancePaise: 50000,
            currency: 'INR',
            sortOrder: 1,
            createdAt: DateTime.utc(2026, 11, 20, 9, 0),
            updatedAt: DateTime.utc(2026, 11, 20, 9, 30),
            serverUpdatedAt: DateTime.utc(2026, 11, 20, 9, 30),
          ),
        ],
      );

      expect(restRequests, hasLength(1));
      final http.Request khataReq = restRequests.single;
      expect(khataReq.method, 'POST');
      expect(khataReq.url.path, '/rest/v1/khatas');
      expect(khataReq.url.queryParameters['on_conflict'], 'user_id,id');
      expect(khataReq.url.queryParameters['select'], '*');
      expect(
        khataReq.headers['Prefer'],
        contains('resolution=merge-duplicates'),
      );
      expect(khataReq.headers['Prefer'], contains('return=representation'));

      final Map<String, dynamic> khataBody = Map<String, dynamic>.from(
        (jsonDecode(khataReq.body) as List<dynamic>).single as Map,
      );
      expect(
        khataBody.keys.toSet(),
        equals(<String>{
          'user_id',
          'id',
          'name',
          'opening_balance_paise',
          'currency',
          'sort_order',
          'created_at',
          'updated_at',
          'deleted_at',
        }),
      );
      expect(khataBody.containsKey('server_updated_at'), isFalse);
      expect(khataBody['user_id'], 'uid-42');
      expect(khataBody['opening_balance_paise'], 50000);
      expect(khataBody['deleted_at'], isNull);

      expect(storedKhatas, hasLength(1));
      expect(storedKhatas.single.userId, 'uid-42');
      expect(storedKhatas.single.name, 'Server Kept Newer Name');
      expect(storedKhatas.single.serverUpdatedAt, serverTime1);

      // Push transaction with tombstone & noteSessionId.
      final DateTime deletedAt = DateTime.utc(2026, 11, 20, 10, 2);
      final List<CloudTransactionRow> storedTx = await backend
          .upsertTransactions(<CloudTransactionRow>[
            CloudTransactionRow(
              id: 'tx-1',
              khataId: 'personal',
              type: CloudTransactionType.expense,
              amountPaise: 12500,
              categoryId: 'Food',
              description: 'Tea & snacks',
              occurredAt: DateTime.utc(2026, 11, 20, 9, 45),
              noteSessionId: 'session-9',
              createdAt: DateTime.utc(2026, 11, 20, 9, 45),
              updatedAt: deletedAt,
              deletedAt: deletedAt,
              serverUpdatedAt: DateTime.utc(2026, 11, 20, 9, 50),
            ),
          ]);

      expect(restRequests, hasLength(2));
      final http.Request txReq = restRequests.last;
      expect(txReq.method, 'POST');
      expect(txReq.url.path, '/rest/v1/transactions');
      expect(txReq.url.queryParameters['on_conflict'], 'user_id,id');

      final Map<String, dynamic> txBody = Map<String, dynamic>.from(
        (jsonDecode(txReq.body) as List<dynamic>).single as Map,
      );
      expect(
        txBody.keys.toSet(),
        equals(<String>{
          'user_id',
          'id',
          'khata_id',
          'type',
          'amount_paise',
          'category_id',
          'description',
          'occurred_at',
          'note_session_id',
          'created_at',
          'updated_at',
          'deleted_at',
        }),
      );
      expect(txBody.containsKey('server_updated_at'), isFalse);
      expect(txBody['user_id'], 'uid-42');
      expect(txBody['type'], 'expense');
      expect(txBody['amount_paise'], 12500);
      expect(txBody['deleted_at'], deletedAt.toIso8601String());

      expect(storedTx, hasLength(1));
      expect(storedTx.single.serverUpdatedAt, serverTime2);
      expect(storedTx.single.deletedAt, deletedAt);
      expect(storedTx.single.noteSessionId, 'session-9');
    });

    test('fetchChanges pages by timestamp and id and tracks cursor', () async {
      final List<Uri> requestedUrls = <Uri>[];
      final DateTime since = DateTime.utc(2026, 11, 20, 8, 0);
      final DateTime t1 = DateTime.utc(2026, 11, 20, 8, 10);
      final DateTime t2 = DateTime.utc(2026, 11, 20, 8, 20);
      final DateTime t3 = DateTime.utc(2026, 11, 20, 8, 35);

      bool returnEmpty = false;

      final SupabaseClient client = _buildClient((http.Request req) async {
        if (req.url.path.endsWith('/auth/v1/token')) {
          return _jsonResponse(
            _sessionPayload(userId: 'uid-42', email: 'sync@example.com'),
          );
        }
        requestedUrls.add(req.url);
        if (returnEmpty) {
          return _jsonResponse(<Object>[]);
        }

        if (req.url.path == '/rest/v1/khatas') {
          if (!req.url.queryParameters.containsKey('or')) {
            return _jsonResponse(<Map<String, dynamic>>[
              <String, dynamic>{
                'user_id': 'uid-42',
                'id': 'k-1',
                'name': 'Personal Khata',
                'opening_balance_paise': 0,
                'currency': 'INR',
                'sort_order': 0,
                'created_at': t1.toIso8601String(),
                'updated_at': t1.toIso8601String(),
                'deleted_at': null,
                'server_updated_at': t1.toIso8601String(),
              },
              <String, dynamic>{
                'user_id': 'uid-42',
                'id': 'k-2',
                'name': 'Shop',
                'opening_balance_paise': 10000,
                'currency': 'INR',
                'sort_order': 1,
                'created_at': t2.toIso8601String(),
                'updated_at': t2.toIso8601String(),
                'deleted_at': null,
                'server_updated_at': t2.toIso8601String(),
              },
            ]);
          }
          // Second page returns 1 row (< pageSize=2) -> terminates paging!
          return _jsonResponse(<Map<String, dynamic>>[
            <String, dynamic>{
              'user_id': 'uid-42',
              'id': 'k-3',
              'name': 'Archived Khata',
              'opening_balance_paise': 0,
              'currency': 'INR',
              'sort_order': 2,
              'created_at': t2.toIso8601String(),
              'updated_at': t2.toIso8601String(),
              'deleted_at': t2.toIso8601String(),
              'server_updated_at': t2.toIso8601String(),
            },
          ]);
        }

        if (req.url.path == '/rest/v1/transactions') {
          return _jsonResponse(<Map<String, dynamic>>[
            <String, dynamic>{
              'user_id': 'uid-42',
              'id': 'tx-99',
              'khata_id': 'k-1',
              'type': 'income',
              'amount_paise': 9900,
              'category_id': 'Salary',
              'description': 'Bonus',
              'occurred_at': t3.toIso8601String(),
              'note_session_id': null,
              'created_at': t3.toIso8601String(),
              'updated_at': t3.toIso8601String(),
              'deleted_at': null,
              'server_updated_at': t3.toIso8601String(),
            },
          ]);
        }
        return _jsonResponse(<Object>[]);
      });
      addTearDown(client.dispose);

      await client.auth.signInWithPassword(
        email: 'sync@example.com',
        password: 'pw',
      );
      final SupabaseCloudBackend backend = SupabaseCloudBackend(
        client: client,
        pageSize: 2,
      );

      final CloudChangeSet firstPull = await backend.fetchChanges(since);
      expect(firstPull.khatas.map((CloudKhataRow k) => k.id), <String>[
        'k-1',
        'k-2',
        'k-3',
      ]);
      expect(firstPull.khatas.last.isArchived, isTrue);
      expect(firstPull.transactions, hasLength(1));
      expect(firstPull.transactions.single.id, 'tx-99');
      expect(firstPull.cursor, t3);

      // Verify query parameters on the two khata page requests and one tx page.
      expect(requestedUrls, hasLength(3));
      expect(
        requestedUrls[0].queryParameters['server_updated_at'],
        'gt.${since.toIso8601String()}',
      );
      expect(
        requestedUrls[0].queryParameters['order'],
        'server_updated_at.asc.nullslast,id.asc.nullslast',
      );
      expect(requestedUrls[0].queryParameters.containsKey('offset'), isFalse);
      expect(requestedUrls[0].queryParameters['limit'], '2');

      expect(requestedUrls[1].queryParameters.containsKey('offset'), isFalse);
      expect(
        requestedUrls[1].queryParameters['or'],
        '(server_updated_at.gt."${t2.toIso8601String()}",'
        'and(server_updated_at.eq."${t2.toIso8601String()}",id.gt."k-2"))',
      );
      expect(requestedUrls[1].queryParameters['limit'], '2');

      expect(requestedUrls[2].path, '/rest/v1/transactions');
      expect(requestedUrls[2].queryParameters.containsKey('offset'), isFalse);
      expect(requestedUrls[2].queryParameters['limit'], '2');

      // When since is null, no server_updated_at filter is sent; when nothing
      // comes back with non-null `since`, `since` is preserved as cursor.
      requestedUrls.clear();
      returnEmpty = true;
      final CloudChangeSet emptyWithSince = await backend.fetchChanges(t3);
      expect(emptyWithSince.khatas, isEmpty);
      expect(emptyWithSince.transactions, isEmpty);
      expect(emptyWithSince.cursor, t3);

      requestedUrls.clear();
      final CloudChangeSet emptyInitial = await backend.fetchChanges(null);
      expect(emptyInitial.cursor, isNull);
      expect(
        requestedUrls.first.queryParameters.containsKey('server_updated_at'),
        isFalse,
      );
    });
  });

  test('pull deduplicates a row updated between keyset pages', () async {
    final DateTime t1 = DateTime.utc(2026, 11, 20, 9);
    final DateTime t2 = DateTime.utc(2026, 11, 20, 10);
    final List<Uri> khataRequests = <Uri>[];

    Map<String, dynamic> khata(String id, DateTime stamp, String name) =>
        <String, dynamic>{
          'user_id': 'uid-42',
          'id': id,
          'name': name,
          'opening_balance_paise': 0,
          'currency': 'INR',
          'sort_order': 0,
          'created_at': t1.toIso8601String(),
          'updated_at': stamp.toIso8601String(),
          'deleted_at': null,
          'server_updated_at': stamp.toIso8601String(),
        };

    final SupabaseClient client = _buildClient((http.Request req) async {
      if (req.url.path.endsWith('/auth/v1/token')) {
        return _jsonResponse(
          _sessionPayload(userId: 'uid-42', email: 'sync@example.com'),
        );
      }
      if (!req.url.path.endsWith('/khatas')) return _jsonResponse(<Object>[]);
      khataRequests.add(req.url);
      switch (khataRequests.length) {
        case 1:
          return _jsonResponse(<Map<String, dynamic>>[
            khata('k-1', t1, 'Old'),
            khata('k-2', t1, 'Second'),
          ]);
        case 2:
          return _jsonResponse(<Map<String, dynamic>>[
            khata('k-3', t1, 'Third'),
            khata('k-1', t2, 'Updated'),
          ]);
        default:
          return _jsonResponse(<Object>[]);
      }
    });
    addTearDown(client.dispose);
    await client.auth.signInWithPassword(
      email: 'sync@example.com',
      password: 'pw',
    );

    final CloudChangeSet changes = await SupabaseCloudBackend(
      client: client,
      pageSize: 2,
    ).fetchChanges(null);
    expect(changes.khatas, hasLength(3));
    expect(
      changes.khatas.singleWhere((CloudKhataRow row) => row.id == 'k-1').name,
      'Updated',
    );
    expect(changes.cursor, t2);
    expect(khataRequests, hasLength(3));
    expect(
      khataRequests.every(
        (Uri uri) => !uri.queryParameters.containsKey('offset'),
      ),
      isTrue,
    );
    expect(khataRequests[1].queryParameters['or'], contains('id.gt."k-2"'));
    expect(khataRequests[2].queryParameters['or'], contains('id.gt."k-1"'));
  });

  test('pull advances by id through legacy null timestamps', () async {
    final List<Uri> requests = <Uri>[];
    final DateTime created = DateTime.utc(2026, 1, 1);
    Map<String, dynamic> khata(String id) => <String, dynamic>{
      'user_id': 'uid-42',
      'id': id,
      'name': id,
      'opening_balance_paise': 0,
      'currency': 'INR',
      'sort_order': 0,
      'created_at': created.toIso8601String(),
      'updated_at': created.toIso8601String(),
      'deleted_at': null,
      'server_updated_at': null,
    };

    final SupabaseClient client = _buildClient((http.Request req) async {
      if (req.url.path.endsWith('/auth/v1/token')) {
        return _jsonResponse(
          _sessionPayload(userId: 'uid-42', email: 'sync@example.com'),
        );
      }
      if (!req.url.path.endsWith('/khatas')) return _jsonResponse(<Object>[]);
      requests.add(req.url);
      return _jsonResponse(
        requests.length == 1
            ? <Map<String, dynamic>>[khata('k-1'), khata('k-2')]
            : <Map<String, dynamic>>[khata('k-3')],
      );
    });
    addTearDown(client.dispose);
    await client.auth.signInWithPassword(
      email: 'sync@example.com',
      password: 'pw',
    );

    final CloudChangeSet changes = await SupabaseCloudBackend(
      client: client,
      pageSize: 2,
    ).fetchChanges(null);
    expect(changes.khatas.map((CloudKhataRow row) => row.id), <String>[
      'k-1',
      'k-2',
      'k-3',
    ]);
    expect(requests[1].queryParameters['server_updated_at'], 'is.null');
    expect(requests[1].queryParameters['id'], 'gt.k-2');
  });

  group('SupabaseCloudBackend offline & error normalization', () {
    test('maps SocketException, ClientException, TimeoutException, and AuthRetryableFetchException to CloudOfflineException and strips secrets from other errors', () async {
      Object? nextFailure;
      int nextStatusCode = 200;
      Object nextJsonBody = <Object>[];

      final SupabaseClient client = _buildClient((http.Request req) async {
        if (req.url.path.endsWith('/auth/v1/token')) {
          if (nextFailure case final Object failure) {
            throw failure;
          }
          return _jsonResponse(
            _sessionPayload(userId: 'uid-1', email: 'u@example.com'),
          );
        }
        if (nextFailure case final Object err) {
          if (err is Future<http.Response> Function()) {
            return err();
          }
          throw err;
        }
        return _jsonResponse(nextJsonBody, statusCode: nextStatusCode);
      });
      addTearDown(client.dispose);

      final SupabaseCloudBackend backend = SupabaseCloudBackend(
        client: client,
        requestTimeout: const Duration(milliseconds: 40),
      );

      // Auth network error -> GoTrue throws AuthRetryableFetchException ->
      // signInWithGoogle surfaces CloudOfflineException when launcher throws it.
      final SupabaseCloudBackend authOfflineBackend = SupabaseCloudBackend(
        client: client,
        oauthLauncher:
            ({
              required String? redirectTo,
              required LaunchMode launchMode,
            }) async {
              throw AuthRetryableFetchException(message: 'Network unreachable');
            },
      );
      await expectLater(
        authOfflineBackend.signInWithGoogle(),
        throwsA(isA<CloudOfflineException>()),
      );

      // Sign in so we can exercise REST failure modes.
      await client.auth.signInWithPassword(
        email: 'u@example.com',
        password: 'pw',
      );

      // 1. SocketException -> CloudOfflineException
      nextFailure = const SocketException('Failed host lookup');
      await expectLater(
        backend.fetchChanges(null),
        throwsA(isA<CloudOfflineException>()),
      );

      // 2. http.ClientException -> CloudOfflineException
      nextFailure = http.ClientException('Connection reset by peer');
      await expectLater(
        backend.fetchChanges(null),
        throwsA(isA<CloudOfflineException>()),
      );

      // 3. Request timeout -> CloudOfflineException
      nextFailure = () async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return _jsonResponse(<Object>[]);
      };
      await expectLater(
        backend.fetchChanges(null),
        throwsA(isA<CloudOfflineException>()),
      );

      // 4. Non-network PostgrestException -> rethrown with secrets stripped!
      nextFailure = null;
      nextStatusCode = 403;
      nextJsonBody = <String, dynamic>{
        'message': 'RLS policy violation for Bearer secret-jwt-token-123 and sb_publishable_abcdef123456 ?apikey=my-secret-key',
        'code': '42501',
      };
      await expectLater(
        backend.fetchChanges(null),
        throwsA(
          predicate<Object>((Object error) {
            final String msg = error.toString();
            return error is! CloudOfflineException &&
                msg.contains('RLS policy violation') &&
                !msg.contains('secret-jwt-token-123') &&
                !msg.contains('sb_publishable_abcdef123456') &&
                !msg.contains('my-secret-key');
          }),
        ),
      );
    });
  });
}
