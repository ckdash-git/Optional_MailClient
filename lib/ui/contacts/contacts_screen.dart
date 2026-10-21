import 'dart:async';

import 'package:flutter/material.dart';
import 'package:optional_mail_client/api/client.dart';
import 'package:optional_mail_client/ui/contacts/contact_detail.dart';
import 'package:optional_mail_client/ui/contacts/contact_editor.dart';
import 'package:optional_mail_client/ui/design.dart';
import 'package:optional_mail_client/ui/scope.dart';
import 'package:optional_mail_client/ui/widgets/account_menu.dart';
import 'package:optional_mail_client/ui/widgets/avatar.dart';
import 'package:optional_mail_client/ui/widgets/states.dart';

bool contactMatches(Contact c, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  final digits = q.replaceAll(RegExp(r'[^0-9+]'), '');
  return c.displayName.toLowerCase().contains(q) ||
      c.org.toLowerCase().contains(q) ||
      c.emails.any((e) => e.value.toLowerCase().contains(q)) ||
      (digits.length >= 3 &&
          c.phones.any(
            (p) => p.value.replaceAll(RegExp(r'[^0-9+]'), '').contains(digits),
          ));
}

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final _search = TextEditingController();
  StreamSubscription<RealtimeEvent>? _sub;
  Timer? _debounce;

  Account? _account;
  List<AddressBook>? _books;
  String? _bookId;
  List<Contact>? _contacts;
  Object? _error;
  int _gen = 0;

  ApiClient get _api => AppScope.of(context).api;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sub ??= SessionScope.realtimeOf(context).events.listen(_onEvent);
    final account = SessionScope.watch(context).selectedAccount;
    if (account?.id != _account?.id) {
      _account = account;
      _books = null;
      _bookId = null;
      _contacts = null;
      _error = null;
      if (account != null && account.hasContacts) unawaited(_load());
    } else {
      _account = account;
    }
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onEvent(RealtimeEvent e) {
    if (e.isResync ||
        (e.type == 'contacts.changed' && e.accountId == _account?.id)) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 400), _load);
    }
  }

  /// Loads the address books (if needed) and the selected book's contacts.
  Future<void> _load() async {
    final account = _account;
    if (account == null || !account.hasContacts) return;
    final gen = ++_gen;
    try {
      var books = _books;
      if (books == null) {
        books = await _api.addressBooks(account.id);
        if (!mounted || gen != _gen) return;
        final ids = books.map((b) => b.id).toSet();
        setState(() {
          _books = books;
          if (!ids.contains(_bookId)) {
            _bookId = books!.isEmpty ? null : books.first.id;
          }
        });
      }
      final bookId = _bookId;
      if (bookId == null) return;
      final contacts = await _api.contacts(account.id, addressbook: bookId);
      if (!mounted || gen != _gen) return;
      contacts.sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );
      setState(() {
        _contacts = contacts;
        _error = null;
      });
    } on Object catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() => _error = e);
    }
  }

  void _retry() {
    setState(() => _error = null);
    unawaited(_load());
  }

  Future<void> _open(Contact c) async {
    final account = _account;
    if (account == null) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ContactDetailScreen(account: account, contact: c),
      ),
    );
    // The contact may have been edited or deleted.
    if (mounted) await _load();
  }

  Future<void> _create() async {
    final account = _account;
    final bookId = _bookId;
    if (account == null || bookId == null) return;
    final saved = await Navigator.of(context).push<Contact>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            ContactEditorScreen(account: account, addressbook: bookId),
      ),
    );
    if (saved != null) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final books = _books;
    String? bookName;
    for (final b in books ?? const <AddressBook>[]) {
      if (b.id == _bookId) bookName = b.name;
    }
    final actions = <Widget>[
      if (books != null && books.length > 1)
        PopupMenuButton<String>(
          tooltip: 'Choose address book',
          icon: const Icon(Icons.import_contacts_outlined),
          onSelected: (id) {
            setState(() {
              _bookId = id;
              _contacts = null;
            });
            unawaited(_load());
          },
          itemBuilder: (context) => [
            for (final b in books)
              CheckedPopupMenuItem(
                value: b.id,
                checked: b.id == _bookId,
                child: Text(b.name.isEmpty ? b.id : b.name),
              ),
          ],
        ),
      const AccountMenuButton(),
    ];
    final ios = isIOS(context);
    return Scaffold(
      appBar: ios
          ? null
          : AppBar(
              title: AppBarTitle(
                'Contacts',
                subtitle: bookName ?? _account?.email,
              ),
              actions: actions,
            ),
      floatingActionButton: _bookId == null
          ? null
          : FloatingActionButton(
              heroTag: 'new-contact',
              tooltip: 'New contact',
              onPressed: _create,
              child: const Icon(Icons.person_add_alt_1_outlined),
            ),
      body: ios
          ? NestedScrollView(
              headerSliverBuilder: (context, _) => [
                largeTitleBar(
                  context,
                  'Contacts',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: actions,
                  ),
                ),
              ],
              body: _body(),
            )
          : _body(),
    );
  }

  Widget _body() {
    final account = _account;
    if (account == null) return const LoadingView();
    if (!account.hasContacts) {
      return MessageView(
        icon: Icons.contacts_outlined,
        title: 'No address book',
        message:
            'There are no contacts (CardDAV) set up for ${account.email}. '
            'You can add a CardDAV address when adding the account.',
      );
    }
    if (_error != null && _contacts == null) {
      return ErrorView(error: _error, onRetry: _retry);
    }
    final books = _books;
    if (books != null && books.isEmpty) {
      return const MessageView(
        icon: Icons.contacts_outlined,
        title: 'No address books',
        message: 'This account has no address books yet.',
      );
    }
    final contacts = _contacts;
    if (contacts == null) return const ListSkeleton();

    final query = _search.text;
    final visible = contacts.where((c) => contactMatches(c, query)).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: SearchBar(
            controller: _search,
            hintText: 'Search contacts',
            leading: const Icon(Icons.search),
            elevation: const WidgetStatePropertyAll(0),
            trailing: [
              if (query.isNotEmpty)
                IconButton(
                  tooltip: 'Clear search',
                  onPressed: _search.clear,
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: visible.isEmpty
                ? MessageView(
                    icon: query.isEmpty
                        ? Icons.person_outline
                        : Icons.search_off_outlined,
                    title: query.isEmpty ? 'No contacts' : 'No matches',
                    message: query.isEmpty
                        ? 'Contacts you add appear here.'
                        : 'Nothing matches “$query”.',
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: visible.length,
                    itemBuilder: (context, i) {
                      final c = visible[i];
                      final letter = _letter(c);
                      final showHeader =
                          i == 0 || _letter(visible[i - 1]) != letter;
                      final detail = c.emails.isNotEmpty
                          ? c.emails.first.value
                          : (c.phones.isNotEmpty
                                ? c.phones.first.value
                                : c.org);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (showHeader && query.isEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                              child: Semantics(
                                header: true,
                                child: Text(
                                  letter,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                      ),
                                ),
                              ),
                            ),
                          ListTile(
                            leading: InitialsAvatar(
                              name: c.displayName,
                              seed: c.uid,
                            ),
                            title: Text(
                              c.displayName,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: detail.isEmpty
                                ? null
                                : Text(detail, overflow: TextOverflow.ellipsis),
                            onTap: () => _open(c),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  static String _letter(Contact c) {
    final name = c.displayName.trim();
    if (name.isEmpty) return '#';
    final first = name.characters.first.toUpperCase();
    // Letters with case get their own section; digits, symbols etc. go to #.
    return first.toLowerCase() != first ? first : '#';
  }
}
