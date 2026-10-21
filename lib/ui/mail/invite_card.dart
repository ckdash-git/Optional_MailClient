import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:optional_mail_client/api/client.dart';
import 'package:optional_mail_client/ui/format.dart';
import 'package:optional_mail_client/ui/mail/ics.dart';
import 'package:optional_mail_client/ui/scope.dart';
import 'package:optional_mail_client/ui/widgets/dialogs.dart';

/// The attachment that carries a meeting invitation, if the message has one.
AttachmentInfo? inviteAttachment(Message m) {
  for (final a in m.attachments) {
    final type = a.contentType.toLowerCase();
    final name = a.filename.toLowerCase();
    if (type.startsWith('text/calendar') ||
        type == 'application/ics' ||
        name.endsWith('.ics')) {
      return a;
    }
  }
  return null;
}

/// Shows a meeting invitation found in a message and adds it to the calendar.
class InviteCard extends StatefulWidget {
  const InviteCard({
    required this.account,
    required this.message,
    required this.attachment,
    super.key,
  });

  final Account account;
  final Message message;
  final AttachmentInfo attachment;

  @override
  State<InviteCard> createState() => _InviteCardState();
}

class _InviteCardState extends State<InviteCard> {
  static const _maxBytes = 256 * 1024;

  Invite? _invite;
  bool _loading = true;
  bool _adding = false;
  bool _added = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (widget.attachment.size > _maxBytes) {
      setState(() => _loading = false);
      return;
    }
    final api = AppScope.of(context).api;
    try {
      final file = await api.attachment(
        widget.account.id,
        widget.message.id,
        folder: widget.message.folder.isEmpty ? 'INBOX' : widget.message.folder,
        index: widget.attachment.index,
      );
      final invite = parseInvite(utf8.decode(file.bytes, allowMalformed: true));
      if (mounted) {
        setState(() {
          _invite = invite;
          _loading = false;
        });
      }
    } on Object {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add() async {
    final invite = _invite;
    if (invite == null || _adding) return;
    final api = AppScope.of(context).api;
    setState(() => _adding = true);
    try {
      final calendars = await api.calendars(widget.account.id);
      if (!mounted) return;
      if (calendars.isEmpty) {
        showSnack(context, 'This account has no calendar to add it to.');
        return;
      }
      final calendar = calendars.length == 1
          ? calendars.first
          : await _pick(calendars);
      if (calendar == null || !mounted) return;
      await api.saveEvent(
        widget.account.id,
        EventInput(
          calendar: calendar.id,
          summary: invite.summary.isEmpty ? '(no title)' : invite.summary,
          description: invite.description,
          location: invite.location,
          start: invite.start,
          end: invite.end,
          allDay: invite.allDay,
        ),
      );
      if (!mounted) return;
      setState(() => _added = true);
      showSnack(context, 'Added to ${calendar.name}');
    } on Object catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<CalendarInfo?> _pick(List<CalendarInfo> calendars) =>
      showModalBottomSheet<CalendarInfo>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Add to which calendar?'),
              ),
              for (final c in calendars)
                ListTile(
                  leading: const Icon(Icons.calendar_today_outlined),
                  title: Text(c.name.isEmpty ? c.id : c.name),
                  onTap: () => Navigator.pop(context, c),
                ),
            ],
          ),
        ),
      );

  String _when(Invite i) {
    if (i.allDay) {
      final last = i.end.subtract(const Duration(days: 1));
      final first = formatDate(i.start);
      return last.isAfter(i.start) ? '$first to ${formatDate(last)}' : first;
    }
    final s = i.start.toLocal();
    final e = i.end.toLocal();
    final sameDay = s.year == e.year && s.month == e.month && s.day == e.day;
    return sameDay
        ? '${formatDate(s)}, ${formatTime(s)} to ${formatTime(e)}'
        : '${formatFullDate(s)} to ${formatFullDate(e)}';
  }

  @override
  Widget build(BuildContext context) {
    final invite = _invite;
    if (_loading) return const SizedBox.shrink();
    if (invite == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final canAdd = widget.account.hasCalendar && !invite.isCancellation;
    return Card.outlined(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  invite.isCancellation
                      ? Icons.event_busy_outlined
                      : Icons.event_outlined,
                  color: invite.isCancellation ? scheme.error : scheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    invite.isCancellation
                        ? 'Meeting cancelled'
                        : 'Meeting invitation',
                    style: theme.textTheme.labelLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              invite.summary.isEmpty ? '(no title)' : invite.summary,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(_when(invite)),
            if (invite.timeZone.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Sent in time zone ${invite.timeZone}. Check the time '
                  'before you add it.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.error,
                  ),
                ),
              ),
            if (invite.location.isNotEmpty) Text(invite.location),
            if (invite.organizer.isNotEmpty)
              Text(
                'Organizer: ${invite.organizer}',
                style: theme.textTheme.bodySmall,
              ),
            if (canAdd) ...[
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: FilledButton.icon(
                  onPressed: _added || _adding ? null : _add,
                  icon: Icon(_added ? Icons.check : Icons.event_available),
                  label: Text(_added ? 'Added to calendar' : 'Add to calendar'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
