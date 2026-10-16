import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import '../support/tool_rig.dart';

const _id = 'k3f9za7q1m';

/// V2-4 §5, E7, E10: WebSockets through the desktop proxy, against a real
/// tool on loopback.
void main() {
  late TestTool tool;
  late ToolProxy proxy;
  late ToolPhone phone;

  Future<void> setUpWith({
    Map<String, Future<void> Function(HttpRequest)> routes = const {},
    ToolProxy? withProxy,
  }) async {
    tool = await TestTool.start(routes: routes);
    proxy = withProxy ?? ToolProxy();
    proxy.serve(catalogOf([tool.entry()]));
    phone = ToolPhone(proxy);
  }

  tearDown(() async {
    proxy.close();
    await tool.close();
  });

  /// Opens `/ws` offering `vite-hmr`; its stream id once it is open.
  Future<int> open() async {
    final id = phone.request(
      _id,
      target: '/ws?token=abc',
      ws: true,
      head: [
        'host',
        'localhost:${tool.port}',
        'upgrade',
        'websocket',
        'connection',
        'Upgrade',
        'sec-websocket-key',
        'dGhlIHNhbXBsZSBub25jZQ==',
        'sec-websocket-version',
        '13',
        'sec-websocket-protocol',
        'vite-hmr',
        'origin',
        'http://localhost:${tool.port}',
      ],
    );
    final response = await phone.response(id);
    expect(response.status, 101);
    expect(toolHeadValues(response.head, 'sec-websocket-protocol'), [
      'vite-hmr',
    ]);
    return id;
  }

  void say(int id, Object message) {
    final bytes = message is String
        ? utf8.encode(message)
        : message as Uint8List;
    phone.send(
      ToolWsMessage(id: id, data: bytes, text: message is String, fin: true),
    );
  }

  test('the tool sees the request as from the page; messages go both ways, '
      'text stays text', () async {
    await setUpWith();
    final id = await open();
    final hit = tool.hits.single;
    expect(hit.uri.query, 'token=abc');
    expect(hit.headers['origin'], ['http://localhost:${tool.port}']);
    expect(hit.headers['host'], ['localhost:${tool.port}']);
    expect(
      hit.headers['sec-websocket-key'],
      isNot(['dGhlIHNhbXBsZSBub25jZQ==']),
      reason: 'the desktop makes its own handshake',
    );
    say(id, 'hello');
    say(id, Uint8List.fromList([1, 2, 3]));
    await until(() => phone.wsPieces(id).length == 2);
    final pieces = phone.wsPieces(id);
    expect(pieces[0].text, isTrue);
    expect(utf8.decode(pieces[0].data), 'hello');
    expect(pieces[1].text, isFalse);
    expect(pieces[1].data, [1, 2, 3]);
  });

  test(
    'a 1 MiB message goes in pieces of ≤ 48 KiB and comes back whole',
    () async {
      await setUpWith();
      final id = await open();
      final big = Uint8List.fromList([
        for (var i = 0; i < 1024 * 1024; i++) i & 0xFF,
      ]);
      // The phone sends it in pieces, within the window the desktop opens.
      var at = 0;
      while (at < big.length) {
        final end = at + kToolMaxChunkBytes > big.length
            ? big.length
            : at + kToolMaxChunkBytes;
        phone.send(
          ToolWsMessage(
            id: id,
            data: Uint8List.sublistView(big, at, end),
            text: false,
            fin: end == big.length,
          ),
        );
        at = end;
        await pumpEventQueue();
      }
      await until(() => phone.wsPieces(id).any((p) => p.fin));
      final pieces = phone.wsPieces(id);
      expect(pieces.every((p) => p.data.length <= kToolMaxChunkBytes), isTrue);
      expect([for (final p in pieces) ...p.data], big);
    },
  );

  test('close codes cross both ways', () async {
    await setUpWith();
    final a = await open();
    say(a, 'close:4001');
    await phone.ended(a);
    expect(phone.endOf(a)?.wsCode, 4001);
    expect(phone.endOf(a)?.wsReason, 'by tool');
    expect(phone.endOf(a)?.code, isNull);

    final b = await open();
    phone.send(ToolEnd(id: b, wsCode: 4002, wsReason: 'bye'));
    await until(() => tool.wsClosed.length == 2);
    expect(tool.wsClosed.last, (4002, 'bye'));
  });

  test(
    'a tool that does not upgrade: its answer goes to the phone as HTTP',
    () async {
      await setUpWith(
        routes: {
          '/ws': (request) async {
            request.response
              ..statusCode = 403
              ..write('Invalid token');
            await request.response.close();
          },
        },
      );
      final id = phone.request(
        _id,
        target: '/ws',
        ws: true,
        head: ['upgrade', 'websocket'],
      );
      final response = await phone.response(id);
      await phone.ended(id);
      expect(response.status, 403);
      expect(utf8.decode(phone.body(id)), 'Invalid token');
    },
  );

  test('a message over the limit closes with 1009, either way (E10)', () async {
    final bigClosed = Completer<int?>();
    await setUpWith(
      withProxy: ToolProxy(maxWsMessage: 1000),
      routes: {
        // A tool that sends a message over the limit once it is open.
        '/big': (request) async {
          final ws = await WebSocketTransformer.upgrade(request);
          ws.listen(null, onDone: () => bigClosed.complete(ws.closeCode));
          ws.add(Uint8List(1001));
        },
      },
    );
    final a = await open();
    say(a, Uint8List(1001));
    await phone.ended(a);
    expect(phone.endOf(a)?.wsCode, 1009);
    await until(() => tool.wsClosed.isNotEmpty);
    expect(tool.wsClosed.single.$1, 1009);

    final b = phone.request(_id, target: '/big', ws: true);
    expect((await phone.response(b)).status, 101);
    await phone.ended(b);
    expect(phone.wsPieces(b), isEmpty, reason: 'never sent on, not a piece');
    expect(phone.endOf(b)?.wsCode, 1009);
    expect(await bigClosed.future.timeout(const Duration(seconds: 10)), 1009);
  });

  test('more than 16 WebSockets: busy', () async {
    await setUpWith();
    for (var i = 0; i < 16; i++) {
      await open();
    }
    final id = phone.request(_id, target: '/ws', ws: true);
    await pumpEventQueue();
    expect(phone.endOf(id)?.code, 'busy');
  });

  test('turning the flag off drops the WebSocket on both sides (E9)', () async {
    await setUpWith();
    final id = await open();
    proxy.serve(catalogOf([], off: [_id]));
    await phone.ended(id);
    expect(phone.endOf(id)?.code, 'disabled');
    await until(() => tool.wsClosed.isNotEmpty);
  });

  test('a WebSocket upgrade must be a GET', () async {
    await setUpWith();
    final id = phone.request(_id, method: 'POST', target: '/ws', ws: true);
    await pumpEventQueue();
    expect(phone.endOf(id)?.code, 'bad_request');
    expect(tool.hits, isEmpty);
  });

  /// `/ws` on a tool that answers each upgrade by hand: [answer]'s raw
  /// bytes, or never. [ends] gets one future per connection, done once the
  /// desktop drops it.
  Future<void> Function(HttpRequest) byHand(
    List<Future<void>> ends, {
    String Function(HttpRequest request)? answer,
  }) => (request) async {
    final socket = await request.response.detachSocket(writeHeaders: false);
    addTearDown(socket.destroy);
    final end = Completer<void>();
    ends.add(end.future);
    socket.listen(
      null,
      onDone: end.complete,
      onError: (Object _) => end.complete(),
      cancelOnError: true,
    );
    if (answer != null) socket.add(latin1.encode(answer(request)));
  };

  test('a stream that ends before the tool answered the upgrade drops its '
      'connection: the phone gone, the flag turned off', () async {
    final ends = <Future<void>>[];
    await setUpWith(routes: {'/ws': byHand(ends)});
    phone.request(_id, target: '/ws', ws: true);
    await until(() => ends.length == 1);
    proxy.phoneGone(phone.mobileId);
    await ends[0].timeout(const Duration(seconds: 5));

    final id = phone.request(_id, target: '/ws', ws: true);
    await until(() => ends.length == 2);
    proxy.serve(catalogOf([], off: [_id]));
    await phone.ended(id);
    expect(phone.endOf(id)?.code, 'disabled');
    await ends[1].timeout(const Duration(seconds: 5));
  });

  test('an upgrade the tool does not answer in time: timeout, and its '
      'connection is dropped', () async {
    final ends = <Future<void>>[];
    await setUpWith(
      routes: {'/ws': byHand(ends)},
      withProxy: ToolProxy(headTimeout: const Duration(milliseconds: 200)),
    );
    final id = phone.request(_id, target: '/ws', ws: true);
    await phone.ended(id);
    expect(phone.endOf(id)?.code, 'timeout');
    await ends.single.timeout(const Duration(seconds: 5));
  });

  test('a 101 with a protocol the webview did not offer, or with more than '
      'one: aborted, and the connection is dropped (RFC 6455 §4.1)', () async {
    final ends = <Future<void>>[];
    await setUpWith(
      routes: {
        '/ws': byHand(
          ends,
          answer: (request) => [
            'HTTP/1.1 101 Switching Protocols',
            'connection: Upgrade',
            'upgrade: websocket',
            for (final p in request.uri.queryParametersAll['p']!)
              'sec-websocket-protocol: $p',
            '',
            '',
          ].join('\r\n'),
        ),
      },
    );
    const offered = ['sec-websocket-protocol', 'vite-hmr, other'];
    final a = phone.request(_id, target: '/ws?p=mine', ws: true, head: offered);
    await phone.ended(a);
    expect(phone.endOf(a)?.code, 'aborted');
    await ends[0].timeout(const Duration(seconds: 5));

    final b = phone.request(
      _id,
      target: '/ws?p=vite-hmr&p=other',
      ws: true,
      head: offered,
    );
    await phone.ended(b);
    expect(phone.endOf(b)?.code, 'aborted');
    await ends[1].timeout(const Duration(seconds: 5));
  });

  test('a reason over 123 bytes reaches the tool cut at a character '
      'boundary', () async {
    await setUpWith();
    final id = await open();
    phone.send(ToolEnd(id: id, wsCode: 4003, wsReason: '😀' * 40));
    await until(() => tool.wsClosed.isNotEmpty);
    expect(tool.wsClosed.single, (4003, '😀' * 30));
  });
}
