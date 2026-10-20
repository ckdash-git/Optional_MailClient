import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:optional_mail_client/api/client.dart';
import 'package:optional_mail_client/api/realtime.dart';
import 'package:optional_mail_client/api/session.dart';
import 'package:optional_mail_client/app.dart';
import 'package:optional_mail_client/ui/design.dart';

import 'helpers.dart';

double _lum(Color c) {
  double ch(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _ratio(Color a, Color b) {
  final l1 = _lum(a);
  final l2 = _lum(b);
  return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
}

ApiClientFixture _fixture() => ApiClientFixture();

class ApiClientFixture {
  Future<ApiClient> build() async {
    final session = await signedInSession(MemoryKeyValueStore());
    return ApiClient(
      session,
      httpClient: MockClient((req) async {
        switch (req.url.path) {
          case '/v1/me':
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
          case '/v1/accounts/acc1/folders':
            return jsonResponse([
              {'name': 'INBOX', 'role': 'inbox', 'unread': 0, 'total': 0},
            ]);
          case '/v1/accounts/acc1/messages':
            return jsonResponse({'messages': <Object>[]});
        }
        return http.Response(
          jsonEncode({
            'error': {'code': 'not_found', 'message': ''},
          }),
          404,
        );
      }),
    );
  }
}

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final api = await _fixture().build();
  await tester.pumpWidget(
    MailApp(
      api: api,
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
  test('contrast: text and signal red meet WCAG AA in light and dark', () {
    for (final t in [Palette.light, Palette.dark]) {
      expect(
        _ratio(t.ink, t.ground),
        greaterThanOrEqualTo(7),
        reason: 'ink on ground',
      );
      expect(
        _ratio(t.mute, t.ground),
        greaterThanOrEqualTo(4.5),
        reason: 'muted text on ground',
      );
      expect(
        _ratio(t.mute, t.grouped),
        greaterThanOrEqualTo(4.5),
        reason: 'muted text on grouped',
      );
      expect(
        _ratio(t.red, t.ground),
        greaterThanOrEqualTo(4.5),
        reason: 'red text on ground',
      );
      expect(
        _ratio(t.onRed, t.red),
        greaterThanOrEqualTo(4.5),
        reason: 'white on red button',
      );
    }
  });

  test('iOS system colours are stable per seed', () {
    expect(
      systemColor('a@x.io', Brightness.light),
      systemColor('A@X.io', Brightness.light),
    );
    expect(
      systemColor('a@x.io', Brightness.light),
      isNot(systemColor('a@x.io', Brightness.dark)),
    );
  });

  testWidgets('iOS gets the liquid-glass tab bar, no Material NavigationBar', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await _pump(tester);
      expect(find.byType(GlassTabBar), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(BackdropFilter), findsWidgets);
      // Tapping Calendar selects that tab.
      await tester.tap(find.text('Calendar'));
      await tester.pump();
      expect(tester.widget<GlassTabBar>(find.byType(GlassTabBar)).selected, 1);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Android keeps the Material 3 NavigationBar, no glass', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await _pump(tester);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(GlassTabBar), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
