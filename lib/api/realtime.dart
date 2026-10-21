import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:optional_mail_client/api/client.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum RealtimeStatus { idle, connecting, connected, waiting }

/// Reconnect delay for the given attempt (0-based): exponential from 1 s up
/// to 60 s, with jitter in the upper half so clients don't reconnect in sync.
Duration reconnectDelay(int attempt, Random random) {
  final capped = min(attempt, 6); // 2^6 = 64 > 60
  final baseMs = min(60000, 1000 * (1 << capped));
  final jittered = baseMs / 2 + random.nextDouble() * baseMs / 2;
  return Duration(milliseconds: jittered.round());
}

typedef ChannelFactory = WebSocketChannel Function(Uri uri);

/// One WebSocket to `/v1/stream`.
///
/// Authenticates with a first text frame (never a token in the URL),
/// reconnects with backoff, and closes while the app is paused. Events are
/// hints only: listeners re-fetch what they show.
class Realtime {
  Realtime(this._api, {ChannelFactory? connect, Random? random})
    : _connectFn = connect ?? WebSocketChannel.connect,
      _random = random ?? Random();

  final ApiClient _api;
  final ChannelFactory _connectFn;
  final Random _random;

  final _events = StreamController<RealtimeEvent>.broadcast();
  final status = ValueNotifier<RealtimeStatus>(RealtimeStatus.idle);

  WebSocketChannel? _channel;
  StreamSubscription<Object?>? _sub;
  Timer? _retry;
  int _attempt = 0;
  int _generation = 0;
  bool _wanted = false;
  bool _disposed = false;
  bool _everConnected = false;

  Stream<RealtimeEvent> get events => _events.stream;

  /// Starts (or resumes) the connection.
  void start() {
    if (_disposed || _wanted) return;
    _wanted = true;
    _attempt = 0;
    unawaited(_connect());
  }

  /// Closes the connection, e.g. when the app goes to the background.
  void stop() {
    _wanted = false;
    _teardown();
    status.value = RealtimeStatus.idle;
  }

  /// App came back: reconnect now and let listeners refresh.
  void resume() {
    if (_disposed) return;
    start();
    _emit(RealtimeEvent.resync);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    stop();
    _disposed = true;
    status.dispose();
    await _events.close();
  }

  void _emit(RealtimeEvent e) {
    if (!_events.isClosed) _events.add(e);
  }

  void _teardown() {
    _generation++;
    _retry?.cancel();
    _retry = null;
    unawaited(_sub?.cancel());
    _sub = null;
    final ch = _channel;
    _channel = null;
    if (ch != null) unawaited(ch.sink.close(1000).catchError((Object _) {}));
  }

  Future<void> _connect() async {
    _teardown();
    final gen = _generation;
    status.value = RealtimeStatus.connecting;

    final server = _api.session.serverUrl;
    if (server == null) return;
    String token;
    try {
      token = await _api.accessToken();
    } on ApiException catch (e) {
      if (gen != _generation) return;
      if (_api.session.isSignedIn) _scheduleRetry();
      debugPrint('Realtime: no token (${e.code})');
      return;
    }
    if (gen != _generation || !_wanted) return;

    final uri = server.replace(
      scheme: server.scheme == 'https' ? 'wss' : 'ws',
      path: '${server.path}/v1/stream',
    );
    if (!isSecureEnough(uri)) return;
    final WebSocketChannel channel;
    try {
      channel = _connectFn(uri);
      _channel = channel;
      await channel.ready.timeout(const Duration(seconds: 15));
    } on Object catch (e) {
      if (gen != _generation) return;
      debugPrint('Realtime: connect failed (${e.runtimeType})');
      _scheduleRetry();
      return;
    }
    if (gen != _generation) return;

    channel.sink.add(jsonEncode({'type': 'auth', 'token': token}));
    _sub = channel.stream.listen(
      (data) => _onFrame(gen, data),
      onError: (Object e) => debugPrint('Realtime: error (${e.runtimeType})'),
      onDone: () => _onClosed(gen, channel.closeCode, token),
    );
  }

  void _onFrame(int gen, Object? data) {
    if (gen != _generation || data is! String) return;
    final RealtimeEvent event;
    try {
      event = RealtimeEvent.fromJson(jsonDecode(data) as Json);
    } on Object {
      return;
    }
    if (event.type == 'ready') {
      _attempt = 0;
      status.value = RealtimeStatus.connected;
      // Events may have been missed while disconnected.
      if (_everConnected) _emit(RealtimeEvent.resync);
      _everConnected = true;
      return;
    }
    _emit(event);
  }

  void _onClosed(int gen, int? code, String token) {
    if (gen != _generation) return;
    _sub = null;
    _channel = null;
    if (!_wanted) return;
    if (code == 4401) {
      // Token rejected: refresh (single-flight) before the next attempt. If
      // that fails the session is wiped and the shell disposes us.
      unawaited(
        _api
            .refreshAfterRejection(token)
            .then(
              (_) {
                if (gen == _generation) _scheduleRetry();
              },
              onError: (Object _) {
                if (gen == _generation && _api.session.isSignedIn) {
                  _scheduleRetry();
                }
              },
            ),
      );
      return;
    }
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (!_wanted || _disposed) return;
    _retry?.cancel();
    final delay = reconnectDelay(_attempt++, _random);
    status.value = RealtimeStatus.waiting;
    _retry = Timer(delay, () {
      _retry = null;
      if (_wanted) unawaited(_connect());
    });
  }
}
