import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:optional_mail_client/api/client.dart';

int defaultIncomingPort(IncomingProtocol p, Security s) => switch ((p, s)) {
  (IncomingProtocol.imap, Security.tls) => 993,
  (IncomingProtocol.imap, _) => 143,
  (IncomingProtocol.pop3, Security.tls) => 995,
  (IncomingProtocol.pop3, _) => 110,
};

int defaultOutgoingPort(Security s) => s == Security.tls ? 465 : 587;

final _hostPattern = RegExp(
  r'^(?=.{1,253}$)([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*\.?$',
);

String? validateHost(String? v) {
  final s = v?.trim() ?? '';
  if (s.isEmpty) return 'Enter the server name';
  if (!_hostPattern.hasMatch(s)) return 'Not a valid server name';
  return null;
}

String? validatePort(String? v) {
  final n = int.tryParse(v?.trim() ?? '');
  if (n == null || n < 1 || n > 65535) return 'Port 1–65535';
  return null;
}

String? validateDavUrl(String? v) {
  final s = v?.trim() ?? '';
  if (s.isEmpty) return null;
  final u = Uri.tryParse(s);
  if (u == null ||
      u.scheme != 'https' ||
      u.host.isEmpty ||
      u.userInfo.isNotEmpty) {
    return 'Must be an https:// address';
  }
  return null;
}

/// Holds the manual server settings and optional login username.
class ServerSettingsController extends ChangeNotifier {
  final username = TextEditingController();
  final inHost = TextEditingController();
  final inPort = TextEditingController(text: '993');
  final outHost = TextEditingController();
  final outPort = TextEditingController(text: '465');
  final caldav = TextEditingController();
  final carddav = TextEditingController();

  IncomingProtocol _protocol = IncomingProtocol.imap;
  Security _inSecurity = Security.tls;
  Security _outSecurity = Security.tls;
  bool _manual = false;

  IncomingProtocol get protocol => _protocol;
  Security get inSecurity => _inSecurity;
  Security get outSecurity => _outSecurity;

  /// Whether the manual settings are sent with the request.
  bool get manual => _manual;

  set manual(bool v) {
    _manual = v;
    notifyListeners();
  }

  void setIncoming({IncomingProtocol? protocol, Security? security}) {
    final oldDefault = defaultIncomingPort(_protocol, _inSecurity);
    _protocol = protocol ?? _protocol;
    _inSecurity = security ?? _inSecurity;
    if (inPort.text.isEmpty || int.tryParse(inPort.text) == oldDefault) {
      inPort.text = '${defaultIncomingPort(_protocol, _inSecurity)}';
    }
    notifyListeners();
  }

  void setOutgoingSecurity(Security security) {
    final oldDefault = defaultOutgoingPort(_outSecurity);
    _outSecurity = security;
    if (outPort.text.isEmpty || int.tryParse(outPort.text) == oldDefault) {
      outPort.text = '${defaultOutgoingPort(security)}';
    }
    notifyListeners();
  }

  /// Fills the fields with discovered settings.
  void prefill(ServerSettings s) {
    _protocol = s.incoming.protocol ?? IncomingProtocol.imap;
    _inSecurity = s.incoming.security == Security.none
        ? Security.starttls
        : s.incoming.security;
    _outSecurity = s.outgoing.security == Security.none
        ? Security.starttls
        : s.outgoing.security;
    inHost.text = s.incoming.host;
    inPort.text = '${s.incoming.port}';
    outHost.text = s.outgoing.host;
    outPort.text = '${s.outgoing.port}';
    caldav.text = s.caldavUrl ?? '';
    carddav.text = s.carddavUrl ?? '';
    notifyListeners();
  }

  /// The settings to send, or null when automatic detection should be used.
  ServerSettings? get settingsOrNull {
    if (!_manual) return null;
    return ServerSettings(
      incoming: ServerEndpoint(
        protocol: _protocol,
        host: inHost.text.trim(),
        port: int.parse(inPort.text.trim()),
        security: _inSecurity,
      ),
      outgoing: ServerEndpoint(
        host: outHost.text.trim(),
        port: int.parse(outPort.text.trim()),
        security: _outSecurity,
      ),
      caldavUrl: caldav.text.trim(),
      carddavUrl: carddav.text.trim(),
    );
  }

  String? get usernameOrNull {
    final u = username.text.trim();
    return u.isEmpty ? null : u;
  }

  @override
  void dispose() {
    for (final c in [
      username,
      inHost,
      inPort,
      outHost,
      outPort,
      caldav,
      carddav,
    ]) {
      c.dispose();
    }
    super.dispose();
  }
}

/// Collapsible "Advanced" section with the manual server settings.
class AdvancedServerSettings extends StatelessWidget {
  const AdvancedServerSettings({
    required this.controller,
    required this.expanded,
    required this.onExpandedChanged,
    super.key,
    this.notice,
    this.busy = false,
    this.enabled = true,
  });

  final ServerSettingsController controller;
  final bool expanded;
  final ValueChanged<bool> onExpandedChanged;

  /// Explanation shown at the top, e.g. when detection failed.
  final String? notice;

  /// Shows a small progress indicator (settings are being detected).
  final bool busy;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final fieldsEnabled = enabled && controller.manual;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              expanded: expanded,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onExpandedChanged(!expanded),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Row(
                    children: [
                      Icon(expanded ? Icons.expand_less : Icons.expand_more),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Advanced server settings',
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      if (busy)
                        Semantics(
                          label: 'Detecting server settings',
                          child: const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              alignment: Alignment.topCenter,
              child: !expanded
                  ? const SizedBox(width: double.infinity)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (notice != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              notice!,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.tertiary,
                              ),
                            ),
                          ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: controller.username,
                          enabled: enabled,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: 'Login name (optional)',
                            helperText: 'Only if it differs from your email',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Enter server settings manually'),
                          subtitle: const Text(
                            'Otherwise they are detected automatically',
                          ),
                          value: controller.manual,
                          onChanged: enabled
                              ? (v) => controller.manual = v
                              : null,
                        ),
                        const _Heading('Incoming mail'),
                        SegmentedButton<IncomingProtocol>(
                          segments: [
                            for (final p in IncomingProtocol.values)
                              ButtonSegment(value: p, label: Text(p.label)),
                          ],
                          selected: {controller.protocol},
                          onSelectionChanged: fieldsEnabled
                              ? (s) => controller.setIncoming(protocol: s.first)
                              : null,
                        ),
                        const SizedBox(height: 12),
                        _HostPortRow(
                          host: controller.inHost,
                          port: controller.inPort,
                          enabled: fieldsEnabled,
                          hostLabel: 'Incoming server',
                        ),
                        const SizedBox(height: 12),
                        _SecurityField(
                          label: 'Incoming security',
                          value: controller.inSecurity,
                          enabled: fieldsEnabled,
                          onChanged: (s) => controller.setIncoming(security: s),
                        ),
                        const _Heading('Outgoing mail (SMTP)'),
                        _HostPortRow(
                          host: controller.outHost,
                          port: controller.outPort,
                          enabled: fieldsEnabled,
                          hostLabel: 'SMTP server',
                        ),
                        const SizedBox(height: 12),
                        _SecurityField(
                          label: 'SMTP security',
                          value: controller.outSecurity,
                          enabled: fieldsEnabled,
                          onChanged: controller.setOutgoingSecurity,
                        ),
                        const _Heading('Calendar and contacts (optional)'),
                        TextFormField(
                          controller: controller.caldav,
                          enabled: fieldsEnabled,
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: 'CalDAV URL',
                            hintText: 'https://dav.example.com/',
                            border: OutlineInputBorder(),
                          ),
                          validator: fieldsEnabled ? validateDavUrl : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: controller.carddav,
                          enabled: fieldsEnabled,
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: 'CardDAV URL',
                            hintText: 'https://dav.example.com/',
                            border: OutlineInputBorder(),
                          ),
                          validator: fieldsEnabled ? validateDavUrl : null,
                        ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 12),
    child: Semantics(
      header: true,
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    ),
  );
}

class _HostPortRow extends StatelessWidget {
  const _HostPortRow({
    required this.host,
    required this.port,
    required this.enabled,
    required this.hostLabel,
  });

  final TextEditingController host;
  final TextEditingController port;
  final bool enabled;
  final String hostLabel;

  @override
  Widget build(BuildContext context) {
    final hostField = TextFormField(
      controller: host,
      enabled: enabled,
      keyboardType: TextInputType.url,
      autocorrect: false,
      decoration: InputDecoration(
        labelText: hostLabel,
        border: const OutlineInputBorder(),
      ),
      validator: enabled ? validateHost : null,
    );
    final portField = TextFormField(
      controller: port,
      enabled: enabled,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(5),
      ],
      decoration: const InputDecoration(
        labelText: 'Port',
        border: OutlineInputBorder(),
      ),
      validator: enabled ? validatePort : null,
    );
    // Stack vertically when large text would squeeze the fields.
    final narrow =
        MediaQuery.textScalerOf(context).scale(14) > 20 ||
        MediaQuery.sizeOf(context).width < 340;
    if (narrow) {
      return Column(
        children: [hostField, const SizedBox(height: 12), portField],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 3, child: hostField),
        const SizedBox(width: 12),
        Expanded(child: portField),
      ],
    );
  }
}

class _SecurityField extends StatelessWidget {
  const _SecurityField({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final Security value;
  final bool enabled;
  final ValueChanged<Security> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<Security>(
    // Keyed by value so prefilled settings replace the initial value.
    key: ValueKey('$label/${value.wire}'),
    initialValue: value,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
    items: [
      for (final s in [Security.tls, Security.starttls])
        DropdownMenuItem(value: s, child: Text(s.label)),
    ],
    onChanged: enabled ? (s) => onChanged(s!) : null,
  );
}
