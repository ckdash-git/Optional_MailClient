import 'package:flutter/material.dart';
import 'package:optional_mail_client/api/client.dart';
import 'package:optional_mail_client/ui/format.dart';

/// Recipients as chips plus the text still being typed.
class RecipientController extends ChangeNotifier {
  RecipientController([List<Address> initial = const []])
    : _addresses = [...initial];

  final List<Address> _addresses;
  final text = TextEditingController();
  String? _error;

  List<Address> get addresses => List.unmodifiable(_addresses);
  String? get error => _error;
  bool get isEmpty => _addresses.isEmpty && text.text.trim().isEmpty;

  set error(String? value) {
    _error = value;
    notifyListeners();
  }

  /// Turns typed text into chips. Returns false if some of it is not a valid
  /// address; that part stays in the text field and [error] is set.
  bool commit() {
    final parts = text.text
        .split(RegExp(r'[,;\n]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);
    final invalid = <String>[];
    for (final part in parts) {
      final a = parseAddress(part);
      if (a == null) {
        invalid.add(part);
      } else if (!_addresses.any(
        (x) => x.email.toLowerCase() == a.email.toLowerCase(),
      )) {
        _addresses.add(a);
      }
    }
    final remaining = invalid.join(', ');
    if (remaining != text.text) {
      text.value = TextEditingValue(
        text: remaining,
        selection: TextSelection.collapsed(offset: remaining.length),
      );
    }
    _error = invalid.isEmpty ? null : 'Not a valid address: ${invalid.first}';
    notifyListeners();
    return invalid.isEmpty;
  }

  void remove(Address a) {
    _addresses.remove(a);
    notifyListeners();
  }

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }
}

/// Address input with chips. Typing a comma, semicolon or Enter, or leaving
/// the field, turns the text into chips.
class RecipientField extends StatefulWidget {
  const RecipientField({
    required this.label,
    required this.controller,
    super.key,
    this.autofocus = false,
    this.trailing,
  });

  final String label;
  final RecipientController controller;
  final bool autofocus;
  final Widget? trailing;

  @override
  State<RecipientField> createState() => _RecipientFieldState();
}

class _RecipientFieldState extends State<RecipientField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  @override
  void dispose() {
    _focus
      ..removeListener(_onFocus)
      ..dispose();
    super.dispose();
  }

  void _onFocus() {
    if (!_focus.hasFocus && widget.controller.text.text.trim().isNotEmpty) {
      widget.controller.commit();
    }
  }

  void _onChanged(String value) {
    final c = widget.controller;
    if (value.endsWith(',') || value.endsWith(';')) {
      c.commit();
    } else if (c.error != null) {
      c.error = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => InputDecorator(
        isFocused: _focus.hasFocus,
        decoration: InputDecoration(
          labelText: widget.label,
          errorText: c.error,
          border: const UnderlineInputBorder(),
          suffixIcon: widget.trailing,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (c.addresses.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 4),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final a in c.addresses)
                      InputChip(
                        label: Text(a.label, overflow: TextOverflow.ellipsis),
                        tooltip: a.email,
                        onDeleted: () => c.remove(a),
                        deleteButtonTooltipMessage: 'Remove ${a.email}',
                      ),
                  ],
                ),
              ),
            Semantics(
              label: '${widget.label} recipients',
              child: TextField(
                key: Key('${widget.label}-input'),
                controller: c.text,
                focusNode: _focus,
                autofocus: widget.autofocus,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.next,
                onChanged: _onChanged,
                onSubmitted: (_) => c.commit(),
                decoration: InputDecoration.collapsed(
                  hintText: c.addresses.isEmpty ? 'name@example.com' : '',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
