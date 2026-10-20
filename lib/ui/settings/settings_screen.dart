import 'dart:async';

import 'package:flutter/material.dart';
import 'package:optional_mail_client/api/client.dart';
import 'package:optional_mail_client/app.dart';
import 'package:optional_mail_client/ui/design.dart';
import 'package:optional_mail_client/ui/format.dart';
import 'package:optional_mail_client/ui/scope.dart';
import 'package:optional_mail_client/ui/settings/add_account_screen.dart';
import 'package:optional_mail_client/ui/widgets/avatar.dart';
import 'package:optional_mail_client/ui/widgets/dialogs.dart';

IconData _platformIcon(String platform) => switch (platform) {
  'android' || 'ios' => Icons.smartphone_outlined,
  'web' => Icons.language_outlined,
  _ => Icons.computer_outlined,
};

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<Device>? _devices;
  Object? _devicesError;
  bool _busy = false;

  ApiClient get _api => AppScope.of(context).api;

  @override
  void initState() {
    super.initState();
    unawaited(_loadDevices());
  }

  Future<void> _loadDevices() async {
    try {
      final devices = await _api.devices();
      devices.sort((a, b) {
        if (a.current != b.current) return a.current ? -1 : 1;
        return b.lastSeenAt.compareTo(a.lastSeenAt);
      });
      if (mounted) {
        setState(() {
          _devices = devices;
          _devicesError = null;
        });
      }
    } on Object catch (e) {
      if (mounted) setState(() => _devicesError = e);
    }
  }

  Future<void> _guarded(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) showSnack(context, done);
    } on Object catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addAccount() async {
    final state = SessionScope.read(context);
    final added = await Navigator.of(context).push<Account>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const AddAccountScreen(),
      ),
    );
    if (added != null) {
      await state.loadAccounts();
      if (mounted) showSnack(context, 'Added ${added.email}');
    }
  }

  Future<void> _removeAccount(Account a) async {
    final state = SessionScope.read(context);
    final ok = await confirm(
      context,
      title: 'Remove ${a.email}?',
      message:
          'The account is removed from this app on all your devices. '
          'Mail on the server is not deleted.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _guarded(() async {
      await _api.deleteAccount(a.id);
      await state.loadAccounts();
    }, 'Removed ${a.email}');
  }

  Future<void> _revoke(Device d) async {
    final ok = await confirm(
      context,
      title: 'Sign out ${d.name}?',
      message: 'That device will need to sign in again.',
      confirmLabel: 'Sign out device',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _guarded(() async {
      await _api.revokeDevice(d.id);
      await _loadDevices();
    }, 'Signed out ${d.name}');
  }

  Future<void> _signOut() async {
    final ok = await confirm(
      context,
      title: 'Sign out?',
      message: 'All data stored by this app on this device is removed.',
      confirmLabel: 'Sign out',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    await _api.logout();
  }

  @override
  Widget build(BuildContext context) {
    final state = SessionScope.watch(context);
    final session = AppScope.of(context).session;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget header(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: theme.textTheme.titleSmall?.copyWith(color: scheme.primary),
        ),
      ),
    );

    final ios = isIOS(context);
    return Scaffold(
      appBar: ios ? null : AppBar(title: const Text('Settings')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: _scrolling(ios, [
          if (_busy) const LinearProgressIndicator(),
          header('Accounts'),
          for (final a in state.accounts)
            ListTile(
              leading: InitialsAvatar(
                name: a.label,
                seed: a.email,
                coded: true,
              ),
              title: Text(a.label, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                [
                  if (a.label != a.email) a.email,
                  a.incomingProtocol.label,
                  if (a.hasCalendar) 'Calendar',
                  if (a.hasContacts) 'Contacts',
                  if (a.lastError.isNotEmpty) 'Problem: ${a.lastError}',
                ].join(' · '),
                style: a.lastError.isEmpty
                    ? null
                    : TextStyle(color: scheme.error),
              ),
              trailing: IconButton(
                tooltip: 'Remove ${a.email}',
                onPressed: () => _removeAccount(a),
                icon: const Icon(Icons.delete_outline),
              ),
            ),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Add account'),
            onTap: _addAccount,
          ),
          header('Devices'),
          if (_devices == null && _devicesError == null)
            const ListTile(
              leading: SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              title: Text('Loading devices'),
            )
          else if (_devices == null)
            ListTile(
              leading: Icon(Icons.error_outline, color: scheme.error),
              title: Text(describeError(_devicesError)),
              trailing: TextButton(
                onPressed: () {
                  setState(() => _devicesError = null);
                  unawaited(_loadDevices());
                },
                child: const Text('Retry'),
              ),
            )
          else
            for (final d in _devices!)
              ListTile(
                leading: Icon(_platformIcon(d.platform)),
                title: Text(d.name.isEmpty ? d.platform : d.name),
                subtitle: Text(
                  d.current
                      ? 'This device'
                      : 'Last active ${formatListDate(d.lastSeenAt)}',
                ),
                trailing: d.current
                    ? Icon(
                        Icons.check_circle,
                        color: scheme.primary,
                        semanticLabel: 'Current',
                      )
                    : IconButton(
                        tooltip: 'Sign out ${d.name}',
                        onPressed: () => _revoke(d),
                        icon: const Icon(Icons.logout),
                      ),
              ),
          header('Appearance'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ListenableBuilder(
              listenable: session,
              builder: (context, _) => SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.system,
                    icon: Icon(Icons.brightness_auto_outlined),
                    label: Text('System'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: Icon(Icons.light_mode_outlined),
                    label: Text('Light'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: Icon(Icons.dark_mode_outlined),
                    label: Text('Dark'),
                  ),
                ],
                selected: {session.themeMode},
                onSelectionChanged: (s) => session.setThemeMode(s.first),
              ),
            ),
          ),
          header('About'),
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: const Text('Server'),
            subtitle: Text(session.serverUrl?.toString() ?? ''),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('$appName $appVersion'),
            subtitle: const Text('Open-source licenses'),
            onTap: () => showLicensePage(
              context: context,
              applicationName: appName,
              applicationVersion: appVersion,
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: scheme.error,
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: _signOut,
              icon: const Icon(Icons.logout),
              label: Text('Sign out ${session.user?.email ?? ''}'.trim()),
            ),
          ),
        ]),
      ),
    );
  }

  /// iOS gets a large collapsing title (and room under the glass tab bar); Android keeps the app bar.
  Widget _scrolling(bool ios, List<Widget> children) {
    if (!ios) {
      return ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: children,
      );
    }
    return CustomScrollView(
      slivers: [
        largeTitleBar(context, 'Settings'),
        SliverList(delegate: SliverChildListDelegate(children)),
        SliverToBoxAdapter(
          child: SizedBox(height: MediaQuery.paddingOf(context).bottom),
        ),
      ],
    );
  }
}
