import 'dart:async';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:optional_mail_client/api/client.dart';
import 'package:optional_mail_client/ui/format.dart';
import 'package:optional_mail_client/ui/scope.dart';
import 'package:optional_mail_client/ui/widgets/dialogs.dart';
import 'package:optional_mail_client/ui/widgets/recipient_field.dart';

/// Raw attachment bytes allowed per message. `POST /send` accepts 25 MiB of
/// JSON and base64 adds a third, so stay well below that.
const maxAttachmentBytes = 18 * 1024 * 1024;

/// Initial contents of the compose screen.
class ComposeDraft {
  const ComposeDraft({
    this.to = const [],
    this.cc = const [],
    this.bcc = const [],
    this.subject = '',
    this.body = '',
    this.inReplyTo,
    this.references = const [],
  });

  /// Reply (or reply-all) quoting the original text.
  factory ComposeDraft.reply(
    Message m, {
    required Account account,
    bool all = false,
  }) {
    final me = account.email.toLowerCase();
    final primary = m.replyTo.isNotEmpty ? m.replyTo : [m.from];
    final seen = <String>{me};
    List<Address> unique(Iterable<Address> list) => [
      for (final a in list)
        if (a.email.isNotEmpty && seen.add(a.email.toLowerCase())) a,
    ];
    var to = unique(primary);
    // Replying to your own sent message: address the original recipients.
    if (to.isEmpty) to = unique(m.to);
    final cc = all ? unique([...m.to, ...m.cc]) : <Address>[];
    return ComposeDraft(
      to: to,
      cc: cc,
      subject: _prefixed('Re:', m.subject),
      body: '\n\n${_quote(m)}',
      inReplyTo: m.messageId.isEmpty ? null : m.messageId,
      references: [
        ...m.references,
        if (m.messageId.isNotEmpty && !m.references.contains(m.messageId))
          m.messageId,
      ],
    );
  }

  /// Forward with the original text included.
  factory ComposeDraft.forward(Message m) {
    String list(List<Address> a) => a.map((x) => x.formatted).join(', ');
    final header = StringBuffer()
      ..writeln('---------- Forwarded message ----------')
      ..writeln('From: ${m.from.formatted}')
      ..writeln('Date: ${formatFullDate(m.date)}')
      ..writeln('Subject: ${m.subject}')
      ..writeln('To: ${list(m.to)}');
    if (m.cc.isNotEmpty) header.writeln('Cc: ${list(m.cc)}');
    return ComposeDraft(
      subject: _prefixed('Fwd:', m.subject),
      body: '\n\n$header\n${_bodyText(m)}',
    );
  }

  final List<Address> to;
  final List<Address> cc;
  final List<Address> bcc;
  final String subject;
  final String body;
  final String? inReplyTo;
  final List<String> references;

  static String _prefixed(String prefix, String subject) {
    final s = subject.trim();
    final lower = s.toLowerCase();
    if (lower.startsWith(prefix.toLowerCase())) return s;
    if (prefix == 'Fwd:' && lower.startsWith('fw:')) return s;
    return s.isEmpty ? prefix : '$prefix $s';
  }

  static String _bodyText(Message m) =>
      m.text.trim().isNotEmpty ? m.text.trimRight() : htmlToText(m.html);

  static String _quote(Message m) {
    final quoted = _bodyText(m)
        .split('\n')
        .map((l) => l.startsWith('>') ? '>$l' : '> $l')
        .join('\n');
    return 'On ${formatFullDate(m.date)}, ${m.from.formatted} wrote:\n$quoted';
  }
}

class ComposeScreen extends StatefulWidget {
  const ComposeScreen({
    required this.account,
    super.key,
    this.draft = const ComposeDraft(),
  });

  final Account account;
  final ComposeDraft draft;

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  late final _to = RecipientController(widget.draft.to);
  late final _cc = RecipientController(widget.draft.cc);
  late final _bcc = RecipientController(widget.draft.bcc);
  late final _subject = TextEditingController(text: widget.draft.subject);
  late final _body = TextEditingController(text: widget.draft.body);
  late final _bodyFocus = FocusNode();
  late Account _from = widget.account;
  late bool _showCcBcc =
      widget.draft.cc.isNotEmpty || widget.draft.bcc.isNotEmpty;
  final List<OutgoingAttachment> _attachments = [];
  bool _sending = false;

  String get _title {
    if (widget.draft.inReplyTo != null) return 'Reply';
    if (widget.draft.subject.startsWith('Fwd:')) return 'Forward';
    return 'New message';
  }

  @override
  void initState() {
    super.initState();
    // Replies and forwards: put the cursor above the quoted text.
    _body.selection = const TextSelection.collapsed(offset: 0);
  }

  @override
  void dispose() {
    for (final c in [_to, _cc, _bcc]) {
      c.dispose();
    }
    _subject.dispose();
    _body.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  bool get _dirty {
    final d = widget.draft;
    bool sameList(List<Address> a, List<Address> b) =>
        a.length == b.length && a.every(b.contains);
    return !sameList(_to.addresses, d.to) ||
        !sameList(_cc.addresses, d.cc) ||
        !sameList(_bcc.addresses, d.bcc) ||
        _to.text.text.isNotEmpty ||
        _cc.text.text.isNotEmpty ||
        _bcc.text.text.isNotEmpty ||
        _subject.text != d.subject ||
        _body.text != d.body ||
        _attachments.isNotEmpty;
  }

  int get _attachedBytes => _attachments.fold(0, (s, a) => s + a.size);

  Future<void> _attach() async {
    final List<XFile> files;
    try {
      files = await openFiles();
    } on Object catch (e) {
      if (mounted) showSnack(context, "Couldn't open the file picker.");
      debugPrint('file picker: ${e.runtimeType}');
      return;
    }
    for (final f in files) {
      final size = await f.length();
      if (!mounted) return;
      if (_attachedBytes + size > maxAttachmentBytes) {
        showSnack(
          context,
          '${f.name} is too large. Attachments are limited to '
          '${formatBytes(maxAttachmentBytes)} per message.',
        );
        continue;
      }
      final bytes = await f.readAsBytes();
      if (!mounted) return;
      setState(() {
        _attachments.add(
          OutgoingAttachment(
            filename: f.name,
            contentType: f.mimeType ?? _guessType(f.name),
            dataBase64: base64Encode(bytes),
            size: bytes.length,
          ),
        );
      });
    }
  }

  Future<void> _send() async {
    final okTo = _to.commit();
    final okCc = _cc.commit();
    final okBcc = _bcc.commit();
    if (!okTo || !okCc || !okBcc) {
      if (!okCc || !okBcc) setState(() => _showCcBcc = true);
      return;
    }
    if (_to.addresses.isEmpty &&
        _cc.addresses.isEmpty &&
        _bcc.addresses.isEmpty) {
      _to.error = 'Add at least one recipient';
      return;
    }
    if (_subject.text.trim().isEmpty &&
        !await confirm(
          context,
          title: 'Send without a subject?',
          confirmLabel: 'Send',
        )) {
      return;
    }
    if (!mounted) return;
    final api = AppScope.of(context).api;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sending = true);
    try {
      await api.send(
        _from.id,
        OutgoingMessage(
          to: _to.addresses,
          cc: _cc.addresses,
          bcc: _bcc.addresses,
          subject: _subject.text.trim(),
          text: _body.text,
          inReplyTo: widget.draft.inReplyTo,
          references: widget.draft.references,
          attachments: _attachments,
        ),
      );
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Message sent')));
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      showError(context, e);
    }
  }

  Future<void> _close() async {
    if (_sending) return;
    if (!_dirty ||
        await confirm(
          context,
          title: 'Discard this message?',
          confirmLabel: 'Discard',
          destructive: true,
        )) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts =
        SessionScope.maybeWatch(context)?.accounts ?? const <Account>[];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_close());
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: _close,
          ),
          title: Text(_title),
          actions: [
            IconButton(
              tooltip: 'Attach files',
              onPressed: _sending ? null : _attach,
              icon: const Icon(Icons.attach_file),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: FilledButton.icon(
                key: const Key('send'),
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: const Text('Send'),
              ),
            ),
          ],
        ),
        body: AbsorbPointer(
          absorbing: _sending,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              if (accounts.length > 1)
                DropdownButtonFormField<String>(
                  initialValue: _from.id,
                  decoration: const InputDecoration(labelText: 'From'),
                  isExpanded: true,
                  items: [
                    for (final a in accounts)
                      DropdownMenuItem(
                        value: a.id,
                        child: Text(a.email, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (id) => setState(
                    () => _from = accounts.firstWhere((a) => a.id == id),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'From: ${_from.email}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              RecipientField(
                label: 'To',
                controller: _to,
                autofocus: widget.draft.to.isEmpty,
                trailing: _showCcBcc
                    ? null
                    : TextButton(
                        onPressed: () => setState(() => _showCcBcc = true),
                        child: const Text('Cc/Bcc'),
                      ),
              ),
              if (_showCcBcc) ...[
                RecipientField(label: 'Cc', controller: _cc),
                RecipientField(label: 'Bcc', controller: _bcc),
              ],
              TextField(
                key: const Key('subject'),
                controller: _subject,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Subject'),
              ),
              if (_attachments.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final a in _attachments)
                      InputChip(
                        avatar: const Icon(Icons.attach_file, size: 18),
                        label: Text(
                          '${a.filename} (${formatBytes(a.size)})',
                          overflow: TextOverflow.ellipsis,
                        ),
                        onDeleted: () => setState(() => _attachments.remove(a)),
                        deleteButtonTooltipMessage: 'Remove ${a.filename}',
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              TextField(
                key: const Key('body'),
                controller: _body,
                focusNode: _bodyFocus,
                autofocus: widget.draft.to.isNotEmpty,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                minLines: 12,
                maxLines: null,
                decoration: const InputDecoration(
                  hintText: 'Write your message',
                  border: InputBorder.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _guessType(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  return const {
        'pdf': 'application/pdf',
        'png': 'image/png',
        'jpg': 'image/jpeg',
        'jpeg': 'image/jpeg',
        'gif': 'image/gif',
        'webp': 'image/webp',
        'heic': 'image/heic',
        'txt': 'text/plain',
        'csv': 'text/csv',
        'html': 'text/html',
        'ics': 'text/calendar',
        'vcf': 'text/vcard',
        'zip': 'application/zip',
        'doc': 'application/msword',
        'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'xls': 'application/vnd.ms-excel',
        'xlsx':
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'ppt': 'application/vnd.ms-powerpoint',
        'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        'mp3': 'audio/mpeg',
        'mp4': 'video/mp4',
      }[ext] ??
      'application/octet-stream';
}
