import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import 'support/test_tool.dart';
import 'support/tool_pipe.dart';

const _id = 'k3f9za7q1m';

/// The head of the answer to [lines] (one HTTP/1.1 request) on a raw socket
/// to [address] (127.0.0.1 unless given) and [port], line by line as it was
/// sent: the status line, then each header line (`name: value`).
Future<List<String>> _rawHead(
  int port,
  List<String> lines, {
  InternetAddress? address,
}) async {
  final socket = await Socket.connect(
    address ?? InternetAddress.loopbackIPv4,
    port,
  );
  final bytes = <int>[];
  final head = Completer<void>();
  final subscription = socket.listen(
    (chunk) {
      bytes.addAll(chunk);
      final text = String.fromCharCodes(bytes);
      if (text.contains('\r\n\r\n') && !head.isCompleted) head.complete();
    },
    onError: (Object _) {},
    onDone: () {
      if (!head.isCompleted) head.complete();
    },
  );
  socket.write('${lines.join('\r\n')}\r\n\r\n');
  await head.future.timeout(const Duration(seconds: 5));
  await subscription.cancel();
  socket.destroy();
  final text = String.fromCharCodes(bytes);
  final end = text.indexOf('\r\n\r\n');
  return (end < 0 ? text : text.substring(0, end)).split('\r\n');
}

/// A WebSocket upgrade of [path] from the page on [port], with [cookie]
/// (the webview's `Cookie` value), for [_rawHead].
List<String> _upgrade(int port, String path, String cookie) => [
  'GET $path HTTP/1.1',
  'host: localhost:$port',
  'connection: Upgrade',
  'upgrade: websocket',
  'sec-websocket-version: 13',
  'sec-websocket-key: dGhlIHNhbXBsZSBub25jZQ==',
  'origin: http://localhost:$port',
  'cookie: $cookie',
];

/// The `Content-Security-Policy` lines of a raw [head], one per line.
List<String> _policies(List<String> head) => [
  for (final line in head.skip(1))
    if (line.toLowerCase().startsWith('content-security-policy:'))
      line.substring(line.indexOf(':') + 1).trim(),
];

/// A stand-in for the computer, for the answers the real proxy gives only
/// in rare cases: it serves the page's tool on [port] and answers each
/// request at once with what [script] gives. It takes no body (never
/// acknowledges), so an upload stays within the windows.
final class _Desktop {
  _Desktop(this.port, this.script) {
    tools = MachineTools(
      send: _fromPhone,
      connect: () async {},
      timeout: const Duration(seconds: 5),
    )..channelReady();
  }

  final int port;
  final List<ToolMessage> Function(ToolRequest request) script;
  late final MachineTools tools;
  final requests = <ToolRequest>[];

  /// The streams the phone ended (`tool.end`), in order.
  final ends = <ToolEnd>[];

  /// What the phone acknowledged (`tool.ack`'s `[id, total, …]`), in order.
  final acked = <List<int>>[];

  bool _fromPhone(List<AppMessage> batch) {
    final messages = decodeBatch(encodeBatch(batch));
    scheduleMicrotask(() {
      for (final message in messages) {
        var replies = const <ToolMessage>[];
        switch (message) {
          case ToolOpen(:final rid, :final tool):
            final serving = {
              'v': 1,
              'tools': [
                {'id': tool, 'port': port, 'path': '/'},
              ],
            };
            replies = [
              ToolOpened(
                rid: rid,
                ok: true,
                body: Uint8List.fromList(utf8.encode(jsonEncode(serving))),
              ),
            ];
          case final ToolRequest request:
            requests.add(request);
            replies = script(request);
          case final ToolEnd end:
            ends.add(end);
          case ToolAck(:final acks):
            acked.add(acks);
          default:
            break;
        }
        for (final reply in replies) {
          tools.handle(decodeBatch(encodeBatch([reply])).single as ToolMessage);
        }
      }
    });
    return true;
  }
}

/// What the stand-in computer sends for a request: `/end/<code>` ends it
/// with that code before any response; `/early` answers in full (`early`)
/// whatever the body; `/bad-status` answers a status no HTTP response has;
/// `/ws-protocol` opens a WebSocket on a protocol nobody offered,
/// `/ws-two-protocols` on two; `/ws-hello`, `/ws-close` and `/ws-hello-bye`
/// open one and, in the same batch as the 101, send `hello`, close with
/// 4000, or send `hello` and `again` and close with 4001; `/hold` gets
/// nothing; anything else 204.
List<ToolMessage> _script(ToolRequest request) {
  final id = request.id;
  final target = request.target;
  if (target.startsWith('/end/')) {
    return [ToolEnd(id: id, code: target.substring(5))];
  }
  final opened = ToolResponse(id: id, status: 101, head: const [], end: false);
  ToolWsMessage say(String text) => ToolWsMessage(
    id: id,
    data: Uint8List.fromList(utf8.encode(text)),
    text: true,
    fin: true,
  );
  return switch (target) {
    '/ws-hello' => [opened, say('hello')],
    '/ws-close' => [opened, ToolEnd(id: id, wsCode: 4000, wsReason: 'bye')],
    '/ws-hello-bye' => [
      opened,
      say('hello'),
      say('again'),
      ToolEnd(id: id, wsCode: 4001),
    ],
    '/early' => [
      ToolResponse(
        id: id,
        status: 200,
        head: const ['content-type', 'text/plain'],
        end: false,
      ),
      ToolData(
        id: id,
        data: Uint8List.fromList(utf8.encode('early')),
        end: true,
      ),
    ],
    '/bad-status' => [
      ToolResponse(id: id, status: 42, head: const [], end: true),
    ],
    '/ws-protocol' => [
      ToolResponse(
        id: id,
        status: 101,
        head: const ['sec-websocket-protocol', 'never-offered'],
        end: false,
      ),
    ],
    '/ws-two-protocols' => [
      ToolResponse(
        id: id,
        status: 101,
        head: const [
          'sec-websocket-protocol',
          'chat',
          'sec-websocket-protocol',
          'chat',
        ],
        end: false,
      ),
    ],
    '/hold' => const [],
    _ => [ToolResponse(id: id, status: 204, head: const [], end: true)],
  };
}

/// V2-4 E2, E3, E4, E11, E13, §8: the phone's loopback server for one open
/// tool, with real sockets: a tool, the desktop's proxy, the phone's
/// session, and a webview stand-in.
void main() {
  late TestTool tool;
  late ToolProxy proxy;
  late ToolPipe pipe;
  late ToolSession session;
  late Webview webview;
  late List<ToolPageEvent> events;

  /// Whether the test opened a page (the policy's own test opens none).
  var opened = false;

  /// Opens the page of [tool], which the test made: the desktop's proxy
  /// reaching tools by [connectTestTool], the phone's session, a webview.
  Future<void> openPage({
    List<Map<String, Object?>> Function(TestTool tool)? catalog,
    List<Duration> retry = kToolRetryDelays,
    Duration headTimeout = kToolHeadTimeout,
  }) async {
    opened = true;
    proxy = ToolProxy(connect: connectTestTool, headTimeout: headTimeout);
    proxy.serve(catalogOf(catalog?.call(tool) ?? [tool.entry()]));
    pipe = ToolPipe(proxy);
    session = ToolSession(
      tool: _id,
      port: tool.port,
      path: '/',
      link: pipe.tools,
      retryDelays: retry,
    );
    events = [];
    session.events.listen(events.add);
    webview = Webview();
    session.start();
    await until(() => events.whereType<ToolLoad>().isNotEmpty);
  }

  /// Same-port mode (E2, R21) with one machine playing both sides: the
  /// window lists a port free on 127.0.0.1 and [::1], which the phone holds
  /// on both; the desktop's connect takes it to where the tool listens
  /// ([TestTool.samePort], [connectTestTool]).
  Future<void> openSamePort({
    Map<String, Future<void> Function(HttpRequest)> routes = const {},
    List<Map<String, Object?>> Function(TestTool tool)? catalog,
    List<Duration> retry = kToolRetryDelays,
    Duration headTimeout = kToolHeadTimeout,
  }) async {
    opened = true;
    tool = await TestTool.samePort(routes: routes);
    await openPage(catalog: catalog, retry: retry, headTimeout: headTimeout);
  }

  Uri at(String path, {int? port}) =>
      Uri.parse('http://localhost:${port ?? session.servedPort}$path');

  /// A page served against the stand-in computer ([_Desktop], [_script]),
  /// its gate cookie set; it cleans up after itself.
  Future<({ToolSession page, Webview view, _Desktop desktop})>
  openScripted() async {
    final port = await freeLoopbackPort();
    final desktop = _Desktop(port, _script);
    final page = ToolSession(
      tool: _id,
      port: port,
      path: '/',
      link: desktop.tools,
    );
    final view = Webview();
    addTearDown(() async {
      await page.close();
      view.close();
    });
    final loads = <ToolLoad>[];
    page.events.listen((event) {
      if (event is ToolLoad) loads.add(event);
    });
    page.start();
    await until(() => loads.isNotEmpty);
    expect((await view.request(loads.single.url)).status, 303);
    return (page: page, view: view, desktop: desktop);
  }

  tearDown(() async {
    if (!opened) return;
    opened = false;
    await session.close();
    webview.close();
    proxy.close();
    await tool.close();
  });

  group('the gate (E11, RF 5)', () {
    test('the entry URL sets the gate cookie once, then the page comes '
        'through the tunnel on the tool\'s own port (E2)', () async {
      await openSamePort();
      expect(session.phase, ToolPhase.ready);
      expect(
        session.servedPort,
        tool.port,
        reason: 'the same port as the tool',
      );
      expect(session.alias, isNull);
      final entry = events.whereType<ToolLoad>().single.url;
      expect(entry.path, '/__shellx/enter');
      final first = await webview.request(entry);
      expect(first.status, 303);
      expect(first.headers['location'], ['/']);
      expect(first.headers['cache-control'], ['no-store']);
      expect(first.headers['referrer-policy'], ['no-referrer']);
      final cookie = first.headers['set-cookie']!.single;
      expect(cookie, startsWith('__shellx_${tool.port}='));
      expect(cookie, contains('HttpOnly'));
      expect(cookie, contains('SameSite=Strict'));
      expect(cookie, contains('Path=/'));
      final page = await webview.request(at('/'));
      expect(page.status, 200);
      expect(page.text, '<h1>/</h1>');
      final hit = tool.hits.single;
      expect(hit.headers['host'], ['localhost:${tool.port}']);
      expect(
        hit.headers['cookie'],
        isNull,
        reason: 'the gate cookie stays on the phone',
      );
      // Used once: the same entry URL is refused now.
      final again = await webview.request(entry, withCookies: false);
      expect(again.status, 403);
    });

    test('without the cookie, with another Host, or with an expired entry: '
        '403, and nothing reaches the tool', () async {
      await openSamePort();
      expect((await webview.request(at('/'))).status, 403);
      await webview.enter(events.whereType<ToolLoad>().single.url);
      tool.hits.clear();
      final rebinding = await webview.request(
        at('/'),
        headers: {'host': 'evil.com:${session.servedPort}'},
      );
      expect(rebinding.status, 403, reason: 'DNS rebinding');
      final other = Webview();
      addTearDown(other.close);
      expect((await other.request(at('/'))).status, 403, reason: 'another app');
      expect(tool.hits, isEmpty);
    });

    test('/__shellx/ is the phone\'s own: never sent on', () async {
      await openSamePort();
      await webview.enter(events.whereType<ToolLoad>().single.url);
      tool.hits.clear();
      expect((await webview.request(at('/__shellx/other'))).status, 404);
      expect((await webview.request(at('/__shellx/enter?n=x'))).status, 403);
      expect(tool.hits, isEmpty);
    });

    test('an unsafe request from another origin, or cross-site, is refused; '
        'a tool cannot set the gate cookie; the phone adds no header of its '
        'own', () async {
      await openSamePort(
        routes: {
          '/post': (request) async {
            await request.drain<void>();
            request.response.headers.add(
              'set-cookie',
              '__shellx_${request.connectionInfo!.localPort}=stolen; Path=/',
            );
            request.response.headers.add('set-cookie', 'sid=1; Path=/');
            await request.response.close();
          },
        },
      );
      await webview.enter(events.whereType<ToolLoad>().single.url);
      final evil = await webview.request(
        at('/post'),
        method: 'POST',
        headers: {'origin': 'http://evil.com'},
        body: [1],
      );
      expect(evil.status, 403);
      final crossSite = await webview.request(
        at('/post'),
        method: 'POST',
        headers: {'sec-fetch-site': 'cross-site'},
        body: [1],
      );
      expect(crossSite.status, 403);
      final ok = await webview.request(
        at('/post'),
        method: 'POST',
        headers: {'origin': 'http://localhost:${session.servedPort}'},
        body: [1],
      );
      expect(ok.status, 200);
      expect(ok.headers['set-cookie'], ['sid=1; Path=/']);
      for (final name in [
        'x-frame-options',
        'x-content-type-options',
        'x-xss-protection',
        'server',
      ]) {
        expect(ok.headers[name], isNull, reason: name);
      }
    });
  });

  test('a head over the limits is answered 431 here; nothing goes to the '
      'computer (RF 1)', () async {
    await openSamePort();
    await webview.enter(events.whereType<ToolLoad>().single.url);
    final before = pipe.batches.length;
    final big = await webview.request(
      at('/'),
      headers: {'x-big': 'x' * (kToolMaxHeadBytes + 1)},
    );
    expect(big.status, 431);
    expect(pipe.batches.length, before);
    expect(tool.hits, hasLength(1), reason: 'only the entry page');
  });

  test('the tool\'s port is taken on the phone: another port, and the '
      'desktop rewrites Host and Origin (E3)', () async {
    opened = true;
    tool = await TestTool.start(); // on 127.0.0.1: the phone cannot have it
    proxy = ToolProxy();
    proxy.serve(catalogOf([tool.entry()]));
    pipe = ToolPipe(proxy);
    session = ToolSession(
      tool: _id,
      port: tool.port,
      path: '/',
      link: pipe.tools,
    );
    events = [];
    session.events.listen(events.add);
    webview = Webview();
    session.start();
    await until(() => events.whereType<ToolLoad>().isNotEmpty);
    expect(session.alias, isNotNull);
    expect(session.alias, isNot(tool.port));
    await webview.enter(events.whereType<ToolLoad>().single.url);
    final page = await webview.request(
      at('/form'),
      method: 'POST',
      headers: {'origin': 'http://localhost:${session.alias}'},
      body: utf8.encode('a=1'),
    );
    expect(page.status, 200);
    final hit = tool.hits.last;
    expect(hit.headers['host'], ['localhost:${tool.port}']);
    expect(hit.headers['origin'], ['http://localhost:${tool.port}']);
  });

  test('a WebSocket through the gate: upgrade, echo, close', () async {
    await openSamePort();
    await webview.enter(events.whereType<ToolLoad>().single.url);
    final ws = await webview.socket(
      Uri.parse('ws://localhost:${session.servedPort}/ws'),
      protocols: ['vite-hmr'],
      origin: 'http://localhost:${session.servedPort}',
    );
    expect(ws.protocol, 'vite-hmr');
    final got = <Object?>[];
    ws.listen(got.add);
    ws.add('ping');
    await until(() => got.isNotEmpty);
    expect(got.single, 'ping');
    ws.add('close:4001');
    await ws.done;
    expect(ws.closeCode, 4001);
  });

  test('a WebSocket without the cookie: 403', () async {
    await openSamePort();
    await expectLater(
      webview.socket(Uri.parse('ws://localhost:${session.servedPort}/ws')),
      throwsA(isA<WebSocketException>()),
    );
    expect(tool.hits, isEmpty);
  });

  group('life of the page (E13)', () {
    test(
      'paused: nothing is served; resumed: served again and loaded',
      () async {
        await openSamePort();
        final port = session.servedPort!;
        await session.pause();
        expect(session.phase, ToolPhase.paused);
        await expectLater(
          webview.request(at('/', port: port)),
          throwsA(isA<SocketException>()),
        );
        session.resume();
        await until(() => events.whereType<ToolLoad>().length == 2);
        expect(session.phase, ToolPhase.ready);
        final page = await webview.enter(events.whereType<ToolLoad>().last.url);
        expect(page.status, 200);
      },
    );

    test('the channel goes: reconnecting, requests get 503; back: ready and '
        'reloaded', () async {
      await openSamePort();
      await webview.enter(events.whereType<ToolLoad>().single.url);
      pipe.drop();
      expect(session.phase, ToolPhase.reconnecting);
      expect((await webview.request(at('/'))).status, 503);
      pipe.restore();
      await until(() => session.phase == ToolPhase.ready);
      expect(events.last, isA<ToolReload>());
      expect((await webview.request(at('/'))).status, 200);
    });

    test('leaving the page tells the computer and ends its streams', () async {
      final held = <HttpResponse>[];
      await openSamePort(
        routes: {
          '/events': (request) async {
            request.response
              ..bufferOutput = false
              ..write('data: 1\n\n');
            await request.response.flush();
            held.add(request.response);
          },
        },
      );
      await webview.enter(events.whereType<ToolLoad>().single.url);
      final request = webview.request(at('/events'));
      await until(() => held.isNotEmpty);
      // Listened to before the page is left: it may fail meanwhile.
      final cut = expectLater(request, throwsA(anything));
      await session.close();
      await cut;
      expect(session.phase, ToolPhase.closed);
    });
  });

  group('the computer changes things (E9, E16)', () {
    test('the flag turned off: disabled within a second, even with no '
        'request (success criterion 5)', () async {
      await openSamePort();
      final clock = Stopwatch()..start();
      proxy.serve(catalogOf([], off: [_id]));
      await until(() => session.phase == ToolPhase.disabled);
      expect(clock.elapsed, lessThan(const Duration(seconds: 1)));
    });

    test('the tool deleted: gone', () async {
      await openSamePort();
      proxy.serve(catalogOf([]));
      await until(() => session.phase == ToolPhase.gone);
    });

    test('nothing runs on the port: refused, tried again, ready when it is '
        'back', () async {
      await openSamePort(retry: const [Duration(milliseconds: 100)]);
      await webview.enter(events.whereType<ToolLoad>().single.url);
      final port = tool.port;
      await tool.server.close(force: true);
      final failed = await webview.request(at('/'));
      expect(failed.status, 502);
      expect(failed.text, contains('localhost:$port'));
      await until(() => session.phase == ToolPhase.refused);
      tool = await TestTool.samePort(port: port);
      await until(() => session.phase == ToolPhase.ready);
      expect(events.last, isA<ToolReload>());
    });
  });

  test('the other tools of the workspace on their own ports (E4); one '
      'turned off answers 502 and is told', () async {
    late TestTool api;
    await openSamePort(catalog: (tool) => [tool.entry()]);
    api = await TestTool.samePort();
    addTearDown(api.close);
    await session.close();
    proxy.serve(
      catalogOf([tool.entry(), api.entry(id: 'api0000001', name: 'API')]),
    );
    events.clear();
    session = ToolSession(
      tool: _id,
      port: tool.port,
      path: '/',
      link: pipe.tools,
    );
    session.events.listen(events.add);
    session.start();
    await until(() => events.whereType<ToolLoad>().isNotEmpty);
    expect(session.origins, {
      'http://localhost:${tool.port}',
      'http://localhost:${api.port}',
    });
    await webview.enter(events.whereType<ToolLoad>().single.url);
    final fromApi = await webview.request(at('/v1', port: api.port));
    expect(fromApi.status, 200);
    expect(api.hits.single.headers['host'], ['localhost:${api.port}']);
    // A CORS preflight carries no cookie: let through for a served origin.
    final preflight = await webview.request(
      at('/v1', port: api.port),
      method: 'OPTIONS',
      withCookies: false,
      headers: {
        'origin': 'http://localhost:${tool.port}',
        'access-control-request-method': 'POST',
      },
    );
    expect(preflight.status, 200);
    proxy.serve(catalogOf([tool.entry()], off: ['api0000001']));
    final off = await webview.request(at('/v1', port: api.port));
    expect(off.status, 502);
    await until(() => events.whereType<ToolSiblingOff>().isNotEmpty);
    expect(events.whereType<ToolSiblingOff>().single.port, api.port);
  });

  test('a download is told; requests are counted (E12, E20)', () async {
    await openSamePort(
      routes: {
        '/file': (request) async {
          request.response.headers.set(
            'content-disposition',
            'attachment; filename="a.csv"',
          );
          request.response.write('a,b');
          await request.response.close();
        },
      },
    );
    await webview.enter(events.whereType<ToolLoad>().single.url);
    session.resetRequests();
    await webview.request(at('/file'));
    await webview.request(at('/'));
    expect(session.requests, 2);
    expect(events.whereType<ToolDownloadBlocked>(), hasLength(1));
  });

  test('toString never shows a URL (E18)', () async {
    await openSamePort();
    expect(session.toString(), 'ToolSession(…)');
    expect(events.whereType<ToolLoad>().single.toString(), 'ToolLoad(…)');
    const info = ToolInfo(
      id: _id,
      name: 'Bảng việc',
      ws: 'shop-web',
      port: 1,
      path: '/secret',
      group: 'g',
    );
    expect(info.toString(), 'ToolInfo(…)');
    expect(const ToolListing(tools: [info]).toString(), 'ToolListing(…)');
    expect(
      const ToolServing(id: _id, port: 1, path: '/secret').toString(),
      'ToolServing(…)',
    );
  });

  /// Top-level ruling (CSP): the policy keeps a page's requests on the ports
  /// this phone serves, so the gate cookie (cookies ignore ports) never
  /// reaches another app listening on a localhost port (RF 5).
  group('the page\'s Content-Security-Policy (CSP ruling)', () {
    test('the policy: every served port ascending, http and ws; deduplicated; '
        'never upgrade-insecure-requests', () {
      expect(
        toolContentSecurityPolicy([8000, 5173]),
        "default-src 'self' http://localhost:5173 ws://localhost:5173 "
        'http://localhost:8000 ws://localhost:8000 https: wss: data: blob: '
        "'unsafe-inline' 'unsafe-eval'; form-action 'self' "
        'http://localhost:5173 http://localhost:8000 https:',
      );
      expect(
        toolContentSecurityPolicy([5173, 8000, 5173]),
        toolContentSecurityPolicy([8000, 5173]),
      );
      expect(
        toolContentSecurityPolicy(const []),
        "default-src 'self' https: wss: data: blob: 'unsafe-inline' "
        "'unsafe-eval'; form-action 'self' https:",
      );
      expect(
        toolContentSecurityPolicy([8000, 5173]),
        isNot(contains('upgrade-insecure-requests')),
      );
    });

    test('the gate\'s own answers carry exactly one: 403 without the cookie, '
        'the entry\'s 303, 403 for another Host, 404 under /__shellx/, '
        '431', () async {
      await openSamePort();
      final policy = toolContentSecurityPolicy([session.servedPort!]);
      final noCookie = await webview.request(at('/'));
      expect(noCookie.status, 403);
      expect(noCookie.headers['content-security-policy'], [policy]);
      final entry = await webview.request(
        events.whereType<ToolLoad>().single.url,
      );
      expect(entry.status, 303);
      expect(entry.headers['content-security-policy'], [policy]);
      final rebinding = await webview.request(
        at('/'),
        headers: {'host': 'evil.com:${session.servedPort}'},
      );
      expect(rebinding.status, 403);
      expect(rebinding.headers['content-security-policy'], [policy]);
      final reserved = await webview.request(at('/__shellx/other'));
      expect(reserved.status, 404);
      expect(reserved.headers['content-security-policy'], [policy]);
      final big = await webview.request(
        at('/'),
        headers: {'x-big': 'x' * (kToolMaxHeadBytes + 1)},
      );
      expect(big.status, 431);
      expect(big.headers['content-security-policy'], [policy]);
    });

    test('a forwarded answer: ShellX\'s policy once, and the tool\'s own '
        'beside it, unchanged, never merged', () async {
      const own = "default-src 'none'; img-src 'self'";
      await openSamePort(
        routes: {
          '/strict': (request) async {
            request.response
              ..headers.set('content-security-policy', own)
              ..write('strict');
            await request.response.close();
          },
        },
      );
      final policy = toolContentSecurityPolicy([session.servedPort!]);
      final page = await webview.enter(events.whereType<ToolLoad>().single.url);
      expect(page.status, 200);
      expect(page.headers['content-security-policy'], [policy]);
      final strict = await webview.request(at('/strict'));
      expect(strict.status, 200);
      expect(strict.text, 'strict');
      expect(strict.headers['content-security-policy'], [policy, own]);
    });

    test('a WebSocket\'s 101 and an upgrade the tool refuses carry exactly '
        'one', () async {
      await openSamePort();
      final port = session.servedPort!;
      final policy = toolContentSecurityPolicy([port]);
      await webview.enter(events.whereType<ToolLoad>().single.url);
      List<String> upgrade(String path) =>
          _upgrade(port, path, webview.cookieHeader);
      final opened = await _rawHead(port, upgrade('/ws'));
      expect(opened.first, startsWith('HTTP/1.1 101'));
      expect(_policies(opened), [policy]);
      // RFC 6455 §1.3's example key and accept.
      expect(
        opened,
        contains('sec-websocket-accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo='),
      );
      final refused = await _rawHead(port, upgrade('/page'));
      expect(refused.first, startsWith('HTTP/1.1 200'));
      expect(_policies(refused), [policy]);
    });

    test('an answer the phone gives after a stream started (a refused port: '
        '502) carries exactly one', () async {
      await openSamePort(retry: const [Duration(seconds: 30)]);
      final policy = toolContentSecurityPolicy([session.servedPort!]);
      await webview.enter(events.whereType<ToolLoad>().single.url);
      await tool.server.close(force: true);
      final failed = await webview.request(at('/'));
      expect(failed.status, 502);
      expect(failed.headers['content-security-policy'], [policy]);
    });

    test('alias mode (E3): the policy names the alias P′, never the tool\'s '
        'port P', () async {
      opened = true;
      tool = await TestTool.start(); // on 127.0.0.1: the phone cannot have it
      proxy = ToolProxy();
      proxy.serve(catalogOf([tool.entry()]));
      pipe = ToolPipe(proxy);
      session = ToolSession(
        tool: _id,
        port: tool.port,
        path: '/',
        link: pipe.tools,
      );
      events = [];
      session.events.listen(events.add);
      webview = Webview();
      session.start();
      await until(() => events.whereType<ToolLoad>().isNotEmpty);
      final alias = session.alias!;
      final expected = toolContentSecurityPolicy([alias]);
      final entry = await webview.request(
        events.whereType<ToolLoad>().single.url,
      );
      expect(entry.headers['content-security-policy'], [expected]);
      final page = await webview.request(at('/'));
      expect(page.status, 200);
      expect(page.headers['content-security-policy'], [expected]);
      final sources = expected.split(RegExp('[ ;]+'));
      expect(
        sources,
        containsAll(['http://localhost:$alias', 'ws://localhost:$alias']),
      );
      expect(sources, isNot(contains('http://localhost:${tool.port}')));
      expect(sources, isNot(contains('ws://localhost:${tool.port}')));
    });

    test('with another tool of the workspace served (E4): both ports, '
        'ascending', () async {
      final api = await TestTool.samePort();
      addTearDown(api.close);
      await openSamePort(
        catalog: (tool) => [
          tool.entry(),
          api.entry(id: 'api0000001', name: 'API'),
        ],
      );
      expect(session.origins, hasLength(2));
      final ports = [tool.port, api.port]..sort();
      final lo = ports.first;
      final hi = ports.last;
      final policy =
          "default-src 'self' http://localhost:$lo ws://localhost:$lo "
          'http://localhost:$hi ws://localhost:$hi https: wss: data: blob: '
          "'unsafe-inline' 'unsafe-eval'; form-action 'self' "
          'http://localhost:$lo http://localhost:$hi https:';
      final page = await webview.enter(events.whereType<ToolLoad>().single.url);
      expect(page.headers['content-security-policy'], [policy]);
      final fromApi = await webview.request(at('/v1', port: api.port));
      expect(fromApi.status, 200);
      expect(fromApi.headers['content-security-policy'], [policy]);
    });
  });

  /// Controller ruling R-C2-2: an answer the phone gives once a stream has
  /// read the request must still be sent and closed (E10, E16).
  group('the phone\'s answers once a stream started', () {
    test('the computer ends a request before its response: the webview gets '
        'the answer at once, with one ShellX policy', () async {
      final (:page, :view, desktop: _) = await openScripted();
      final policy = toolContentSecurityPolicy([page.servedPort!]);
      const statuses = {
        ToolCode.busy: 503,
        ToolCode.timeout: 504,
        ToolCode.badRequest: 400,
        ToolCode.aborted: 502,
        'a_newer_word': 502,
        ToolCode.tooLarge: 502,
        ToolCode.refused: 502,
        ToolCode.disabled: 502,
        ToolCode.gone: 502,
        ToolCode.unavailable: 503,
        ToolCode.desktopClosed: 503,
      };
      for (final MapEntry(key: code, value: status) in statuses.entries) {
        final answer = await view
            .request(Uri.parse('http://localhost:${page.servedPort}/end/$code'))
            .timeout(const Duration(seconds: 2));
        expect(answer.status, status, reason: code);
        expect(answer.headers['content-security-policy'], [
          policy,
        ], reason: code);
      }
    });

    test('an answer the phone gives finishes its response: the next request '
        'on the same connection is served', () async {
      final (:page, :view, desktop: _) = await openScripted();
      final port = page.servedPort!;
      final text = const ToolHostTexts().refused(page.port);
      final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
      addTearDown(socket.destroy);
      final received = StringBuffer();
      socket.listen(
        (bytes) => received.write(String.fromCharCodes(bytes)),
        onError: (Object _) {},
      );
      void ask() => socket.write(
        'GET /end/refused HTTP/1.1\r\nhost: localhost:$port\r\n'
        'cookie: ${view.cookieHeader}\r\n\r\n',
      );
      int answers() => 'HTTP/1.1 502'.allMatches('$received').length;
      ask();
      await until(() => answers() == 1 && '$received'.endsWith(text));
      ask();
      await until(
        () => answers() == 2 && '$received'.endsWith(text),
        timeout: const Duration(seconds: 2),
      );
    });

    test('the channel goes while a request waits for its response: 502 at '
        'once (R18)', () async {
      final held = <HttpResponse>[];
      await openSamePort(
        routes: {'/slow': (request) async => held.add(request.response)},
      );
      await webview.enter(events.whereType<ToolLoad>().single.url);
      final policy = toolContentSecurityPolicy([session.servedPort!]);
      final waiting = webview.request(at('/slow'));
      await until(() => held.isNotEmpty);
      pipe.drop();
      final answer = await waiting.timeout(const Duration(seconds: 2));
      expect(answer.status, 502);
      expect(answer.headers['content-security-policy'], [policy]);
    });

    test('the tool takes longer than the computer waits for a head: 504 '
        '(E10)', () async {
      final held = <HttpResponse>[];
      await openSamePort(
        routes: {'/slow': (request) async => held.add(request.response)},
        headTimeout: const Duration(milliseconds: 200),
      );
      await webview.enter(events.whereType<ToolLoad>().single.url);
      final policy = toolContentSecurityPolicy([session.servedPort!]);
      final answer = await webview
          .request(at('/slow'))
          .timeout(const Duration(seconds: 3));
      expect(answer.status, 504);
      expect(answer.headers['content-security-policy'], [policy]);
    });
  });

  /// Controller ruling R-C2-3: every end of a stream stops its request-body
  /// outlet; what is left of the body is read and dropped, so a webview
  /// still sending finishes and takes the answer.
  group('an upload the stream no longer sends', () {
    final upload = Uint8List(2 * 1024 * 1024);

    test('the computer ends it before a response, or answers a status no '
        'response has: the answer reaches the webview', () async {
      final (:page, :view, desktop: _) = await openScripted();
      const paths = {'/end/busy': 503, '/end/refused': 502, '/bad-status': 502};
      for (final MapEntry(key: path, value: status) in paths.entries) {
        final answer = await view
            .request(
              Uri.parse('http://localhost:${page.servedPort}$path'),
              method: 'POST',
              body: upload,
            )
            .timeout(const Duration(seconds: 5));
        expect(answer.status, status, reason: path);
      }
    });

    test('the tool answers in full while the page still uploads: the '
        'response arrives whole', () async {
      final (:page, :view, desktop: _) = await openScripted();
      final answer = await view
          .request(
            Uri.parse('http://localhost:${page.servedPort}/early'),
            method: 'POST',
            body: upload,
          )
          .timeout(const Duration(seconds: 5));
      expect(answer.status, 200);
      expect(answer.text, 'early');
    });

    test('the channel goes during an upload: 502', () async {
      final (:page, :view, :desktop) = await openScripted();
      final waiting = view
          .request(
            Uri.parse('http://localhost:${page.servedPort}/hold'),
            method: 'POST',
            body: upload,
          )
          .timeout(const Duration(seconds: 5));
      await until(() => desktop.requests.any((r) => r.target == '/hold'));
      desktop.tools.channelLost();
      expect((await waiting).status, 502);
    });
  });

  /// Found in review: the gate reads some headers as one value (dart:io's
  /// `HttpHeaders.value` throws on a repeated one, which left the request
  /// unanswered), and some answers of the computer cannot be passed on.
  group('what the phone cannot pass on', () {
    test('a header the gate reads once, given twice: 400 at once, with one '
        'ShellX policy, and nothing reaches the tool (RF 5)', () async {
      await openSamePort();
      final port = session.servedPort!;
      final policy = toolContentSecurityPolicy([port]);
      await webview.enter(events.whereType<ToolLoad>().single.url);
      tool.hits.clear();
      final host = 'host: localhost:$port';
      final origin = 'origin: http://localhost:$port';
      final cookie = 'cookie: ${webview.cookieHeader}';
      final requests = {
        'origin': ['GET / HTTP/1.1', host, origin, 'origin: http://evil.com'],
        'sec-fetch-site': [
          'POST / HTTP/1.1',
          host,
          cookie,
          'content-length: 0',
          'sec-fetch-site: same-origin',
          'sec-fetch-site: cross-site',
        ],
        'access-control-request-method': [
          'OPTIONS / HTTP/1.1',
          host,
          origin,
          'access-control-request-method: POST',
          'access-control-request-method: PUT',
        ],
        'sec-websocket-key': [
          ..._upgrade(port, '/ws', webview.cookieHeader),
          'sec-websocket-key: AQIDBAUGBwgJCgsMDQ4PEA==',
        ],
      };
      for (final MapEntry(key: name, value: lines) in requests.entries) {
        final head = await _rawHead(port, lines);
        expect(head.first, startsWith('HTTP/1.1 400'), reason: name);
        expect(_policies(head), [policy], reason: name);
      }
      expect(tool.hits, isEmpty);
    });

    test('an answer of the computer the phone cannot pass on (a status no '
        'response has, a protocol the page did not offer): the computer is '
        'told, the webview gets 502', () async {
      final (:page, :view, :desktop) = await openScripted();
      final port = page.servedPort!;
      final policy = toolContentSecurityPolicy([port]);
      final http = await view
          .request(Uri.parse('http://localhost:$port/bad-status'))
          .timeout(const Duration(seconds: 2));
      expect(http.status, 502);
      expect(http.headers['content-security-policy'], [policy]);
      for (final path in ['/bad-status', '/ws-protocol', '/ws-two-protocols']) {
        final head = await _rawHead(port, [
          ..._upgrade(port, path, view.cookieHeader),
          'sec-websocket-protocol: chat',
        ]);
        expect(head.first, startsWith('HTTP/1.1 502'), reason: path);
        expect(_policies(head), [policy], reason: path);
      }
      await until(() => desktop.ends.length == 4);
      expect(
        [for (final end in desktop.ends) (end.id, end.code)],
        [for (final request in desktop.requests) (request.id, 'aborted')],
      );
    });
  });

  /// Ruling I1: the webview tries `localhost` on ::1 first, so a port is
  /// served only when this phone holds it on every loopback address it has
  /// (an app holding [::1]:P would get the entry URL's nonce and every
  /// request carrying the gate cookie, RF 5).
  group('every loopback address, or not at all (I1)', () {
    test('another app holds the tool\'s port on [::1]: the page goes to an '
        'alias P′ held on 127.0.0.1 and [::1], and the phone keeps nothing '
        'on P', () async {
      opened = true;
      tool = await TestTool.samePort();
      final other = await ServerSocket.bind(
        InternetAddress.loopbackIPv6,
        tool.port,
        v6Only: true,
      );
      addTearDown(other.close);
      await openPage();
      final alias = session.alias;
      expect(alias, isNotNull, reason: 'P is not wholly the phone\'s');
      expect(alias, isNot(tool.port));
      for (final address in [
        InternetAddress.loopbackIPv4,
        InternetAddress.loopbackIPv6,
      ]) {
        final head = await _rawHead(alias!, [
          'GET / HTTP/1.1',
          'host: localhost:$alias',
        ], address: address);
        expect(head.first, startsWith('HTTP/1.1 403'), reason: address.address);
      }
      await expectLater(
        Socket.connect(InternetAddress.loopbackIPv4, tool.port),
        throwsA(isA<SocketException>()),
      );
      final page = await webview.enter(events.whereType<ToolLoad>().single.url);
      expect(page.status, 200);
      expect(tool.hits.single.headers['host'], ['localhost:${tool.port}']);
    });

    test('another app holds a sibling\'s port on [::1]: that tool is not '
        'served — not in the origins, not in the policy (E4)', () async {
      final api = await TestTool.samePort();
      addTearDown(api.close);
      final other = await ServerSocket.bind(
        InternetAddress.loopbackIPv6,
        api.port,
        v6Only: true,
      );
      addTearDown(other.close);
      await openSamePort(
        catalog: (tool) => [
          tool.entry(),
          api.entry(id: 'api0000001', name: 'API'),
        ],
      );
      expect(session.origins, {'http://localhost:${tool.port}'});
      final page = await webview.enter(events.whereType<ToolLoad>().single.url);
      expect(page.headers['content-security-policy'], [
        toolContentSecurityPolicy([tool.port]),
      ]);
      await expectLater(
        Socket.connect(InternetAddress.loopbackIPv4, api.port),
        throwsA(isA<SocketException>()),
      );
      expect(api.hits, isEmpty);
    });
  });

  /// Ruling I2: the WebSocket's way to the webview exists from the moment
  /// the 101 is accepted. What the computer sends with it, before the
  /// upgraded socket is ready, waits in order and goes out once it is:
  /// never dropped, acknowledged only once written (E7, E8, RF 3).
  group('what comes with the 101 (I2)', () {
    Future<WebSocket> connect(ToolSession page, Webview view, String path) {
      final port = page.servedPort!;
      return view
          .socket(
            Uri.parse('ws://localhost:$port$path'),
            origin: 'http://localhost:$port',
          )
          .timeout(const Duration(seconds: 5));
    }

    /// What [ws] hears until the webview sees it closed (its stream ends;
    /// dart:io's `done` is the sink's and waits for this side to write).
    Future<List<Object?>> heard(WebSocket ws) {
      final got = <Object?>[];
      final closed = Completer<List<Object?>>();
      ws.listen(
        got.add,
        onError: (Object _) {},
        onDone: () => closed.complete(got),
      );
      return closed.future.timeout(const Duration(seconds: 3));
    }

    test('a message in the same batch as the 101 reaches the webview, and '
        'is acknowledged once written', () async {
      final (:page, :view, :desktop) = await openScripted();
      final ws = await connect(page, view, '/ws-hello');
      final got = <Object?>[];
      ws.listen(got.add, onError: (Object _) {});
      await until(() => got.isNotEmpty, timeout: const Duration(seconds: 3));
      expect(got, ['hello']);
      await until(() => desktop.acked.isNotEmpty);
      final id = desktop.requests.last.id;
      expect(desktop.acked.single, [id, toolWsPieceCost(5)]);
      await ws.close();
    });

    test('a close in the same batch as the 101 reaches the webview with its '
        'code', () async {
      final (:page, :view, desktop: _) = await openScripted();
      final ws = await connect(page, view, '/ws-close');
      expect(await heard(ws), isEmpty);
      expect(ws.closeCode, 4000);
      expect(ws.closeReason, 'bye');
    });

    test('messages, then the close, all with the 101: in that order', () async {
      final (:page, :view, desktop: _) = await openScripted();
      final ws = await connect(page, view, '/ws-hello-bye');
      expect(await heard(ws), ['hello', 'again']);
      expect(ws.closeCode, 4001);
    });
  });
}
