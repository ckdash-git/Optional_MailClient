import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:optional_mail_client/api/client.dart';
import 'package:optional_mail_client/api/realtime.dart';
import 'package:optional_mail_client/api/session.dart';

import 'helpers.dart';

void main() {
  test('reconnect delay grows from ~1 s to at most 60 s with jitter', () {
    final random = Random(1);
    for (var attempt = 0; attempt < 20; attempt++) {
      final base = min(60000, 1000 * pow(2, min(attempt, 6)).toInt());
      for (var i = 0; i < 20; i++) {
        final d = reconnectDelay(attempt, random).inMilliseconds;
        expect(
          d,
          inInclusiveRange(base ~/ 2, base),
          reason: 'attempt $attempt',
        );
      }
    }
    expect(
      reconnectDelay(0, Random(2)).inMilliseconds,
      lessThanOrEqualTo(1000),
    );
    expect(
      reconnectDelay(30, Random(3)).inMilliseconds,
      lessThanOrEqualTo(60000),
    );
  });

  test(
    'authenticates with the first frame, not the URL, and emits events',
    () async {
      final session = await signedInSession(
        MemoryKeyValueStore(),
        access: 'tok-1',
      );
      final api = ApiClient(
        session,
        httpClient: MockClient((req) async => fail('no HTTP expected')),
      );
      final channel = FakeChannel();
      Uri? connectedTo;
      final realtime = Realtime(
        api,
        connect: (uri) {
          connectedTo = uri;
          return channel;
        },
      );
      final events = <RealtimeEvent>[];
      final sub = realtime.events.listen(events.add);

      realtime.start();
      await pumpEventQueue();

      expect(connectedTo.toString(), 'wss://master.example.com/v1/stream');
      expect(connectedTo.toString(), isNot(contains('tok-1')));
      expect(channel.fakeSink.sent, hasLength(1));
      expect(jsonDecode(channel.fakeSink.sent.first! as String), {
        'type': 'auth',
        'token': 'tok-1',
      });

      channel.incoming
        ..add('{"type":"ready"}')
        ..add('{"type":"mail.new","account_id":"acc1","folder":"INBOX"}');
      await pumpEventQueue();
      expect(realtime.status.value, RealtimeStatus.connected);
      expect(events.single.type, 'mail.new');
      expect(events.single.accountId, 'acc1');

      realtime.stop();
      expect(channel.fakeSink.closedWith, 1000);
      await sub.cancel();
      await realtime.dispose();
      await channel.dispose();
    },
  );
}
