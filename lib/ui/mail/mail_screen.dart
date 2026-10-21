import 'dart:async';

import 'package:flutter/material.dart';
import 'package:optional_mail_client/api/client.dart';
import 'package:optional_mail_client/ui/mail/compose_screen.dart';
import 'package:optional_mail_client/ui/mail/message_list.dart';
import 'package:optional_mail_client/ui/scope.dart';
import 'package:optional_mail_client/ui/widgets/account_menu.dart';
import 'package:optional_mail_client/ui/widgets/avatar.dart';
import 'package:optional_mail_client/ui/widgets/states.dart';

const _roleOrder = [
  FolderRole.inbox,
  FolderRole.drafts,
  FolderRole.sent,
  FolderRole.archive,
  FolderRole.junk,
  FolderRole.trash,
];

String folderLabel(Folder f) => switch (f.role) {
  FolderRole.inbox => 'Inbox',
  FolderRole.sent => 'Sent',
  FolderRole.drafts => 'Drafts',
  FolderRole.trash => 'Trash',
  FolderRole.junk => 'Junk',
  FolderRole.archive => 'Archive',
  FolderRole.none => f.name,
};

IconData folderIcon(FolderRole role) => switch (role) {
  FolderRole.inbox => Icons.inbox_outlined,
  FolderRole.sent => Icons.send_outlined,
  FolderRole.drafts => Icons.drafts_outlined,
  FolderRole.trash => Icons.delete_outline,
  FolderRole.junk => Icons.report_outlined,
  FolderRole.archive => Icons.archive_outlined,
  FolderRole.none => Icons.folder_outlined,
};

List<Folder> sortFolders(List<Folder> folders) {
  int rank(Folder f) {
    if (f.name.toUpperCase() == 'INBOX') return -1;
    final i = _roleOrder.indexOf(f.role);
    return i < 0 ? _roleOrder.length : i;
  }

  return [...folders]..sort((a, b) {
    final r = rank(a).compareTo(rank(b));
    return r != 0 ? r : a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
}

class MailScreen extends StatefulWidget {
  const MailScreen({super.key, this.pushed = false});

  /// iOS: opened from the Mailboxes screen, so it shows a back button instead of the drawer.
  final bool pushed;

  @override
  State<MailScreen> createState() => _MailScreenState();
}

class _MailScreenState extends State<MailScreen> {
  final _refresh = ValueNotifier<int>(0);
  StreamSubscription<RealtimeEvent>? _sub;
  Timer? _debounce;

  String? _accountId;
  List<Folder>? _folders;
  Object? _folderError;
  int _gen = 0;
  MailFilter _filter = MailFilter.all;
  String? _filterScope;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sub ??= SessionScope.realtimeOf(context).events.listen(_onEvent);
    final state = SessionScope.watch(context);
    // A filter belongs to one folder view: switching folder or account clears it.
    final scope = '${state.selectedAccount?.id}|${state.folder}';
    if (scope != _filterScope) {
      _filterScope = scope;
      _filter = MailFilter.all;
    }
    final account = state.selectedAccount;
    if (account != null && account.id != _accountId) {
      _accountId = account.id;
      _folders = null;
      _folderError = null;
      unawaited(_loadFolders());
    }
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _debounce?.cancel();
    _refresh.dispose();
    super.dispose();
  }

  void _onEvent(RealtimeEvent e) {
    if (e.isResync ||
        (e.isMail && e.accountId == _accountId) ||
        e.type == 'account.error') {
      _scheduleFolderReload();
    }
  }

  void _scheduleFolderReload() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _loadFolders);
  }

  Future<void> _loadFolders() async {
    final accountId = _accountId;
    if (accountId == null) return;
    final gen = ++_gen;
    try {
      final folders = await AppScope.of(context).api.folders(accountId);
      if (!mounted || gen != _gen) return;
      setState(() {
        _folders = sortFolders(folders);
        _folderError = null;
      });
    } on Object catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() => _folderError = e);
    }
  }

  void _selectFolder(BuildContext context, String name) {
    SessionScope.read(context).selectFolder(name);
    final scaffold = Scaffold.maybeOf(context);
    if (scaffold?.isDrawerOpen ?? false) scaffold!.closeDrawer();
  }

  @override
  Widget build(BuildContext context) {
    final state = SessionScope.watch(context);
    final account = state.selectedAccount;
    if (account == null) return const Scaffold(body: LoadingView());

    final folders = _folders ?? const <Folder>[];
    Folder? current;
    for (final f in folders) {
      if (f.name == state.folder) current = f;
    }
    final title = current == null
        ? (state.folder == 'INBOX' ? 'Inbox' : state.folder)
        : folderLabel(current);
    final wide = MediaQuery.sizeOf(context).width >= 1100;

    Widget pane(BuildContext context) => FolderPane(
      accounts: state.accounts,
      selectedAccount: account,
      folders: _folders,
      error: _folderError,
      selectedFolder: state.folder,
      onRetry: _loadFolders,
      onSelectAccount: (id) {
        state.selectAccount(id);
        final scaffold = Scaffold.maybeOf(context);
        if (scaffold?.isDrawerOpen ?? false) scaffold!.closeDrawer();
      },
      onSelectFolder: (name) => _selectFolder(context, name),
    );

    return Scaffold(
      appBar: AppBar(
        title: AppBarTitle(title, subtitle: account.email),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _refresh.value++;
              unawaited(_loadFolders());
            },
          ),
        ],
      ),
      drawer: wide || widget.pushed
          ? null
          : Drawer(
              child: SafeArea(child: Builder(builder: pane)),
            ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'compose',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => ComposeScreen(account: account),
          ),
        ),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Compose'),
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (wide) ...[
            SizedBox(width: 300, child: Builder(builder: pane)),
            const VerticalDivider(width: 1),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (account.lastError.isNotEmpty)
                  _AccountErrorBanner(message: account.lastError),
                FilterBar(
                  selected: _filter,
                  unread: current?.unread ?? 0,
                  onSelected: (f) => setState(() => _filter = f),
                ),
                Expanded(
                  child: MessageList(
                    key: ValueKey('${account.id}|${state.folder}'),
                    filter: _filter,
                    account: account,
                    folder: state.folder,
                    folders: folders,
                    refresh: _refresh,
                    onChanged: _scheduleFolderReload,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Capsule filters above the list (All, Unread, Starred).
class FilterBar extends StatelessWidget {
  const FilterBar({
    required this.selected,
    required this.onSelected,
    required this.unread,
    super.key,
  });

  final MailFilter selected;
  final ValueChanged<MailFilter> onSelected;
  final int unread;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        children: [
          for (final f in MailFilter.values)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: ChoiceChip(
                label: Text(
                  f == MailFilter.unread && unread > 0
                      ? '${f.label} · ${unread > 999 ? '999+' : unread}'
                      : f.label,
                ),
                selected: f == selected,
                showCheckmark: false,
                onSelected: (_) => onSelected(f),
              ),
            ),
        ],
      ),
    );
  }
}

class _AccountErrorBanner extends StatelessWidget {
  const _AccountErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Material(
        color: scheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Problem with this account: $message',
                  style: TextStyle(color: scheme.onErrorContainer),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Account switcher and folder list, used as drawer or side pane.
class FolderPane extends StatelessWidget {
  const FolderPane({
    required this.accounts,
    required this.selectedAccount,
    required this.folders,
    required this.error,
    required this.selectedFolder,
    required this.onRetry,
    required this.onSelectAccount,
    required this.onSelectFolder,
    super.key,
  });

  final List<Account> accounts;
  final Account selectedAccount;
  final List<Folder>? folders;
  final Object? error;
  final String selectedFolder;
  final VoidCallback onRetry;
  final ValueChanged<String> onSelectAccount;
  final ValueChanged<String> onSelectFolder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(28),
    );
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Semantics(
            header: true,
            child: Text('Accounts', style: theme.textTheme.titleSmall),
          ),
        ),
        for (final (i, a) in accounts.indexed)
          ListTile(
            shape: shape,
            selected: a.id == selectedAccount.id,
            selectedTileColor: scheme.secondaryContainer,
            leading: InitialsAvatar(
              name: a.label,
              seed: a.email,
              radius: 16,
              coded: true,
              colorIndex: i,
            ),
            title: Text(a.label, overflow: TextOverflow.ellipsis),
            subtitle: a.label == a.email
                ? null
                : Text(a.email, overflow: TextOverflow.ellipsis),
            trailing: a.lastError.isEmpty
                ? null
                : Icon(
                    Icons.warning_amber_rounded,
                    color: scheme.error,
                    semanticLabel: 'Account problem',
                  ),
            onTap: () => onSelectAccount(a.id),
          ),
        const Divider(height: 24),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Semantics(
            header: true,
            child: Text('Folders', style: theme.textTheme.titleSmall),
          ),
        ),
        if (folders == null && error == null)
          const Padding(
            padding: EdgeInsets.all(24),
            child: LoadingView(label: 'Loading folders'),
          )
        else if (folders == null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text("Couldn't load folders"),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ],
            ),
          )
        else
          for (final f in folders!)
            ListTile(
              shape: shape,
              selected: f.name == selectedFolder,
              selectedTileColor: scheme.secondaryContainer,
              leading: Icon(folderIcon(f.role)),
              title: Text(folderLabel(f), overflow: TextOverflow.ellipsis),
              trailing: f.unread > 0 && f.role != FolderRole.trash
                  ? Text(
                      f.unread > 999 ? '999+' : '${f.unread}',
                      semanticsLabel: '${f.unread} unread',
                      style: theme.textTheme.labelLarge,
                    )
                  : null,
              onTap: () => onSelectFolder(f.name),
            ),
      ],
    );
  }
}
