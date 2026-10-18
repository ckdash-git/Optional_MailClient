import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:optional_mail_client/api/models.dart';

/// Minimal key/value store. Production uses [SecureKeyValueStore]; tests use
/// [MemoryKeyValueStore].
abstract interface class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> deleteAll();
}

/// Keychain / Keystore-backed storage. Tokens are only ever stored here.
class SecureKeyValueStore implements KeyValueStore {
  SecureKeyValueStore()
    : _storage = const FlutterSecureStorage(
        aOptions: AndroidOptions.defaultOptions,
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device,
        ),
        mOptions: MacOsOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device,
        ),
      );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> deleteAll() => _storage.deleteAll();
}

class MemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> deleteAll() async => values.clear();
}

enum SessionStatus { loading, signedOut, signedIn }

/// Holds the signed-in state: master URL, tokens and user. Persisted in a
/// [KeyValueStore]. The mail password is never stored.
///
/// Only two non-secret preferences survive [clear]: the master URL (so the
/// sign-in form can prefill it) and the theme mode.
class Session extends ChangeNotifier {
  Session(this._store);

  static const _kServer = 'server_url';
  static const _kTheme = 'theme_mode';
  static const _kTokens = 'tokens';
  static const _kUser = 'user';

  final KeyValueStore _store;

  /// Extra cleanup run by [clear] (downloaded files, push token, ...).
  final List<Future<void> Function()> wipeHooks = [];

  SessionStatus _status = SessionStatus.loading;
  Uri? _serverUrl;
  Tokens? _tokens;
  User? _user;
  ThemeMode _themeMode = ThemeMode.system;

  SessionStatus get status => _status;
  Uri? get serverUrl => _serverUrl;
  Tokens? get tokens => _tokens;
  User? get user => _user;
  ThemeMode get themeMode => _themeMode;
  bool get isSignedIn => _status == SessionStatus.signedIn;

  Future<void> load() async {
    try {
      final server = await _store.read(_kServer);
      _serverUrl = server == null ? null : Uri.tryParse(server);
      _themeMode = _parseTheme(await _store.read(_kTheme));
      final tokens = await _store.read(_kTokens);
      final user = await _store.read(_kUser);
      if (tokens != null && user != null && _serverUrl != null) {
        final t = Tokens.fromJson(jsonDecode(tokens) as Json);
        if (t.isValid) {
          _tokens = t;
          _user = User.fromJson(jsonDecode(user) as Json);
        }
      }
    } on Object catch (e) {
      // Corrupt or unreadable storage: start signed out.
      debugPrint('Session: could not read stored state (${e.runtimeType})');
      _tokens = null;
      _user = null;
    }
    _status = _tokens == null
        ? SessionStatus.signedOut
        : SessionStatus.signedIn;
    notifyListeners();
  }

  Future<void> signIn(Uri server, LoginResult result) async {
    _serverUrl = server;
    _tokens = result.tokens;
    _user = result.user;
    await _store.write(_kServer, server.toString());
    await _store.write(_kTokens, jsonEncode(result.tokens.toJson()));
    await _store.write(
      _kUser,
      jsonEncode({'id': result.user.id, 'email': result.user.email}),
    );
    _status = SessionStatus.signedIn;
    notifyListeners();
  }

  /// Stores rotated tokens. The pair is written as one value so a crash can
  /// never leave a new access token next to an already-used refresh token.
  Future<void> updateTokens(Tokens tokens) async {
    if (_status != SessionStatus.signedIn) return;
    _tokens = tokens;
    await _store.write(_kTokens, jsonEncode(tokens.toJson()));
  }

  /// Remembers the master URL without signing in.
  Future<void> rememberServer(Uri server) async {
    _serverUrl = server;
    await _store.write(_kServer, server.toString());
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    await _store.write(_kTheme, mode.name);
  }

  /// Signs out locally and wipes everything except the master URL and theme.
  Future<void> clear() async {
    final wasSignedIn = _status != SessionStatus.signedOut;
    _tokens = null;
    _user = null;
    _status = SessionStatus.signedOut;
    if (wasSignedIn) notifyListeners();
    try {
      await _store.deleteAll();
      if (_serverUrl != null) {
        await _store.write(_kServer, _serverUrl.toString());
      }
      if (_themeMode != ThemeMode.system) {
        await _store.write(_kTheme, _themeMode.name);
      }
    } on Object catch (e) {
      debugPrint('Session: wipe failed (${e.runtimeType})');
    }
    for (final hook in wipeHooks) {
      try {
        await hook();
      } on Object catch (e) {
        debugPrint('Session: wipe hook failed (${e.runtimeType})');
      }
    }
  }

  static ThemeMode _parseTheme(String? s) => ThemeMode.values.firstWhere(
    (m) => m.name == s,
    orElse: () => ThemeMode.system,
  );
}
