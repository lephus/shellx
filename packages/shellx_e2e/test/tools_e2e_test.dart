@TestOn('mac-os || linux')
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:test/test.dart';

import 'support/e2e_world.dart';

final String? relayUrl = Platform.environment['SHELLX_E2E_RELAY'];

const _id = 'k3f9za7q1m';
const _size = 50 * 1000 * 1000;
int _byte(int i) => (i * 131 + (i >> 9)) & 0xFF;

/// The tool, on 127.0.0.1 at a port of its own: a page, 50 MB at `/big`, a
/// WebSocket echo at `/ws`.
Future<HttpServer> _tool() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final response = request.response;
    switch (request.uri.path) {
      case '/big':
        response.contentLength = _size;
        final chunk = Uint8List(65536);
        for (var at = 0; at < _size; at += chunk.length) {
          final n = _size - at < chunk.length ? _size - at : chunk.length;
          for (var i = 0; i < n; i++) {
            chunk[i] = _byte(at + i);
          }
          response.add(Uint8List.fromList(chunk.sublist(0, n)));
          await response.flush();
        }
        await response.close();
      case '/ws':
        final ws = await WebSocketTransformer.upgrade(request);
        ws.listen(ws.add);
      default:
        response.write('<h1>tool</h1>');
        await response.close();
    }
  });
  return server;
}

/// A port free on 127.0.0.1 and on [::1] (held on both, then let go): the
/// port the window lists, which the phone then holds on both addresses as it
/// must (same-port mode, E2).
Future<int> _freeLoopbackPort() async {
  for (var tries = 1; ; tries++) {
    final v4 = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    try {
      final v6 = await ServerSocket.bind(
        InternetAddress.loopbackIPv6,
        v4.port,
        v6Only: true,
      );
      await v6.close();
      return v4.port;
    } on SocketException {
      if (tries == 20) rethrow;
    } finally {
      await v4.close();
    }
  }
}

/// V2-4 §8 and success criterion 7 over a real relay (run with
/// `SHELLX_E2E_RELAY=http://127.0.0.1:8787` while `npm run dev` runs in
/// `relay/`): the relay's 500 frames a second and its frame size are real
/// here.
void main() {
  test('50 MB through the tunnel: whole, the channel and a terminal stay; '
      'a WebSocket echoes; turned off, the page says so', () async {
    final tool = await _tool();
    // R21, same-port mode (E2), one machine playing both sides: the window
    // lists [listed], which the phone holds on its loopback; the proxy's
    // connect takes that port (and no other) to where the tool listens.
    final listed = await _freeLoopbackPort();
    final proxy = ToolProxy(
      connect: (port) {
        if (port != listed) {
          throw const SocketException('no test tool is listed on this port');
        }
        return Socket.connect(InternetAddress.loopbackIPv4, tool.port);
      },
    );
    final world = await E2eWorld.create(Uri.parse(relayUrl!), tools: proxy);
    final client = HttpClient()
      ..findProxy = ((_) => 'DIRECT')
      ..connectionFactory = (uri, _, _) async => ConnectionTask.fromSocket(
        Socket.connect(InternetAddress.loopbackIPv4, uri.port),
        () {},
      );
    addTearDown(() async {
      client.close(force: true);
      proxy.close();
      await world.dispose();
      await tool.close(force: true);
    });
    proxy.serve(
      ToolCatalog.fromServeBody(
        ToolCatalog.serveBody([
          {
            'id': _id,
            'name': 'Bảng việc',
            'ws': 'shop-web',
            'group': 'ws:a',
            'url': 'http://localhost:$listed/',
          },
        ]),
      ),
    );
    await world.pair(world.phone, registered: false);
    final machine = world.phone.service.machine(world.agentId);
    await machine.connect();
    await machine.listSessions(includeDesktop: true);
    expect(machine.tools.supported, isTrue);
    final tab = await machine.openSession(cols: 80, rows: 24);
    final output = TabText(tab);

    final session = ToolSession(
      tool: _id,
      port: listed,
      path: '/',
      link: machine.tools,
    );
    addTearDown(session.close);
    final loads = <Uri>[];
    session.events.listen((e) {
      if (e is ToolLoad) loads.add(e.url);
    });
    session.start();
    await waitUntil(() => loads.isNotEmpty, reason: 'the tool did not open');
    // Same-port mode (E2): the tool's own port, no alias.
    final served = session.servedPort!;
    expect(served, listed);
    expect(session.alias, isNull);

    // The entry URL: its cookie is the gate.
    final entering = await client.getUrl(loads.single);
    entering.followRedirects = false;
    final enter = await entering.close();
    expect(enter.statusCode, 303);
    final cookie = enter.headers['set-cookie']!.single.split(';').first;
    await enter.drain<void>();
    Future<HttpClientResponse> get(String path) async {
      final request = await client.getUrl(
        Uri.parse('http://localhost:$served$path'),
      );
      request.headers.set('cookie', cookie);
      return request.close();
    }

    // The page, through the tunnel.
    final page = await get('/');
    expect(page.statusCode, 200);
    expect(await utf8.decodeStream(page), '<h1>tool</h1>');

    // 50 MB, checked byte by byte as it streams, while a terminal echoes. The
    // shell prints "ready-42" for the sum, which its echo of the line does
    // not contain: only the shell's answer does.
    final big = await get('/big');
    expect(big.statusCode, 200);
    var at = 0;
    var wrong = 0;
    var echoed = false;
    await for (final chunk in big) {
      for (final b in chunk) {
        if (b != _byte(at++)) wrong++;
      }
      if (!echoed && at > _size ~/ 2) {
        echoed = true;
        machine.input(
          tab.id,
          Uint8List.fromList(utf8.encode('echo ready-\$((20+22))\n')),
        );
      }
    }
    expect(at, _size);
    expect(wrong, 0);
    // The other half of the download took seconds: the terminal answered
    // while it ran, not once it was over.
    expect(output.text, contains('ready-42'), reason: 'terminal');
    expect(machine.state, isA<MachineReady>());

    // A WebSocket echo.
    final ws = await WebSocket.connect(
      'ws://localhost:$served/ws',
      headers: {'cookie': cookie},
      customClient: client,
    );
    final got = <Object?>[];
    ws.listen(got.add);
    ws.add('xin chào');
    await waitUntil(() => got.isNotEmpty, reason: 'no echo');
    expect(got.single, 'xin chào');

    // Turned off on the computer: the page says so within a second, the
    // WebSocket is gone and nothing is served on the phone any more.
    final clock = Stopwatch()..start();
    proxy.serve(ToolCatalog([], off: {_id}));
    await waitUntil(
      () => session.phase == ToolPhase.disabled,
      reason: 'not disabled',
    );
    expect(clock.elapsed, lessThan(const Duration(seconds: 1)));
    await ws.done.timeout(const Duration(seconds: 5));
    await expectLater(get('/'), throwsA(isA<SocketException>()));
    await session.close();
  }, skip: relayUrl == null ? 'SHELLX_E2E_RELAY is not set' : null);
}
