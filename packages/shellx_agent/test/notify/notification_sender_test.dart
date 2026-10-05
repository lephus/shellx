import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

final class _Clock {
  DateTime now = DateTime.utc(2026, 10, 5, 12);
  void advance(Duration d) => now = now.add(d);
}

/// A ShellxApi whose relay answers with [reply]; records request bodies.
(ShellxApi, List<Map<String, dynamic>>) _api(
  Future<http.Response> Function() reply,
) {
  final bodies = <Map<String, dynamic>>[];
  final api = ShellxApi(
    baseUri: Uri.parse('https://relay.test'),
    httpClient: MockClient((request) async {
      bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
      return reply();
    }),
  )..token = 'agent-token';
  return (api, bodies);
}

Future<http.Response> _ok() async => http.Response(
  '{"sent":1}',
  202,
  headers: {'content-type': 'application/json'},
);

const _n = AgentNotification(
  title: 'Mac · Session 1',
  body: '✓ make · 45 s',
  data: {'session_id': '7', 'kind': 'command'},
);

void main() {
  test('sends title, body and data through POST /v1/notifications', () {
    fakeAsync((async) {
      final (api, bodies) = _api(_ok);
      final sender = NotificationSender(api: api);
      expect(sender.send(_n), isTrue);
      async.flushMicrotasks();
      expect(bodies, [
        {
          'title': 'Mac · Session 1',
          'body': '✓ make · 45 s',
          'data': {'session_id': '7', 'kind': 'command'},
        },
      ]);
      expect(sender.failed, 0);
    });
  });

  test('at most 6 per sliding 60 s; the 7th is dropped and counted', () {
    fakeAsync((async) {
      final clock = _Clock();
      final logs = <String>[];
      final (api, bodies) = _api(_ok);
      final sender = NotificationSender(
        api: api,
        now: () => clock.now,
        log: logs.add,
      );
      for (var i = 0; i < 6; i++) {
        expect(sender.send(_n), isTrue);
        clock.advance(const Duration(seconds: 5));
      }
      expect(sender.send(_n), isFalse);
      expect(sender.droppedByLimit, 1);
      expect(logs.single, contains('1 dropped'));
      // 60 s after the first one, one slot is free again.
      clock.advance(const Duration(seconds: 30));
      expect(sender.send(_n), isTrue);
      expect(sender.send(_n), isFalse);
      async.flushMicrotasks();
      expect(bodies, hasLength(7));
    });
  });

  test('failures never throw and are dropped: network, 404, 503, 429, 401', () {
    fakeAsync((async) {
      for (final reply in <Future<http.Response> Function()>[
        () async => throw const SocketExceptionLike(),
        () async => http.Response(
          '{"error":{"code":"not_found",'
          '"message":"x"}}',
          404,
        ),
        () async => http.Response(
          '{"error":{"code":"push_unavailable",'
          '"message":"x"}}',
          503,
        ),
        () async => http.Response(
          '{"error":{"code":"rate_limited",'
          '"message":"x"}}',
          429,
        ),
        () async => http.Response(
          '{"error":{"code":"unauthorized",'
          '"message":"x"}}',
          401,
        ),
        () async => http.Response('not json', 202),
      ]) {
        final (api, bodies) = _api(reply);
        final sender = NotificationSender(api: api);
        expect(sender.send(_n), isTrue);
        async.flushMicrotasks();
        expect(bodies, hasLength(1), reason: 'not retried');
        expect(sender.failed, 1);
      }
    });
  });

  test('a request that never answers is dropped after the API timeout', () {
    fakeAsync((async) {
      final (api, _) = _api(() => Future.delayed(const Duration(hours: 1)));
      final sender = NotificationSender(api: api);
      sender.send(_n);
      async.elapse(const Duration(seconds: 21));
      expect(sender.failed, 1);
    });
  });

  test('without a signed-in token it fails locally, quietly', () {
    fakeAsync((async) {
      final api = ShellxApi(
        baseUri: Uri.parse('https://relay.test'),
        httpClient: MockClient((_) async => fail('no request expected')),
      );
      final sender = NotificationSender(api: api);
      expect(() => sender.send(_n), returnsNormally);
      async.flushMicrotasks();
      expect(sender.failed, 1);
    });
  });

  test('title and body are cut to the relay limits (200 / 1000)', () {
    fakeAsync((async) {
      final (api, bodies) = _api(_ok);
      NotificationSender(
        api: api,
      ).send(AgentNotification(title: 'é' * 300, body: 'x' * 2000));
      async.flushMicrotasks();
      expect((bodies.single['title'] as String).runes.length, 200);
      expect((bodies.single['title'] as String), endsWith('…'));
      expect((bodies.single['body'] as String).runes.length, 1000);
    });
  });
}

/// A transport failure, as IOClient would surface it.
final class SocketExceptionLike implements Exception {
  const SocketExceptionLike();
}
