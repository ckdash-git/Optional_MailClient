import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:optional_mail_client/ui/widgets/dialogs.dart';
import 'package:url_launcher/url_launcher.dart';

/// Widget factory that never loads anything: no network, file or asset
/// images. Inline `data:` images still render.
class _OfflineWidgetFactory extends WidgetFactory {
  @override
  ImageProvider? imageProviderFromNetwork(String url) => null;

  @override
  ImageProvider? imageProviderFromFileUri(String url) => null;

  @override
  ImageProvider? imageProviderFromAsset(String url) => null;
}

String _escape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

final _urlPattern = RegExp(r'''\b(https?://[^\s<>"']+[^\s<>"'.,;:!?)\]])''');

/// Converts plain text to minimal HTML with clickable http(s) links.
String plainTextToHtml(String text) {
  final out = StringBuffer();
  var last = 0;
  for (final m in _urlPattern.allMatches(text)) {
    out.write(_escape(text.substring(last, m.start)));
    final url = m.group(1)!;
    out.write('<a href="${_escape(url)}">${_escape(url)}</a>');
    last = m.end;
  }
  out.write(_escape(text.substring(last)));
  return out.toString().replaceAll('\r\n', '\n').replaceAll('\n', '<br>');
}

/// Renders a message body as a sliver. HTML comes pre-sanitised from the
/// master and is rendered without JavaScript or a web view. Links only open
/// after the user confirms the real address.
class MessageBodySliver extends StatelessWidget {
  const MessageBodySliver({
    required this.html,
    required this.text,
    required this.onMailto,
    super.key,
  });

  final String html;
  final String text;
  final ValueChanged<String> onMailto;

  @override
  Widget build(BuildContext context) {
    final source = html.trim().isNotEmpty
        ? html
        : (text.trim().isEmpty
              ? '<p><i>(This message has no text)</i></p>'
              : plainTextToHtml(text));
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      sliver: HtmlWidget(
        source,
        renderMode: RenderMode.sliverList,
        factoryBuilder: _OfflineWidgetFactory.new,
        textStyle: Theme.of(context).textTheme.bodyLarge,
        onTapUrl: (url) => _onTapUrl(context, url),
      ),
    );
  }

  Future<bool> _onTapUrl(BuildContext context, String url) async {
    if (url.startsWith('#')) return false; // in-page anchor
    final uri = Uri.tryParse(url.trim());
    final scheme = uri?.scheme.toLowerCase() ?? '';
    if (uri == null || scheme.isEmpty) {
      showSnack(context, "This link can't be opened.");
      return true;
    }
    if (scheme == 'mailto') {
      onMailto(Uri.decodeComponent(uri.path));
      return true;
    }
    if (scheme != 'http' && scheme != 'https' && scheme != 'tel') {
      showSnack(context, "Links of type '$scheme:' can't be opened.");
      return true;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Open link?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('This link goes to:'),
            const SizedBox(height: 8),
            SelectableText(
              uri.toString(),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Text(
              scheme == 'tel'
                  ? 'Your phone app will open.'
                  : 'It will open in your browser. Only continue if you trust '
                        'the sender and the address above.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Open'),
          ),
        ],
      ),
    );
    if (ok != true) return true;
    final launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    ).catchError((Object _) => false);
    if (!launched && context.mounted) {
      showSnack(context, "Couldn't open the link.");
    }
    return true;
  }
}

/// Opens `tel:` or `mailto:` style URIs from contact details.
Future<void> launchExternal(BuildContext context, Uri uri) async {
  final ok = await launchUrl(
    uri,
    mode: LaunchMode.externalApplication,
  ).catchError((Object _) => false);
  if (!ok && context.mounted) showSnack(context, "Couldn't open $uri");
}
