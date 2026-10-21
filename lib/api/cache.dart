import 'dart:convert';

import 'package:optional_mail_client/api/models.dart';

/// Key/value storage under [MailCache]. Keys are `/`-separated paths.
abstract class BlobStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<List<String>> keys(String prefix);
  Future<void> clear();
}

class MemoryBlobStore implements BlobStore {
  final Map<String, String> _data = {};

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async => _data[key] = value;

  @override
  Future<void> delete(String key) async => _data.remove(key);

  @override
  Future<List<String>> keys(String prefix) async => [
    for (final k in _data.keys)
      if (k.startsWith(prefix)) k,
  ];

  @override
  Future<void> clear() async => _data.clear();
}

/// A saved folder page: what the list showed last time.
class CachedPage {
  const CachedPage(this.messages, {this.next});
  final List<MessageSummary> messages;
  final String? next;
}

/// A search hit with the account it belongs to.
class CachedHit {
  const CachedHit(this.accountId, this.message);
  final String accountId;
  final MessageSummary message;
}

/// Messages saved on this device so lists, messages and search keep working
/// offline.
///
/// Holds only what the user has opened or scrolled past: folder pages (capped)
/// and recently read messages (capped, already sanitised by the master). It
/// never stores passwords, tokens or attachments, and is wiped on sign-out and
/// when an account is removed.
class MailCache {
  MailCache(this._store, {DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  final BlobStore _store;
  final DateTime Function() _now;

  static const maxPageMessages = 200;
  static const maxMessagesPerAccount = 100;

  static String _pageKey(String account, String folder) =>
      'p/${Uri.encodeComponent(account)}/${Uri.encodeComponent(folder)}';

  static String _messageKey(String account, String folder, String id) =>
      'm/${Uri.encodeComponent(account)}/${Uri.encodeComponent(folder)}/'
      '${Uri.encodeComponent(id)}';

  Future<CachedPage?> page(String account, String folder) async {
    final raw = await _store.read(_pageKey(account, folder));
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Json;
      return CachedPage(
        MessagePage.fromJson(j).messages,
        next: j['next_before'] as String?,
      );
    } on Object {
      await _store.delete(_pageKey(account, folder)); // corrupt: drop it
      return null;
    }
  }

  Future<void> savePage(
    String account,
    String folder,
    List<MessageSummary> messages, {
    String? next,
  }) async {
    final kept = messages.take(maxPageMessages).toList();
    await _store.write(
      _pageKey(account, folder),
      jsonEncode({
        'messages': [for (final m in kept) m.toJson()],
        // The cursor is only valid for the full list we kept.
        if (next != null && kept.length == messages.length) 'next_before': next,
      }),
    );
  }

  Future<Message?> message(String account, String folder, String id) async {
    final key = _messageKey(account, folder, id);
    final raw = await _store.read(key);
    if (raw == null) return null;
    try {
      return Message.fromJson((jsonDecode(raw) as Json)['message']! as Json);
    } on Object {
      await _store.delete(key);
      return null;
    }
  }

  Future<void> saveMessage(String account, Message m) async {
    await _store.write(
      _messageKey(account, m.folder, m.id),
      jsonEncode({
        'saved': _now().toUtc().toIso8601String(),
        'message': m.toJson(),
      }),
    );
    await _trim(account);
  }

  Future<void> _trim(String account) async {
    final prefix = 'm/${Uri.encodeComponent(account)}/';
    final keys = await _store.keys(prefix);
    if (keys.length <= maxMessagesPerAccount) return;
    final saved = <String, String>{};
    for (final k in keys) {
      final raw = await _store.read(k);
      try {
        saved[k] = (jsonDecode(raw ?? '') as Json)['saved'] as String? ?? '';
      } on Object {
        saved[k] = ''; // unreadable entries go first
      }
    }
    final oldestFirst = keys.toList()
      ..sort((a, b) => saved[a]!.compareTo(saved[b]!));
    for (final k in oldestFirst.take(keys.length - maxMessagesPerAccount)) {
      await _store.delete(k);
    }
  }

  /// Saved messages matching [query] across [accounts], newest first. See
  /// [SearchQuery] for the syntax.
  Future<List<CachedHit>> search(
    String query,
    Iterable<String> accounts, {
    int limit = 200,
  }) async {
    final q = SearchQuery.parse(query);
    if (q.isEmpty) return const [];
    final hits = <CachedHit>[];
    final seen = <String>{};
    for (final account in accounts) {
      for (final key in await _store.keys(
        'p/${Uri.encodeComponent(account)}/',
      )) {
        final folder = Uri.decodeComponent(key.split('/').last);
        final page = await this.page(account, folder);
        for (final m in page?.messages ?? const <MessageSummary>[]) {
          if (seen.add('$account/$folder/${m.id}') && q.matches(m)) {
            hits.add(CachedHit(account, m));
          }
        }
      }
    }
    hits.sort((a, b) => b.message.date.compareTo(a.message.date));
    return hits.take(limit).toList();
  }

  Future<void> removeAccount(String account) async {
    final a = Uri.encodeComponent(account);
    for (final prefix in ['p/$a/', 'm/$a/']) {
      for (final k in await _store.keys(prefix)) {
        await _store.delete(k);
      }
    }
  }

  Future<void> clear() => _store.clear();
}

/// Search words plus filters: `is:unread`, `is:starred`, `has:attachment`.
/// Every word must appear in the subject, sender or recipients.
class SearchQuery {
  const SearchQuery(this.words, {this.unread, this.starred, this.attachment});

  factory SearchQuery.parse(String input) {
    final words = <String>[];
    bool? unread;
    bool? starred;
    bool? attachment;
    for (final part in input.toLowerCase().split(RegExp(r'\s+'))) {
      switch (part) {
        case '':
          break;
        case 'is:unread':
          unread = true;
        case 'is:read':
          unread = false;
        case 'is:starred' || 'is:flagged':
          starred = true;
        case 'has:attachment' || 'has:attachments':
          attachment = true;
        default:
          words.add(part);
      }
    }
    return SearchQuery(
      words,
      unread: unread,
      starred: starred,
      attachment: attachment,
    );
  }

  final List<String> words;
  final bool? unread;
  final bool? starred;
  final bool? attachment;

  bool get isEmpty =>
      words.isEmpty && unread == null && starred == null && attachment == null;

  bool matches(MessageSummary m) {
    if (unread != null && unread == m.seen) return false;
    if (starred != null && starred != m.flagged) return false;
    if (attachment != null && attachment != m.hasAttachments) return false;
    if (words.isEmpty) return true;
    final hay = [
      m.subject,
      m.from.name,
      m.from.email,
      for (final a in m.to) ...[a.name, a.email],
    ].join(' ').toLowerCase();
    return words.every(hay.contains);
  }
}
