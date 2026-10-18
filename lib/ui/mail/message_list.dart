import 'dart:async';

import 'package:flutter/material.dart';
import 'package:optional_mail_client/api/client.dart';
import 'package:optional_mail_client/ui/format.dart';
import 'package:optional_mail_client/ui/mail/message_screen.dart';
import 'package:optional_mail_client/ui/scope.dart';
import 'package:optional_mail_client/ui/widgets/avatar.dart';
import 'package:optional_mail_client/ui/widgets/dialogs.dart';
import 'package:optional_mail_client/ui/widgets/states.dart';

/// Paged list of messages in one folder.
class MessageList extends StatefulWidget {
  const MessageList({
    required this.account,
    required this.folder,
    required this.folders,
    super.key,
    this.refresh,
    this.onChanged,
  });

  final Account account;
  final String folder;

  /// All folders of the account (for roles, archive and move targets).
  final List<Folder> folders;

  /// Reloads the list when notified.
  final Listenable? refresh;

  /// Called after local changes that affect unread counts.
  final VoidCallback? onChanged;

  @override
  State<MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<MessageList> {
  static const _pageSize = 50;

  final _scroll = ScrollController();
  StreamSubscription<RealtimeEvent>? _sub;
  Timer? _debounce;

  List<MessageSummary> _items = [];
  final Set<String> _hidden = {}; // swiped away, waiting for undo
  String? _next;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;
  Object? _moreError;
  int _gen = 0;

  ApiClient get _api => AppScope.of(context).api;

  Folder? get _folderInfo {
    for (final f in widget.folders) {
      if (f.name == widget.folder) return f;
    }
    return null;
  }

  Folder? get _archive {
    if (!widget.account.isImap) return null;
    for (final f in widget.folders) {
      if (f.role == FolderRole.archive && f.name != widget.folder) return f;
    }
    return null;
  }

  bool get _deletesPermanently =>
      !widget.account.isImap || _folderInfo?.role == FolderRole.trash;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    widget.refresh?.addListener(_reload);
    unawaited(_load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sub ??= SessionScope.realtimeOf(context).events.listen(_onEvent);
  }

  @override
  void didUpdateWidget(MessageList old) {
    super.didUpdateWidget(old);
    if (old.refresh != widget.refresh) {
      old.refresh?.removeListener(_reload);
      widget.refresh?.addListener(_reload);
    }
  }

  @override
  void dispose() {
    widget.refresh?.removeListener(_reload);
    unawaited(_sub?.cancel());
    _debounce?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _onEvent(RealtimeEvent e) {
    final relevant =
        e.isResync ||
        (e.isMail &&
            e.accountId == widget.account.id &&
            (e.folder.isEmpty || e.folder == widget.folder));
    if (!relevant) return;
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => unawaited(_load(merge: true)),
    );
  }

  void _reload() => unawaited(_load(showSpinner: _items.isEmpty));

  void _onScroll() {
    if (_scroll.position.extentAfter < 600) unawaited(_loadMore());
  }

  /// Loads the newest page. With [merge], older pages already shown are kept
  /// (used for background refreshes so the scroll position survives).
  Future<void> _load({bool showSpinner = true, bool merge = false}) async {
    final gen = ++_gen;
    if (showSpinner && !merge) {
      setState(() {
        _loading = _items.isEmpty;
        _error = null;
      });
    }
    try {
      final page = await _api.messages(
        widget.account.id,
        folder: widget.folder,
        limit: _pageSize,
      );
      if (!mounted || gen != _gen) return;
      setState(() {
        var items = page.messages;
        var next = page.nextBefore;
        if (merge && page.messages.isNotEmpty && _items.isNotEmpty) {
          final lastId = page.messages.last.id;
          final i = _items.indexWhere((m) => m.id == lastId);
          if (i >= 0) {
            items = [...page.messages, ..._items.skip(i + 1)];
            next = _next;
          }
        }
        _items = items;
        _next = next;
        _loading = false;
        _error = null;
        _moreError = null;
      });
    } on Object catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _loading = false;
        // Keep showing what we have if a background refresh fails.
        if (_items.isEmpty) _error = e;
      });
      if (_items.isNotEmpty && !merge) showError(context, e);
    }
  }

  Future<void> _loadMore() async {
    final before = _next;
    if (before == null || _loadingMore || _loading) return;
    final gen = _gen;
    setState(() {
      _loadingMore = true;
      _moreError = null;
    });
    try {
      final page = await _api.messages(
        widget.account.id,
        folder: widget.folder,
        before: before,
        limit: _pageSize,
      );
      if (!mounted || gen != _gen) return;
      final known = {for (final m in _items) m.id};
      setState(() {
        _items = [
          ..._items,
          ...page.messages.where((m) => !known.contains(m.id)),
        ];
        _next = page.nextBefore;
      });
    } on Object catch (e) {
      if (mounted) setState(() => _moreError = e);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _replace(MessageSummary updated) {
    if (!mounted) return;
    setState(() {
      _items = [for (final m in _items) m.id == updated.id ? updated : m];
    });
  }

  void _remove(String id) {
    if (!mounted) return;
    setState(() {
      _items = _items.where((m) => m.id != id).toList();
      _hidden.remove(id);
    });
    widget.onChanged?.call();
  }

  Future<void> _toggleStar(MessageSummary m) async {
    final api = _api;
    _replace(m.copyWith(flagged: !m.flagged));
    try {
      await api.updateFlags(
        widget.account.id,
        m.id,
        folder: widget.folder,
        flagged: !m.flagged,
      );
    } on Object catch (e) {
      _replace(m);
      if (mounted) showError(context, e);
    }
  }

  Future<void> _open(MessageSummary m) async {
    if (!m.seen) {
      _replace(m.copyWith(seen: true));
      widget.onChanged?.call();
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MessageScreen(
          account: widget.account,
          summary: m,
          folders: widget.folders,
          onChanged: (u) {
            _replace(u);
            widget.onChanged?.call();
          },
          onRemoved: () => _remove(m.id),
        ),
      ),
    );
  }

  /// Swipe action with an undo window: the server call is made only after
  /// the snack bar closes without "Undo".
  Future<void> _swiped(MessageSummary m, {required bool archive}) async {
    final api = _api;
    final archiveFolder = _archive?.name;
    final accountId = widget.account.id;
    final folder = widget.folder;
    setState(() => _hidden.add(m.id));

    final text = archive
        ? 'Archived'
        : (_deletesPermanently ? 'Deleted permanently' : 'Moved to Trash');
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    final reason = await messenger
        .showSnackBar(
          SnackBar(
            content: Text(text),
            persist: false,
            action: SnackBarAction(label: 'Undo', onPressed: () {}),
          ),
        )
        .closed;
    if (reason == SnackBarClosedReason.action) {
      if (mounted) setState(() => _hidden.remove(m.id));
      return;
    }
    try {
      if (archive && archiveFolder != null) {
        await api.moveMessage(
          accountId,
          m.id,
          folder: folder,
          to: archiveFolder,
        );
      } else {
        await api.deleteMessage(accountId, m.id, folder: folder);
      }
      _remove(m.id);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _hidden.remove(m.id));
      showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _items.isEmpty) return const ListSkeleton();
    if (_error != null && _items.isEmpty) {
      return ErrorView(error: _error, onRetry: _load);
    }
    final visible = _items.where((m) => !_hidden.contains(m.id)).toList();
    final isSent =
        _folderInfo?.role == FolderRole.sent ||
        _folderInfo?.role == FolderRole.drafts;
    final archive = _archive;

    return RefreshIndicator(
      onRefresh: () => _load(showSpinner: false),
      child: visible.isEmpty
          ? const MessageView(
              icon: Icons.inbox_outlined,
              title: 'No messages',
              message: 'This folder is empty.',
            )
          : ListView.separated(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: visible.length + 1,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
              itemBuilder: (context, i) {
                if (i == visible.length) return _footer();
                final m = visible[i];
                return Dismissible(
                  key: ValueKey('msg-${m.id}'),
                  direction: archive != null
                      ? DismissDirection.horizontal
                      : DismissDirection.endToStart,
                  background: _SwipeBackground(
                    icon: Icons.archive_outlined,
                    label: 'Archive',
                    color: Theme.of(context).colorScheme.tertiaryContainer,
                    alignment: AlignmentDirectional.centerStart,
                  ),
                  secondaryBackground: _SwipeBackground(
                    icon: Icons.delete_outline,
                    label: 'Delete',
                    color: Theme.of(context).colorScheme.errorContainer,
                    alignment: AlignmentDirectional.centerEnd,
                  ),
                  onDismissed: (dir) => unawaited(
                    _swiped(m, archive: dir == DismissDirection.startToEnd),
                  ),
                  child: MessageTile(
                    message: m,
                    showRecipients: isSent,
                    onTap: () => _open(m),
                    onToggleStar: () => _toggleStar(m),
                  ),
                );
              },
            ),
    );
  }

  Widget _footer() {
    if (_next == null) return const SizedBox(height: 16);
    if (_moreError != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: TextButton.icon(
            onPressed: _loadMore,
            icon: const Icon(Icons.refresh),
            label: const Text("Couldn't load more. Try again"),
          ),
        ),
      );
    }
    // Short lists never scroll, so ask for more when the footer is built.
    if (!_loadingMore) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_loadMore());
      });
    }
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Center(child: LoadingView(label: 'Loading more messages')),
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({
    required this.icon,
    required this.label,
    required this.color,
    required this.alignment,
  });

  final IconData icon;
  final String label;
  final Color color;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: color,
    child: Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [Icon(icon), const SizedBox(width: 8), Text(label)],
        ),
      ),
    ),
  );
}

/// One row in the message list.
class MessageTile extends StatelessWidget {
  const MessageTile({
    required this.message,
    required this.onTap,
    required this.onToggleStar,
    super.key,
    this.showRecipients = false,
  });

  final MessageSummary message;
  final VoidCallback onTap;
  final VoidCallback onToggleStar;
  final bool showRecipients;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final m = message;
    final unread = !m.seen;
    final who = showRecipients && m.to.isNotEmpty
        ? 'To: ${m.to.map((a) => a.label).join(', ')}'
        : (m.from.label.isEmpty ? '(unknown sender)' : m.from.label);
    final subject = m.subject.trim().isEmpty ? '(no subject)' : m.subject;
    final date = formatListDate(m.date);
    final weight = unread ? FontWeight.w700 : FontWeight.w400;
    final semantics = [
      if (unread) 'Unread',
      if (m.flagged) 'Starred',
      who,
      subject,
      date,
      if (m.hasAttachments) 'Has attachments',
    ].join('. ');

    return Semantics(
      container: true,
      button: true,
      label: semantics,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 4, 10),
          child: Row(
            children: [
              ExcludeSemantics(
                child: InitialsAvatar(
                  name: showRecipients && m.to.isNotEmpty
                      ? m.to.first.label
                      : m.from.label,
                  seed: showRecipients && m.to.isNotEmpty
                      ? m.to.first.email
                      : m.from.email,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ExcludeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              who,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: weight,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            date,
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: weight,
                              color: unread
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (m.answered)
                            Padding(
                              padding: const EdgeInsetsDirectional.only(end: 4),
                              child: Icon(
                                Icons.reply,
                                size: 16,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          Expanded(
                            child: Text(
                              subject,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: weight,
                                color: unread
                                    ? scheme.onSurface
                                    : scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          if (m.hasAttachments)
                            Padding(
                              padding: const EdgeInsetsDirectional.only(
                                start: 4,
                              ),
                              child: Icon(
                                Icons.attach_file,
                                size: 18,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: m.flagged ? 'Remove star' : 'Star',
                isSelected: m.flagged,
                onPressed: onToggleStar,
                icon: const Icon(Icons.star_outline),
                selectedIcon: Icon(Icons.star, color: Colors.amber.shade700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
