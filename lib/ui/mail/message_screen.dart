import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:optional_mail_client/api/client.dart';
import 'package:optional_mail_client/ui/design.dart';
import 'package:optional_mail_client/ui/format.dart';
import 'package:optional_mail_client/ui/mail/compose_screen.dart';
import 'package:optional_mail_client/ui/mail/invite_card.dart';
import 'package:optional_mail_client/ui/mail/mail_screen.dart';
import 'package:optional_mail_client/ui/scope.dart';
import 'package:optional_mail_client/ui/widgets/attachment_saver.dart';
import 'package:optional_mail_client/ui/widgets/avatar.dart';
import 'package:optional_mail_client/ui/widgets/dialogs.dart';
import 'package:optional_mail_client/ui/widgets/html_body.dart';
import 'package:optional_mail_client/ui/widgets/states.dart';

class MessageScreen extends StatefulWidget {
  const MessageScreen({
    required this.account,
    required this.summary,
    required this.folders,
    required this.onChanged,
    required this.onRemoved,
    super.key,
  });

  final Account account;
  final MessageSummary summary;
  final List<Folder> folders;

  /// Flags changed (seen / flagged).
  final ValueChanged<MessageSummary> onChanged;

  /// The message was moved or deleted.
  final VoidCallback onRemoved;

  @override
  State<MessageScreen> createState() => _MessageScreenState();
}

class _MessageScreenState extends State<MessageScreen> {
  Message? _message;
  Object? _error;
  late MessageSummary _summary = widget.summary;
  bool _busy = false;
  int? _downloading;

  String get _folder =>
      widget.summary.folder.isEmpty ? 'INBOX' : widget.summary.folder;

  ApiClient get _api => AppScope.of(context).api;

  Folder? get _currentFolder {
    for (final f in widget.folders) {
      if (f.name == _folder) return f;
    }
    return null;
  }

  Folder? get _archive {
    if (!widget.account.isImap) return null;
    for (final f in widget.folders) {
      if (f.role == FolderRole.archive && f.name != _folder) return f;
    }
    return null;
  }

  bool get _deletesPermanently =>
      !widget.account.isImap || _currentFolder?.role == FolderRole.trash;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final api = _api;
    final cache = AppScope.of(context).cache;
    setState(() => _error = null);
    // A message already read opens instantly and works offline.
    final saved = await cache.message(widget.account.id, _folder, _summary.id);
    if (!mounted) return;
    if (saved != null && _message == null) setState(() => _message = saved);
    try {
      final m = await api.message(
        widget.account.id,
        _summary.id,
        folder: _folder,
      );
      if (!mounted) return;
      setState(() => _message = m);
      unawaited(cache.saveMessage(widget.account.id, m));
      if (!m.seen) {
        // Opening a message marks it read (GET does not).
        try {
          await api.updateFlags(
            widget.account.id,
            m.id,
            folder: _folder,
            seen: true,
          );
          _setFlags(seen: true);
        } on ApiException catch (e) {
          debugPrint('mark read failed: ${e.code}');
        }
      }
    } on Object catch (e) {
      // Keep showing the saved copy when the master is unreachable.
      if (mounted && _message == null) setState(() => _error = e);
    }
  }

  void _setFlags({bool? seen, bool? flagged}) {
    _summary = _summary.copyWith(seen: seen, flagged: flagged);
    widget.onChanged(_summary);
    if (mounted) setState(() {});
  }

  Future<void> _toggleStar() async {
    final flagged = !_summary.flagged;
    _setFlags(flagged: flagged);
    try {
      await _api.updateFlags(
        widget.account.id,
        _summary.id,
        folder: _folder,
        flagged: flagged,
      );
    } on Object catch (e) {
      _setFlags(flagged: !flagged);
      if (mounted) showError(context, e);
    }
  }

  Future<void> _markUnread() async {
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      await _api.updateFlags(
        widget.account.id,
        _summary.id,
        folder: _folder,
        seen: false,
      );
      _setFlags(seen: false);
      navigator.pop();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showError(context, e);
    }
  }

  Future<void> _delete() async {
    if (_deletesPermanently &&
        !await confirm(
          context,
          title: 'Delete permanently?',
          message: 'This message will be removed and cannot be recovered.',
          confirmLabel: 'Delete',
          destructive: true,
        )) {
      return;
    }
    if (!mounted) return;
    await _run(
      () => _api.deleteMessage(widget.account.id, _summary.id, folder: _folder),
      done: _deletesPermanently ? 'Message deleted' : 'Moved to Trash',
    );
  }

  Future<void> _moveTo(String target, String label) => _run(
    () => _api.moveMessage(
      widget.account.id,
      _summary.id,
      folder: _folder,
      to: target,
    ),
    done: 'Moved to $label',
  );

  Future<void> _chooseFolder() async {
    final targets = widget.folders.where((f) => f.name != _folder).toList();
    final chosen = await showDialog<Folder>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Move to'),
        children: [
          for (final f in targets)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, f),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 40),
                child: Row(
                  children: [
                    Icon(folderIcon(f.role)),
                    const SizedBox(width: 16),
                    Expanded(child: Text(folderLabel(f))),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
    if (chosen != null && mounted) {
      await _moveTo(chosen.name, folderLabel(chosen));
    }
  }

  /// Runs a removing action, then leaves the screen.
  Future<void> _run(
    Future<void> Function() action, {
    required String done,
  }) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await action();
      widget.onRemoved();
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showError(context, e);
    }
  }

  void _compose(ComposeDraft draft) {
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => ComposeScreen(account: widget.account, draft: draft),
        ),
      ),
    );
  }

  Future<void> _download(AttachmentInfo a, BuildContext tileContext) async {
    final box = tileContext.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    setState(() => _downloading = a.index);
    try {
      final file = await _api.attachment(
        widget.account.id,
        _summary.id,
        folder: _folder,
        index: a.index,
      );
      final note = await saveAttachment(
        bytes: file.bytes,
        filename: a.filename.isEmpty ? 'attachment-${a.index}' : a.filename,
        contentType: a.contentType.isEmpty ? file.contentType : a.contentType,
        origin: origin,
      );
      if (note != null && mounted) showSnack(context, note);
    } on Object catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _downloading = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = _message;
    final archive = _archive;
    final ios = isIOS(context);
    return Scaffold(
      appBar: AppBar(
        leading: const BackChevron(),
        actions: [
          IconButton(
            tooltip: _summary.flagged ? 'Remove star' : 'Star',
            isSelected: _summary.flagged,
            onPressed: _busy ? null : _toggleStar,
            icon: Icon(ios ? CupertinoIcons.star : Icons.star_outline),
            selectedIcon: Icon(
              ios ? CupertinoIcons.star_fill : Icons.star,
              color: const Color(0xFFFF9F0A),
            ),
          ),
          if (archive != null)
            IconButton(
              tooltip: 'Archive',
              onPressed: _busy ? null : () => _moveTo(archive.name, 'Archive'),
              icon: Icon(
                ios ? CupertinoIcons.archivebox : Icons.archive_outlined,
              ),
            ),
          IconButton(
            tooltip: 'Delete',
            onPressed: _busy ? null : _delete,
            icon: Icon(ios ? CupertinoIcons.trash : Icons.delete_outline),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: Icon(ios ? CupertinoIcons.ellipsis_circle : Icons.more_vert),
            enabled: !_busy,
            onSelected: (v) => switch (v) {
              'unread' => _markUnread(),
              'move' => _chooseFolder(),
              _ => Future<void>.value(),
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'unread',
                child: ListTile(
                  leading: Icon(Icons.mark_email_unread_outlined),
                  title: Text('Mark as unread'),
                ),
              ),
              if (widget.account.isImap && widget.folders.length > 1)
                const PopupMenuItem(
                  value: 'move',
                  child: ListTile(
                    leading: Icon(Icons.drive_file_move_outline),
                    title: Text('Move to…'),
                  ),
                ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: m == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _compose(
                          ComposeDraft.reply(m, account: widget.account),
                        ),
                        icon: const Icon(Icons.reply),
                        label: const Text(
                          'Reply',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _compose(
                          ComposeDraft.reply(
                            m,
                            account: widget.account,
                            all: true,
                          ),
                        ),
                        icon: const Icon(Icons.reply_all),
                        label: const Text(
                          'Reply all',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _compose(ComposeDraft.forward(m)),
                        icon: const Icon(Icons.forward),
                        label: const Text(
                          'Forward',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(),
          Expanded(child: _body(m)),
        ],
      ),
    );
  }

  Widget _body(Message? m) {
    if (m == null) {
      return _error != null
          ? ErrorView(error: _error, onRetry: _load)
          : const LoadingView(label: 'Loading message');
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SelectionArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      m.subject.trim().isEmpty ? '(no subject)' : m.subject,
                      style: theme.textTheme.headlineSmall,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _Headers(message: m),
                  if (m.remoteContentBlocked) ...[
                    const SizedBox(height: 12),
                    _InfoBanner(
                      icon: Icons.image_not_supported_outlined,
                      text:
                          'Remote images and content were blocked to protect '
                          'your privacy.',
                      color: scheme.secondaryContainer,
                      onColor: scheme.onSecondaryContainer,
                    ),
                  ],
                  if (inviteAttachment(m) case final invite?) ...[
                    const SizedBox(height: 12),
                    InviteCard(
                      key: ValueKey('invite-${m.id}'),
                      account: widget.account,
                      message: m,
                      attachment: invite,
                    ),
                  ],
                  if (m.attachments.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    for (final a in m.attachments)
                      Builder(
                        builder: (tileContext) => Card.outlined(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: const Icon(Icons.attach_file),
                            title: Text(
                              a.filename.isEmpty
                                  ? 'Attachment ${a.index + 1}'
                                  : a.filename,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(formatBytes(a.size)),
                            trailing: _downloading == a.index
                                ? const SizedBox.square(
                                    dimension: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.download_outlined),
                            onTap: _downloading != null
                                ? null
                                : () => _download(a, tileContext),
                          ),
                        ),
                      ),
                  ],
                  const Divider(height: 24),
                ],
              ),
            ),
          ),
          MessageBodySliver(
            html: m.html,
            text: m.text,
            onMailto: (address) =>
                _compose(ComposeDraft(to: [?parseAddress(address)])),
          ),
        ],
      ),
    );
  }
}

class _Headers extends StatefulWidget {
  const _Headers({required this.message});

  final Message message;

  @override
  State<_Headers> createState() => _HeadersState();
}

class _HeadersState extends State<_Headers> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    String list(List<Address> a) => a.map((x) => x.formatted).join(', ');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InitialsAvatar(name: m.from.label, seed: m.from.email),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(m.from.label, style: theme.textTheme.titleSmall),
              if (m.from.name.isNotEmpty) Text(m.from.email, style: muted),
              Text(formatFullDate(m.date), style: muted),
              if (_expanded) ...[
                const SizedBox(height: 8),
                if (m.to.isNotEmpty) Text('To: ${list(m.to)}', style: muted),
                if (m.cc.isNotEmpty) Text('Cc: ${list(m.cc)}', style: muted),
                if (m.replyTo.isNotEmpty)
                  Text('Reply-To: ${list(m.replyTo)}', style: muted),
              ] else if (m.to.isNotEmpty)
                Text(
                  'To: ${m.to.map((a) => a.label).join(', ')}',
                  style: muted,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        IconButton(
          tooltip: _expanded ? 'Hide details' : 'Show details',
          onPressed: () => setState(() => _expanded = !_expanded),
          icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
        ),
      ],
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({
    required this.icon,
    required this.text,
    required this.color,
    required this.onColor,
  });

  final IconData icon;
  final String text;
  final Color color;
  final Color onColor;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Icon(icon, color: onColor),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text, style: TextStyle(color: onColor)),
        ),
      ],
    ),
  );
}
