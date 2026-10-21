import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:optional_mail_client/api/client.dart';
import 'package:optional_mail_client/api/session.dart';
import 'package:optional_mail_client/ui/mail/compose_screen.dart';

import 'helpers.dart';

void main() {
  testWidgets('requires valid recipients before sending', (tester) async {
    final session = await signedInSession(MemoryKeyValueStore());
    final sent = <http.Request>[];
    final api = ApiClient(
      session,
      httpClient: MockClient((req) async {
        sent.add(req);
        return jsonResponse({'message_id': '<new@example.com>'}, 202);
      }),
    );

    await tester.pumpWidget(
      harness(
        api,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ComposeScreen(account: testAccount),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // No recipients.
    await tester.tap(find.byKey(const Key('send')));
    await tester.pumpAndSettle();
    expect(find.text('Add at least one recipient'), findsOneWidget);

    // An invalid address stays as text and is reported.
    await tester.enterText(find.byKey(const Key('To-input')), 'not-an-email');
    await tester.tap(find.byKey(const Key('send')));
    await tester.pumpAndSettle();
    expect(find.text('Not a valid address: not-an-email'), findsOneWidget);
    expect(sent, isEmpty);

    // A valid address becomes a chip and the message is sent.
    await tester.enterText(
      find.byKey(const Key('To-input')),
      'Bob Stone <bob@example.com>',
    );
    await tester.enterText(find.byKey(const Key('subject')), 'Lunch');
    await tester.enterText(find.byKey(const Key('body')), 'Tomorrow at noon?');
    await tester.tap(find.byKey(const Key('send')));
    await tester.pumpAndSettle();

    expect(sent, hasLength(1));
    expect(sent.single.url.path, '/v1/accounts/acc1/send');
    expect(jsonDecode(sent.single.body), {
      'to': [
        {'name': 'Bob Stone', 'email': 'bob@example.com'},
      ],
      'subject': 'Lunch',
      'text': 'Tomorrow at noon?',
    });
    // The compose screen closed and confirmed the send.
    expect(find.text('Message sent'), findsOneWidget);
    expect(find.byType(ComposeScreen), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  test('reply-all quotes the original and skips my own address', () {
    final original = Message(
      id: '1.2',
      folder: 'INBOX',
      from: const Address(email: 'bob@example.com', name: 'Bob'),
      to: const [
        Address(email: 'ana@example.com', name: 'Ana'),
        Address(email: 'carol@example.com'),
      ],
      cc: const [Address(email: 'dave@example.com')],
      subject: 'Plans',
      date: DateTime.utc(2026, 10, 18, 9, 30),
      messageId: '<m1@example.com>',
      references: const ['<m0@example.com>'],
      text: 'Line one\nLine two',
    );
    final d = ComposeDraft.reply(original, account: testAccount, all: true);
    expect(d.to.map((a) => a.email), ['bob@example.com']);
    expect(d.cc.map((a) => a.email), ['carol@example.com', 'dave@example.com']);
    expect(d.subject, 'Re: Plans');
    expect(d.inReplyTo, '<m1@example.com>');
    expect(d.references, ['<m0@example.com>', '<m1@example.com>']);
    expect(d.body, contains('> Line one\n> Line two'));

    final f = ComposeDraft.forward(original);
    expect(f.subject, 'Fwd: Plans');
    expect(f.to, isEmpty);
    expect(f.body, contains('Line two'));
    expect(f.body, contains('From: Bob <bob@example.com>'));
  });
}
