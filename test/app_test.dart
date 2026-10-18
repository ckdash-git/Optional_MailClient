import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:optional_mail_client/api/client.dart';
import 'package:optional_mail_client/api/realtime.dart';
import 'package:optional_mail_client/api/session.dart';
import 'package:optional_mail_client/app.dart';
import 'package:optional_mail_client/ui/mail/compose_screen.dart';
import 'package:optional_mail_client/ui/sign_in_screen.dart';

import 'helpers.dart';

const _summary = {
  'id': '1700000000.42',
  'folder': 'INBOX',
  'from': {'name': 'Bob Stone', 'email': 'bob@example.com'},
  'to': [
    {'name': 'Ana', 'email': 'ana@example.com'},
  ],
  'subject': 'Quarterly numbers',
  'date': '2026-10-18T09:30:00Z',
  'seen': false,
  'flagged': false,
  'answered': false,
  'has_attachments': false,
  'size': 2048,
};

/// pumpAndSettle with a short timeout so a stuck animation fails fast.
Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 100),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 10),
);

void main() {
  testWidgets('signed-in flow: inbox, message, reply, sign out', (
    tester,
  ) async {
    final store = MemoryKeyValueStore();
    final session = await signedInSession(store);
    final requests = <String>[];
    final api = ApiClient(
      session,
      httpClient: MockClient((req) async {
        requests.add('${req.method} ${req.url.path}');
        final path = req.url.path;
        if (path == '/v1/me') {
          return jsonResponse({
            'user': {'id': 'u1', 'email': 'ana@example.com'},
            'device_id': 'd1',
            'accounts': [
              {
                'id': 'acc1',
                'email': 'ana@example.com',
                'display_name': 'Ana',
                'incoming_protocol': 'imap',
                'has_calendar': false,
                'has_contacts': false,
                'last_error': '',
              },
            ],
          });
        }
        if (path == '/v1/accounts/acc1/folders') {
          return jsonResponse([
            {'name': 'INBOX', 'role': 'inbox', 'unread': 1, 'total': 1},
            {'name': 'Archive', 'role': 'archive', 'unread': 0, 'total': 0},
          ]);
        }
        if (path == '/v1/accounts/acc1/messages') {
          return jsonResponse({
            'messages': [_summary],
          });
        }
        if (path == '/v1/accounts/acc1/messages/1700000000.42') {
          if (req.method == 'PATCH') {
            expect(jsonDecode(req.body), {'seen': true});
            return http.Response('', 204);
          }
          return jsonResponse({
            ..._summary,
            'cc': <Object>[],
            'reply_to': <Object>[],
            'message_id': '<q3@example.com>',
            'in_reply_to': '',
            'references': <Object>[],
            'text': 'Numbers attached.',
            'html': '<p>Numbers are <b>up</b>.</p>',
            'remote_content_blocked': true,
            'attachments': <Object>[],
          });
        }
        if (path == '/v1/auth/logout') return http.Response('', 204);
        return errorResponse(404, 'not_found');
      }),
    );
    final channel = FakeChannel();

    await tester.pumpWidget(
      MailApp(
        api: api,
        realtimeFactory: (api) => Realtime(api, connect: (_) => channel),
      ),
    );
    await _settle(tester);

    // Inbox with the message; the WebSocket authenticated with a frame.
    expect(find.text('Inbox'), findsOneWidget);
    expect(find.text('Quarterly numbers'), findsOneWidget);
    expect(jsonDecode(channel.fakeSink.sent.single! as String), {
      'type': 'auth',
      'token': 'access-1',
    });

    // Open it: body, privacy banner, marked read.
    await tester.tap(find.text('Quarterly numbers'));
    await _settle(tester);
    expect(
      find.textContaining('Remote images and content were blocked'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Numbers are', findRichText: true),
      findsOneWidget,
    );
    expect(
      requests,
      contains('PATCH /v1/accounts/acc1/messages/1700000000.42'),
    );

    // Reply opens compose (a pushed route that reads the session scope).
    await tester.tap(find.text('Reply'));
    await _settle(tester);
    expect(find.text('Re: Quarterly numbers'), findsOneWidget);
    expect(find.text('Bob Stone'), findsWidgets); // recipient chip

    // Signing out while screens are open drops them all and wipes the store.
    await api.logout();
    await _settle(tester);
    expect(find.byType(SignInScreen), findsOneWidget);
    expect(find.byType(ComposeScreen), findsNothing);
    expect(store.values.containsKey('tokens'), isFalse);
    expect(requests, contains('POST /v1/auth/logout'));
    expect(channel.fakeSink.closedWith, 1000);
    await channel.dispose();
  });
}
