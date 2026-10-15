import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import 'support/test_tool.dart';
import 'support/tool_pipe.dart';

const _id = 'k3f9za7q1m';

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

  /// The tool on [::1] only and the proxy reaching [::1] only, so the phone
  /// can hold 127.0.0.1 on the tool's own port (one machine plays both).
  Future<void> openSamePort({
    Map<String, Future<void> Function(HttpRequest)> routes = const {},
    List<Map<String, Object?>> Function(TestTool tool)? catalog,
    List<Duration> retry = kToolRetryDelays,
  }) async {
    tool = await TestTool.start(
      routes: routes,
      address: InternetAddress.loopbackIPv6,
    );
    proxy = ToolProxy(connect: ipv6Only);
    proxy.serve(catalogOf(catalog?.call(tool) ?? [tool.entry(host: '[::1]')]));
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

  Uri at(String path, {int? port}) =>
      Uri.parse('http://localhost:${port ?? session.servedPort}$path');

  tearDown(() async {
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
      await session.close();
      await expectLater(request, throwsA(anything));
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
      tool = await TestTool.start(
        address: InternetAddress.loopbackIPv6,
        port: port,
      );
      await until(() => session.phase == ToolPhase.ready);
      expect(events.last, isA<ToolReload>());
    });
  });

  test('the other tools of the workspace on their own ports (E4); one '
      'turned off answers 502 and is told', () async {
    late TestTool api;
    await openSamePort(catalog: (tool) => [tool.entry(host: '[::1]')]);
    api = await TestTool.start(address: InternetAddress.loopbackIPv6);
    addTearDown(api.close);
    await session.close();
    proxy.serve(
      catalogOf([
        tool.entry(host: '[::1]'),
        api.entry(id: 'api0000001', name: 'API', host: '[::1]'),
      ]),
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
    proxy.serve(catalogOf([tool.entry(host: '[::1]')], off: ['api0000001']));
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
}
