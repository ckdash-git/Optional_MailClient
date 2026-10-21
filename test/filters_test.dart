import 'package:flutter/cupertino.dart' show CupertinoSliverNavigationBar;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:optional_mail_client/api/client.dart';
import 'package:optional_mail_client/api/realtime.dart';
import 'package:optional_mail_client/api/session.dart';
import 'package:optional_mail_client/app.dart';
import 'package:optional_mail_client/ui/mail/mail_screen.dart';

import 'helpers.dart';

Map<String, Object?> _msg(
  String id,
  String subject, {
  bool seen = true,
  bool flagged = false,
}) => {
  'id': id,
  'folder': 'INBOX',
  'from': {'name': 'Sender $id', 'email': '$id@x.io'},
  'to': <Object>[],
  'subject': subject,
  'date': '2026-10-20T10:00:00Z',
  'seen': seen,
  'flagged': flagged,
  'answered': false,
  'has_attachments': false,
  'size': 1,
};

Future<ApiClient> _api({bool paged = false}) async => ApiClient(
  await signedInSession(MemoryKeyValueStore()),
  httpClient: MockClient((req) async {
    final p = req.url.path;
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
            'has_calendar': false,
            'has_contacts': true,
            'last_error': '',
          },
        ],
      });
    }
    if (p.endsWith('/folders')) {
      return jsonResponse([
        {'name': 'INBOX', 'role': 'inbox', 'unread': 2, 'total': 5},
      ]);
    }
    if (p == '/v1/accounts/w/messages') {
      if (paged && req.url.queryParameters['before'] == null) {
        // The first page has nothing starred; the match is on page two.
        return jsonResponse({
          'messages': [for (var i = 0; i < 30; i++) _msg('p$i', 'Plain $i')],
          'next_before': 'p29',
        });
      }
      if (paged) {
        return jsonResponse({
          'messages': [_msg('c', 'Old favourite', flagged: true)],
        });
      }
      return jsonResponse({
        'messages': [
          _msg('a', 'Read message'),
          _msg('b', 'Unread message', seen: false),
          _msg('c', 'Starred message', flagged: true),
        ],
      });
    }
    if (p.endsWith('/addressbooks')) {
      return jsonResponse([
        {'id': 'ab', 'name': 'Work'},
      ]);
    }
    if (p.endsWith('/contacts')) {
      return jsonResponse([
        {
          'id': 'c1',
          'addressbook': 'ab',
          'etag': 'e',
          'uid': 'u1',
          'full_name': 'Ada Lovelace',
          'emails': [
            {'type': 'work', 'value': 'ada@x.io'},
          ],
        },
      ]);
    }
    return errorResponse(404, 'not_found');
  }),
);

Future<void> _pump(
  WidgetTester tester, {
  bool paged = false,
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    MailApp(
      api: await _api(paged: paged),
      realtimeFactory: (api) => Realtime(api, connect: (_) => FakeChannel()),
    ),
  );
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 10),
  );
}

Future<void> _onPlatform(
  TargetPlatform platform,
  Future<void> Function() body,
) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  testWidgets('Unread and Starred chips filter the open folder', (
    tester,
  ) async {
    await _onPlatform(TargetPlatform.android, () async {
      await _pump(tester);
      expect(find.byType(FilterBar), findsOneWidget);
      expect(find.text('Unread · 2'), findsOneWidget);
      for (final s in ['Read message', 'Unread message', 'Starred message']) {
        expect(find.text(s), findsOneWidget);
      }

      await tester.tap(find.text('Unread · 2'));
      await tester.pumpAndSettle();
      expect(find.text('Unread message'), findsOneWidget);
      expect(find.text('Read message'), findsNothing);

      await tester.tap(find.text('Starred'));
      await tester.pumpAndSettle();
      expect(find.text('Starred message'), findsOneWidget);
      expect(find.text('Unread message'), findsNothing);

      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      expect(find.text('Read message'), findsOneWidget);
    });
  });

  testWidgets('a filter keeps loading older pages until something matches', (
    tester,
  ) async {
    await _onPlatform(TargetPlatform.android, () async {
      await _pump(tester, paged: true);
      expect(find.text('Old favourite'), findsNothing);
      await tester.tap(find.text('Starred'));
      await tester.pumpAndSettle();
      expect(find.text('Old favourite'), findsOneWidget);
      expect(find.text('Plain 0'), findsNothing);
    });
  });

  testWidgets('a filter with no matches says so', (tester) async {
    await _onPlatform(TargetPlatform.android, () async {
      await _pump(tester, paged: true);
      await tester.tap(find.text('Unread · 2'));
      await tester.pumpAndSettle();
      // Both loaded messages are read and the last page is exhausted.
      expect(find.text('All caught up'), findsOneWidget);
    });
  });

  testWidgets('iOS Contacts has a large title; Android keeps the app bar', (
    tester,
  ) async {
    await _onPlatform(TargetPlatform.iOS, () async {
      await _pump(tester);
      await tester.tap(find.text('Contacts').last);
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoSliverNavigationBar), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      expect(find.text('Ada Lovelace'), findsOneWidget);
    });
    await _onPlatform(TargetPlatform.android, () async {
      await _pump(tester);
      await tester.tap(find.text('Contacts').last);
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsWidgets);
      expect(find.text('Ada Lovelace'), findsOneWidget);
    });
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('${platform.name}: no overflow at 200% text size', (
      tester,
    ) async {
      await _onPlatform(platform, () async {
        await _pump(tester, textScale: 2);
        // Layout errors fail the test on their own; walk every tab.
        for (final tab in ['Calendar', 'Contacts', 'Settings', 'Mail']) {
          await tester.tap(find.text(tab).last);
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
      });
    });
  }
}
