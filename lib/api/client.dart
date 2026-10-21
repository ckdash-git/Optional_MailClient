import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:optional_mail_client/api/models.dart';
import 'package:optional_mail_client/api/session.dart';

export 'package:optional_mail_client/api/models.dart';

/// Error returned by the master (`{"error":{"code","message"}}`) or raised
/// locally for transport failures ([status] 0, code [ApiException.network]).
class ApiException implements Exception {
  const ApiException(this.status, this.code, this.message, {this.retryAfter});

  const ApiException.networkError([String message = 'Network error'])
    : this(0, network, message);

  const ApiException.signedOut()
    : this(401, unauthorized, 'Your session has ended. Please sign in again.');

  static const network = 'network';
  static const badResponse = 'bad_response';
  static const badRequest = 'bad_request';
  static const unauthorized = 'unauthorized';
  static const invalidCredentials = 'invalid_credentials';
  static const forbidden = 'forbidden';
  static const notFound = 'not_found';
  static const conflict = 'conflict';
  static const tooLarge = 'too_large';
  static const discoveryFailed = 'discovery_failed';
  static const rateLimited = 'rate_limited';
  static const upstreamError = 'upstream_error';

  final int status;
  final String code;
  final String message;
  final Duration? retryAfter;

  bool get isConflict => code == conflict;
  bool get isNotFound => code == notFound;
  bool get isNetwork => code == network;

  /// A message suitable for showing to the user.
  String get userMessage => switch (code) {
    network => "Can't reach the server. Check your connection and try again.",
    unauthorized => 'Your session has ended. Please sign in again.',
    invalidCredentials =>
      'The mail server rejected the email address or password.',
    forbidden =>
      message.isNotEmpty
          ? message
          : 'This action is not allowed by the server.',
    notFound => 'This item no longer exists.',
    conflict => 'This item was changed somewhere else.',
    tooLarge => 'This is too large to send.',
    discoveryFailed =>
      "We couldn't detect the server settings for this address. "
          'Enter them under Advanced.',
    rateLimited =>
      retryAfter == null
          ? 'Too many attempts. Please wait a moment and try again.'
          : 'Too many attempts. Try again in ${retryAfter!.inSeconds} s.',
    upstreamError =>
      'Your mail server failed or is unreachable. Try again later.',
    badResponse => 'The server sent an unexpected response.',
    _ => message.isNotEmpty ? message : 'Something went wrong ($status).',
  };

  @override
  String toString() => 'ApiException($status, $code, $message)';
}

/// Validates and normalises the master URL typed by the user.
///
/// HTTPS is required. Plain HTTP is accepted only for local development hosts
/// (`localhost`, `127.0.0.1`, `::1`, `10.0.2.2`) and only when
/// [allowInsecureLocal] is true, which defaults to debug builds.
const _localHosts = {'localhost', '127.0.0.1', '::1', '10.0.2.2'};

/// Whether requests may be sent to [url]: HTTPS, or plain HTTP to a local
/// development host when [allowInsecureLocal] (debug builds).
bool isSecureEnough(Uri url, {bool allowInsecureLocal = kDebugMode}) {
  final scheme = url.scheme.toLowerCase();
  if (scheme == 'https' || scheme == 'wss') return true;
  return (scheme == 'http' || scheme == 'ws') &&
      allowInsecureLocal &&
      _localHosts.contains(url.host.toLowerCase());
}

Uri parseServerUrl(String input, {bool allowInsecureLocal = kDebugMode}) {
  var text = input.trim();
  if (text.isEmpty) throw const FormatException('Enter the server address.');
  if (!text.contains('://')) text = 'https://$text';
  final uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty) {
    throw const FormatException('This is not a valid server address.');
  }
  if (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
    throw const FormatException(
      'Enter only the server address, without credentials or parameters.',
    );
  }
  final scheme = uri.scheme.toLowerCase();
  if ((scheme != 'https' && scheme != 'http') ||
      !isSecureEnough(uri, allowInsecureLocal: allowInsecureLocal)) {
    throw const FormatException('The server address must start with https://');
  }
  var path = uri.path;
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  return Uri(
    scheme: scheme,
    host: uri.host.toLowerCase(),
    port: uri.hasPort ? uri.port : null,
    path: path,
  );
}

/// Bytes of a downloaded attachment.
class DownloadedFile {
  const DownloadedFile(this.bytes, this.contentType);
  final Uint8List bytes;
  final String contentType;
}

/// Thin typed client for the master REST API.
///
/// Access tokens are refreshed proactively shortly before they expire and
/// once more if the master answers `401 unauthorized`. Refreshing is
/// single-flight: concurrent requests share one refresh call, because reusing
/// a rotated refresh token makes the master revoke the device. If refreshing
/// fails the session is wiped.
class ApiClient {
  ApiClient(this.session, {http.Client? httpClient, DateTime Function()? clock})
    : _http = httpClient ?? http.Client(),
      _now = clock ?? DateTime.now;

  final Session session;
  final http.Client _http;
  final DateTime Function() _now;

  static const _defaultTimeout = Duration(seconds: 30);
  static const _longTimeout = Duration(minutes: 3);
  static const _refreshMargin = Duration(seconds: 60);

  Future<void>? _refreshing;

  void close() => _http.close();

  // ---------------------------------------------------------------------
  // Auth (unauthenticated calls take the server explicitly)

  Future<ServerSettings> discover(Uri server, String email) async {
    final res = await _send(
      'POST',
      _url(server, '/v1/discover'),
      body: {'email': email},
    );
    return _decode(res, (j) => ServerSettings.fromJson(j as Json));
  }

  /// Logs in and stores the tokens in [session]. The password is sent once
  /// and not kept.
  Future<LoginResult> login({
    required Uri server,
    required String email,
    required String password,
    required String deviceName,
    required String platform,
    ServerSettings? settings,
    String? username,
  }) async {
    final res = await _send(
      'POST',
      _url(server, '/v1/auth/login'),
      body: {
        'email': email,
        'password': password,
        'device': {'name': deviceName, 'platform': platform},
        if (settings != null) 'server': settings.toJson(),
        if (username != null && username.isNotEmpty) 'username': username,
      },
    );
    final result = _decode(res, (j) => LoginResult.fromJson(j as Json));
    if (!result.tokens.isValid) {
      throw const ApiException(0, ApiException.badResponse, 'missing tokens');
    }
    await session.signIn(server, result);
    return result;
  }

  /// Revokes this device on the master (best effort) and wipes local state.
  Future<void> logout() async {
    final server = session.serverUrl;
    if (server != null && session.tokens != null) {
      try {
        // A fresh token, so the device is revoked even after a long pause.
        final token = await accessToken();
        await _send(
          'POST',
          _url(server, '/v1/auth/logout'),
          token: token,
          timeout: const Duration(seconds: 10),
        );
      } on ApiException catch (e) {
        debugPrint('logout: ${e.code}');
      }
    }
    await session.clear();
  }

  /// Returns a valid access token, refreshing it first if it is about to
  /// expire. Used for the WebSocket auth frame as well.
  Future<String> accessToken() async {
    final t = session.tokens;
    if (t == null) throw const ApiException.signedOut();
    if (!t.accessExpiresAt.isAfter(_now().toUtc().add(_refreshMargin))) {
      await _refreshFrom(t.accessToken);
    }
    final current = session.tokens;
    if (current == null) throw const ApiException.signedOut();
    return current.accessToken;
  }

  /// Called when the master rejected [staleAccessToken] (e.g. WebSocket close
  /// 4401). Refreshes unless another caller already did.
  Future<void> refreshAfterRejection(String staleAccessToken) =>
      _refreshFrom(staleAccessToken);

  Future<void> _refreshFrom(String staleAccessToken) {
    final current = session.tokens;
    if (current == null) return Future.error(const ApiException.signedOut());
    if (current.accessToken != staleAccessToken) return Future.value();
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<void> _doRefresh() async {
    final server = session.serverUrl;
    final tokens = session.tokens;
    if (server == null || tokens == null) {
      throw const ApiException.signedOut();
    }
    // Transport errors propagate without signing out: the user may be offline.
    final res = await _send(
      'POST',
      _url(server, '/v1/auth/refresh'),
      body: {'refresh_token': tokens.refreshToken},
    );
    if (res.statusCode == 200) {
      final fresh = _decode(res, (j) => Tokens.fromJson(j as Json));
      if (fresh.isValid) {
        await session.updateTokens(fresh);
        return;
      }
    }
    final error = res.statusCode == 200
        ? const ApiException(0, ApiException.badResponse, 'missing tokens')
        : _errorFrom(res);
    if (error.code == ApiException.rateLimited || error.status >= 500) {
      throw error;
    }
    await session.clear();
    throw const ApiException.signedOut();
  }

  // ---------------------------------------------------------------------
  // Me, devices, push

  Future<Me> me() async =>
      _decode(await _authed('GET', '/v1/me'), (j) => Me.fromJson(j as Json));

  Future<List<Device>> devices() async =>
      _decodeList(await _authed('GET', '/v1/devices'), Device.fromJson);

  Future<void> revokeDevice(String id) =>
      _authed('DELETE', '/v1/devices/${_seg(id)}');

  Future<void> registerPush(String fcmToken) => _authed(
    'PUT',
    '/v1/devices/current/push',
    body: {'provider': 'fcm', 'token': fcmToken},
  );

  Future<void> unregisterPush() =>
      _authed('DELETE', '/v1/devices/current/push');

  // ---------------------------------------------------------------------
  // Accounts

  Future<List<Account>> accounts() async =>
      _decodeList(await _authed('GET', '/v1/accounts'), Account.fromJson);

  Future<Account> addAccount({
    required String email,
    required String password,
    String? displayName,
    String? username,
    ServerSettings? settings,
  }) async {
    final res = await _authed(
      'POST',
      '/v1/accounts',
      body: {
        'email': email,
        'password': password,
        if (displayName != null && displayName.isNotEmpty)
          'display_name': displayName,
        if (username != null && username.isNotEmpty) 'username': username,
        if (settings != null) 'server': settings.toJson(),
      },
    );
    return _decode(res, (j) => Account.fromJson(j as Json));
  }

  Future<void> deleteAccount(String accountId) =>
      _authed('DELETE', '/v1/accounts/${_seg(accountId)}');

  // ---------------------------------------------------------------------
  // Mail

  Future<List<Folder>> folders(String accountId) async => _decodeList(
    await _authed('GET', '/v1/accounts/${_seg(accountId)}/folders'),
    Folder.fromJson,
  );

  Future<MessagePage> messages(
    String accountId, {
    required String folder,
    String? before,
    int limit = 50,
  }) async {
    final res = await _authed(
      'GET',
      '/v1/accounts/${_seg(accountId)}/messages',
      query: {'folder': folder, 'before': ?before, 'limit': '$limit'},
    );
    return _decode(res, (j) => MessagePage.fromJson(j as Json));
  }

  Future<Message> message(
    String accountId,
    String id, {
    required String folder,
  }) async {
    final res = await _authed(
      'GET',
      '/v1/accounts/${_seg(accountId)}/messages/${_seg(id)}',
      query: {'folder': folder},
    );
    return _decode(res, (j) => Message.fromJson(j as Json));
  }

  Future<DownloadedFile> attachment(
    String accountId,
    String id, {
    required String folder,
    required int index,
  }) async {
    final res = await _authed(
      'GET',
      '/v1/accounts/${_seg(accountId)}/messages/${_seg(id)}/attachments/$index',
      query: {'folder': folder},
      timeout: _longTimeout,
    );
    return DownloadedFile(
      res.bodyBytes,
      res.headers['content-type'] ?? 'application/octet-stream',
    );
  }

  Future<void> updateFlags(
    String accountId,
    String id, {
    required String folder,
    bool? seen,
    bool? flagged,
  }) => _authed(
    'PATCH',
    '/v1/accounts/${_seg(accountId)}/messages/${_seg(id)}',
    query: {'folder': folder},
    body: {'seen': ?seen, 'flagged': ?flagged},
  );

  Future<void> moveMessage(
    String accountId,
    String id, {
    required String folder,
    required String to,
  }) => _authed(
    'POST',
    '/v1/accounts/${_seg(accountId)}/messages/${_seg(id)}/move',
    query: {'folder': folder},
    body: {'to': to},
  );

  Future<void> deleteMessage(
    String accountId,
    String id, {
    required String folder,
  }) => _authed(
    'DELETE',
    '/v1/accounts/${_seg(accountId)}/messages/${_seg(id)}',
    query: {'folder': folder},
  );

  /// Returns the new message id.
  Future<String> send(String accountId, OutgoingMessage message) async {
    final res = await _authed(
      'POST',
      '/v1/accounts/${_seg(accountId)}/send',
      body: message.toJson(),
      timeout: _longTimeout,
    );
    return _decode(res, (j) => (j as Json)['message_id'] as String? ?? '');
  }

  // ---------------------------------------------------------------------
  // Calendar

  Future<List<CalendarInfo>> calendars(String accountId) async => _decodeList(
    await _authed('GET', '/v1/accounts/${_seg(accountId)}/calendars'),
    CalendarInfo.fromJson,
  );

  Future<List<CalendarEvent>> events(
    String accountId, {
    required String calendar,
    required DateTime from,
    required DateTime to,
  }) async => _decodeList(
    await _authed(
      'GET',
      '/v1/accounts/${_seg(accountId)}/events',
      query: {'calendar': calendar, 'from': rfc3339(from), 'to': rfc3339(to)},
    ),
    CalendarEvent.fromJson,
  );

  Future<CalendarEvent> saveEvent(String accountId, EventInput input) async =>
      _decode(
        await _authed(
          'PUT',
          '/v1/accounts/${_seg(accountId)}/events',
          body: input.toJson(),
        ),
        (j) => CalendarEvent.fromJson(j as Json),
      );

  Future<void> deleteEvent(
    String accountId, {
    required String id,
    required String etag,
  }) => _authed(
    'DELETE',
    '/v1/accounts/${_seg(accountId)}/events',
    query: {'id': id, 'etag': etag},
  );

  // ---------------------------------------------------------------------
  // Contacts

  Future<List<AddressBook>> addressBooks(String accountId) async => _decodeList(
    await _authed('GET', '/v1/accounts/${_seg(accountId)}/addressbooks'),
    AddressBook.fromJson,
  );

  Future<List<Contact>> contacts(
    String accountId, {
    required String addressbook,
  }) async => _decodeList(
    await _authed(
      'GET',
      '/v1/accounts/${_seg(accountId)}/contacts',
      query: {'addressbook': addressbook},
    ),
    Contact.fromJson,
  );

  Future<Contact> saveContact(String accountId, ContactInput input) async =>
      _decode(
        await _authed(
          'PUT',
          '/v1/accounts/${_seg(accountId)}/contacts',
          body: input.toJson(),
        ),
        (j) => Contact.fromJson(j as Json),
      );

  Future<void> deleteContact(
    String accountId, {
    required String id,
    required String etag,
  }) => _authed(
    'DELETE',
    '/v1/accounts/${_seg(accountId)}/contacts',
    query: {'id': id, 'etag': etag},
  );

  // ---------------------------------------------------------------------
  // Plumbing

  /// Builds `<server><path>` keeping any path prefix of the server URL.
  static Uri _url(Uri server, String path, [Map<String, String>? query]) =>
      server.replace(
        path: '${server.path}$path',
        queryParameters: (query == null || query.isEmpty) ? null : query,
      );

  static String _seg(String s) => Uri.encodeComponent(s);

  Future<http.Response> _authed(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    Duration timeout = _defaultTimeout,
  }) async {
    final server = session.serverUrl;
    if (server == null) throw const ApiException.signedOut();
    final url = _url(server, path, query);

    final token = await accessToken();
    var res = await _send(
      method,
      url,
      body: body,
      token: token,
      timeout: timeout,
    );
    if (_tokenRejected(res)) {
      await _refreshFrom(token);
      final retryToken = session.tokens?.accessToken;
      if (retryToken == null) throw const ApiException.signedOut();
      res = await _send(
        method,
        url,
        body: body,
        token: retryToken,
        timeout: timeout,
      );
      if (_tokenRejected(res)) {
        await session.clear();
        throw const ApiException.signedOut();
      }
    }
    if (res.statusCode >= 400) throw _errorFrom(res);
    return res;
  }

  static bool _tokenRejected(http.Response res) =>
      res.statusCode == 401 &&
      _errorFrom(res).code != ApiException.invalidCredentials;

  Future<http.Response> _send(
    String method,
    Uri url, {
    Object? body,
    String? token,
    Duration timeout = _defaultTimeout,
  }) async {
    if (!isSecureEnough(url)) {
      throw const ApiException(
        0,
        'insecure',
        'Refusing an insecure connection.',
      );
    }
    final req = http.Request(method, url)
      ..followRedirects = false
      ..headers['Accept'] = 'application/json';
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      req.headers['Content-Type'] = 'application/json; charset=utf-8';
      req.bodyBytes = utf8.encode(jsonEncode(body));
    }
    try {
      final streamed = await _http.send(req).timeout(timeout);
      return await http.Response.fromStream(streamed).timeout(timeout);
    } on TimeoutException {
      throw const ApiException.networkError('The request timed out');
    } on ApiException {
      rethrow;
    } on Exception catch (e) {
      // ClientException, SocketException, HandshakeException, ...
      throw ApiException.networkError(e.runtimeType.toString());
    }
  }

  static ApiException _errorFrom(http.Response res) {
    final retry = int.tryParse(res.headers['retry-after'] ?? '');
    final retryAfter = retry == null ? null : Duration(seconds: retry);
    try {
      final j = jsonDecode(utf8.decode(res.bodyBytes)) as Json;
      final e = j['error']! as Json;
      return ApiException(
        res.statusCode,
        e['code'] as String? ?? 'http_${res.statusCode}',
        e['message'] as String? ?? '',
        retryAfter: retryAfter,
      );
    } on Object {
      final code = switch (res.statusCode) {
        400 => ApiException.badRequest,
        401 => ApiException.unauthorized,
        403 => ApiException.forbidden,
        404 => ApiException.notFound,
        409 => ApiException.conflict,
        413 => ApiException.tooLarge,
        429 => ApiException.rateLimited,
        502 => ApiException.upstreamError,
        _ => 'http_${res.statusCode}',
      };
      return ApiException(
        res.statusCode,
        code,
        res.statusCode >= 500 ? 'Server error (${res.statusCode})' : '',
        retryAfter: retryAfter,
      );
    }
  }

  static T _decode<T>(http.Response res, T Function(Object? json) parse) {
    if (res.statusCode >= 400) throw _errorFrom(res);
    try {
      return parse(jsonDecode(utf8.decode(res.bodyBytes)));
    } on Object catch (e) {
      throw ApiException(0, ApiException.badResponse, e.runtimeType.toString());
    }
  }

  static List<T> _decodeList<T>(http.Response res, T Function(Json) parse) =>
      _decode(
        res,
        (j) => [for (final e in j! as List<Object?>) parse(e! as Json)],
      );
}
