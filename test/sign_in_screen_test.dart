import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:optional_mail_client/api/client.dart';
import 'package:optional_mail_client/api/session.dart';
import 'package:optional_mail_client/ui/scope.dart';
import 'package:optional_mail_client/ui/sign_in_screen.dart';

import 'helpers.dart';

Future<ApiClient> _api(
  Future<http.Response> Function(http.Request) handler,
) async {
  final session = Session(MemoryKeyValueStore());
  await session.load();
  return ApiClient(session, httpClient: MockClient(handler));
}

Future<void> _tapSignIn(WidgetTester tester) async {
  final button = find.byKey(const Key('sign-in'));
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
}

Widget _app(ApiClient api) => AppScope(
  api: api,
  push: null,
  child: const MaterialApp(home: SignInScreen()),
);

void main() {
  testWidgets('validates the form before calling the server', (tester) async {
    var calls = 0;
    final api = await _api((req) async {
      calls++;
      return http.Response('', 500);
    });
    await tester.pumpWidget(_app(api));

    await _tapSignIn(tester);
    await tester.pump();
    expect(find.text('Enter the server address.'), findsOneWidget);
    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('server')),
      'http://mail.example.com',
    );
    await tester.enterText(find.byKey(const Key('email')), 'not-an-email');
    await tester.enterText(find.byKey(const Key('password')), 'pw');
    await _tapSignIn(tester);
    await tester.pump();
    expect(
      find.text('The server address must start with https://'),
      findsOneWidget,
    );
    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(find.text('Enter your password'), findsNothing);
    expect(calls, 0);
  });

  testWidgets('shows the server error and keeps the user on the form', (
    tester,
  ) async {
    final api = await _api((req) async {
      if (req.url.path == '/v1/discover') {
        return jsonResponse({
          'incoming': {
            'protocol': 'imap',
            'host': 'imap.example.com',
            'port': 993,
            'security': 'tls',
          },
          'outgoing': {
            'host': 'smtp.example.com',
            'port': 465,
            'security': 'tls',
          },
        });
      }
      return errorResponse(401, 'invalid_credentials', 'login failed');
    });
    await tester.pumpWidget(_app(api));

    await tester.enterText(
      find.byKey(const Key('server')),
      'master.example.com',
    );
    await tester.enterText(find.byKey(const Key('email')), 'ana@example.com');
    await tester.enterText(find.byKey(const Key('password')), 'wrong');
    await _tapSignIn(tester);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('rejected the email address or password'),
      findsOneWidget,
    );
    expect(api.session.isSignedIn, isFalse);
  });

  testWidgets('discovery_failed opens the manual server settings', (
    tester,
  ) async {
    final api = await _api((req) async {
      expect(req.url.path, '/v1/discover');
      return errorResponse(422, 'discovery_failed', 'no settings');
    });
    await tester.pumpWidget(_app(api));

    await tester.enterText(
      find.byKey(const Key('server')),
      'master.example.com',
    );
    await tester.enterText(find.byKey(const Key('email')), 'ana@example.org');
    // Leaving the email field triggers discovery.
    await tester.tap(find.byKey(const Key('password')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining(
        "couldn't detect the server settings for example.org",
      ),
      findsOneWidget,
    );
    expect(find.text('Incoming server'), findsOneWidget);
    final toggle = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(toggle.value, isTrue);
  });
}
