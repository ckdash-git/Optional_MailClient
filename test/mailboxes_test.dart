import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:optional_mail_client/api/client.dart';
import 'package:optional_mail_client/api/realtime.dart';
import 'package:optional_mail_client/api/session.dart';
import 'package:optional_mail_client/app.dart';
import 'package:optional_mail_client/ui/mail/mail_screen.dart';
import 'package:optional_mail_client/ui/mail/mailboxes_screen.dart';

import 'helpers.dart';

Map<String, Object?> _msg(String id, String subject, String date) => {
  'id': id,
  'folder': 'INBOX',
  'from': {'name': 'Sender $id', 'email': '$id@x.io'},
  'to': <Object>[],
  'subject': subject,
  'date': date,
  'seen': false,
  'flagged': false,
  'answered': false,
  'has_attachments': false,
  'size': 1,
};

Map<String, Object?> _account(String id, String email) => {
  'id': id,
  'email': email,
  'display_name': '',
  'incoming_protocol': 'imap',
  'has_calendar': false,
  'has_contacts': false,
  'last_error': '',
};

Future<ApiClient> _api() async => ApiClient(
  await signedInSession(MemoryKeyValueStore()),
  httpClient: MockClient((req) async {
    final p = req.url.path;
    if (p == '/v1/me') {
      return jsonResponse({
        'user': {'id': 'u', 'email': 'a@work.io'},
        'device_id': 'd',
        'accounts': [_account('w', 'a@work.io'), _account('s', 'a@studio.io')],
      });
    }
    if (p.endsWith('/folders')) {
      return jsonResponse([
        {'name': 'INBOX', 'role': 'inbox', 'unread': 4, 'total': 9},
        {'name': 'Sent', 'role': 'sent', 'unread': 0, 'total': 2},
      ]);
    }
    if (p == '/v1/accounts/w/messages') {
      return jsonResponse({
        'messages': [
          _msg('w1', 'Work newest', '2026-10-20T10:00:00Z'),
          _msg('w2', 'Work oldest', '2026-10-18T10:00:00Z'),
        ],
      });
    }
    if (p == '/v1/accounts/s/messages') {
      return jsonResponse({
        'messages': [_msg('s1', 'Studio middle', '2026-10-19T10:00:00Z')],
      });
    }
    return errorResponse(404, 'not_found');
  }),
);

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MailApp(
      api: await _api(),
      realtimeFactory: (api) => Realtime(api, connect: (_) => FakeChannel()),
    ),
  );
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 10),
  );
}

void main() {
  testWidgets(
    'iOS: Mailboxes root, merged Recents, account → folders → inbox',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await _pump(tester);
        expect(find.byType(MailboxesScreen), findsOneWidget);
        expect(find.text('Mailboxes'), findsWidgets);
        expect(find.text('a@work.io'), findsOneWidget);
        expect(find.text('a@studio.io'), findsOneWidget);
        expect(find.text('Instant'), findsNWidgets(2));

        // Recents merges both accounts, newest first.
        final y = {
          for (final s in ['Work newest', 'Studio middle', 'Work oldest'])
            s: tester.getTopLeft(find.text(s)).dy,
        };
        expect(y['Work newest']!, lessThan(y['Studio middle']!));
        expect(y['Studio middle']!, lessThan(y['Work oldest']!));

        // Account → its folders → the inbox, with a way back.
        await tester.tap(find.text('a@work.io'));
        await tester.pumpAndSettle();
        expect(find.byType(AccountFoldersScreen), findsOneWidget);
        expect(find.text('Sent'), findsOneWidget);
        await tester.tap(find.text('Inbox'));
        await tester.pumpAndSettle();
        expect(find.byType(MailScreen), findsOneWidget);
        expect(find.byType(BackButton), findsOneWidget);
        expect(find.byType(Drawer), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('Android keeps the inbox with its folder drawer', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await _pump(tester);
      expect(find.byType(MailboxesScreen), findsNothing);
      expect(find.byType(MailScreen), findsOneWidget);
      expect(find.byTooltip('Open navigation menu'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
