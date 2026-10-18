import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:optional_mail_client/api/client.dart';
import 'package:optional_mail_client/api/realtime.dart';
import 'package:optional_mail_client/api/session.dart';
import 'package:optional_mail_client/ui/app_state.dart';
import 'package:optional_mail_client/ui/scope.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

final server = Uri.parse('https://master.example.com');

http.Response jsonResponse(Object? body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

http.Response errorResponse(
  int status,
  String code, [
  String message = '',
  Map<String, String> headers = const {},
]) => http.Response(
  jsonEncode({
    'error': {'code': code, 'message': message},
  }),
  status,
  headers: {'content-type': 'application/json', ...headers},
);

Json tokensJson(String access, String refresh, {DateTime? expires}) => {
  'access_token': access,
  'access_expires_at': rfc3339(
    expires ?? DateTime.now().toUtc().add(const Duration(minutes: 15)),
  ),
  'refresh_token': refresh,
};

/// A session that is already signed in with the given tokens.
Future<Session> signedInSession(
  KeyValueStore store, {
  String access = 'access-1',
  String refresh = 'refresh-1',
  DateTime? expires,
}) async {
  final session = Session(store);
  await session.load();
  await session.signIn(
    server,
    LoginResult.fromJson({
      ...tokensJson(access, refresh, expires: expires),
      'user': {'id': 'u1', 'email': 'ana@example.com'},
      'account_id': 'acc1',
    }),
  );
  return session;
}

const testAccount = Account(
  id: 'acc1',
  email: 'ana@example.com',
  displayName: 'Ana',
  hasCalendar: true,
  hasContacts: true,
);

/// Wraps [child] with the scopes the screens expect.
Widget harness(ApiClient api, Widget child) {
  final state = AppState(api);
  final realtime = Realtime(api);
  return AppScope(
    api: api,
    push: null,
    child: SessionScope(
      state: state,
      realtime: realtime,
      child: MaterialApp(home: child),
    ),
  );
}

/// In-memory WebSocket for realtime tests.
class FakeSink implements WebSocketSink {
  final sent = <Object?>[];
  final _done = Completer<void>();
  int? closedWith;

  @override
  void add(Object? data) => sent.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<Object?> stream) => stream.forEach(add);

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    closedWith = closeCode;
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future<void> get done => _done.future;
}

class FakeChannel extends StreamChannelMixin<Object?>
    implements WebSocketChannel {
  final incoming = StreamController<Object?>();
  final fakeSink = FakeSink();

  @override
  Future<void> get ready => Future.value();

  @override
  int? closeCode;

  @override
  String? closeReason;

  @override
  String? get protocol => null;

  @override
  Stream<Object?> get stream => incoming.stream;

  @override
  WebSocketSink get sink => fakeSink;

  Future<void> dispose() async {
    // The listener may already have cancelled; don't wait for delivery.
    unawaited(incoming.close());
    await fakeSink.close();
  }
}
