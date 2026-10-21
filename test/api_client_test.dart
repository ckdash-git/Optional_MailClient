import 'dart:convert';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:optional_mail_client/api/client.dart';
import 'package:optional_mail_client/api/session.dart';

import 'helpers.dart';

void main() {
  group('login', () {
    test('stores tokens in the secure store, never the password', () async {
      final store = MemoryKeyValueStore();
      final session = Session(store);
      await session.load();
      expect(session.status, SessionStatus.signedOut);

      late http.Request sent;
      final api = ApiClient(
        session,
        httpClient: MockClient((req) async {
          sent = req;
          return jsonResponse({
            ...tokensJson('access-1', 'refresh-1'),
            'user': {'id': 'u1', 'email': 'ana@example.com'},
            'account_id': 'acc1',
          });
        }),
      );

      final result = await api.login(
        server: server,
        email: 'ana@example.com',
        password: 'hunter2',
        deviceName: 'Test device',
        platform: 'android',
      );

      expect(result.accountId, 'acc1');
      expect(sent.method, 'POST');
      expect(sent.url.toString(), 'https://master.example.com/v1/auth/login');
      expect(sent.headers.containsKey('Authorization'), isFalse);
      final body = jsonDecode(sent.body) as Map<String, Object?>;
      expect(body, {
        'email': 'ana@example.com',
        'password': 'hunter2',
        'device': {'name': 'Test device', 'platform': 'android'},
      });

      expect(session.isSignedIn, isTrue);
      expect(session.tokens!.accessToken, 'access-1');
      final stored =
          jsonDecode(store.values['tokens']!) as Map<String, Object?>;
      expect(stored['access_token'], 'access-1');
      expect(stored['refresh_token'], 'refresh-1');
      expect(store.values['server_url'], 'https://master.example.com');
      expect(store.values.values.any((v) => v.contains('hunter2')), isFalse);

      // A fresh start restores the session from the store.
      final restored = Session(store);
      await restored.load();
      expect(restored.isSignedIn, isTrue);
      expect(restored.tokens!.refreshToken, 'refresh-1');
      expect(restored.user!.email, 'ana@example.com');
    });

    test('sends manual server settings and username when given', () async {
      final session = Session(MemoryKeyValueStore());
      await session.load();
      late Map<String, Object?> body;
      final api = ApiClient(
        session,
        httpClient: MockClient((req) async {
          body = jsonDecode(req.body) as Map<String, Object?>;
          return jsonResponse({
            ...tokensJson('a', 'r'),
            'user': {'id': 'u1', 'email': 'ana@example.com'},
            'account_id': 'acc1',
          });
        }),
      );
      await api.login(
        server: server,
        email: 'ana@example.com',
        password: 'pw',
        deviceName: 'd',
        platform: 'ios',
        username: 'ana',
        settings: const ServerSettings(
          incoming: ServerEndpoint(
            protocol: IncomingProtocol.pop3,
            host: 'pop.example.com',
            port: 995,
            security: Security.tls,
          ),
          outgoing: ServerEndpoint(
            host: 'smtp.example.com',
            port: 587,
            security: Security.starttls,
          ),
        ),
      );
      expect(body['username'], 'ana');
      expect(body['server'], {
        'incoming': {
          'protocol': 'pop3',
          'host': 'pop.example.com',
          'port': 995,
          'security': 'tls',
        },
        'outgoing': {
          'host': 'smtp.example.com',
          'port': 587,
          'security': 'starttls',
        },
      });
    });

    test('invalid_credentials is reported without a refresh attempt', () async {
      final session = Session(MemoryKeyValueStore());
      await session.load();
      var calls = 0;
      final api = ApiClient(
        session,
        httpClient: MockClient((req) async {
          calls++;
          return errorResponse(401, 'invalid_credentials', 'login failed');
        }),
      );
      await expectLater(
        api.login(
          server: server,
          email: 'ana@example.com',
          password: 'wrong',
          deviceName: 'd',
          platform: 'linux',
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.status, 'status', 401)
              .having((e) => e.code, 'code', 'invalid_credentials'),
        ),
      );
      expect(calls, 1);
      expect(session.isSignedIn, isFalse);
    });
  });

  group('token refresh', () {
    test(
      '401 triggers exactly one refresh for 3 concurrent requests',
      () async {
        final store = MemoryKeyValueStore();
        final session = await signedInSession(
          store,
          access: 'old',
          refresh: 'r1',
        );
        var refreshCalls = 0;
        final authHeaders = <String>[];

        final api = ApiClient(
          session,
          httpClient: MockClient((req) async {
            if (req.url.path == '/v1/auth/refresh') {
              refreshCalls++;
              expect(jsonDecode(req.body), {'refresh_token': 'r1'});
              await Future<void>.delayed(const Duration(milliseconds: 30));
              return jsonResponse(tokensJson('new', 'r2'));
            }
            final auth = req.headers['Authorization']!;
            authHeaders.add(auth);
            if (auth == 'Bearer old') {
              return errorResponse(401, 'unauthorized', 'token expired');
            }
            return jsonResponse(<Object>[]);
          }),
        );

        final results = await Future.wait([
          api.accounts(),
          api.accounts(),
          api.accounts(),
        ]);

        expect(results, everyElement(isEmpty));
        expect(refreshCalls, 1);
        expect(session.tokens!.accessToken, 'new');
        expect(session.tokens!.refreshToken, 'r2');
        expect(authHeaders.where((h) => h == 'Bearer new'), hasLength(3));
        final stored =
            jsonDecode(store.values['tokens']!) as Map<String, Object?>;
        expect(stored['refresh_token'], 'r2');
      },
    );

    test(
      'a token about to expire is refreshed once before the requests',
      () async {
        final session = await signedInSession(
          MemoryKeyValueStore(),
          access: 'old',
          refresh: 'r1',
          expires: DateTime.now().toUtc().add(const Duration(seconds: 5)),
        );
        var refreshCalls = 0;
        final api = ApiClient(
          session,
          httpClient: MockClient((req) async {
            if (req.url.path == '/v1/auth/refresh') {
              refreshCalls++;
              await Future<void>.delayed(const Duration(milliseconds: 10));
              return jsonResponse(tokensJson('new', 'r2'));
            }
            expect(req.headers['Authorization'], 'Bearer new');
            return jsonResponse(<Object>[]);
          }),
        );
        await Future.wait([api.devices(), api.devices(), api.devices()]);
        expect(refreshCalls, 1);
      },
    );

    test('refresh failure signs out and wipes the store', () async {
      final store = MemoryKeyValueStore();
      final session = await signedInSession(
        store,
        access: 'old',
        refresh: 'r1',
      );
      await session.setThemeMode(ThemeMode.dark);
      var wiped = false;
      session.wipeHooks.add(() async => wiped = true);

      final api = ApiClient(
        session,
        httpClient: MockClient((req) async {
          if (req.url.path == '/v1/auth/refresh') {
            return errorResponse(401, 'unauthorized', 'refresh token reused');
          }
          return errorResponse(401, 'unauthorized');
        }),
      );

      await expectLater(
        Future.wait([api.accounts(), api.accounts()]),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'unauthorized'),
        ),
      );
      expect(session.status, SessionStatus.signedOut);
      expect(session.tokens, isNull);
      expect(store.values.containsKey('tokens'), isFalse);
      expect(store.values.containsKey('user'), isFalse);
      // Non-secret preferences survive.
      expect(store.values['server_url'], 'https://master.example.com');
      expect(store.values['theme_mode'], 'dark');
      expect(wiped, isTrue);
    });

    test('a 401 after a successful refresh signs out', () async {
      final session = await signedInSession(
        MemoryKeyValueStore(),
        access: 'old',
      );
      final api = ApiClient(
        session,
        httpClient: MockClient((req) async {
          if (req.url.path == '/v1/auth/refresh') {
            return jsonResponse(tokensJson('new', 'r2'));
          }
          return errorResponse(401, 'unauthorized');
        }),
      );
      await expectLater(api.me(), throwsA(isA<ApiException>()));
      expect(session.isSignedIn, isFalse);
    });

    test('a network error during refresh keeps the session', () async {
      final session = await signedInSession(
        MemoryKeyValueStore(),
        access: 'old',
      );
      final api = ApiClient(
        session,
        httpClient: MockClient((req) async {
          if (req.url.path == '/v1/auth/refresh') {
            throw http.ClientException('offline');
          }
          return errorResponse(401, 'unauthorized');
        }),
      );
      await expectLater(
        api.me(),
        throwsA(
          isA<ApiException>().having((e) => e.isNetwork, 'network', true),
        ),
      );
      expect(session.isSignedIn, isTrue);
      expect(session.tokens!.refreshToken, 'refresh-1');
    });
  });

  group('errors', () {
    Future<ApiException> errorFor(http.Response response) async {
      final session = await signedInSession(MemoryKeyValueStore());
      final api = ApiClient(
        session,
        httpClient: MockClient((req) async => response),
      );
      try {
        await api.accounts();
      } on ApiException catch (e) {
        return e;
      }
      fail('expected an ApiException');
    }

    test('parses the error envelope', () async {
      final e = await errorFor(errorResponse(409, 'conflict', 'etag mismatch'));
      expect(e.status, 409);
      expect(e.code, 'conflict');
      expect(e.message, 'etag mismatch');
      expect(e.isConflict, isTrue);
    });

    test('reads Retry-After on 429', () async {
      final e = await errorFor(
        errorResponse(429, 'rate_limited', 'slow down', {'retry-after': '30'}),
      );
      expect(e.code, 'rate_limited');
      expect(e.retryAfter, const Duration(seconds: 30));
      expect(e.userMessage, contains('30'));
    });

    test('falls back to the status code for non-JSON bodies', () async {
      final e = await errorFor(http.Response('<html>Bad gateway</html>', 502));
      expect(e.status, 502);
      expect(e.code, 'upstream_error');
    });

    test('transport failures become network errors', () async {
      final session = await signedInSession(MemoryKeyValueStore());
      final api = ApiClient(
        session,
        httpClient: MockClient((req) async => throw http.ClientException('x')),
      );
      await expectLater(
        api.accounts(),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'network')),
      );
    });

    test('malformed success bodies become bad_response', () async {
      final e = await errorFor(http.Response('{"not": "a list"}', 200));
      expect(e.code, 'bad_response');
    });
  });

  group('requests', () {
    test(
      'build URLs under a path prefix with the token only in a header',
      () async {
        final store = MemoryKeyValueStore();
        final session = Session(store);
        await session.load();
        await session.signIn(
          Uri.parse('https://example.com/mail'),
          LoginResult.fromJson({
            ...tokensJson('secret-token', 'r'),
            'user': {'id': 'u', 'email': 'ana@example.com'},
            'account_id': 'acc1',
          }),
        );
        late http.Request sent;
        final api = ApiClient(
          session,
          httpClient: MockClient((req) async {
            sent = req;
            return jsonResponse({'messages': <Object>[], 'next_before': null});
          }),
        );
        await api.messages('acc1', folder: 'Sent Items/2026', before: '17.42');
        expect(sent.url.path, '/mail/v1/accounts/acc1/messages');
        expect(sent.url.queryParameters, {
          'folder': 'Sent Items/2026',
          'before': '17.42',
          'limit': '50',
        });
        expect(sent.url.toString(), isNot(contains('secret-token')));
        expect(sent.headers['Authorization'], 'Bearer secret-token');
      },
    );

    test('request bodies omit unset optional fields', () async {
      final session = await signedInSession(MemoryKeyValueStore());
      final bodies = <Object?>[];
      final api = ApiClient(
        session,
        httpClient: MockClient((req) async {
          bodies.add(jsonDecode(req.body));
          return req.url.path.endsWith('/send')
              ? jsonResponse({'message_id': '<m@x>'}, 202)
              : http.Response('', 204);
        }),
      );
      await api.updateFlags('acc1', '1.2', folder: 'INBOX', seen: true);
      final id = await api.send(
        'acc1',
        const OutgoingMessage(
          to: [Address(email: 'bob@example.com', name: 'Bob')],
          subject: 'Hi',
          text: 'Hello',
        ),
      );
      expect(id, '<m@x>');
      expect(bodies[0], {'seen': true});
      expect(bodies[1], {
        'to': [
          {'name': 'Bob', 'email': 'bob@example.com'},
        ],
        'subject': 'Hi',
        'text': 'Hello',
      });
    });
  });

  test('never sends a request to a non-HTTPS server', () async {
    final session = Session(MemoryKeyValueStore());
    await session.load();
    await session.signIn(
      Uri.parse('http://mail.example.com'),
      LoginResult.fromJson({
        ...tokensJson('a', 'r'),
        'user': {'id': 'u', 'email': 'ana@example.com'},
        'account_id': 'acc1',
      }),
    );
    var calls = 0;
    final api = ApiClient(
      session,
      httpClient: MockClient((req) async {
        calls++;
        return jsonResponse(<Object>[]);
      }),
    );
    await expectLater(
      api.accounts(),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'insecure')),
    );
    expect(calls, 0);
    expect(isSecureEnough(Uri.parse('wss://x.example.com/v1/stream')), isTrue);
    expect(
      isSecureEnough(
        Uri.parse('ws://localhost/v1/stream'),
        allowInsecureLocal: false,
      ),
      isFalse,
    );
  });

  group('parseServerUrl', () {
    test('requires https', () {
      expect(
        parseServerUrl('https://mail.example.com/').toString(),
        'https://mail.example.com',
      );
      expect(
        parseServerUrl('mail.example.com').toString(),
        'https://mail.example.com',
      );
      expect(
        parseServerUrl('HTTPS://Mail.Example.com:8443/api//').toString(),
        'https://mail.example.com:8443/api',
      );
      for (final bad in [
        'http://mail.example.com',
        'ftp://mail.example.com',
        'ws://mail.example.com',
        '',
        'https://',
        'https://user:pw@mail.example.com',
        'https://mail.example.com/?x=1',
      ]) {
        expect(
          () => parseServerUrl(bad, allowInsecureLocal: true),
          throwsFormatException,
          reason: bad,
        );
      }
    });

    test('allows http only for local hosts in debug builds', () {
      expect(
        parseServerUrl(
          'http://localhost:8080',
          allowInsecureLocal: true,
        ).toString(),
        'http://localhost:8080',
      );
      expect(
        parseServerUrl('http://10.0.2.2:8080', allowInsecureLocal: true).host,
        '10.0.2.2',
      );
      expect(
        () =>
            parseServerUrl('http://localhost:8080', allowInsecureLocal: false),
        throwsFormatException,
      );
      expect(
        () => parseServerUrl('http://192.168.1.2', allowInsecureLocal: true),
        throwsFormatException,
      );
    });
  });

  group('read retries', () {
    Future<(ApiClient, List<Duration>)> build(
      Future<http.Response> Function(http.Request, int n) handler,
    ) async {
      final waits = <Duration>[];
      var n = 0;
      final api = ApiClient(
        await signedInSession(MemoryKeyValueStore()),
        httpClient: MockClient((req) => handler(req, n++)),
        delay: (d) async => waits.add(d),
      );
      return (api, waits);
    }

    test('a GET survives a gateway error and a dropped connection', () async {
      final (api, waits) = await build((req, n) async {
        if (n == 0) return http.Response('', 503);
        if (n == 1) throw http.ClientException('reset');
        return jsonResponse(<Object>[]);
      });
      expect(await api.accounts(), isEmpty);
      expect(waits, hasLength(2));
    });

    test('gives up after two retries and reports the last failure', () async {
      var calls = 0;
      final (api, _) = await build((req, n) async {
        calls++;
        return http.Response('', 502);
      });
      await expectLater(
        api.accounts(),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'upstream_error'),
        ),
      );
      expect(calls, 3);
    });

    test(
      'honours a short Retry-After but never blocks on a long one',
      () async {
        final (api, waits) = await build((req, n) async {
          if (n == 0) {
            return http.Response('', 429, headers: {'retry-after': '2'});
          }
          return jsonResponse(<Object>[]);
        });
        await api.accounts();
        expect(waits, [const Duration(seconds: 2)]);

        var calls = 0;
        final (slow, slowWaits) = await build((req, n) async {
          calls++;
          return http.Response('', 429, headers: {'retry-after': '120'});
        });
        await expectLater(
          slow.accounts(),
          throwsA(
            isA<ApiException>().having((e) => e.code, 'code', 'rate_limited'),
          ),
        );
        expect(calls, 1);
        expect(slowWaits, isEmpty);
      },
    );

    test('writes are never repeated', () async {
      var calls = 0;
      final (api, _) = await build((req, n) async {
        calls++;
        return http.Response('', 503);
      });
      await expectLater(
        api.deleteMessage('a', 'm', folder: 'INBOX'),
        throwsA(isA<ApiException>()),
      );
      expect(calls, 1);
    });

    test('client errors are not retried', () async {
      var calls = 0;
      final (api, _) = await build((req, n) async {
        calls++;
        return errorResponse(404, 'not_found');
      });
      await expectLater(api.accounts(), throwsA(isA<ApiException>()));
      expect(calls, 1);
    });
  });
}
