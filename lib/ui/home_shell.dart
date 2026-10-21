import 'dart:async';

import 'package:flutter/material.dart';
import 'package:optional_mail_client/api/client.dart';
import 'package:optional_mail_client/api/realtime.dart';
import 'package:optional_mail_client/ui/app_state.dart';
import 'package:optional_mail_client/ui/calendar/calendar_screen.dart';
import 'package:optional_mail_client/ui/contacts/contacts_screen.dart';
import 'package:optional_mail_client/ui/design.dart';
import 'package:optional_mail_client/ui/format.dart';
import 'package:optional_mail_client/ui/mail/mail_screen.dart';
import 'package:optional_mail_client/ui/mail/mailboxes_screen.dart';
import 'package:optional_mail_client/ui/scope.dart';
import 'package:optional_mail_client/ui/settings/settings_screen.dart';
import 'package:optional_mail_client/ui/widgets/states.dart';

typedef _Destination = ({IconData icon, IconData selected, String label});

const _destinations = <HomeTab, _Destination>{
  HomeTab.mail: (icon: Icons.mail_outline, selected: Icons.mail, label: 'Mail'),
  HomeTab.calendar: (
    icon: Icons.calendar_month_outlined,
    selected: Icons.calendar_month,
    label: 'Calendar',
  ),
  HomeTab.contacts: (
    icon: Icons.contacts_outlined,
    selected: Icons.contacts,
    label: 'Contacts',
  ),
  HomeTab.settings: (
    icon: Icons.settings_outlined,
    selected: Icons.settings,
    label: 'Settings',
  ),
};

/// Owns the per-sign-in state ([AppState], [Realtime], push registration).
///
/// Installed by `MaterialApp.builder` above the Navigator, so every route of
/// the session (compose, message view, editors) can reach [SessionScope].
/// Keyed by user, so nothing survives into the next session.
class SessionHost extends StatefulWidget {
  const SessionHost({
    required this.navigatorKey,
    required this.child,
    super.key,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<SessionHost> createState() => _SessionHostState();
}

class _SessionHostState extends State<SessionHost> {
  late final AppScope _scope = AppScope.of(context);
  late final AppState _state = AppState(_scope.api);
  late final Realtime _realtime = _scope.realtimeFactory(_scope.api);
  late final AppLifecycleListener _lifecycle;
  StreamSubscription<RealtimeEvent>? _sub;

  @override
  void initState() {
    super.initState();
    unawaited(_state.loadAccounts());
    _realtime.start();
    _lifecycle = AppLifecycleListener(
      onPause: _realtime.stop,
      onResume: _realtime.resume,
    );
    _sub = _realtime.events.listen((e) {
      if (e.type == 'account.error' || e.isResync) {
        unawaited(_state.loadAccounts());
      }
      if (e.type == 'mail.new') _announce(e);
    });
    final push = _scope.push;
    if (push != null) {
      unawaited(push.register(_scope.api));
      push.openAccount.addListener(_onPushOpen);
      // A tap that launched the app is handled once the first frame is up.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onPushOpen();
      });
    }
  }

  DateTime? _lastAnnounced;

  /// In-app banner for new mail the user isn't already looking at. Closed-app
  /// notifications come from push; this covers the app being open.
  void _announce(RealtimeEvent e) {
    final account = _state.accountById(e.accountId);
    if (account == null) return;
    final folder = e.folder.isEmpty ? 'INBOX' : e.folder;
    final viewing =
        _state.tab == HomeTab.mail &&
        _state.selectedAccount?.id == account.id &&
        _state.folder == folder &&
        (widget.navigatorKey.currentState?.canPop() ?? false) == false;
    final now = DateTime.now();
    final recent =
        _lastAnnounced != null &&
        now.difference(_lastAnnounced!) < const Duration(seconds: 4);
    if (viewing || recent) return;
    _lastAnnounced = now;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('New mail in ${account.label}'),
          action: SnackBarAction(
            label: 'Open',
            onPressed: () {
              widget.navigatorKey.currentState?.popUntil((r) => r.isFirst);
              _state.openMailbox(account.id, folder: folder);
            },
          ),
        ),
      );
  }

  void _onPushOpen() {
    final push = _scope.push;
    final account = push?.openAccount.value;
    if (push == null || account == null) return;
    push.openAccount.value = null;
    // Close anything opened on top of the home screen, then show the inbox.
    widget.navigatorKey.currentState?.popUntil((r) => r.isFirst);
    _state.openMailbox(account);
  }

  @override
  void dispose() {
    _scope.push?.openAccount.removeListener(_onPushOpen);
    _lifecycle.dispose();
    unawaited(_sub?.cancel());
    unawaited(_realtime.dispose());
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      SessionScope(state: _state, realtime: _realtime, child: widget.child);
}

/// Signed-in home: navigation between the four areas.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final _visited = <HomeTab>{HomeTab.mail};

  Widget _tab(HomeTab tab) => switch (tab) {
    // iOS phones start Mail at "Mailboxes"; everywhere else keeps the folder drawer or pane.
    HomeTab.mail =>
      isIOS(context) && MediaQuery.sizeOf(context).width < 840
          ? const MailboxesScreen()
          : const MailScreen(),
    HomeTab.calendar => const CalendarScreen(),
    HomeTab.contacts => const ContactsScreen(),
    HomeTab.settings => const SettingsScreen(),
  };

  @override
  Widget build(BuildContext context) {
    final state = SessionScope.watch(context);
    if (state.accounts.isEmpty) {
      return Scaffold(
        body: state.error == null
            ? const LoadingView(label: 'Loading your accounts')
            : MessageView(
                icon: Icons.cloud_off_outlined,
                title: "Couldn't load your accounts",
                message: describeError(state.error),
                action: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: state.loadAccounts,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try again'),
                    ),
                    OutlinedButton(
                      onPressed: AppScope.of(context).api.logout,
                      child: const Text('Sign out'),
                    ),
                  ],
                ),
              ),
      );
    }

    _visited.add(state.tab);
    final body = IndexedStack(
      index: state.tab.index,
      children: [
        for (final tab in HomeTab.values)
          _visited.contains(tab) ? _tab(tab) : const SizedBox.shrink(),
      ],
    );
    final wide = MediaQuery.sizeOf(context).width >= 840;

    if (wide) {
      return Material(
        child: Row(
          children: [
            SafeArea(
              right: false,
              child: NavigationRail(
                selectedIndex: state.tab.index,
                onDestinationSelected: (i) =>
                    state.selectTab(HomeTab.values[i]),
                labelType: NavigationRailLabelType.all,
                groupAlignment: -0.8,
                destinations: [
                  for (final d in _destinations.values)
                    NavigationRailDestination(
                      icon: Icon(d.icon),
                      selectedIcon: Icon(d.selected),
                      label: Text(d.label),
                    ),
                ],
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeLeft: true,
                child: body,
              ),
            ),
          ],
        ),
      );
    }
    if (isIOS(context)) {
      // Content runs under the floating glass bar; scrollables inherit the extra inset.
      final mq = MediaQuery.of(context);
      final inset =
          GlassTabBar.height +
          (mq.padding.bottom > 0 ? mq.padding.bottom : 12) +
          12;
      return Material(
        child: Stack(
          children: [
            MediaQuery(
              data: mq.copyWith(
                padding: mq.padding.copyWith(bottom: inset),
                viewPadding: mq.viewPadding.copyWith(bottom: inset),
              ),
              child: body,
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: GlassTabBar(
                items: _destinations.values.toList(),
                selected: state.tab.index,
                onSelected: (i) => state.selectTab(HomeTab.values[i]),
              ),
            ),
          ],
        ),
      );
    }
    return Material(
      child: Column(
        children: [
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeBottom: true,
              child: body,
            ),
          ),
          NavigationBar(
            selectedIndex: state.tab.index,
            onDestinationSelected: (i) => state.selectTab(HomeTab.values[i]),
            destinations: [
              for (final d in _destinations.values)
                NavigationDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selected),
                  label: d.label,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
