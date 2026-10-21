import 'dart:async';

import 'package:flutter/material.dart';
import 'package:optional_mail_client/api/cache.dart';
import 'package:optional_mail_client/api/client.dart';
import 'package:optional_mail_client/ui/design.dart';
import 'package:optional_mail_client/ui/format.dart';
import 'package:optional_mail_client/ui/mail/message_screen.dart';
import 'package:optional_mail_client/ui/scope.dart';
import 'package:optional_mail_client/ui/widgets/avatar.dart';
import 'package:optional_mail_client/ui/widgets/dialogs.dart';
import 'package:optional_mail_client/ui/widgets/states.dart';

/// Which messages a folder view shows.
enum MailFilter {
  all('All'),
  unread('Unread'),
  starred('Starred');

  const MailFilter(this.label);
  final String label;

  bool accepts(MessageSummary m) => switch (this) {
    all => true,
    unread => !m.seen,
    starred => m.flagged,
  };
}

/// Paged list of messages in one folder.
class MessageList extends StatefulWidget {
  const MessageList({
    required this.account,
    required this.folder,
    required this.folders,
    super.key,
    this.refresh,
    this.onChanged,
    this.filter = MailFilter.all,
  });

  final Account account;

  /// Applied to the pages loaded so far; more pages are fetched until it fills.
  final MailFilter filter;
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

  StreamSubscription<RealtimeEvent>? _sub;
  Timer? _debounce;

  List<MessageSummary> _items = [];
  final Set<String> _hidden = {}; // swiped away, waiting for undo
  String? _next;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;
  Object? _moreError;
  bool _offline =
      false; // showing saved messages because the master is unreachable
  int _gen = 0;

  ApiClient get _api => AppScope.of(context).api;
  MailCache get _cache => AppScope.of(context).cache;

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
    widget.refresh?.addListener(_reload);
    unawaited(_showSaved().then((_) => _load()));
  }

  /// Shows the last saved page right away while the fresh one loads.
  Future<void> _showSaved() async {
    final saved = await _cache.page(widget.account.id, widget.folder);
    if (!mounted || saved == null || _items.isNotEmpty) return;
    setState(() {
      _items = saved.messages;
      _next = saved.next;
      _loading = false;
    });
  }

  void _persist() => unawaited(
    _cache.savePage(widget.account.id, widget.folder, _items, next: _next),
  );

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

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis == Axis.vertical && n.metrics.extentAfter < 600) {
      unawaited(_loadMore());
    }
    return false;
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
        _offline = false;
      });
      _persist();
    } on Object catch (e) {
      if (!mounted || gen != _gen) return;
      final unreachable = e is ApiException && e.isNetwork;
      setState(() {
        _loading = false;
        // Keep showing what we have if a refresh fails.
        if (_items.isEmpty) _error = e;
        if (_items.isNotEmpty && unreachable) _offline = true;
      });
      if (_items.isNotEmpty && !merge && !unreachable) showError(context, e);
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
      _persist();
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
    _persist();
  }

  void _remove(String id) {
    if (!mounted) return;
    setState(() {
      _items = _items.where((m) => m.id != id).toList();
      _hidden.remove(id);
    });
    _persist();
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
    final visible = _items
        .where((m) => !_hidden.contains(m.id) && widget.filter.accepts(m))
        .toList();
    final isSent =
        _folderInfo?.role == FolderRole.sent ||
        _folderInfo?.role == FolderRole.drafts;
    final archive = _archive;

    final list = NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: RefreshIndicator(
        onRefresh: () => _load(showSpinner: false),
        child: visible.isEmpty
            ? _empty()
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: visible.length + 1,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, indent: 76),
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
      ),
    );
    if (!_offline) return list;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _OfflineBanner(),
        Expanded(child: list),
      ],
    );
  }

  Widget _empty() {
    final filter = widget.filter;
    // The filter may match older pages that are not loaded yet.
    if (filter != MailFilter.all && _next != null && _moreError == null) {
      if (!_loadingMore) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_loadMore());
        });
      }
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          Padding(
            padding: EdgeInsets.all(32),
            child: LoadingView(label: 'Looking for messages'),
          ),
        ],
      );
    }
    return switch (filter) {
      MailFilter.all => const MessageView(
        icon: Icons.inbox_outlined,
        title: 'No messages',
        message: 'This folder is empty.',
      ),
      MailFilter.unread => const MessageView(
        icon: Icons.mark_email_read_outlined,
        title: 'All caught up',
        message: 'No unread messages here.',
      ),
      MailFilter.starred => const MessageView(
        icon: Icons.star_border,
        title: 'No starred messages',
        message: 'Star a message to find it here.',
      ),
    };
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

/// Shown over saved messages while the master can't be reached.
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Material(
        color: scheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.cloud_off_outlined, size: 18, color: scheme.onSurface),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Offline. Showing messages saved on this device.'),
              ),
            ],
          ),
        ),
      ),
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
    this.accent,
  });

  final MessageSummary message;
  final VoidCallback onTap;
  final VoidCallback? onToggleStar;
  final bool showRecipients;

  /// Colour of the account this message belongs to (shown as a thin edge bar in merged lists).
  final Color? accent;

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

    final tile = Semantics(
      container: true,
      button: true,
      label: semantics,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(6, 10, 4, 10),
          child: Row(
            children: [
              // iOS-style unread marker in the leading gutter.
              SizedBox(
                width: 14,
                child: unread
                    ? ExcludeSemantics(
                        child: Center(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              shape: BoxShape.circle,
                            ),
                            child: const SizedBox.square(dimension: 9),
                          ),
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 4),
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
                              color: scheme.onSurfaceVariant,
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
              // iOS shows the star only on starred rows; Android always offers it.
              if (onToggleStar != null && (m.flagged || !isIOS(context)))
                IconButton(
                  tooltip: m.flagged ? 'Remove star' : 'Star',
                  isSelected: m.flagged,
                  onPressed: onToggleStar,
                  icon: const Icon(Icons.star_outline),
                  selectedIcon: const Icon(
                    Icons.star,
                    color: Color(0xFFFF9F0A),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (accent == null) return tile;
    return Stack(
      children: [
        tile,
        Positioned.fill(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: ExcludeSemantics(
              child: Container(width: 3, height: 44, color: accent),
            ),
          ),
        ),
      ],
    );
  }
}
