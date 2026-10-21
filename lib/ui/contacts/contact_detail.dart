import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:optional_mail_client/api/client.dart';
import 'package:optional_mail_client/ui/contacts/contact_editor.dart';
import 'package:optional_mail_client/ui/mail/compose_screen.dart';
import 'package:optional_mail_client/ui/scope.dart';
import 'package:optional_mail_client/ui/widgets/avatar.dart';
import 'package:optional_mail_client/ui/widgets/dialogs.dart';
import 'package:optional_mail_client/ui/widgets/html_body.dart';

String _typeLabel(String type) {
  final t = type.trim().toLowerCase();
  if (t.isEmpty) return 'Other';
  return switch (t) {
    'cell' || 'mobile' => 'Mobile',
    'home' => 'Home',
    'work' => 'Work',
    _ => t[0].toUpperCase() + t.substring(1),
  };
}

/// Shows one contact. The list reloads when this screen closes.
class ContactDetailScreen extends StatefulWidget {
  const ContactDetailScreen({
    required this.account,
    required this.contact,
    super.key,
  });

  final Account account;
  final Contact contact;

  @override
  State<ContactDetailScreen> createState() => _ContactDetailScreenState();
}

class _ContactDetailScreenState extends State<ContactDetailScreen> {
  late Contact _contact = widget.contact;
  bool _busy = false;

  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<Contact>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ContactEditorScreen(
          account: widget.account,
          addressbook: _contact.addressbook,
          contact: _contact,
        ),
      ),
    );
    if (saved != null && mounted) {
      setState(() => _contact = saved);
    }
  }

  Future<void> _delete() async {
    final ok = await confirm(
      context,
      title: 'Delete ${_contact.displayName}?',
      message: 'The contact is removed from the address book.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final api = AppScope.of(context).api;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await api.deleteContact(
        widget.account.id,
        id: _contact.id,
        etag: _contact.etag,
      );
      navigator.pop(true);
      messenger.showSnackBar(const SnackBar(content: Text('Contact deleted')));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      if (e.isConflict || e.isNotFound) {
        navigator.pop(true);
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'The contact was changed on another device. The list has been '
              'reloaded; please check it and try again.',
            ),
          ),
        );
      } else {
        showError(context, e);
      }
    }
  }

  void _compose(String email) {
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => ComposeScreen(
            account: widget.account,
            draft: ComposeDraft(
              to: [Address(email: email, name: _contact.fullName.trim())],
            ),
          ),
        ),
      ),
    );
  }

  void _copy(String value) {
    unawaited(Clipboard.setData(ClipboardData(text: value)));
    showSnack(context, 'Copied');
  }

  @override
  Widget build(BuildContext context) {
    final c = _contact;
    final theme = Theme.of(context);
    final subtitle = [c.title, c.org].where((s) => s.isNotEmpty).join(' · ');
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Edit contact',
            onPressed: _busy ? null : _edit,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Delete contact',
            onPressed: _busy ? null : _delete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (_busy) const LinearProgressIndicator(),
          const SizedBox(height: 16),
          Center(
            child: InitialsAvatar(name: c.displayName, seed: c.uid, radius: 44),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SelectableText(
              c.displayName,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
          ),
          if (subtitle.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(
                subtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: 16),
          for (final e in c.emails)
            ListTile(
              leading: const Icon(Icons.mail_outline),
              title: Text(e.value),
              subtitle: Text(_typeLabel(e.type)),
              onTap: () => _compose(e.value),
              onLongPress: () => _copy(e.value),
              trailing: IconButton(
                tooltip: 'Copy email address',
                onPressed: () => _copy(e.value),
                icon: const Icon(Icons.copy_outlined),
              ),
            ),
          for (final p in c.phones)
            ListTile(
              leading: const Icon(Icons.phone_outlined),
              title: Text(p.value),
              subtitle: Text(_typeLabel(p.type)),
              onTap: () => launchExternal(
                context,
                Uri(
                  scheme: 'tel',
                  path: p.value.replaceAll(RegExp(r'[^0-9+*#,;]'), ''),
                ),
              ),
              onLongPress: () => _copy(p.value),
              trailing: IconButton(
                tooltip: 'Copy phone number',
                onPressed: () => _copy(p.value),
                icon: const Icon(Icons.copy_outlined),
              ),
            ),
          if (c.note.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.notes_outlined),
              title: const Text('Note'),
              subtitle: SelectableText(c.note),
            ),
          if (c.emails.isEmpty && c.phones.isEmpty && c.note.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No details yet. Tap edit to add an email or phone number.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
