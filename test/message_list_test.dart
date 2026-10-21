import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:optional_mail_client/api/client.dart';
import 'package:optional_mail_client/api/session.dart';
import 'package:optional_mail_client/ui/mail/message_list.dart';

import 'helpers.dart';

void main() {
  testWidgets('renders message summaries from the API', (tester) async {
    final session = await signedInSession(MemoryKeyValueStore());
    final requested = <Uri>[];
    final api = ApiClient(
      session,
      httpClient: MockClient((req) async {
        requested.add(req.url);
        return jsonResponse({
          'messages': [
            {
              'id': '1700000000.42',
              'folder': 'INBOX',
              'from': {'name': 'Bob Stone', 'email': 'bob@example.com'},
              'to': [
                {'name': 'Ana', 'email': 'ana@example.com'},
              ],
              'subject': 'Quarterly numbers',
              'date': '2026-10-18T09:30:00Z',
              'seen': false,
              'flagged': true,
              'answered': false,
              'has_attachments': true,
              'size': 20480,
            },
            {
              'id': '1700000000.41',
              'folder': 'INBOX',
              'from': {'name': '', 'email': 'news@example.org'},
              'to': <Object>[],
              'subject': '',
              'date': '2026-10-01T09:30:00Z',
              'seen': true,
              'flagged': false,
              'answered': true,
              'has_attachments': false,
              'size': 1024,
            },
          ],
        });
      }),
    );

    await tester.pumpWidget(
      harness(
        api,
        const Scaffold(
          body: MessageList(
            account: testAccount,
            folder: 'INBOX',
            folders: [Folder(name: 'INBOX', role: FolderRole.inbox)],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(requested.single.path, '/v1/accounts/acc1/messages');
    expect(requested.single.queryParameters['folder'], 'INBOX');

    expect(find.text('Bob Stone'), findsOneWidget);
    expect(find.text('Quarterly numbers'), findsOneWidget);
    expect(find.text('news@example.org'), findsOneWidget);
    expect(find.text('(no subject)'), findsOneWidget);
    expect(find.byIcon(Icons.attach_file), findsOneWidget);
    expect(find.byIcon(Icons.star), findsOneWidget);

    // Unread messages are bold, read ones are not.
    final unread = tester.widget<Text>(find.text('Quarterly numbers'));
    expect(unread.style?.fontWeight, FontWeight.w700);
    final read = tester.widget<Text>(find.text('(no subject)'));
    expect(read.style?.fontWeight, FontWeight.w400);

    expect(
      find.bySemanticsLabel(
        RegExp('^Unread. Starred. Bob Stone. Quarterly numbers'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('shows an empty state and an error state with retry', (
    tester,
  ) async {
    final session = await signedInSession(MemoryKeyValueStore());
    var fail = true;
    final api = ApiClient(
      session,
      httpClient: MockClient((req) async {
        if (fail) return errorResponse(502, 'upstream_error', 'imap down');
        return jsonResponse({'messages': <Object>[]});
      }),
    );
    await tester.pumpWidget(
      harness(
        api,
        const Scaffold(
          body: MessageList(account: testAccount, folder: 'INBOX', folders: []),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load"), findsOneWidget);
    expect(find.textContaining('mail server failed'), findsOneWidget);

    fail = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('No messages'), findsOneWidget);
  });
}
