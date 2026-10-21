import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:optional_mail_client/api/cache.dart';
import 'package:optional_mail_client/api/client.dart';
import 'package:optional_mail_client/api/realtime.dart';
import 'package:optional_mail_client/api/session.dart';
import 'package:optional_mail_client/app.dart';
import 'package:optional_mail_client/ui/mail/invite_card.dart';
import 'package:optional_mail_client/ui/mail/search_screen.dart';

import 'helpers.dart';

const _ics =
    'BEGIN:VCALENDAR\r\nMETHOD:REQUEST\r\nBEGIN:VEVENT\r\nUID:u1\r\n'
    'SUMMARY:Budget review\r\nDTSTART:20261105T140000Z\r\nDTEND:20261105T150000Z\r\n'
    'LOCATION:Room 4\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n';

Map<String, Object?> _summary(String id, String subject, {bool seen = true}) =>
    {
      'id': id,
      'folder': 'INBOX',
      'from': {'name': 'Sender', 'email': 'sender@x.io'},
      'to': <Object>[],
      'subject': subject,
      'date': '2026-10-20T10:00:00Z',
      'seen': seen,
      'flagged': false,
      'answered': false,
      'has_attachments': false,
      'size': 1,
    };

class _Server {
  /// Only `/v1/me` answers; every other call fails like a dropped connection.
  bool offline = false;
  final puts = <Map<String, Object?>>[];

  Future<http.Response> handle(http.Request req) async {
    final p = req.url.path;
    if (offline && p != '/v1/me') throw http.ClientException('offline');
    if (p == '/v1/me') {
      return jsonResponse({
        'user': {'id': 'u', 'email': 'a@work.io'},
        'device_id': 'd',
        'accounts': [
          {
            'id': 'w',
            'email': 'a@work.io',
            'display_name': '',
            'incoming_protocol': 'imap',
            'has_calendar': true,
            'has_contacts': false,
            'last_error': '',
          },
        ],
      });
    }
    if (p.endsWith('/folders')) {
      return jsonResponse([
        {'name': 'INBOX', 'role': 'inbox', 'unread': 1, 'total': 2},
        {'name': 'Archive', 'role': 'archive', 'unread': 0, 'total': 0},
      ]);
    }
    if (p == '/v1/accounts/w/messages') {
      return jsonResponse({
        'messages': [
          _summary('1', 'Invoice October', seen: false),
          _summary('2', 'Meeting request'),
        ],
      });
    }
    if (p == '/v1/accounts/w/messages/2/attachments/0') {
      return http.Response(
        _ics,
        200,
        headers: {'content-type': 'text/calendar'},
      );
    }
    if (p == '/v1/accounts/w/messages/2') {
      return jsonResponse({
        ..._summary('2', 'Meeting request'),
        'text': 'Please join.',
        'attachments': [
          {
            'index': 0,
            'filename': 'invite.ics',
            'content_type': 'text/calendar',
            'size': _ics.length,
          },
        ],
      });
    }
    if (p == '/v1/accounts/w/messages/1') {
      return jsonResponse({
        ..._summary('1', 'Invoice October', seen: false),
        'text': 'Fresh body from the server',
      });
    }
    if (p == '/v1/accounts/w/calendars') {
      return jsonResponse([
        {'id': '/cal/work/', 'name': 'Work', 'color': ''},
      ]);
    }
    if (p == '/v1/accounts/w/events' && req.method == 'PUT') {
      puts.add(jsonDecode(req.body) as Map<String, Object?>);
      return jsonResponse({
        'id': '/cal/work/new.ics',
        'calendar': '/cal/work/',
        'etag': '"1"',
        'uid': 'u1',
        'summary': 'Budget review',
        'start': '2026-11-05T14:00:00Z',
        'end': '2026-11-05T15:00:00Z',
        'all_day': false,
      });
    }
    if (req.method == 'PATCH') return http.Response('', 204);
    return errorResponse(404, 'not_found');
  }
}

Future<(_Server, MailCache, List<FakeChannel>)> _pump(
  WidgetTester tester, {
  MailCache? cache,
  bool online = true,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final server = _Server()..offline = !online;
  final api = ApiClient(
    await signedInSession(MemoryKeyValueStore()),
    httpClient: MockClient(server.handle),
    delay: (_) async {},
  );
  final channels = <FakeChannel>[];
  final c = cache ?? MailCache(MemoryBlobStore());
  await tester.pumpWidget(
    MailApp(
      api: api,
      cache: c,
      realtimeFactory: (api) => Realtime(
        api,
        connect: (_) {
          final ch = FakeChannel();
          channels.add(ch);
          return ch;
        },
      ),
    ),
  );
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 10),
  );
  return (server, c, channels);
}

Future<void> _android(Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

MessageSummary _saved(String id, String subject) =>
    MessageSummary.fromJson(_summary(id, subject));

void main() {
  testWidgets('a loaded folder is saved for offline use', (tester) async {
    await _android(() async {
      final (_, cache, _) = await _pump(tester);
      expect(find.text('Invoice October'), findsOneWidget);
      final page = await tester.runAsync(() => cache.page('w', 'INBOX'));
      expect(page!.messages.map((m) => m.subject), [
        'Invoice October',
        'Meeting request',
      ]);
    });
  });

  testWidgets('offline, the saved list shows with an offline banner', (
    tester,
  ) async {
    await _android(() async {
      final cache = MailCache(MemoryBlobStore());
      await tester.runAsync(
        () => cache.savePage('w', 'INBOX', [_saved('9', 'Saved earlier')]),
      );
      await _pump(tester, cache: cache, online: false);
      expect(find.text('Saved earlier'), findsOneWidget);
      expect(
        find.textContaining('Offline. Showing messages saved'),
        findsOneWidget,
      );
      expect(find.text("Couldn't load"), findsNothing);
    });
  });

  testWidgets('offline, a message already read still opens', (tester) async {
    await _android(() async {
      final cache = MailCache(MemoryBlobStore());
      await tester.runAsync(() async {
        await cache.savePage('w', 'INBOX', [_saved('9', 'Saved earlier')]);
        await cache.saveMessage(
          'w',
          Message.fromJson({
            ..._summary('9', 'Saved earlier'),
            'text': 'Body kept on the device',
          }),
        );
      });
      await _pump(tester, cache: cache, online: false);
      await tester.tap(find.text('Saved earlier'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Body kept on the device', findRichText: true),
        findsOneWidget,
      );
    });
  });

  testWidgets('search finds saved messages and opens them', (tester) async {
    await _android(() async {
      await _pump(tester);
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      expect(find.byType(SearchScreen), findsOneWidget);
      expect(find.text('Search your mail'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'invoice');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.text('Invoice October'), findsOneWidget);
      expect(find.text('Meeting request'), findsNothing);

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.text('No matches'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'is:unread');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Invoice October'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Fresh body from the server', findRichText: true),
        findsOneWidget,
      );
    });
  });

  testWidgets('a meeting invitation can be added to the calendar', (
    tester,
  ) async {
    await _android(() async {
      final (server, _, _) = await _pump(tester);
      await tester.tap(find.text('Meeting request'));
      await tester.pumpAndSettle();
      expect(find.byType(InviteCard), findsOneWidget);
      expect(find.text('Meeting invitation'), findsOneWidget);
      expect(find.text('Budget review'), findsOneWidget);
      expect(find.text('Room 4'), findsOneWidget);

      await tester.tap(find.text('Add to calendar'));
      await tester.pumpAndSettle();
      expect(server.puts, hasLength(1));
      expect(server.puts.single['calendar'], '/cal/work/');
      expect(server.puts.single['summary'], 'Budget review');
      expect(server.puts.single['start'], '2026-11-05T14:00:00Z');
      expect(server.puts.single['end'], '2026-11-05T15:00:00Z');
      expect(server.puts.single['all_day'], false);
      expect(server.puts.single.containsKey('id'), isFalse);
      expect(find.text('Added to calendar'), findsOneWidget);
    });
  });

  testWidgets('new mail elsewhere shows a banner that opens the folder', (
    tester,
  ) async {
    await _android(() async {
      final (_, _, channels) = await _pump(tester);
      final ch = channels.last;

      // Mail in the folder on screen: no banner.
      ch.incoming.add('{"type":"mail.new","account_id":"w","folder":"INBOX"}');
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('New mail in a@work.io'), findsNothing);

      // Mail in another folder: banner, and "Open" goes there.
      ch.incoming.add(
        '{"type":"mail.new","account_id":"w","folder":"Archive"}',
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('New mail in a@work.io'), findsOneWidget);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Archive'), findsWidgets);
    });
  });
}
