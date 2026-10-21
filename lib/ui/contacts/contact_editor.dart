import 'package:flutter/material.dart';
import 'package:optional_mail_client/api/client.dart';
import 'package:optional_mail_client/ui/format.dart';
import 'package:optional_mail_client/ui/scope.dart';
import 'package:optional_mail_client/ui/widgets/dialogs.dart';

const _emailTypes = ['home', 'work', 'other'];
const _phoneTypes = ['cell', 'home', 'work', 'other'];

String _typeName(String t) => switch (t) {
  'cell' => 'Mobile',
  'home' => 'Home',
  'work' => 'Work',
  _ => 'Other',
};

/// One editable email or phone row.
class _Entry {
  _Entry(this.type, String value)
    : controller = TextEditingController(text: value);

  String type;
  final TextEditingController controller;
}

/// Create or edit a contact. Pops the saved [Contact].
class ContactEditorScreen extends StatefulWidget {
  const ContactEditorScreen({
    required this.account,
    required this.addressbook,
    super.key,
    this.contact,
  });

  final Account account;
  final String addressbook;
  final Contact? contact;

  @override
  State<ContactEditorScreen> createState() => _ContactEditorScreenState();
}

class _ContactEditorScreenState extends State<ContactEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _org = TextEditingController();
  final _title = TextEditingController();
  final _note = TextEditingController();
  final List<_Entry> _emails = [];
  final List<_Entry> _phones = [];
  Contact? _contact;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final c = widget.contact;
    if (c != null) {
      _fill(c);
    } else {
      _emails.add(_Entry('home', ''));
      _phones.add(_Entry('cell', ''));
    }
  }

  void _fill(Contact c) {
    _contact = c;
    _name.text = c.fullName;
    _org.text = c.org;
    _title.text = c.title;
    _note.text = c.note;
    _disposeLater([..._emails, ..._phones]);
    _emails
      ..clear()
      ..addAll(
        c.emails.map((e) => _Entry(_normalType(e.type, _emailTypes), e.value)),
      );
    _phones
      ..clear()
      ..addAll(
        c.phones.map((p) => _Entry(_normalType(p.type, _phoneTypes), p.value)),
      );
  }

  /// Disposes controllers after the fields using them are gone.
  void _disposeLater(List<_Entry> entries) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final e in entries) {
        e.controller.dispose();
      }
    });
  }

  static String _normalType(String t, List<String> allowed) {
    final l = t.toLowerCase();
    if (l == 'mobile') return 'cell';
    return allowed.contains(l) ? l : 'other';
  }

  @override
  void dispose() {
    for (final c in [_name, _org, _title, _note]) {
      c.dispose();
    }
    for (final e in [..._emails, ..._phones]) {
      e.controller.dispose();
    }
    super.dispose();
  }

  ContactInput _input({bool asNew = false}) {
    List<LabeledValue> values(List<_Entry> list) => [
      for (final e in list)
        if (e.controller.text.trim().isNotEmpty)
          LabeledValue(type: e.type, value: e.controller.text.trim()),
    ];
    final c = asNew ? null : _contact;
    return ContactInput(
      addressbook: widget.addressbook,
      id: c?.id,
      etag: c?.etag,
      fullName: _name.text.trim(),
      emails: values(_emails),
      phones: values(_phones),
      org: _org.text.trim(),
      title: _title.text.trim(),
      note: _note.text.trim(),
    );
  }

  Future<void> _save({bool asNew = false}) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final input = _input(asNew: asNew);
    if (input.fullName.isEmpty &&
        input.emails.isEmpty &&
        input.phones.isEmpty) {
      showSnack(context, 'Add a name, email or phone number');
      return;
    }
    final api = AppScope.of(context).api;
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      final saved = await api.saveContact(widget.account.id, input);
      navigator.pop(saved);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      if (e.isConflict) {
        await _resolveConflict();
      } else {
        showError(context, e);
      }
    }
  }

  Future<void> _resolveConflict() async {
    final old = _contact!;
    Contact? current;
    try {
      final all = await AppScope.of(context).api
          .contacts(widget.account.id, addressbook: old.addressbook);
      for (final c in all) {
        if (c.id == old.id) current = c;
      }
    } on Object catch (e) {
      if (mounted) showError(context, e);
      return;
    }
    if (!mounted) return;
    final deleted = current == null;
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(deleted ? 'Contact was deleted' : 'Contact was changed'),
        content: Text(
          deleted
              ? 'This contact was deleted on another device.'
              : 'This contact was changed on another device. Load the latest '
                    'version (your changes are lost) or keep your version?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          if (deleted)
            FilledButton(
              onPressed: () => Navigator.pop(context, 'new'),
              child: const Text('Save as new'),
            )
          else ...[
            TextButton(
              onPressed: () => Navigator.pop(context, 'reload'),
              child: const Text('Load latest'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'overwrite'),
              child: const Text('Keep mine'),
            ),
          ],
        ],
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'reload':
        setState(() => _fill(current!));
        showSnack(context, 'Loaded the latest version');
      case 'overwrite':
        _contact = current;
        await _save();
      case 'new':
        await _save(asNew: true);
    }
  }

  Widget _entries({
    required String label,
    required List<_Entry> entries,
    required List<String> types,
    required IconData icon,
    required TextInputType keyboard,
    required String? Function(String?) validator,
    required String defaultType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, e) in entries.indexed)
          Padding(
            key: ObjectKey(e),
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: e.controller,
                    keyboardType: keyboard,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: '$label ${i + 1}',
                      prefixIcon: Icon(icon),
                      border: const OutlineInputBorder(),
                    ),
                    validator: validator,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    initialValue: e.type,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Type',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final t in types)
                        DropdownMenuItem(value: t, child: Text(_typeName(t))),
                    ],
                    onChanged: (v) => setState(() => e.type = v!),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove ${label.toLowerCase()} ${i + 1}',
                  onPressed: () {
                    setState(() => entries.remove(e));
                    _disposeLater([e]);
                  },
                  icon: const Icon(Icons.remove_circle_outline),
                ),
              ],
            ),
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: () =>
                setState(() => entries.add(_Entry(defaultType, ''))),
            icon: const Icon(Icons.add),
            label: Text('Add ${label.toLowerCase()}'),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.contact == null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? 'New contact' : 'Edit contact'),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: _saving,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: _name,
                autofocus: isNew,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Full name',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              _entries(
                label: 'Email',
                entries: _emails,
                types: _emailTypes,
                icon: Icons.mail_outline,
                keyboard: TextInputType.emailAddress,
                defaultType: 'home',
                validator: (v) {
                  final s = v?.trim() ?? '';
                  return s.isEmpty || isValidEmail(s)
                      ? null
                      : 'Not a valid email';
                },
              ),
              const SizedBox(height: 8),
              _entries(
                label: 'Phone',
                entries: _phones,
                types: _phoneTypes,
                icon: Icons.phone_outlined,
                keyboard: TextInputType.phone,
                defaultType: 'cell',
                validator: (v) {
                  final s = v?.trim() ?? '';
                  return s.isEmpty ||
                          RegExp(r'^[0-9+()\-.\s/*#]{3,}$').hasMatch(s)
                      ? null
                      : 'Not a valid phone number';
                },
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _org,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Company',
                  prefixIcon: Icon(Icons.business_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _title,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Job title',
                  prefixIcon: Icon(Icons.badge_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _note,
                minLines: 3,
                maxLines: 8,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Note',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
