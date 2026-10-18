import 'package:flutter/widgets.dart';
import 'package:optional_mail_client/api/client.dart';
import 'package:optional_mail_client/api/push.dart';
import 'package:optional_mail_client/api/realtime.dart';
import 'package:optional_mail_client/api/session.dart';
import 'package:optional_mail_client/ui/app_state.dart';

/// App-wide services, available above the navigator.
class AppScope extends InheritedWidget {
  const AppScope({
    required this.api,
    required this.push,
    required super.child,
    super.key,
    this.realtimeFactory = Realtime.new,
  });

  final ApiClient api;

  /// Creates the per-session WebSocket connection (replaceable in tests).
  final Realtime Function(ApiClient api) realtimeFactory;

  /// Null when Firebase is not configured.
  final PushService? push;

  Session get session => api.session;

  static AppScope of(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No AppScope above this widget');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      api != oldWidget.api ||
      push != oldWidget.push ||
      realtimeFactory != oldWidget.realtimeFactory;
}

/// Per-sign-in state: accounts, selection and the realtime stream. Created by
/// the home shell and disposed on sign out, so nothing leaks between users.
class SessionScope extends InheritedNotifier<AppState> {
  const SessionScope({
    required AppState state,
    required this.realtime,
    required super.child,
    super.key,
  }) : super(notifier: state);

  final Realtime realtime;

  /// The app state; the caller rebuilds when it changes.
  static AppState watch(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SessionScope>()!.notifier!;

  /// Like [watch], but null once the session has ended. For pushed routes,
  /// which may still rebuild during their exit animation after sign-out.
  static AppState? maybeWatch(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SessionScope>()?.notifier;

  /// The app state without subscribing to changes (for callbacks).
  static AppState read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SessionScope>()!.notifier!;

  static Realtime realtimeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SessionScope>()!.realtime;
}
