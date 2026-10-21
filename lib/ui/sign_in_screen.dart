import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:optional_mail_client/api/client.dart';
import 'package:optional_mail_client/ui/format.dart';
import 'package:optional_mail_client/ui/scope.dart';
import 'package:optional_mail_client/ui/widgets/server_settings_form.dart';

/// Platform name in the form the master expects.
String devicePlatform() {
  if (kIsWeb) return 'web';
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => 'android',
    TargetPlatform.iOS => 'ios',
    TargetPlatform.macOS => 'macos',
    TargetPlatform.windows => 'windows',
    _ => 'linux',
  };
}

String deviceName() {
  const names = {
    'android': 'Android',
    'ios': 'iPhone / iPad',
    'macos': 'Mac',
    'windows': 'Windows PC',
    'linux': 'Linux PC',
    'web': 'Web browser',
  };
  return 'Optional Mail on ${names[devicePlatform()]}';
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _server = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _emailFocus = FocusNode();
  final _settings = ServerSettingsController();

  bool _advanced = false;
  bool _obscure = true;
  bool _busy = false;
  bool _discovering = false;
  String? _discoveredFor;
  String? _notice;
  String? _error;

  @override
  void initState() {
    super.initState();
    final remembered = AppScope.of(context).session.serverUrl;
    if (remembered != null) _server.text = remembered.toString();
    _emailFocus.addListener(_onEmailFocus);
  }

  @override
  void dispose() {
    _emailFocus
      ..removeListener(_onEmailFocus)
      ..dispose();
    _server.dispose();
    _email.dispose();
    _password.dispose();
    _settings.dispose();
    super.dispose();
  }

  void _onEmailFocus() {
    if (!_emailFocus.hasFocus) unawaited(_discover());
  }

  /// Prefills the advanced settings from `/v1/discover` when possible.
  Future<void> _discover() async {
    final email = _email.text.trim();
    if (!isValidEmail(email) || email == _discoveredFor || _settings.manual) {
      return;
    }
    final Uri server;
    try {
      server = parseServerUrl(_server.text);
    } on FormatException {
      return;
    }
    _discoveredFor = email;
    setState(() => _discovering = true);
    try {
      final found = await AppScope.of(context).api.discover(server, email);
      if (!mounted || _settings.manual) return;
      _settings.prefill(found);
      setState(() => _notice = null);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == ApiException.discoveryFailed) {
        _openManual();
      } else {
        _discoveredFor = null; // try again on the next blur
      }
    } finally {
      if (mounted) setState(() => _discovering = false);
    }
  }

  void _openManual() {
    final domain = _email.text.split('@').last.trim();
    setState(() {
      _advanced = true;
      _settings.manual = true;
      _notice =
          "We couldn't detect the server settings for $domain. "
          'Enter them below — your provider’s help pages list them.';
    });
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) {
      // Validation errors inside a collapsed section would be invisible.
      if (_settings.manual && !_advanced) setState(() => _advanced = true);
      return;
    }
    final server = parseServerUrl(_server.text);
    final api = AppScope.of(context).api;
    setState(() => _busy = true);
    try {
      await api.login(
        server: server,
        email: _email.text.trim(),
        password: _password.text,
        deviceName: deviceName(),
        platform: devicePlatform(),
        settings: _settings.settingsOrNull,
        username: _settings.usernameOrNull,
      );
      // The app switches to the home screen when the session changes.
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == ApiException.discoveryFailed) _openManual();
      if (e.code == ApiException.invalidCredentials) _password.clear();
      setState(() => _error = _loginError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _loginError(ApiException e) => switch (e.code) {
    ApiException.network =>
      "Can't reach the server at ${_server.text.trim()}. "
          'Check the address and your connection.',
    ApiException.invalidCredentials =>
      'Your mail provider rejected the email address or password. '
          'Some providers need an app password.',
    ApiException.forbidden =>
      e.message.isNotEmpty
          ? e.message
          : 'This server does not allow custom mail server settings.',
    ApiException.badRequest =>
      e.message.isNotEmpty ? e.message : 'Some of the details are not valid.',
    _ => e.userMessage,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: AutofillGroup(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        Icons.mark_email_unread_outlined,
                        size: 56,
                        color: theme.colorScheme.primary,
                        semanticLabel: 'Optional Mail',
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Sign in',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Use your email address and its password. '
                        'The password is sent once to your server and is '
                        'not stored on this device.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (_error != null) ...[
                        _ErrorBanner(text: _error!),
                        const SizedBox(height: 16),
                      ],
                      TextFormField(
                        key: const Key('server'),
                        controller: _server,
                        enabled: !_busy,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Server address',
                          hintText: 'https://mail.example.com',
                          prefixIcon: Icon(Icons.dns_outlined),
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) {
                          try {
                            parseServerUrl(v ?? '');
                            return null;
                          } on FormatException catch (e) {
                            return e.message;
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('email'),
                        controller: _email,
                        focusNode: _emailFocus,
                        enabled: !_busy,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        autofillHints: const [
                          AutofillHints.email,
                          AutofillHints.username,
                        ],
                        textInputAction: TextInputAction.next,
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
                        key: const Key('password'),
                        controller: _password,
                        enabled: !_busy,
                        obscureText: _obscure,
                        autocorrect: false,
                        enableSuggestions: false,
                        autofillHints: const [AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: _obscure
                                ? 'Show password'
                                : 'Hide password',
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: (v) =>
                            (v ?? '').isEmpty ? 'Enter your password' : null,
                      ),
                      const SizedBox(height: 8),
                      AdvancedServerSettings(
                        controller: _settings,
                        expanded: _advanced,
                        onExpandedChanged: (v) => setState(() => _advanced = v),
                        notice: _notice,
                        busy: _discovering,
                        enabled: !_busy,
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        key: const Key('sign-in'),
                        onPressed: _busy ? null : _submit,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                        ),
                        child: _busy
                            ? Semantics(
                                label: 'Signing in',
                                child: const SizedBox.square(
                                  dimension: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                  ),
                                ),
                              )
                            : const Text('Sign in'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
