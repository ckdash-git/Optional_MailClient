import 'dart:async';

import 'package:flutter/material.dart';
import 'package:optional_mail_client/api/cache.dart';
import 'package:optional_mail_client/api/client.dart';
import 'package:optional_mail_client/ui/app_state.dart';
import 'package:optional_mail_client/ui/design.dart';
import 'package:optional_mail_client/ui/mail/message_list.dart';
import 'package:optional_mail_client/ui/mail/message_screen.dart';
import 'package:optional_mail_client/ui/scope.dart';
import 'package:optional_mail_client/ui/widgets/states.dart';

/// Searches the messages saved on this device across every account.
///
/// Plain words must all appear in the subject, sender or recipients. Filters:
/// `is:unread`, `is:starred`, `has:attachment`.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.accountId});

  /// Limit the search to one account; all accounts when null.
  final String? accountId;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<CachedHit> _hits = const [];
  String _query = '';
  int _gen = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () => _run(text));
  }

  Future<void> _run(String text) async {
    final gen = ++_gen;
    final state = SessionScope.read(context);
    final cache = AppScope.of(context).cache;
    final ids = widget.accountId != null
        ? [widget.accountId!]
        : [for (final a in state.accounts) a.id];
    final hits = await cache.search(text, ids);
    if (!mounted || gen != _gen) return;
    setState(() {
      _query = text;
      _hits = hits;
    });
  }

  Future<void> _open(CachedHit hit) async {
    final state = SessionScope.read(context);
    final account = state.accountById(hit.accountId);
    if (account == null) return;
    var folders = const <Folder>[];
    try {
      folders = await AppScope.of(context).api.folders(account.id);
    } on Object {
      // Offline: the message opens from the saved copy without folder actions.
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MessageScreen(
          account: account,
          summary: hit.message,
          folders: folders,
          onChanged: (_) {},
          onRemoved: () => unawaited(_run(_query)),
        ),
      ),
    );
    if (mounted) unawaited(_run(_query));
  }

  @override
  Widget build(BuildContext context) {
    final state = SessionScope.watch(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Search saved mail',
            border: InputBorder.none,
          ),
          onChanged: _onChanged,
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              tooltip: 'Clear search',
              icon: const Icon(Icons.close),
              onPressed: () {
                _controller.clear();
                unawaited(_run(''));
              },
            ),
        ],
      ),
      body: _body(state, theme),
    );
  }

  Widget _body(AppState state, ThemeData theme) {
    if (_query.trim().isEmpty) {
      return const MessageView(
        icon: Icons.manage_search,
        title: 'Search your mail',
        message:
            'Finds messages saved on this device, even offline. '
            'Try is:unread, is:starred or has:attachment.',
      );
    }
    if (_hits.isEmpty) {
      return MessageView(
        icon: Icons.search_off_outlined,
        title: 'No matches',
        message:
            'Nothing saved on this device matches “${_query.trim()}”. '
            'Open a folder to save more of it.',
      );
    }
    return ListView.separated(
      itemCount: _hits.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 76),
      itemBuilder: (context, i) {
        final hit = _hits[i];
        return MessageTile(
          message: hit.message,
          accent: state.accounts.length > 1
              ? systemColorAt(
                  state.accountIndex(hit.accountId),
                  theme.brightness,
                )
              : null,
          onTap: () => unawaited(_open(hit)),
          onToggleStar: null,
        );
      },
    );
  }
}
