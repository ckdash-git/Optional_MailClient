import 'package:flutter/material.dart';
import 'package:optional_mail_client/api/client.dart';
import 'package:optional_mail_client/ui/format.dart';
import 'package:optional_mail_client/ui/scope.dart';
import 'package:optional_mail_client/ui/widgets/server_settings_form.dart';

/// Adds another mail account (`POST /v1/accounts`). Pops the new [Account].
class AddAccountScreen extends StatefulWidget {
  const AddAccountScreen({super.key});

  @override
  State<AddAccountScreen> createState() => _AddAccountScreenState();
}

class _AddAccountScreenState extends State<AddAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _settings = ServerSettingsController();
  bool _advanced = false;
  bool _obscure = true;
  bool _busy = false;
  String? _notice;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    _settings.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) {
      if (_settings.manual && !_advanced) setState(() => _advanced = true);
      return;
    }
    final api = AppScope.of(context).api;
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      final account = await api.addAccount(
        email: _email.text.trim(),
        password: _password.text,
        displayName: _name.text.trim(),
        username: _settings.usernameOrNull,
        settings: _settings.settingsOrNull,
      );
      navigator.pop(account);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (e.code == ApiException.discoveryFailed) {
          _advanced = true;
          _settings.manual = true;
          _notice =
              "We couldn't detect the server settings for this address. "
              'Enter them below.';
        }
        if (e.code == ApiException.invalidCredentials) _password.clear();
        _error = switch (e.code) {
          ApiException.invalidCredentials =>
            'The mail server rejected the email address or password.',
          ApiException.forbidden =>
            e.message.isNotEmpty
                ? e.message
                : 'The server does not allow custom mail server settings.',
          ApiException.badRequest =>
            e.message.isNotEmpty ? e.message : 'Some details are not valid.',
          _ => e.userMessage,
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add account'),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Add'),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null)
              Semantics(
                liveRegion: true,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(color: scheme.onErrorContainer),
                  ),
                ),
              ),
            TextFormField(
              controller: _email,
              enabled: !_busy,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.alternate_email),
                border: OutlineInputBorder(),
              ),
              validator: (v) => isValidEmail(v?.trim() ?? '')
                  ? null
                  : 'Enter a valid email address',
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _password,
              enabled: !_busy,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Show password' : 'Hide password',
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              validator: (v) => (v ?? '').isEmpty ? 'Enter the password' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              enabled: !_busy,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Your name (optional)',
                helperText: 'Shown to people you write to',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            AdvancedServerSettings(
              controller: _settings,
              expanded: _advanced,
              onExpandedChanged: (v) => setState(() => _advanced = v),
              notice: _notice,
              enabled: !_busy,
            ),
          ],
        ),
      ),
    );
  }
}
