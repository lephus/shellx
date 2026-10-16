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

/// Sends [lines] (one HTTP/1.1 request) on a raw socket to 127.0.0.1:[port]
/// and gives up on the answer once [after] bytes of it arrived: the socket is
/// dropped mid-body, as a webview drops a download when its page is left or
/// reloaded. The bytes read.
Future<int> _abandon(
  int port,
  List<String> lines, {
  int after = 64 * 1024,
}) async {
  final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
  var got = 0;
  final enough = Completer<void>();
  final subscription = socket.listen(
    (chunk) {
      got += chunk.length;
      if (got >= after && !enough.isCompleted) enough.complete();
    },
    onError: (Object _) {},
    onDone: () {
      if (!enough.isCompleted) enough.complete();
    },
  );
  socket.write('${lines.join('\r\n')}\r\n\r\n');
  await enough.future.timeout(const Duration(seconds: 5));
  socket.destroy();
  await subscription.cancel();
  return got;
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
/// in rare cases: it serves the page's tool on [port] (and the other tools
/// of its workspace, [siblings]) and answers each request at once with what
/// [script] gives. It takes no body (never acknowledges), so an upload stays
/// within the windows.
final class _Desktop {
  _Desktop(this.port, this.script, {this.siblings = const {}}) {
    tools = MachineTools(
      send: _fromPhone,
      connect: () async {},
      timeout: const Duration(seconds: 5),
    )..channelReady();
  }

  final int port;
  final List<ToolMessage> Function(ToolRequest request) script;

  /// The ports of the workspace's other tools (E4), by id.
  final Map<String, int> siblings;

  late final MachineTools tools;
  final requests = <ToolRequest>[];

  /// The streams the phone ended (`tool.end`), in order.
  final ends = <ToolEnd>[];

  /// What the phone acknowledged (`tool.ack`'s `[id, total, …]`), in order.
  final acked = <List<int>>[];

  /// The pages the phone left (`tool.close`), in order.
  final closes = <ToolClose>[];

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
                for (final MapEntry(key: id, value: at) in siblings.entries)
                  {'id': id, 'port': at, 'path': '/'},
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
          case final ToolClose close:
            closes.add(close);
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

/// S2: the phone's loopback interface as an injected list gives it.
final class _Loopback implements NetworkInterface {
  _Loopback(this.addresses);

  @override
  final List<InternetAddress> addresses;

  @override
  String get name => 'lo';

  @override
  int get index => 1;
}

/// S2: an interface list whose loopback holds [addresses].
ToolInterfaces _listing(List<InternetAddress> addresses) =>
    () async => [_Loopback(addresses)];

/// One bind the phone asked for.
typedef _Ask = ({InternetAddress address, int port, bool v6Only});

/// S2's injected binder: a real [HttpServer.bind], unless [refuse] says
/// another app holds that address and port (then a [SocketException], as a
/// held port gives). It keeps every bind asked, in order, and every port it
/// gave on 127.0.0.1. A bind [hold] names is made, then answered only once
/// [release] completes: a bind still under way ([holding] meanwhile).
final class _Binder {
  _Binder({this.refuse, this.hold});

  final bool Function(InternetAddress address, int port)? refuse;
  final bool Function(InternetAddress address, int port)? hold;
  final release = Completer<void>();
  var holding = false;
  final asked = <_Ask>[];
  final given = <int>[];

  Future<HttpServer> bind(
    InternetAddress address,
    int port, {
    required bool v6Only,
  }) async {
    asked.add((address: address, port: port, v6Only: v6Only));
    if (refuse?.call(address, port) ?? false) {
      throw const SocketException('held by another app');
    }
    final server = await HttpServer.bind(address, port, v6Only: v6Only);
    if (address == InternetAddress.loopbackIPv4) given.add(server.port);
    if (hold?.call(address, port) ?? false) {
      holding = true;
      await release.future;
    }
    return server;
  }
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
    Duration nonceLife = const Duration(seconds: 10),
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
      nonceLife: nonceLife,
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
    Duration nonceLife = const Duration(seconds: 10),
  }) async {
    opened = true;
    tool = await TestTool.samePort(routes: routes);
    await openPage(
      catalog: catalog,
      retry: retry,
      headTimeout: headTimeout,
      nonceLife: nonceLife,
    );
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

    test('without the cookie, with another Host, or from another app: 403, '
        'and nothing reaches the tool', () async {
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

    // Review I2: a page whose computer had no list (E5: the background
    // service runs alone) or whose tool was off comes back by itself when
    // the list changes (a window that connects pushes its list; turning 📱 on
    // changes it): served again, with a fresh entry.
    test('no list on the computer, then the list again: unavailable, then '
        'ready with a fresh entry (I2)', () async {
      await openSamePort();
      proxy.serve(null);
      await until(() => session.phase == ToolPhase.unavailable);
      proxy.serve(catalogOf([tool.entry()]));
      await until(
        () => session.phase == ToolPhase.ready,
        timeout: const Duration(seconds: 3),
      );
      final loads = events.whereType<ToolLoad>().toList();
      expect(loads, hasLength(2));
      expect(loads.last.url, isNot(loads.first.url), reason: 'a new nonce');
      final page = await webview.enter(loads.last.url);
      expect(page.status, 200);
    });

    test('the flag turned off, then on again: disabled, then ready with a '
        'fresh entry (I2)', () async {
      await openSamePort();
      proxy.serve(catalogOf([], off: [_id]));
      await until(() => session.phase == ToolPhase.disabled);
      proxy.serve(catalogOf([tool.entry()]));
      await until(
        () => session.phase == ToolPhase.ready,
        timeout: const Duration(seconds: 3),
      );
      final loads = events.whereType<ToolLoad>().toList();
      expect(loads, hasLength(2));
      expect(loads.last.url, isNot(loads.first.url), reason: 'a new nonce');
      final page = await webview.enter(loads.last.url);
      expect(page.status, 200);
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

  // Review I3: the computer answers `busy` (a 503) past E10's 120 stream
  // opens at once and 60 a second; the phone paces its own (100 at once, then
  // 50 a second), so a page's burst of modules waits instead of failing.
  test('a burst of 160 requests from one page: every answer arrives, none '
      'refused as busy (I3)', () async {
    const requests = 160;
    const parallel = 24; // under the phone's 32 HTTP streams (E10)
    // A reload of a page of modules: each answered 304 Not Modified. Without
    // a body no answer waits for the computer's frame budget (R9), so the
    // page asks as fast as the tunnel answers.
    await openSamePort(
      routes: {
        for (var i = 0; i < requests; i++)
          '/m/$i.js': (request) async {
            request.response.statusCode = HttpStatus.notModified;
            await request.response.close();
          },
      },
    );
    await webview.enter(events.whereType<ToolLoad>().single.url);
    final answers = <int, Page>{};
    var next = 0;
    Future<void> lane() async {
      while (next < requests) {
        final i = next++;
        answers[i] = await webview.request(at('/m/$i.js'));
      }
    }

    await Future.wait([for (var c = 0; c < parallel; c++) lane()]);
    final wrong = [
      for (var i = 0; i < requests; i++)
        if (answers[i]?.status != HttpStatus.notModified)
          '#$i: ${answers[i]?.status}',
    ];
    expect(wrong, isEmpty);
    expect(
      tool.hits.where((hit) => hit.uri.path.startsWith('/m/')),
      hasLength(requests),
    );
  });

  group('a request waiting its turn on the phone (I3)', () {
    /// [page]'s next request waits its turn: every token is taken and a
    /// second's worth of opens is queued ahead of it.
    void queueAhead(_Desktop desktop) {
      for (var i = 0; i < kToolPhoneOpenBurst + kToolPhoneOpensPerSecond; i++) {
        desktop.tools.acquireOpen(() {});
      }
    }

    test('the page paused: its tool.req never goes, the computer hears '
        'nothing of it, the webview is not left waiting', () async {
      final (:page, :view, :desktop) = await openScripted();
      queueAhead(desktop);
      final port = page.servedPort!;
      final waiting = view
          .request(Uri.parse('http://localhost:$port/hold'))
          .then<Object>((answer) => answer, onError: (Object e) => e);
      await until(() => page.requests == 1);
      await page.pause();
      await waiting.timeout(const Duration(seconds: 2));
      // The opens queued ahead are all granted by now.
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(desktop.requests.where((r) => r.target == '/hold'), isEmpty);
      expect(
        desktop.ends,
        isEmpty,
        reason:
            'no tool.end for a stream it '
            'never heard of',
      );
    });

    test('the channel goes: its tool.req never goes, the webview gets '
        '502', () async {
      final (:page, :view, :desktop) = await openScripted();
      queueAhead(desktop);
      final port = page.servedPort!;
      final waiting = view.request(Uri.parse('http://localhost:$port/hold'));
      await until(() => page.requests == 1);
      desktop.tools.channelLost();
      expect((await waiting.timeout(const Duration(seconds: 2))).status, 502);
      desktop.tools.channelReady();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(desktop.requests.where((r) => r.target == '/hold'), isEmpty);
    });
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
        'forms only to the served ports (S1); never '
        'upgrade-insecure-requests', () {
      final policy = toolContentSecurityPolicy([8000, 5173]);
      expect(
        policy,
        "default-src 'self' http://localhost:5173 ws://localhost:5173 "
        'http://localhost:8000 ws://localhost:8000 https: wss: data: blob: '
        "'unsafe-inline' 'unsafe-eval'; form-action 'self' "
        'http://localhost:5173 http://localhost:8000',
      );
      expect(
        policy.split('form-action').last,
        isNot(contains('https:')),
        reason: 'S1: a form never posts to a remote site',
      );
      expect(
        toolContentSecurityPolicy([5173, 8000, 5173]),
        toolContentSecurityPolicy([8000, 5173]),
      );
      expect(
        toolContentSecurityPolicy(const []),
        "default-src 'self' https: wss: data: blob: 'unsafe-inline' "
        "'unsafe-eval'; form-action 'self'",
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
          'http://localhost:$lo http://localhost:$hi';
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

  /// Review I1: a webview that gives up on a response mid-body (↻ during a
  /// load, a page left, an aborted fetch) has dart:io end the response
  /// quietly. The stream must still end toward the computer: its bytes not
  /// acknowledged would otherwise hold the phone's shared window (512 KiB)
  /// until the computer's 5-minute idle drop, and every larger response of
  /// the page would wait that long.
  group('a response the webview gives up on (I1)', () {
    const big = 8 * 1024 * 1024;
    const medium = 100 * 1024;

    /// The `/big` answers the tool is done with: the computer let go of the
    /// connection (its stream ended), or all of it was sent.
    var finished = 0;
    setUp(() => finished = 0);

    /// 8 MiB, as the socket takes it: the tool waits while the windows are
    /// full.
    Future<void> serveBig(HttpRequest request) async {
      final chunk = Uint8List(64 * 1024);
      try {
        request.response.contentLength = big;
        for (var at = 0; at < big; at += chunk.length) {
          request.response.add(chunk);
          await request.response.flush();
        }
        await request.response.close();
      } on Object {
        // The desktop dropped the connection.
      }
      finished++;
    }

    Future<void> serveMedium(HttpRequest request) async {
      request.response
        ..contentLength = medium
        ..add(Uint8List(medium));
      await request.response.close();
    }

    test('two downloads given up mid-body: each ends, and a 100 KiB '
        'resource after them arrives at once', () async {
      await openSamePort(routes: {'/big': serveBig, '/medium': serveMedium});
      await webview.enter(events.whereType<ToolLoad>().single.url);
      final port = session.servedPort!;
      for (var i = 0; i < 2; i++) {
        final got = await _abandon(port, [
          'GET /big HTTP/1.1',
          'host: localhost:$port',
          'cookie: ${webview.cookieHeader}',
        ]);
        expect(got, lessThan(big), reason: 'given up mid-body');
      }
      // Both streams ended toward the computer: it let go of the tool.
      await until(() => finished == 2, timeout: const Duration(seconds: 5));
      final page = await webview
          .request(at('/medium'))
          .timeout(const Duration(seconds: 5));
      expect(page.status, 200);
      expect(page.body.length, medium);
    });

    test('two upgrades the tool answers with a large body instead, given up '
        'mid-body: each ends, and a 100 KiB resource after them arrives at '
        'once', () async {
      await openSamePort(routes: {'/big': serveBig, '/medium': serveMedium});
      await webview.enter(events.whereType<ToolLoad>().single.url);
      final port = session.servedPort!;
      for (var i = 0; i < 2; i++) {
        final got = await _abandon(
          port,
          _upgrade(port, '/big', webview.cookieHeader),
        );
        expect(got, lessThan(big), reason: 'given up mid-body');
      }
      await until(() => finished == 2, timeout: const Duration(seconds: 5));
      final page = await webview
          .request(at('/medium'))
          .timeout(const Duration(seconds: 5));
      expect(page.status, 200);
      expect(page.body.length, medium);
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

  /// Top-level ruling S2: an app holding [::1]'s ports must never make the
  /// phone serve 127.0.0.1 alone (it would then get `localhost` requests,
  /// with the gate cookie, on [::1]). A port is served on 127.0.0.1 alone
  /// only when the phone's interface list shows no ::1; otherwise only when
  /// it is held on 127.0.0.1 and [::1]. The list and the binder are
  /// injected; the binder binds for real unless it refuses.
  group('127.0.0.1 alone only when the phone lists no ::1 (S2)', () {
    final v4 = InternetAddress.loopbackIPv4;
    final v6 = InternetAddress.loopbackIPv6;

    /// A page of the stand-in computer's tool on [port] (with [siblings]),
    /// its interface list and binds injected; started, closed after the
    /// test. Nothing is tried again within a test unless [retry] says so.
    Future<({ToolSession page, List<ToolLoad> loads})> start(
      _Binder binder, {
      required int port,
      required ToolInterfaces interfaces,
      Map<String, int> siblings = const {},
      List<Duration> retry = const [Duration(hours: 1)],
    }) async {
      final desktop = _Desktop(port, _script, siblings: siblings);
      final page = ToolSession(
        tool: _id,
        port: port,
        path: '/',
        link: desktop.tools,
        retryDelays: retry,
        interfaces: interfaces,
        bind: binder.bind,
      );
      addTearDown(page.close);
      final loads = <ToolLoad>[];
      page.events.listen((event) {
        if (event is ToolLoad) loads.add(event);
      });
      page.start();
      await until(() => page.phase != ToolPhase.opening);
      return (page: page, loads: loads);
    }

    /// Nothing is served, and never was on 127.0.0.1 alone: each pair asked
    /// 127.0.0.1 first, then [::1] (v6Only) on the port 127.0.0.1 gave, and
    /// was refused there — the tool's port [p], then an ephemeral one 16
    /// times (E3) — and nothing bound stays bound.
    Future<void> expectNoPort(ToolSession page, _Binder binder, int p) async {
      expect(page.servedPort, isNull, reason: 'never 127.0.0.1 alone');
      expect(page.origins, isEmpty);
      expect(page.phase, ToolPhase.noPort);
      expect(binder.given, hasLength(1 + 16));
      expect(binder.asked, [
        for (final (i, given) in binder.given.indexed) ...[
          (address: v4, port: i == 0 ? p : 0, v6Only: false),
          (address: v6, port: given, v6Only: true),
        ],
      ]);
      for (final port in binder.given) {
        await expectLater(
          Socket.connect(v4, port),
          throwsA(isA<SocketException>()),
          reason: 'nothing stays bound on 127.0.0.1:$port',
        );
      }
    }

    test('::1 listed and every bind of it refused: never 127.0.0.1 alone; an '
        'alias is tried, then nothing is served (no port)', () async {
      final p = await freeLoopbackPort();
      final binder = _Binder(refuse: (address, _) => address == v6);
      final (:page, :loads) = await start(
        binder,
        port: p,
        interfaces: _listing([v4, v6]),
      );
      await expectNoPort(page, binder, p);
      expect(loads, isEmpty);
    });

    test('an interface list that cannot be read counts as listing ::1 '
        '(R-C3-2): with its binds refused, nothing is served', () async {
      final p = await freeLoopbackPort();
      final binder = _Binder(refuse: (address, _) => address == v6);
      final (:page, :loads) = await start(
        binder,
        port: p,
        interfaces: () async => throw const SocketException('no list'),
      );
      await expectNoPort(page, binder, p);
      expect(loads, isEmpty);
    });

    test('no ::1 listed: 127.0.0.1 alone, on the tool\'s own port; [::1] is '
        'never asked for', () async {
      final p = await freeLoopbackPort();
      final binder = _Binder();
      final (:page, :loads) = await start(
        binder,
        port: p,
        interfaces: _listing([v4]),
      );
      expect(binder.asked, [(address: v4, port: p, v6Only: false)]);
      expect(page.phase, ToolPhase.ready);
      expect(page.servedPort, p);
      expect(page.alias, isNull);
      final view = Webview();
      addTearDown(view.close);
      expect((await view.request(loads.single.url)).status, 303);
    });

    test('::1 listed and both bind: the tool\'s own port on 127.0.0.1 and '
        '[::1] (same-port mode, E2), with E11\'s settings', () async {
      final p = await freeLoopbackPort();
      final binder = _Binder();
      final (:page, loads: _) = await start(
        binder,
        port: p,
        interfaces: _listing([v4, v6]),
      );
      expect(binder.asked, [
        (address: v4, port: p, v6Only: false),
        (address: v6, port: p, v6Only: true),
      ]);
      expect(page.phase, ToolPhase.ready);
      expect(page.servedPort, p);
      expect(page.alias, isNull);
      for (final address in [v4, v6]) {
        final head = await _rawHead(p, [
          'GET / HTTP/1.1',
          'host: localhost:$p',
        ], address: address);
        expect(head.first, startsWith('HTTP/1.1 403'), reason: address.address);
        final names = [
          for (final line in head.skip(1))
            line.substring(0, line.indexOf(':')).toLowerCase(),
        ];
        for (final name in ['x-frame-options', 'x-content-type-options']) {
          expect(names, isNot(contains(name)), reason: address.address);
        }
      }
    });

    test('::1 listed and the tool\'s port held there only: an alias P′ held '
        'on 127.0.0.1 and [::1], named by the policy (E3); nothing stays on '
        'P', () async {
      final p = await freeLoopbackPort();
      final binder = _Binder(
        refuse: (address, port) => address == v6 && port == p,
      );
      final (:page, :loads) = await start(
        binder,
        port: p,
        interfaces: _listing([v4, v6]),
      );
      expect(page.phase, ToolPhase.ready);
      final alias = page.alias!;
      expect(alias, isNot(p));
      expect(page.servedPort, alias);
      expect(binder.asked, [
        (address: v4, port: p, v6Only: false),
        (address: v6, port: p, v6Only: true),
        (address: v4, port: 0, v6Only: false),
        (address: v6, port: alias, v6Only: true),
      ]);
      for (final address in [v4, v6]) {
        final head = await _rawHead(alias, [
          'GET / HTTP/1.1',
          'host: localhost:$alias',
        ], address: address);
        expect(head.first, startsWith('HTTP/1.1 403'), reason: address.address);
      }
      final view = Webview();
      addTearDown(view.close);
      final entry = await view.request(loads.single.url);
      expect(entry.status, 303);
      expect(entry.headers['content-security-policy'], [
        toolContentSecurityPolicy([alias]),
      ]);
      await expectLater(
        Socket.connect(v4, p),
        throwsA(isA<SocketException>()),
        reason: 'nothing stays bound on 127.0.0.1:P',
      );
    });

    test('a sibling whose port is held on [::1] is not served, takes no '
        'alias, and nothing stays bound for it (E4, R5)', () async {
      final p = await freeLoopbackPort();
      var s = await freeLoopbackPort();
      while (s == p) {
        s = await freeLoopbackPort();
      }
      final binder = _Binder(
        refuse: (address, port) => address == v6 && port == s,
      );
      final (:page, loads: _) = await start(
        binder,
        port: p,
        siblings: {'api0000001': s},
        interfaces: _listing([v4, v6]),
      );
      expect(page.phase, ToolPhase.ready);
      expect(page.origins, {'http://localhost:$p'});
      expect(binder.asked, [
        (address: v4, port: p, v6Only: false),
        (address: v6, port: p, v6Only: true),
        (address: v4, port: s, v6Only: false),
        (address: v6, port: s, v6Only: true),
      ]);
      await expectLater(
        Socket.connect(v4, s),
        throwsA(isA<SocketException>()),
        reason: 'nothing stays bound on 127.0.0.1 for the sibling',
      );
    });

    test('no port is tried again by itself, with refused\'s growing delays, '
        'and served once both addresses bind (R-C3-1)', () async {
      final p = await freeLoopbackPort();
      var held = true;
      final binder = _Binder(refuse: (address, _) => held && address == v6);
      final (:page, :loads) = await start(
        binder,
        port: p,
        interfaces: _listing([v4, v6]),
        retry: const [Duration(milliseconds: 50), Duration(seconds: 1)],
      );
      int tries() => binder.asked
          .where((ask) => ask.address == v4 && ask.port == p)
          .length;
      expect(page.phase, ToolPhase.noPort);
      await until(() => tries() == 2); // after the first delay
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(tries(), 2, reason: 'the next try waits the second delay');
      held = false;
      await until(() => loads.isNotEmpty);
      expect(page.phase, ToolPhase.ready);
      expect(page.servedPort, p);
      expect(tries(), 3);
    });
  });

  /// Review M1 and M2 (ledger L359, L382, L472, L522): a pause or a close
  /// that comes while the page is being served. What a serve under way
  /// binds afterwards is closed at once; a close is final and tells the
  /// computer once; a resume during a pause still under way serves again
  /// once that pause is over.
  group('a pause or a close while the page is served (M1, M2)', () {
    final v4 = InternetAddress.loopbackIPv4;
    final v6 = InternetAddress.loopbackIPv6;

    /// The tool's port and a sibling's, both free on both addresses.
    Future<(int, int)> twoPorts() async {
      final p = await freeLoopbackPort();
      var s = await freeLoopbackPort();
      while (s == p) {
        s = await freeLoopbackPort();
      }
      return (p, s);
    }

    /// Nothing listens on [address]:[port] (a close under way has a second
    /// to finish).
    Future<void> refused(InternetAddress address, int port) async {
      final deadline = DateTime.now().add(const Duration(seconds: 2));
      while (true) {
        try {
          (await Socket.connect(address, port)).destroy();
        } on SocketException {
          return;
        }
        if (DateTime.now().isAfter(deadline)) {
          fail('${address.address}:$port is still bound');
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }

    /// A page of the stand-in computer's tool on [p], with a sibling on
    /// [s], whose [::1] bind of [s] is held by [binder]; started.
    ({ToolSession page, _Desktop desktop, List<ToolLoad> loads}) start(
      _Binder binder,
      int p,
      int s,
    ) {
      final desktop = _Desktop(p, _script, siblings: {'api0000001': s});
      final page = ToolSession(
        tool: _id,
        port: p,
        path: '/',
        link: desktop.tools,
        interfaces: _listing([v4, v6]),
        bind: binder.bind,
      );
      addTearDown(page.close);
      final loads = <ToolLoad>[];
      page.events.listen((event) {
        if (event is ToolLoad) loads.add(event);
      });
      page.start();
      return (page: page, desktop: desktop, loads: loads);
    }

    test('close() while a sibling binds: nothing stays bound, the page says '
        'closed from then on, and the computer is told', () async {
      final (p, s) = await twoPorts();
      final binder = _Binder(
        hold: (address, port) => address == v6 && port == s,
      );
      final (:page, :desktop, :loads) = start(binder, p, s);
      await until(() => binder.holding);
      final phases = <ToolPhase>[];
      page.changes.listen((_) => phases.add(page.phase));
      final closing = page.close();
      binder.release.complete();
      await closing;
      expect(phases, [ToolPhase.closed], reason: 'final from the call on');
      expect(loads, isEmpty, reason: 'no entry on the sibling\'s port');
      for (final port in [p, s]) {
        for (final address in [v4, v6]) {
          await refused(address, port);
        }
      }
      await until(() => desktop.closes.isNotEmpty);
    });

    test('a second close() sends no second tool.close', () async {
      final (:page, view: _, :desktop) = await openScripted();
      final first = page.close();
      final second = page.close();
      await first;
      await second;
      expect(page.phase, ToolPhase.closed);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(desktop.closes, hasLength(1));
    });

    test('pause() while a sibling binds, then resume(): served on the tool\'s '
        'port and the sibling\'s, nothing stale', () async {
      final (p, s) = await twoPorts();
      final binder = _Binder(
        hold: (address, port) => address == v6 && port == s,
      );
      final (:page, desktop: _, :loads) = start(binder, p, s);
      await until(() => binder.holding);
      final pausing = page.pause();
      binder.release.complete();
      await pausing;
      expect(page.phase, ToolPhase.paused);
      expect(
        page.servedPort,
        isNull,
        reason: 'nothing served in the background',
      );
      expect(loads, isEmpty);
      for (final address in [v4, v6]) {
        await refused(address, s);
      }
      page.resume();
      await until(() => loads.isNotEmpty);
      expect(page.phase, ToolPhase.ready);
      expect(page.servedPort, p);
      expect(page.origins, {'http://localhost:$p', 'http://localhost:$s'});
      expect(loads.single.url.port, p);
    });

    test('resume() while a pause is still under way: served again once it '
        'is over', () async {
      final (:page, :view, desktop: _) = await openScripted();
      final loads = <ToolLoad>[];
      page.events.listen((event) {
        if (event is ToolLoad) loads.add(event);
      });
      final pausing = page.pause();
      page.resume();
      await pausing;
      await until(() => loads.isNotEmpty, timeout: const Duration(seconds: 3));
      expect(page.phase, ToolPhase.ready);
      expect((await view.request(loads.single.url)).status, 303);
    });

    // pause() and close() say their phase at once; a check of the computer
    // still under way (here one that fails with the channel) never
    // overwrites it, and nothing is served in the background.
    for (final leave in ['pause', 'close']) {
      test('a check under way when the page is left by $leave(), the channel '
          'going with it: the page stays ${leave}d', () async {
        final (:page, view: _, :desktop) = await openScripted();
        // The list changes: the page asks the computer again.
        desktop.tools.handle(
          ToolListResult(
            available: true,
            body: Uint8List.fromList(utf8.encode('{"v":1,"tools":[]}')),
          ),
        );
        final leaving = leave == 'pause' ? page.pause() : page.close();
        desktop.tools.channelLost();
        await leaving;
        await Future<void>.delayed(const Duration(milliseconds: 100));
        final left = leave == 'pause' ? ToolPhase.paused : ToolPhase.closed;
        expect(page.phase, left);
        desktop.tools.channelReady(); // a channel again, still left
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(page.phase, left);
        expect(page.servedPort, isNull);
      });
    }

    test('pause(), resume(), pause() while the first pause is under way: the '
        'last word holds, nothing is served', () async {
      final (:page, view: _, desktop: _) = await openScripted();
      final loads = <ToolLoad>[];
      page.events.listen((event) {
        if (event is ToolLoad) loads.add(event);
      });
      final pausing = page.pause();
      page.resume();
      final again = page.pause();
      await pausing;
      await again;
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(page.phase, ToolPhase.paused);
      expect(page.servedPort, isNull);
      expect(loads, isEmpty);
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

  /// Ruling I3: a request the gate cannot read is still answered (with the
  /// policy, and its response closed), never left open.
  group('a request the gate cannot read (I3)', () {
    test('an entry whose query is not UTF-8, without the cookie: 403 at '
        'once', () async {
      await openSamePort();
      final port = session.servedPort!;
      final answer = await webview
          .request(Uri.parse('http://localhost:$port/__shellx/enter?n=%FF'))
          .timeout(const Duration(seconds: 2));
      expect(answer.status, 403);
      expect(answer.headers['content-security-policy'], [
        toolContentSecurityPolicy([port]),
      ]);
      expect(tool.hits, isEmpty);
    });
  });

  /// Review I4 (RF 5): the gate's secret, the entry's life and its two
  /// exemptions are each pinned: another app on the phone gets nothing
  /// through.
  group('the gate\'s own checks (I4, RF 5)', () {
    test('a gate cookie with the right name and a wrong value: 403, and '
        'nothing reaches the tool', () async {
      await openSamePort();
      await webview.enter(events.whereType<ToolLoad>().single.url);
      tool.hits.clear();
      final port = session.servedPort!;
      final name = toolGateCookieName(port);
      final right = webview.cookies[name]!;
      final wrong = '${right.substring(1)}${right[0] == 'A' ? 'B' : 'A'}';
      final answer = await webview.request(
        at('/'),
        withCookies: false,
        headers: {'cookie': '$name=$wrong'},
      );
      expect(answer.status, 403);
      expect(tool.hits, isEmpty);
    });

    test('an entry used after its life (zero here): 403, no gate cookie, '
        'and nothing reaches the tool', () async {
      await openSamePort(nonceLife: Duration.zero);
      final entry = await webview.request(
        events.whereType<ToolLoad>().single.url,
      );
      expect(entry.status, 403);
      expect(entry.headers['set-cookie'], isNull);
      expect((await webview.request(at('/'))).status, 403);
      expect(tool.hits, isEmpty);
    });

    test('a request without the cookie passes only as a CORS preflight of a '
        'served origin: OPTIONS from another origin, or without '
        'Access-Control-Request-Method, gets 403 and nothing reaches the '
        'tool (R6)', () async {
      await openSamePort();
      final port = session.servedPort!;
      final foreign = await webview.request(
        at('/'),
        method: 'OPTIONS',
        withCookies: false,
        headers: {
          'origin': 'http://evil.com',
          'access-control-request-method': 'POST',
        },
      );
      expect(foreign.status, 403);
      final notPreflight = await webview.request(
        at('/'),
        method: 'OPTIONS',
        withCookies: false,
        headers: {'origin': 'http://localhost:$port'},
      );
      expect(notPreflight.status, 403);
      expect(tool.hits, isEmpty);
    });

    test('a WebSocket upgrade with the cookie from another origin, or '
        'cross-site: 403, and nothing reaches the tool', () async {
      await openSamePort();
      await webview.enter(events.whereType<ToolLoad>().single.url);
      tool.hits.clear();
      final port = session.servedPort!;
      final upgrade = _upgrade(port, '/ws', webview.cookieHeader);
      final foreign = await _rawHead(port, [
        for (final line in upgrade)
          line.startsWith('origin:') ? 'origin: http://evil.com' : line,
      ]);
      expect(foreign.first, startsWith('HTTP/1.1 403'));
      final crossSite = await _rawHead(port, [
        ...upgrade,
        'sec-fetch-site: cross-site',
      ]);
      expect(crossSite.first, startsWith('HTTP/1.1 403'));
      expect(tool.hits, isEmpty);
    });
  });
}
