import 'package:flutter_test/flutter_test.dart';
import 'package:optional_mail_client/api/client.dart';
import 'package:optional_mail_client/ui/mail/recents_feed.dart';

Account _acct(String id) => Account(
  id: id,
  email: '$id@x.io',
  displayName: '',
  hasCalendar: false,
  hasContacts: false,
);

MessageSummary _msg(String id, int day) => MessageSummary(
  id: id,
  folder: 'INBOX',
  from: const Address(email: 'a@x.io'),
  subject: id,
  date: DateTime.utc(2026, 10, day),
);

/// Serves each account's inbox in pages, newest first, and counts requests.
class _Server {
  _Server(this.inboxes);

  final Map<String, List<MessageSummary>> inboxes;
  final requests = <String>[];

  Future<MessagePage> fetch(Account a, String? before, int limit) async {
    requests.add('${a.id}:${before ?? '-'}');
    final all = inboxes[a.id]!;
    final start = before == null
        ? 0
        : all.indexWhere((m) => m.id == before) + 1;
    final page = all.skip(start).take(limit).toList();
    final more = start + page.length < all.length;
    return MessagePage(messages: page, nextBefore: more ? page.last.id : null);
  }
}

List<String> _ids(RecentsFeed f) => [
  for (final r in f.items) r.message.subject,
];

void main() {
  final a = _acct('a');
  final b = _acct('b');

  test(
    'merges accounts newest first and never shows a message out of order',
    () async {
      final server = _Server({
        'a': [_msg('a28', 28), _msg('a20', 20), _msg('a10', 10), _msg('a2', 2)],
        'b': [_msg('b25', 25), _msg('b24', 24), _msg('b5', 5), _msg('b1', 1)],
      });
      final feed = RecentsFeed(server.fetch, [a, b], pageSize: 2);

      await feed.extend(3);
      // Page one of each is a28 a20 / b25 b24. Past b24, b may still hold
      // something newer than a20, so only messages down to b24 are safe.
      expect(_ids(feed), ['a28', 'b25', 'b24']);
      expect(feed.hasMore, isTrue);

      await feed.extend(5);
      expect(_ids(feed).take(5), ['a28', 'b25', 'b24', 'a20', 'a10']);

      await feed.extend(100);
      expect(_ids(feed), ['a28', 'b25', 'b24', 'a20', 'a10', 'b5', 'a2', 'b1']);
      expect(feed.hasMore, isFalse);
    },
  );

  test('stops fetching once enough messages are safe to show', () async {
    final server = _Server({
      'a': [for (var d = 30; d > 10; d--) _msg('a$d', d)],
      'b': [for (var d = 9; d > 0; d--) _msg('b$d', d)],
    });
    final feed = RecentsFeed(server.fetch, [a, b], pageSize: 5);
    await feed.extend(5);
    expect(_ids(feed), ['a30', 'a29', 'a28', 'a27', 'a26']);
    // One page each to start, then nothing more: b is all older than a26.
    expect(server.requests, ['a:-', 'b:-']);
  });

  test('an empty account does not hold the others back', () async {
    final server = _Server({
      'a': [_msg('a3', 3), _msg('a2', 2), _msg('a1', 1)],
      'b': <MessageSummary>[],
    });
    final feed = RecentsFeed(server.fetch, [a, b], pageSize: 2);
    await feed.extend(3);
    expect(_ids(feed), ['a3', 'a2', 'a1']);
    expect(feed.hasMore, isFalse);
  });

  test('no accounts, no messages, no requests', () async {
    final server = _Server({});
    final feed = RecentsFeed(server.fetch, const [], pageSize: 5);
    await feed.extend(10);
    expect(feed.items, isEmpty);
    expect(feed.hasMore, isFalse);
    expect(server.requests, isEmpty);
  });

  test(
    'a failed page throws, keeps what was loaded, and can be retried',
    () async {
      final server = _Server({
        'a': [_msg('a9', 9), _msg('a8', 8), _msg('a1', 1)],
        'b': [_msg('b7', 7), _msg('b6', 6), _msg('b2', 2)],
      });
      var fail = false;
      final feed = RecentsFeed(
        (acct, before, limit) => fail
            ? Future.error(StateError('down'))
            : server.fetch(acct, before, limit),
        [a, b],
        pageSize: 2,
      );
      await feed.extend(2);
      final before = _ids(feed);
      fail = true;
      await expectLater(feed.extend(6), throwsStateError);
      expect(_ids(feed), before);

      fail = false;
      await feed.extend(6);
      expect(_ids(feed), ['a9', 'a8', 'b7', 'b6', 'b2', 'a1']);
    },
  );

  test(
    'a server that returns an empty page with a cursor cannot loop forever',
    () async {
      var calls = 0;
      final feed = RecentsFeed(
        (acct, before, limit) async {
          calls++;
          return const MessagePage(messages: [], nextBefore: 'again');
        },
        [a],
        pageSize: 2,
      );
      await feed.extend(10);
      expect(calls, 1);
      expect(feed.hasMore, isFalse);
    },
  );
}
