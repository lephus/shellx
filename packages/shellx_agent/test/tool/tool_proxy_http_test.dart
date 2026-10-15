import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/dart.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import '../support/tool_rig.dart';

const _id = 'k3f9za7q1m';

/// V2-4 E9, E10, §8: the desktop proxy against a real tool on loopback.
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

  group('a page', () {
    test('GET goes to the tool; head and body come back; Host is the '
        "phone's own when it names the tool's port (E2)", () async {
      await setUpWith();
      final id = phone.request(
        _id,
        target: '/src/main.ts?t=1',
        head: ['host', 'localhost:${tool.port}', 'accept', '*/*'],
      );
      final response = await phone.response(id);
      await phone.ended(id);
      expect(response.status, 200);
      expect(
        toolHeadValues(response.head, 'content-type').single,
        contains('text/html'),
      );
      expect(utf8.decode(phone.body(id)), '<h1>/src/main.ts</h1>');
      final hit = tool.hits.single;
      expect(hit.uri.toString(), '/src/main.ts?t=1');
      expect(hit.headers['host'], ['localhost:${tool.port}']);
      expect(hit.headers['accept'], ['*/*']);
      expect(hit.headers['user-agent'], isNull, reason: 'no Dart user agent');
    });

    test('a 3xx is not followed: the phone gets it as is (RF 4)', () async {
      await setUpWith(
        routes: {
          '/go': (request) async {
            request.response
              ..statusCode = 302
              ..headers.set('location', 'http://evil.com/');
            await request.response.close();
          },
        },
      );
      final id = phone.request(_id, target: '/go');
      final response = await phone.response(id);
      expect(response.status, 302);
      expect(toolHeadValues(response.head, 'location'), ['http://evil.com/']);
      await phone.ended(id);
      expect(tool.hits, hasLength(1));
    });

    test('a body is passed through untouched (no unpacking)', () async {
      final gzipped = gzip.encode(utf8.encode('x' * 10000));
      await setUpWith(
        routes: {
          '/z': (request) async {
            request.response.headers.set('content-encoding', 'gzip');
            request.response.add(gzipped);
            await request.response.close();
          },
        },
      );
      final id = phone.request(
        _id,
        target: '/z',
        head: ['accept-encoding', 'gzip, br'],
      );
      await phone.ended(id);
      expect(phone.body(id), gzipped);
      expect(tool.hits.single.headers['accept-encoding'], ['gzip, br']);
    });

    test(
      'a POST body streams to the tool; what it took is acknowledged',
      () async {
        final got = Completer<List<int>>();
        final answer = Completer<void>();
        await setUpWith(
          routes: {
            '/up': (request) async {
              got.complete(
                await request.fold<List<int>>([], (a, b) => a..addAll(b)),
              );
              await answer.future;
              await request.response.close();
            },
          },
        );
        final id = phone.request(
          _id,
          method: 'POST',
          target: '/up',
          head: ['content-type', 'application/json'],
          end: false,
        );
        final body = utf8.encode('{"title":"Bảng việc"}');
        phone.send(
          ToolData(id: id, data: Uint8List.sublistView(body, 0, 5), end: false),
        );
        phone.send(
          ToolData(id: id, data: Uint8List.sublistView(body, 5), end: true),
        );
        expect(await got.future, body);
        await until(() => phone.messages.whereType<ToolAck>().isNotEmpty);
        expect(phone.messages.whereType<ToolAck>().last.acks, [
          id,
          body.length,
        ]);
        answer.complete();
        await phone.ended(id);
      },
    );
  });

  group('only the tool, nothing else (E9, RF 4)', () {
    test('a target that is not origin form, a forbidden method, CRLF in a '
        'header: bad_request, nothing reaches the tool', () async {
      await setUpWith();
      final ids = [
        phone.request(_id, target: '@evil.com/'),
        phone.request(_id, target: 'http://evil.com/'),
        phone.request(_id, target: '//evil.com/x'),
        phone.request(_id, method: 'CONNECT', target: '/'),
        phone.request(_id, method: 'TRACE', target: '/'),
        phone.request(_id, head: ['x-a', 'b\r\nHost: evil.com']),
        phone.request(_id, head: ['bad name', 'v']),
      ];
      await pumpEventQueue();
      for (final id in ids) {
        expect(phone.endOf(id)?.code, 'bad_request', reason: 'stream $id');
      }
      expect(tool.hits, isEmpty);
    });

    test('a foreign Host is replaced with the tool\'s; hop-by-hop, '
        'forwarding headers and the gate cookie are dropped; cookies are '
        'joined', () async {
      await setUpWith();
      final id = phone.request(
        _id,
        head: [
          'host',
          'evil.com',
          'connection',
          'keep-alive, x-secret',
          'x-secret',
          '1',
          'x-forwarded-for',
          '10.0.0.1',
          'forwarded',
          'for=10.0.0.1',
          'via',
          '1.1 phone',
          'cookie',
          'sid=1; __shellx_${tool.port}=s3cr3t',
          'cookie',
          'theme=dark',
          'x-latin',
          'café',
        ],
      );
      await phone.ended(id);
      final headers = tool.hits.single.headers;
      expect(headers['host'], ['localhost:${tool.port}']);
      for (final name in [
        'x-secret',
        'x-forwarded-for',
        'forwarded',
        'via',
        'x-latin',
      ]) {
        expect(headers[name], isNull, reason: name);
      }
      expect(headers['cookie'], ['sid=1; theme=dark']);
    });

    test('http_proxy is ignored: the request never goes to a proxy', () async {
      await setUpWith();
      final trap = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var trapped = 0;
      trap.listen((r) {
        trapped++;
        r.response.close();
      });
      addTearDown(() => trap.close(force: true));
      await HttpOverrides.runZoned(() async {
        // The override works: a plain client in this zone goes to the trap.
        final plain = HttpClient();
        final r = await (await plain.get('localhost', tool.port, '/')).close();
        await r.drain<void>();
        plain.close();
        expect(trapped, 1);
        final id = phone.request(_id, target: '/through');
        await phone.ended(id);
      }, findProxyFromEnvironment: (_, _) => 'PROXY 127.0.0.1:${trap.port}');
      expect(trapped, 1, reason: 'the proxy went to the tool, not the trap');
      expect(tool.hits.map((h) => h.uri.path), contains('/through'));
    });

    test('a tool on ::1 only is reached; a name is never resolved', () async {
      await setUpWith();
      final six = await TestTool.start(address: InternetAddress.loopbackIPv6);
      addTearDown(six.close);
      proxy.serve(catalogOf([six.entry(host: '[::1]')]));
      final id = phone.request(_id, target: '/six');
      await phone.ended(id);
      expect(six.hits.single.headers['host'], ['[::1]:${six.port}']);
    });

    test('a tool not on the list: disabled when its flag is off, gone '
        'otherwise; never by URL', () async {
      await setUpWith();
      proxy.serve(catalogOf([tool.entry()], off: ['offtool111']));
      final a = phone.request('offtool111');
      final b = phone.request('unknown111');
      await pumpEventQueue();
      expect(phone.endOf(a)?.code, 'disabled');
      expect(phone.endOf(b)?.code, 'gone');
      expect(tool.hits, isEmpty);
    });

    test('nothing listens on the port: refused', () async {
      await setUpWith();
      final port = tool.port;
      await tool.server.close(force: true);
      final id = phone.request(_id);
      await phone.ended(id);
      expect(phone.endOf(id)?.code, 'refused');
      expect(port, greaterThan(0));
    });
  });

  group('the flag is checked at every stream (E9)', () {
    test('turning the flag off ends a stream that is open; removing the '
        'tool or changing its URL too', () async {
      final hold = <HttpResponse>[];
      await setUpWith(
        routes: {
          '/events': (request) async {
            request.response
              ..bufferOutput = false
              ..headers.contentType = ContentType('text', 'event-stream')
              ..write('data: 1\n\n');
            await request.response.flush();
            hold.add(request.response); // never closed: an endless stream
          },
        },
      );
      final a = phone.request(_id, target: '/events');
      await phone.response(a);
      proxy.serve(catalogOf([], off: [_id]));
      await phone.ended(a);
      expect(phone.endOf(a)?.code, 'disabled');
      final refused = phone.request(_id);
      await pumpEventQueue();
      expect(phone.endOf(refused)?.code, 'disabled', reason: 'checked again');

      proxy.serve(catalogOf([tool.entry()]));
      final b = phone.request(_id, target: '/events');
      await phone.response(b);
      proxy.serve(catalogOf([tool.entry(path: '/other')]));
      await phone.ended(b);
      expect(phone.endOf(b)?.code, 'gone', reason: 'its URL changed');

      final c = phone.request(_id, target: '/events');
      await phone.response(c);
      proxy.serve(catalogOf([]));
      await phone.ended(c);
      expect(phone.endOf(c)?.code, 'gone', reason: 'deleted');
    });
  });

  group('windows and pacing (E7, RF 2, RF 3)', () {
    test('50 MB arrive whole (SHA-256), ≤ 256 KiB unacknowledged, the tool '
        'paused, ≤ 150 frames and ≤ 8 MiB a second', () async {
      const size = 50 * 1000 * 1000;
      final sent = const DartSha256().newHashSink();
      await setUpWith(
        routes: {
          '/big': (request) async {
            request.response.contentLength = size;
            var seed = 1;
            for (var at = 0; at < size; at += 65536) {
              final chunk = Uint8List(at + 65536 > size ? size - at : 65536);
              for (var i = 0; i < chunk.length; i++) {
                seed = (seed * 1103515245 + 12345) & 0x7fffffff;
                chunk[i] = seed >> 16;
              }
              sent.add(chunk);
              request.response.add(chunk);
              await request.response.flush(); // honours back-pressure
            }
            await request.response.close();
          },
        },
      );
      phone.autoAck = false;
      final acking = Timer.periodic(
        const Duration(milliseconds: 20),
        (_) => phone.ackAll(),
      );
      addTearDown(acking.cancel);
      final id = phone.request(_id, target: '/big');
      await phone.ended(id);
      acking.cancel();
      final got = const DartSha256().newHashSink()..add(phone.body(id));
      sent.close();
      got.close();
      expect(phone.body(id).length, size);
      expect((await got.hash()).bytes, (await sent.hash()).bytes);
      expect(phone.maxUnacked[id], lessThanOrEqualTo(kToolStreamWindow));
      // Pacing over the whole transfer (a token bucket's burst on top).
      final seconds = phone.dataTimes.last.inMicroseconds / 1e6;
      expect(phone.dataTimes.length, lessThanOrEqualTo(16 + 150 * seconds));
      expect(size, lessThanOrEqualTo(1024 * 1024 + 8 * 1024 * 1024 * seconds));
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('limits (E10)', () {
    test('more than 32 HTTP streams: busy', () async {
      final waiting = <HttpRequest>[];
      await setUpWith(
        routes: {'/hang': (request) async => waiting.add(request)},
      );
      final ids = [
        for (var i = 0; i < 33; i++) phone.request(_id, target: '/hang'),
      ];
      await pumpEventQueue();
      expect(phone.endOf(ids.last)?.code, 'busy');
      expect(ids.take(32).where((id) => phone.endOf(id) != null), isEmpty);
      for (final request in waiting) {
        unawaited(request.response.close());
      }
    });

    test('opens beyond 120 at once: busy', () async {
      await setUpWith();
      for (var rid = 1; rid <= 121; rid++) {
        phone.send(ToolOpen(rid: rid, tool: 'unknown111'));
      }
      await pumpEventQueue();
      final opened = phone.messages.whereType<ToolOpened>().toList();
      expect(
        opened.where((o) => o.code == 'busy').length,
        greaterThanOrEqualTo(1),
      );
    });

    test('a request body past the limit: too_large', () async {
      await setUpWith(
        routes: {
          '/up': (request) async {
            await request.drain<void>();
            await request.response.close();
          },
        },
        withProxy: ToolProxy(maxRequestBody: 1000),
      );
      final id = phone.request(_id, method: 'POST', target: '/up', end: false);
      phone.send(ToolData(id: id, data: Uint8List(600), end: false));
      phone.send(ToolData(id: id, data: Uint8List(600), end: true));
      await phone.ended(id);
      expect(phone.endOf(id)?.code, 'too_large');
    });

    test(
      'a response head over 32 KiB: too_large (the phone shows 502)',
      () async {
        await setUpWith(
          routes: {
            '/fat': (request) async {
              request.response.headers.set(
                'x-big',
                'x' * (kToolMaxHeadBytes + 1),
              );
              await request.response.close();
            },
          },
        );
        final id = phone.request(_id, target: '/fat');
        await phone.ended(id);
        expect(phone.endOf(id)?.code, 'too_large');
      },
    );

    test('no response head within the limit: timeout', () async {
      await setUpWith(
        routes: {'/slow': (request) async {}},
        withProxy: ToolProxy(headTimeout: const Duration(milliseconds: 200)),
      );
      final id = phone.request(_id, target: '/slow');
      await phone.ended(id);
      expect(phone.endOf(id)?.code, 'timeout');
    });

    test('bytes in flight and no ack for the idle limit: aborted', () async {
      await setUpWith(
        routes: {
          '/drip': (request) async {
            request.response
              ..bufferOutput = false
              ..add(Uint8List(1000));
            await request.response.flush();
          },
        },
        withProxy: ToolProxy(idleTimeout: const Duration(milliseconds: 300)),
      );
      phone.autoAck = false;
      final id = phone.request(_id, target: '/drip');
      await phone.ended(id);
      expect(phone.endOf(id)?.code, 'aborted');
    });
  });

  group('alias mode (E3): the phone serves on another port', () {
    test('Host is the tool\'s; Origin and Referer of the phone\'s origin '
        'become the tool\'s; Location and ACAO of the tool\'s come back as '
        'the phone\'s; a tool cookie named __shellx_ is dropped', () async {
      await setUpWith(
        routes: {
          '/login': (request) async {
            request.response
              ..statusCode = 303
              ..headers.set(
                'location',
                'http://localhost:${tool.port}/home?x=1',
              )
              ..headers.set(
                'access-control-allow-origin',
                'http://localhost:${tool.port}',
              )
              ..headers.add('set-cookie', 'sid=1; Path=/')
              ..headers.add(
                'set-cookie',
                '__shellx_${tool.port}=stolen; Path=/',
              );
            await request.response.close();
          },
        },
      );
      const alias = 49152;
      final id = phone.request(
        _id,
        target: '/login',
        alias: alias,
        head: [
          'host',
          'localhost:$alias',
          'origin',
          'http://localhost:$alias',
          'referer',
          'http://localhost:$alias/form?a=1',
        ],
      );
      final response = await phone.response(id);
      await phone.ended(id);
      final headers = tool.hits.single.headers;
      expect(headers['host'], ['localhost:${tool.port}']);
      expect(headers['origin'], ['http://localhost:${tool.port}']);
      expect(headers['referer'], ['http://localhost:${tool.port}/form?a=1']);
      expect(toolHeadValues(response.head, 'location'), [
        'http://localhost:$alias/home?x=1',
      ]);
      expect(toolHeadValues(response.head, 'access-control-allow-origin'), [
        'http://localhost:$alias',
      ]);
      expect(toolHeadValues(response.head, 'set-cookie'), ['sid=1; Path=/']);
    });

    test('another origin is passed through untouched', () async {
      await setUpWith();
      final id = phone.request(
        _id,
        alias: 49152,
        head: [
          'origin',
          'http://other.example',
          'referer',
          'http://other.example/x',
        ],
      );
      await phone.ended(id);
      final headers = tool.hits.single.headers;
      expect(headers['origin'], ['http://other.example']);
      expect(headers['referer'], ['http://other.example/x']);
    });
  });

  group('the list (§4.2) and opening (E4)', () {
    test('only tools on the list; again whenever it changes; nothing '
        'before the window said', () async {
      tool = await TestTool.start();
      proxy = ToolProxy();
      phone = ToolPhone(proxy);
      final listings = <ToolListResult>[];
      phone.listings.listen(listings.add);
      phone.send(const ToolList());
      await pumpEventQueue();
      expect(listings.single.available, isFalse);
      proxy.serve(
        catalogOf([tool.entry(), tool.entry(id: 'api0000001', name: 'API')]),
      );
      proxy.serve(
        catalogOf([tool.entry(), tool.entry(id: 'api0000001', name: 'API')]),
      );
      await pumpEventQueue();
      expect(
        listings,
        hasLength(2),
        reason: 'an unchanged list is not sent again',
      );
      final json =
          jsonDecode(utf8.decode(listings.last.body)) as Map<String, Object?>;
      expect(json['v'], 1);
      expect((json['tools']! as List).map((t) => (t as Map)['name']), [
        'Bảng việc',
        'API',
      ]);
      expect((json['tools']! as List).first, {
        'id': _id,
        'name': 'Bảng việc',
        'ws': 'shop-web',
        'port': tool.port,
        'path': '/',
        'group': 'ws:a',
      });
    });

    test('open: refused while nothing listens; then the tool and its '
        'workspace\'s other tools, one per port', () async {
      await setUpWith();
      final api = await TestTool.start();
      addTearDown(api.close);
      proxy.serve(
        catalogOf([
          tool.entry(path: '/app'),
          api.entry(id: 'api0000001', name: 'API', path: '/v1'),
          api.entry(id: 'api0000002', name: 'API 2'),
          tool.entry(id: 'other00001', group: 'ws:b'),
        ]),
      );
      phone.send(const ToolOpen(rid: 1, tool: _id));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final opened = phone.messages.whereType<ToolOpened>().single;
      expect(opened.ok, isTrue);
      final json =
          jsonDecode(utf8.decode(opened.body!)) as Map<String, Object?>;
      expect(json['tools'], [
        {'id': _id, 'port': tool.port, 'path': '/app'},
        {'id': 'api0000001', 'port': api.port, 'path': '/v1'},
      ]);
      await api.server.close(force: true);
      phone.send(const ToolOpen(rid: 2, tool: 'api0000001'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(phone.messages.whereType<ToolOpened>().last.code, 'refused');
    });
  });

  test('a phone that goes, and the window that quits (E5, E17)', () async {
    final hold = <HttpResponse>[];
    await setUpWith(
      routes: {
        '/events': (request) async {
          request.response
            ..bufferOutput = false
            ..write('data: 1\n\n');
          await request.response.flush();
          hold.add(request.response);
        },
      },
    );
    final a = phone.request(_id, target: '/events');
    await phone.response(a);
    proxy.phoneGone(phone.mobileId);
    await pumpEventQueue();
    expect(
      phone.endOf(a),
      isNull,
      reason: 'a phone that is gone hears nothing',
    );
    final other = ToolPhone(
      proxy,
      mobileId: 'b0000000-0000-4000-8000-000000000003',
    );
    other.send(const ToolList());
    final b = other.request(_id, target: '/events');
    await other.response(b);
    proxy.close();
    await pumpEventQueue();
    expect(other.endOf(b)?.code, 'desktop_closed');
    expect(other.messages.whereType<ToolListResult>().last.available, isFalse);
    expect(proxy.serving, isFalse);
  });

  test('toString never shows a URL or a name (E18)', () async {
    await setUpWith(); // the tear-down closes what it starts
    final catalog = catalogOf([
      {
        'id': _id,
        'name': 'Bảng việc',
        'ws': 'w',
        'group': 'g',
        'url': 'http://localhost:1/secret',
      },
    ]);
    expect(catalog.toString(), 'ToolCatalog(…)');
    expect(catalog.tools.single.toString(), 'ServedTool(…)');
    expect(
      forwardRequestHead(const [
        'cookie',
        'session=secret',
      ], catalog.tools.single).toString(),
      'ToolForwardedHead(…)',
    );
  });
}
