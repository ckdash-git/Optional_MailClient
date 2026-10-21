import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:optional_mail_client/api/client.dart';

/// Optional Firebase Cloud Messaging integration.
///
/// [PushService.initialize] returns null when Firebase is not configured
/// (no google-services.json / GoogleService-Info.plist) or the platform is
/// unsupported. The app then relies on the WebSocket alone.
///
/// Push payloads carry no message content: `mail.new` only names the account,
/// so tapping the notification opens that account's inbox.
class PushService {
  PushService._(this._messaging);

  final FirebaseMessaging _messaging;

  /// Account whose inbox should be opened because a notification was tapped.
  /// The home screen consumes it and resets it to null.
  final openAccount = ValueNotifier<String?>(null);

  StreamSubscription<String>? _tokenSub;
  StreamSubscription<RemoteMessage>? _openedSub;

  static Future<PushService?> initialize() async {
    if (kIsWeb) return null; // Web push needs a service worker; not shipped.
    try {
      await Firebase.initializeApp();
      final service = PushService._(FirebaseMessaging.instance);
      await service._listenForTaps();
      return service;
    } on Object catch (e) {
      debugPrint(
        'Push disabled: Firebase is not configured (${e.runtimeType})',
      );
      return null;
    }
  }

  Future<void> _listenForTaps() async {
    _openedSub = FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);
    final initial = await _messaging.getInitialMessage();
    if (initial != null) _handleTap(initial);
  }

  void _handleTap(RemoteMessage message) {
    final data = message.data;
    if (data['type'] == 'mail.new') {
      final account = data['account_id'];
      if (account is String && account.isNotEmpty) openAccount.value = account;
    }
  }

  /// Registers this device's FCM token with the master and keeps it current.
  Future<void> register(ApiClient api) async {
    try {
      final settings = await _messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      // The master sends to FCM registration tokens (`{provider: fcm,
      // token}`), so use the token API rather than FID-based register().
      // ignore: deprecated_member_use
      final token = await _messaging.getToken();
      if (token != null) await api.registerPush(token);
      await _tokenSub?.cancel();
      // ignore: deprecated_member_use
      _tokenSub = _messaging.onTokenRefresh.listen((t) {
        unawaited(
          api.registerPush(t).catchError((Object e) {
            debugPrint('Push: token update failed (${e.runtimeType})');
          }),
        );
      });
    } on Object catch (e) {
      debugPrint('Push: registration failed (${e.runtimeType})');
    }
  }

  /// Stops token updates and drops the local FCM token (used on sign out).
  Future<void> unregister() async {
    await _tokenSub?.cancel();
    _tokenSub = null;
    openAccount.value = null;
    try {
      // ignore: deprecated_member_use
      await _messaging.deleteToken();
    } on Object catch (e) {
      debugPrint('Push: deleteToken failed (${e.runtimeType})');
    }
  }

  Future<void> dispose() async {
    await _tokenSub?.cancel();
    await _openedSub?.cancel();
    openAccount.dispose();
  }
}
