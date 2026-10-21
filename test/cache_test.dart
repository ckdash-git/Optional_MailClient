import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:optional_mail_client/api/cache.dart';
import 'package:optional_mail_client/api/cache_files.dart';
import 'package:optional_mail_client/api/models.dart';

MessageSummary _m(
  String id,
  String subject, {
  String from = 'ana@x.io',
  bool seen = true,
  bool flagged = false,
  bool attachments = false,
  DateTime? date,
}) => MessageSummary(
  id: id,
  folder: 'INBOX',
  from: Address(name: from.split('@').first, email: from),
  to: const [Address(email: 'me@work.io')],
  subject: subject,
  date: date ?? DateTime.utc(2026, 10, 20),
  seen: seen,
  flagged: flagged,
  hasAttachments: attachments,
);

Message _full(String id, {String folder = 'INBOX'}) => Message(
  id: id,
  folder: folder,
  from: const Address(name: 'Ana', email: 'ana@x.io'),
  subject: 'Body $id',
  date: DateTime.utc(2026, 10, 20),
  text: 'hello',
  html: '<p>hello</p>',
  attachments: const [
    AttachmentInfo(
      index: 0,
      filename: 'a.ics',
      contentType: 'text/calendar',
      size: 9,
    ),
  ],
);

void main() {
  for (final kind in ['memory', 'file']) {
    group('$kind store', () {
      late Directory dir;
      late BlobStore store;

      setUp(() {
        dir = Directory.systemTemp.createTempSync('mailcache');
        store = kind == 'memory' ? MemoryBlobStore() : FileBlobStore(dir);
      });
      tearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      test('pages and messages round-trip', () async {
        final cache = MailCache(store);
        expect(await cache.page('a', 'INBOX'), isNull);

        await cache.savePage('a', 'INBOX', [
          _m('1', 'Hello', flagged: true),
          _m('2', 'World', seen: false),
        ], next: '2');
        final page = (await cache.page('a', 'INBOX'))!;
        expect(page.messages.map((m) => m.id), ['1', '2']);
        expect(page.messages.first.flagged, isTrue);
        expect(page.messages.last.seen, isFalse);
        expect(page.next, '2');

        await cache.saveMessage('a', _full('9'));
        final m = (await cache.message('a', 'INBOX', '9'))!;
        expect(m.html, '<p>hello</p>');
        expect(m.attachments.single.filename, 'a.ics');
        expect(await cache.message('a', 'INBOX', 'nope'), isNull);
        expect(await cache.message('b', 'INBOX', '9'), isNull);
      });

      test('odd folder names and ids cannot escape the store', () async {
        final cache = MailCache(store);
        await cache.savePage('a/../b', '../../etc/passwd', [_m('../x', 'S')]);
        final page = await cache.page('a/../b', '../../etc/passwd');
        expect(page!.messages.single.id, '../x');
        if (kind == 'file') {
          expect(
            dir.parent.listSync().whereType<File>().where(
              (f) => f.path.contains('passwd'),
            ),
            isEmpty,
          );
        }
      });

      test(
        'a page keeps at most 200 messages and drops a stale cursor',
        () async {
          final cache = MailCache(store);
          await cache.savePage('a', 'INBOX', [
            for (var i = 0; i < 250; i++) _m('$i', 'S$i'),
          ], next: 'x');
          final page = (await cache.page('a', 'INBOX'))!;
          expect(page.messages, hasLength(200));
          expect(page.next, isNull);
        },
      );

      test('keeps the 100 most recently saved messages per account', () async {
        var t = DateTime.utc(2026);
        final cache = MailCache(
          store,
          clock: () => t = t.add(const Duration(seconds: 1)),
        );
        for (var i = 0; i < 105; i++) {
          await cache.saveMessage('a', _full('m$i'));
        }
        await cache.saveMessage('b', _full('other'));
        expect(await cache.message('a', 'INBOX', 'm0'), isNull);
        expect(await cache.message('a', 'INBOX', 'm4'), isNull);
        expect(await cache.message('a', 'INBOX', 'm5'), isNotNull);
        expect(await cache.message('a', 'INBOX', 'm104'), isNotNull);
        expect(await cache.message('b', 'INBOX', 'other'), isNotNull);
      });

      test('removeAccount and clear leave nothing behind', () async {
        final cache = MailCache(store);
        await cache.savePage('a', 'INBOX', [_m('1', 'S')]);
        await cache.saveMessage('a', _full('1'));
        await cache.savePage('b', 'INBOX', [_m('2', 'S')]);
        await cache.removeAccount('a');
        expect(await cache.page('a', 'INBOX'), isNull);
        expect(await cache.message('a', 'INBOX', '1'), isNull);
        expect(await cache.page('b', 'INBOX'), isNotNull);
        await cache.clear();
        expect(await cache.page('b', 'INBOX'), isNull);
        expect(await store.keys(''), isEmpty);
      });

      test('a corrupt entry is dropped, not thrown', () async {
        final cache = MailCache(store);
        await store.write('p/a/INBOX', '{not json');
        expect(await cache.page('a', 'INBOX'), isNull);
        expect(await store.read('p/a/INBOX'), isNull);
      });

      test('search spans accounts and folders, newest first', () async {
        final cache = MailCache(store);
        await cache.savePage('a', 'INBOX', [
          _m(
            '1',
            'Quarterly numbers',
            from: 'bob@x.io',
            date: DateTime.utc(2026, 10, 1),
          ),
          _m('2', 'Lunch', seen: false, flagged: true, attachments: true),
        ]);
        await cache.savePage('a', 'Sent', [
          _m('3', 'Re: Quarterly numbers', date: DateTime.utc(2026, 10, 5)),
        ]);
        await cache.savePage('b', 'INBOX', [
          _m('4', 'Numbers for Q4', date: DateTime.utc(2026, 10, 9)),
        ]);

        Future<List<String>> ids(
          String q, [
          List<String> accounts = const ['a', 'b'],
        ]) async => [
          for (final h in await cache.search(q, accounts)) h.message.id,
        ];

        expect(await ids('quarterly numbers'), ['3', '1']);
        expect(await ids('NUMBERS'), ['4', '3', '1']);
        expect(await ids('numbers', ['b']), ['4']);
        expect(await ids('bob'), ['1']);
        expect(await ids('me@work.io lunch'), ['2']);
        expect(await ids('is:unread'), ['2']);
        expect(await ids('is:starred has:attachment'), ['2']);
        expect(await ids('is:read lunch'), isEmpty);
        expect(await ids('   '), isEmpty);
        expect(await ids('nothing like this'), isEmpty);
      });
    });
  }
}
