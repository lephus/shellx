import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

/// Random whose nextInt always returns the smallest or largest value.
final class _EdgeRandom implements Random {
  _EdgeRandom({required this.largest});
  final bool largest;

  @override
  int nextInt(int max) => largest ? max - 1 : 0;

  @override
  double nextDouble() => largest ? 0.999999 : 0;

  @override
  bool nextBool() => largest;
}

List<int> _delaysMs(Backoff backoff, int count) => [
  for (var i = 0; i < count; i++) backoff.next().inMilliseconds,
];

void main() {
  group('Backoff', () {
    test('upper bound doubles from 1 s and caps at 30 s', () {
      expect(_delaysMs(Backoff(random: _EdgeRandom(largest: true)), 8), [
        1000,
        2000,
        4000,
        8000,
        16000,
        30000,
        30000,
        30000,
      ]);
    });

    test('lower bound is half of the base', () {
      expect(_delaysMs(Backoff(random: _EdgeRandom(largest: false)), 8), [
        500,
        1000,
        2000,
        4000,
        8000,
        15000,
        15000,
        15000,
      ]);
    });

    test('random jitter always stays within [base/2, base]', () {
      final backoff = Backoff(random: Random(42));
      const bases = [1000, 2000, 4000, 8000, 16000, 30000];
      for (var round = 0; round < 200; round++) {
        backoff.reset();
        for (var attempt = 0; attempt < 10; attempt++) {
          final base = bases[min(attempt, bases.length - 1)];
          final delay = backoff.next().inMilliseconds;
          expect(delay, inInclusiveRange(base ~/ 2, base));
        }
      }
    });

    test('reset starts over; many attempts never overflow', () {
      final backoff = Backoff(random: _EdgeRandom(largest: true));
      for (var i = 0; i < 100; i++) {
        backoff.next();
      }
      expect(backoff.next(), const Duration(seconds: 30));
      backoff.reset();
      expect(backoff.next(), const Duration(seconds: 1));
    });

    test('custom initial and max', () {
      final backoff = Backoff(
        initial: const Duration(milliseconds: 100),
        max: const Duration(milliseconds: 250),
        random: _EdgeRandom(largest: true),
      );
      expect(_delaysMs(backoff, 4), [100, 200, 250, 250]);
    });
  });

  group('ioRelaySocketConnector', () {
    late HttpServer server;

    tearDown(() => server.close(force: true));

    test(
      'sends headers, exchanges text and binary frames, reports close code',
      () async {
        final authorization = Completer<String?>();
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((request) async {
          authorization.complete(request.headers.value('authorization'));
          final ws = await WebSocketTransformer.upgrade(request);
          ws.listen((event) {
            if (event == 'ping') {
              ws.add('pong');
            } else if (event == 'bye') {
              ws.close(4002, 'revoked');
            } else if (event is List<int>) {
              ws.add(Uint8List.fromList(event.reversed.toList()));
            }
          });
        });

        final socket = await ioRelaySocketConnector(
          Uri.parse('ws://127.0.0.1:${server.port}/v1/ws'),
          {'Authorization': 'Bearer secret-token'},
        );
        final received = <Object>[];
        final done = Completer<void>();
        socket.messages.listen(received.add, onDone: done.complete);
        socket.sendText('ping');
        socket.sendBytes(Uint8List.fromList([1, 2, 3]));
        socket.sendText('bye');
        await done.future;

        expect(await authorization.future, 'Bearer secret-token');
        expect(received, hasLength(2));
        expect(received[0], 'pong');
        expect(received[1], isA<Uint8List>());
        expect(received[1], [3, 2, 1]);
        expect(socket.closeCode, 4002);
      },
    );

    test(
      'a rejected upgrade throws WebSocketException with the HTTP status',
      () async {
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((request) {
          request.response
            ..statusCode = HttpStatus.unauthorized
            ..close();
        });
        await expectLater(
          ioRelaySocketConnector(
            Uri.parse('ws://127.0.0.1:${server.port}/v1/ws'),
            const {},
          ),
          throwsA(
            isA<WebSocketException>().having(
              (e) => e.httpStatusCode,
              'httpStatusCode',
              HttpStatus.unauthorized,
            ),
          ),
        );
      },
    );
  });
}
