import 'dart:async';
import 'dart:convert';

import 'package:async/async.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:test/test.dart';

/// Two connected ends: what one writes, the other reads.
(JsonRpcConnection, JsonRpcConnection) pair() {
  final aToB = StreamController<List<int>>();
  final bToA = StreamController<List<int>>();
  return (
    JsonRpcConnection(input: bToA.stream, output: aToB.sink),
    JsonRpcConnection(input: aToB.stream, output: bToA.sink),
  );
}

/// One connection driven by raw bytes; its output decoded as JSON lines.
final class Raw {
  Raw({int maxLineChars = 1 << 20, int maxBadLines = 20}) {
    conn = JsonRpcConnection(
      input: toConn.stream,
      output: fromConn.sink,
      maxLineChars: maxLineChars,
      maxBadLines: maxBadLines,
    );
    out = StreamQueue(
      fromConn.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .map((l) => jsonDecode(l) as JsonMap),
    );
  }
  final toConn = StreamController<List<int>>();
  final fromConn = StreamController<List<int>>();
  late final JsonRpcConnection conn;
  late final StreamQueue<JsonMap> out;

  void send(String text) => toConn.add(utf8.encode(text));
  void line(Object json) => send('${jsonEncode(json)}\n');
}

void main() {
  group('request and response', () {
    test('round trip between two ends', () async {
      final (a, b) = pair();
      b.onRequest('echo', (p) => {'got': p['x']});
      expect(await a.request('echo', {'x': 1}), {'got': 1});
    });

    test('a notification reaches its handler with its params', () async {
      final (a, b) = pair();
      final got = Completer<JsonMap>();
      b.onNotification('n', got.complete);
      a.notify('n', {'k': 'v'});
      expect(await got.future, {'k': 'v'});
    });

    test('an unknown method answers -32601', () async {
      final (a, _) = pair();
      await expectLater(
        a.request('nope'),
        throwsA(isA<JsonRpcError>().having((e) => e.code, 'code', -32601)),
      );
    });

    test(
      'a handler error keeps its code; toString hides the message',
      () async {
        final (a, b) = pair();
        b.onRequest(
          'session/new',
          (_) => throw const JsonRpcError(
            -32000,
            'Authentication required: secret',
          ),
        );
        final e = await a
            .request('session/new')
            .then<Object?>((_) => null, onError: (Object e) => e);
        expect(
          e,
          isA<JsonRpcError>().having(
            (e) => e.code,
            'code',
            JsonRpcError.authRequired,
          ),
        );
        expect(
          (e! as JsonRpcError).message,
          contains('Authentication required'),
        );
        expect(e.toString(), 'JsonRpcError(-32000)');
      },
    );

    test('a handler bug answers -32603 and is reported to the zone', () async {
      final reported = <Object>[];
      await runZonedGuarded(() async {
        final (a, b) = pair();
        b.onRequest('boom', (_) => throw StateError('bug'));
        await expectLater(
          a.request('boom'),
          throwsA(isA<JsonRpcError>().having((e) => e.code, 'code', -32603)),
        );
      }, (e, _) => reported.add(e));
      expect(reported.single, isA<StateError>());
    });

    test('responses out of order reach the right callers', () async {
      final r = Raw();
      final first = r.conn.request('a');
      final second = r.conn.request('b');
      final m1 = await r.out.next;
      final m2 = await r.out.next;
      r.line({'jsonrpc': '2.0', 'id': m2['id'], 'result': 'B'});
      r.line({'jsonrpc': '2.0', 'id': m1['id'], 'result': 'A'});
      expect(await first, 'A');
      expect(await second, 'B');
    });

    test('a response with an unknown id is ignored', () async {
      final r = Raw();
      r.line({'jsonrpc': '2.0', 'id': 999, 'result': 1});
      final f = r.conn.request('x');
      final m = await r.out.next;
      r.line({'jsonrpc': '2.0', 'id': m['id'], 'result': 2});
      expect(await f, 2);
    });

    test('an error object without an int code becomes -32603', () async {
      final r = Raw();
      final f = r.conn.request('x');
      final m = await r.out.next;
      r.line({
        'jsonrpc': '2.0',
        'id': m['id'],
        'error': {'message': 'odd'},
      });
      await expectLater(
        f,
        throwsA(isA<JsonRpcError>().having((e) => e.code, 'code', -32603)),
      );
    });

    test('incoming requests echo string ids', () async {
      final r = Raw();
      r.conn.onRequest('ping', (_) => 'pong');
      r.line({'jsonrpc': '2.0', 'id': 'abc', 'method': 'ping'});
      expect(await r.out.next, {
        'jsonrpc': '2.0',
        'id': 'abc',
        'result': 'pong',
      });
    });
  });

  group('framing', () {
    test('a multibyte character split across chunks arrives whole', () async {
      final r = Raw();
      final got = Completer<JsonMap>();
      r.conn.onNotification('n', got.complete);
      final bytes = utf8.encode(
        '${jsonEncode({
          'jsonrpc': '2.0',
          'method': 'n',
          'params': {'t': 'Tiếng Việt ✓'},
        })}\n',
      );
      final cut =
          utf8
              .encode('{"jsonrpc":"2.0","method":"n","params":{"t":"Ti')
              .length +
          1;
      r.toConn.add(bytes.sublist(0, cut)); // ends inside "ế"
      r.toConn.add(bytes.sublist(cut));
      expect((await got.future)['t'], 'Tiếng Việt ✓');
    });

    test('CRLF endings and blank lines are accepted', () async {
      final r = Raw();
      final got = <String>[];
      r.conn.onNotification('n', (p) => got.add(p['v']! as String));
      r.send('\r\n\n{"jsonrpc":"2.0","method":"n","params":{"v":"1"}}\r\n');
      r.send('{"jsonrpc":"2.0","method":"n","params":{"v":"2"}}\n');
      await pumpEventQueue();
      expect(got, ['1', '2']);
    });

    test(
      'a notification and a response in one chunk: notification first',
      () async {
        final r = Raw();
        final order = <String>[];
        r.conn.onNotification('session/update', (_) => order.add('update'));
        final f = r.conn
            .request('session/prompt')
            .then((_) => order.add('response'));
        final m = await r.out.next;
        r.send(
          '${jsonEncode({'jsonrpc': '2.0', 'method': 'session/update', 'params': {}})}\n'
          '${jsonEncode({
            'jsonrpc': '2.0',
            'id': m['id'],
            'result': {'stopReason': 'end_turn'},
          })}\n',
        );
        await f;
        expect(order, ['update', 'response']);
      },
    );

    test('every outgoing message is exactly one line', () async {
      final r = Raw();
      final lines = <String>[];
      final sub = r.fromConn.stream.listen((b) => lines.add(utf8.decode(b)));
      r.conn.notify('n', {'text': 'a\nb\r\nc'});
      await pumpEventQueue();
      await sub.cancel();
      expect(lines.single.indexOf('\n'), lines.single.length - 1);
    });

    test('a line of 10 MiB is accepted with the default limit', () async {
      final toConn = StreamController<List<int>>();
      final conn = JsonRpcConnection(
        input: toConn.stream,
        output: StreamController<List<int>>().sink,
      );
      final got = Completer<int>();
      conn.onNotification('n', (p) => got.complete((p['t']! as String).length));
      final big = utf8.encode(
        '${jsonEncode({
          'jsonrpc': '2.0',
          'method': 'n',
          'params': {'t': 'x' * (10 << 20)},
        })}\n',
      );
      for (var i = 0; i < big.length; i += 65536) {
        toConn.add(
          big.sublist(i, i + 65536 > big.length ? big.length : i + 65536),
        );
      }
      expect(await got.future, 10 << 20);
      expect(conn.isClosed, isFalse);
    });

    test(
      'a line at the limit is fine; one char more stops the connection',
      () async {
        final ok = Raw(maxLineChars: 64);
        final line = jsonEncode({
          'jsonrpc': '2.0',
          'method': 'n',
          'params': {'t': ''},
        });
        final pad = 'x' * (64 - line.length);
        ok.send(
          '${jsonEncode({
            'jsonrpc': '2.0',
            'method': 'n',
            'params': {'t': pad},
          })}\n',
        );
        await pumpEventQueue();
        expect(ok.conn.isClosed, isFalse);

        final tooLong = Raw(maxLineChars: 64);
        // Armed before the close: a future that fails while nothing listens is
        // reported as an uncaught error, even if a listener attaches later.
        final pending = expectLater(
          tooLong.conn.request('x'),
          throwsA(isA<ConnectionClosed>()),
        );
        tooLong.send('y' * 65);
        expect(await tooLong.conn.done, ConnectionCloseReason.lineTooLong);
        await pending;
      },
    );

    test(
      'bad lines are skipped; more than maxBadLines in a row stop it',
      () async {
        final r = Raw(maxBadLines: 3);
        final got = <String>[];
        r.conn.onNotification('n', (p) => got.add(p['v']! as String));
        r.send('garbage\n[1,2]\n"str"\n'); // three bad lines: still open
        r.line({
          'jsonrpc': '2.0',
          'method': 'n',
          'params': {'v': 'ok'},
        }); // resets the count
        r.send('bad\nbad\nbad\n');
        await pumpEventQueue();
        expect(r.conn.isClosed, isFalse);
        expect(got, ['ok']);
        final pending = expectLater(
          r.conn.request('x'),
          throwsA(
            isA<ConnectionClosed>().having(
              (e) => e.reason,
              'reason',
              ConnectionCloseReason.tooManyBadLines,
            ),
          ),
        );
        r.send('bad\n'); // the fourth in a row
        expect(await r.conn.done, ConnectionCloseReason.tooManyBadLines);
        await pending;
      },
    );

    test('a throwing notification handler does not drop later lines', () async {
      final got = <String>[];
      final reported = <Object>[];
      await runZonedGuarded(() async {
        final r = Raw();
        r.conn.onNotification('bad', (_) => throw StateError('bug'));
        r.conn.onNotification('good', (p) => got.add('good'));
        r.send(
          '${jsonEncode({'jsonrpc': '2.0', 'method': 'bad'})}\n'
          '${jsonEncode({'jsonrpc': '2.0', 'method': 'good'})}\n',
        );
        await pumpEventQueue();
      }, (e, _) => reported.add(e));
      expect(got, ['good']);
      expect(reported.single, isA<StateError>());
    });
  });

  group('lifecycle', () {
    test('input end: done is ended, pending and later requests fail', () async {
      final r = Raw();
      final pending = expectLater(
        r.conn.request('x'),
        throwsA(isA<ConnectionClosed>()),
      );
      await r.toConn.close();
      expect(await r.conn.done, ConnectionCloseReason.ended);
      await pending;
      await expectLater(r.conn.request('y'), throwsA(isA<ConnectionClosed>()));
      expect(r.conn.closeReason, ConnectionCloseReason.ended);
    });

    test('close() closes the output so the peer sees the end', () async {
      final (a, b) = pair();
      await a.close();
      expect(await a.done, ConnectionCloseReason.closed);
      expect(await b.done, ConnectionCloseReason.ended);
      a.notify('ignored'); // no throw after close
    });
  });
}
