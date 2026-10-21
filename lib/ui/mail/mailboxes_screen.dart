import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoButton, CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:optional_mail_client/api/client.dart';
import 'package:optional_mail_client/ui/design.dart';
import 'package:optional_mail_client/ui/format.dart';
import 'package:optional_mail_client/ui/mail/mail_screen.dart';
import 'package:optional_mail_client/ui/mail/message_list.dart';
import 'package:optional_mail_client/ui/mail/message_screen.dart';
import 'package:optional_mail_client/ui/mail/search_screen.dart';
import 'package:optional_mail_client/ui/scope.dart';
import 'package:optional_mail_client/ui/widgets/avatar.dart';
import 'package:optional_mail_client/ui/widgets/states.dart';

/// A recent message together with the account it belongs to.
typedef Recent = ({Account account, MessageSummary message});

const _recentsPerAccount = 10;
const _recentsShown = 12;

/// iOS root of the Mail tab: accounts first, then "Recents", a merged newest-first list across
/// accounts. Tapping an account opens its folders; the inbox is a pushed screen with the
/// system back gesture. Android and wide layouts keep the drawer and are unaffected.
class MailboxesScreen extends StatefulWidget {
  const MailboxesScreen({super.key});

  @override
  State<MailboxesScreen> createState() => _MailboxesScreenState();
}

class _MailboxesScreenState extends State<MailboxesScreen> {
  StreamSubscription<RealtimeEvent>? _sub;
  Timer? _debounce;
  Map<String, List<Folder>> _folders = {};
  List<Recent> _recents = const [];
  Object? _error;
  bool _loaded = false;
  int _gen = 0;
  int _seenOpenRequest = 0;
  String _accountsKey = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sub ??= SessionScope.realtimeOf(context).events.listen((e) {
      if (e.isResync || e.isMail || e.type == 'account.error') _schedule();
    });
    final state = SessionScope.watch(context);
    final key = state.accounts.map((a) => a.id).join(',');
    if (key != _accountsKey) {
      _accountsKey = key;
      unawaited(_load());
    }
    // A tapped push notification asks for a mailbox: show its inbox.
    if (state.openRequest != _seenOpenRequest) {
      _seenOpenRequest = state.openRequest;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openInbox(state.selectedAccount);
      });
    }
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _debounce?.cancel();
    super.dispose();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _load);
  }

  /// ponytail: one page per account, merged client-side. A server-side unified list (with paging)
  /// is the upgrade once accounts routinely have more than a handful of busy inboxes.
  Future<void> _load() async {
    if (!mounted) return;
    final api = AppScope.of(context).api;
    final accounts = SessionScope.read(context).accounts;
    final gen = ++_gen;
    try {
      final results = await Future.wait([
        for (final a in accounts)
          Future.wait([
            api.folders(a.id),
            api.messages(a.id, folder: 'INBOX', limit: _recentsPerAccount),
          ]),
      ]);
      if (!mounted || gen != _gen) return;
      final folders = <String, List<Folder>>{};
      final recents = <Recent>[];
      for (var i = 0; i < accounts.length; i++) {
        folders[accounts[i].id] = sortFolders(results[i][0] as List<Folder>);
        for (final m in (results[i][1] as MessagePage).messages) {
          recents.add((account: accounts[i], message: m));
        }
      }
      recents.sort((a, b) => b.message.date.compareTo(a.message.date));
      setState(() {
        _folders = folders;
        _recents = recents.take(_recentsShown).toList();
        _error = null;
        _loaded = true;
      });
    } on Object catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _error = e;
        _loaded = true;
      });
    }
  }

  void _openInbox(Account? account) {
    if (account == null) return;
    final state = SessionScope.read(context)
      ..selectAccount(account.id)
      ..selectFolder('INBOX');
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const MailScreen(pushed: true)),
      ),
    );
    assert(state.selectedAccount?.id == account.id);
  }

  void _openAccount(Account account) {
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AccountFoldersScreen(
            account: account,
            folders: _folders[account.id] ?? const [],
          ),
        ),
      ),
    );
  }

  Future<void> _openMessage(Recent r) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MessageScreen(
          account: r.account,
          summary: r.message,
          folders: _folders[r.account.id] ?? const [],
          onChanged: (_) => _schedule(),
          onRemoved: _schedule,
        ),
      ),
    );
    _schedule();
  }

  @override
  Widget build(BuildContext context) {
    final state = SessionScope.watch(context);
    final theme = Theme.of(context);
    final t = Palette.of(theme.brightness);
    Widget header(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            largeTitleBar(
              context,
              'Mailboxes',
              trailing: CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size.square(44),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const SearchScreen()),
                ),
                child: const Icon(
                  CupertinoIcons.search,
                  semanticLabel: 'Search',
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Material(
                  color: t.grouped,
                  borderRadius: BorderRadius.circular(14),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (var i = 0; i < state.accounts.length; i++) ...[
                        if (i > 0) Divider(indent: 60, color: t.line),
                        _AccountRow(
                          account: state.accounts[i],
                          colorIndex: i,
                          unread: _inboxUnread(state.accounts[i]),
                          onTap: () => _openAccount(state.accounts[i]),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(child: header('Recents')),
            if (!_loaded)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: LoadingView(label: 'Loading recent mail'),
                ),
              )
            else if (_error != null && _recents.isEmpty)
              SliverToBoxAdapter(
                child: MessageView(
                  icon: Icons.cloud_off_outlined,
                  title: "Couldn't load recent mail",
                  message: describeError(_error),
                  action: FilledButton(
                    onPressed: _load,
                    child: const Text('Try again'),
                  ),
                ),
              )
            else if (_recents.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: Text('No recent mail')),
                ),
              )
            else
              SliverList.separated(
                itemCount: _recents.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, indent: 76),
                itemBuilder: (context, i) {
                  final r = _recents[i];
                  return MessageTile(
                    message: r.message,
                    accent: state.accounts.length > 1
                        ? systemColorAt(
                            state.accountIndex(r.account.id),
                            theme.brightness,
                          )
                        : null,
                    onTap: () => unawaited(_openMessage(r)),
                    onToggleStar: null,
                  );
                },
              ),
            // Room for the floating glass tab bar.
            SliverToBoxAdapter(
              child: SizedBox(height: MediaQuery.paddingOf(context).bottom),
            ),
          ],
        ),
      ),
    );
  }

  int? _inboxUnread(Account a) {
    final folders = _folders[a.id];
    if (folders == null) return null;
    for (final f in folders) {
      if (f.role == FolderRole.inbox || f.name.toUpperCase() == 'INBOX') {
        return f.unread;
      }
    }
    return null;
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.account,
    required this.colorIndex,
    required this.unread,
    required this.onTap,
  });

  final Account account;
  final int colorIndex;
  final int? unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final problem = account.lastError.isNotEmpty;
    final status = problem
        ? 'Not instant: ${account.lastError}'
        : account.incomingProtocol == IncomingProtocol.imap
        ? 'Instant'
        : 'Checks every few minutes';
    return Semantics(
      button: true,
      label:
          '${account.label}. ${unread == null ? '' : '$unread unread. '}$status',
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: ExcludeSemantics(
            child: Row(
              children: [
                InitialsAvatar(
                  name: account.label,
                  seed: account.email,
                  radius: 16,
                  coded: true,
                  colorIndex: colorIndex,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account.label,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: problem
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (unread != null && unread! > 0)
                  Text(
                    unread! > 999 ? '999+' : '$unread',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Folders of one account, as an inset grouped list like iOS Mail.
class AccountFoldersScreen extends StatelessWidget {
  const AccountFoldersScreen({
    required this.account,
    required this.folders,
    super.key,
  });

  final Account account;
  final List<Folder> folders;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = Palette.of(theme.brightness);
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          largeTitleBar(context, account.label, previousPageTitle: 'Mailboxes'),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Material(
                color: t.grouped,
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (var i = 0; i < folders.length; i++) ...[
                      if (i > 0) Divider(indent: 52, color: t.line),
                      ListTile(
                        leading: Icon(
                          folderIcon(folders[i].role),
                          color: theme.colorScheme.primary,
                        ),
                        title: Text(folderLabel(folders[i])),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (folders[i].unread > 0 &&
                                folders[i].role != FolderRole.trash)
                              Text(
                                '${folders[i].unread}',
                                semanticsLabel: '${folders[i].unread} unread',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            Icon(
                              Icons.chevron_right,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ],
                        ),
                        onTap: () {
                          SessionScope.read(context)
                            ..selectAccount(account.id)
                            ..selectFolder(folders[i].name);
                          unawaited(
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const MailScreen(pushed: true),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
