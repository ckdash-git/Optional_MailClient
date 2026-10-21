import 'package:flutter/material.dart';
import 'package:optional_mail_client/api/cache.dart';
import 'package:optional_mail_client/api/client.dart';
import 'package:optional_mail_client/api/push.dart';
import 'package:optional_mail_client/api/realtime.dart';
import 'package:optional_mail_client/api/session.dart';
import 'package:optional_mail_client/ui/design.dart';
import 'package:optional_mail_client/ui/home_shell.dart';
import 'package:optional_mail_client/ui/scope.dart';
import 'package:optional_mail_client/ui/sign_in_screen.dart';
import 'package:optional_mail_client/ui/widgets/states.dart';

const appName = 'Optional Mail';
const appVersion = '1.0.0';

class MailApp extends StatefulWidget {
  const MailApp({
    required this.api,
    super.key,
    this.push,
    this.cache,
    this.realtimeFactory = Realtime.new,
  });

  final ApiClient api;

  /// Offline message cache; in memory when null (tests, web).
  final MailCache? cache;
  final PushService? push;
  final Realtime Function(ApiClient api) realtimeFactory;

  @override
  State<MailApp> createState() => _MailAppState();
}

class _MailAppState extends State<MailApp> {
  final _navigator = GlobalKey<NavigatorState>();
  SessionStatus? _lastStatus;
  late final MailCache _cache = widget.cache ?? MailCache(MemoryBlobStore());

  Session get _session => widget.api.session;

  @override
  void initState() {
    super.initState();
    _lastStatus = _session.status;
    _session.addListener(_onSession);
  }

  @override
  void dispose() {
    _session.removeListener(_onSession);
    super.dispose();
  }

  void _onSession() {
    final status = _session.status;
    if (status == SessionStatus.signedOut && _lastStatus != status) {
      // Drop every screen and dialog of the old session.
      _navigator.currentState?.popUntil((r) => r.isFirst);
    }
    _lastStatus = status;
  }

  @override
  Widget build(BuildContext context) => AppScope(
    api: widget.api,
    push: widget.push,
    cache: _cache,
    realtimeFactory: widget.realtimeFactory,
    child: ListenableBuilder(
      listenable: _session,
      builder: (context, _) => MaterialApp(
        title: appName,
        navigatorKey: _navigator,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light, platform: previewPlatform()),
        darkTheme: buildTheme(Brightness.dark, platform: previewPlatform()),
        themeMode: _session.themeMode,
        // Session state sits above the Navigator so pushed routes see it.
        builder: (context, child) => _session.isSignedIn
            ? SessionHost(
                key: ValueKey(_session.user?.id ?? ''),
                navigatorKey: _navigator,
                child: child!,
              )
            : child!,
        home: switch (_session.status) {
          SessionStatus.loading => const Scaffold(body: LoadingView()),
          SessionStatus.signedOut => const SignInScreen(),
          SessionStatus.signedIn => const HomeShell(),
        },
      ),
    ),
  );
}
