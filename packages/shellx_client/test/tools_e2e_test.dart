@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import 'support/fake_pty.dart';
import 'support/fake_relay.dart';
import 'support/harness.dart'
    show TestKeys, TabRecorder, agentId, phoneId, phonePairingId, userId;
import 'support/test_tool.dart';
import 'support/tool_pipe.dart' show Page, Webview, until;

const _id = 'k3f9za7q1m';

/// A relay socket that notes every frame its device puts on the wire, at the
/// socket and before the relay has any say: the fake relay refuses a frame
/// over [kMaxFrameBytes] before its `onData` hook, so only here is one seen.
final class _TappedSocket implements RelaySocket {
  _TappedSocket(this._inner, this._noted);

  final RelaySocket _inner;
  final void Function(int bytes) _noted;

  @override
  Stream<Object> get messages => _inner.messages;

  @override
  int? get closeCode => _inner.closeCode;

  @override
  void sendText(String text) {
    _noted(text.length);
    _inner.sendText(text);
  }

  @override
  void sendBytes(Uint8List bytes) {
    _noted(bytes.length);
    _inner.sendBytes(bytes);
  }

  @override
  Future<void> close([int? code, String? reason]) => _inner.close(code, reason);
}

/// Every frame one device put on its relay connection: when, and how big.
final class _Wire {
  final frames = <(Duration, int)>[];
  final _clock = Stopwatch()..start();

  RelaySocketConnector tap(RelaySocketConnector inner) =>
      (uri, headers) async => _TappedSocket(
        await inner(uri, headers),
        (bytes) => frames.add((_clock.elapsed, bytes)),
      );
}

/// The proxy as the session router sees it, noting when each tool message of
/// the phone reaches the computer and how big it is: the phone's messages as
/// messages, whatever frames carried them.
final class _CountedTools implements ToolEndpoint {
  _CountedTools(this._inner);

  final ToolEndpoint _inner;
  final arrivals = <(Duration, int)>[];
  final _clock = Stopwatch()..start();

  @override
  Stream<OutboundMessage> get outbound => _inner.outbound;

  @override
  bool get serving => _inner.serving;

  @override
  void handle(String mobileId, ToolMessage message) {
    arrivals.add((_clock.elapsed, encodeBatch([message]).length));
    _inner.handle(mobileId, message);
  }

  @override
  void phoneGone(String mobileId) => _inner.phoneGone(mobileId);

  @override
  void allPhonesGone() => _inner.allPhonesGone();
}

/// The largest of [frames], in bytes.
int _largest(Iterable<(Duration, int)> frames) =>
    frames.fold(0, (largest, f) => max(largest, f.$2));

/// The most [frames] that fall in any one second (counted from each frame).
int _busiestSecond(List<(Duration, int)> frames) {
  var busiest = 0;
  var end = 0;
  for (var i = 0; i < frames.length; i++) {
    while (end < frames.length &&
        frames[end].$1 < frames[i].$1 + const Duration(seconds: 1)) {
      end++;
    }
    busiest = max(busiest, end - i);
  }
  return busiest;
}

/// The first place [a] and [b] differ; -1 when they are the same bytes.
int _firstDifference(List<int> a, List<int> b) {
  if (a.length != b.length) return min(a.length, b.length);
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return i;
  }
  return -1;
}

/// A real agent with a tool proxy and a real phone over the fake relay and
/// the real encrypted channel, in real time. One machine plays both sides
/// (R21, same-port mode): the window lists the tool's port P, the phone holds
/// P on its loopback, and the proxy's connect (`connectTestTool`) takes P to
/// where the tool really listens.
final class _World {
  _World._();

  final relay = FakeRelay();
  late final ToolProxy proxy;

  /// [proxy] as the agent's router has it: counts the phone's tool messages.
  late final _CountedTools counted;
  late final FakePtyFactory ptys;
  late final AgentService agent;
  late final ClientService phone;
  late final MachineClient machine;

  /// What the agent and the phone put on the relay connection.
  final agentWire = _Wire();
  final phoneWire = _Wire();

  static Future<_World> start(TestKeys keys) async {
    final w = _World._();
    final agentDevice = w.relay.addDevice(
      id: agentId,
      userId: userId,
      kind: DeviceKind.agent,
    );
    final phoneDevice = w.relay.addDevice(
      id: phoneId,
      userId: userId,
      kind: DeviceKind.mobile,
    );
    final trusted = TrustedStore(InMemoryKeyValueStore());
    await trusted.add(
      TrustedDevice(
        mobileId: phoneId,
        publicKey: keys.phone.publicKey,
        name: 'Test Phone',
        pairedAt: DateTime.utc(2026),
        pairingId: phonePairingId,
      ),
    );
    w.relay.pairings[(agentId, phoneId)] = phonePairingId;
    w.ptys = FakePtyFactory();
    final ids = sessionIdAllocator(Random(7));
    w.proxy = ToolProxy(connect: connectTestTool);
    w.counted = _CountedTools(w.proxy);
    final router = SessionRouter(
      shells: SessionManager(
        ptyFactory: w.ptys,
        shellResolver: const FixedShellResolver(),
        homeDirectory: '/Users/test',
        baseEnvironment: const {},
        nextId: ids,
      ),
      desktop: DesktopSessionManager(nextId: ids),
      desktopSharing: () => true,
      tools: w.counted,
    );
    w.agent = AgentService(
      relay: RelayConnection(
        wsUri: w.relay.wsUri,
        token: () => agentDevice.token,
        connector: w.agentWire.tap(w.relay.connector),
      ),
      api: ShellxApi(baseUri: w.relay.baseUri, httpClient: w.relay.httpClient)
        ..token = agentDevice.token,
      deviceId: agentId,
      identity: keys.agent,
      trusted: trusted,
      sessions: router,
      pairing: PairingCodeManager(),
      appVersion: '1.0.0',
    );
    await w.agent.start();
    final pins = PinnedStore(InMemoryKeyValueStore(), userId: userId);
    await pins.add(
      PinnedMachine(
        agentId: agentId,
        publicKey: keys.agent.publicKey,
        pairedAt: DateTime.utc(2026),
      ),
    );
    w.phone = ClientService(
      relay: RelayConnection(
        wsUri: w.relay.wsUri,
        token: () => phoneDevice.token,
        connector: w.phoneWire.tap(w.relay.connector),
      ),
      api: ShellxApi(baseUri: w.relay.baseUri, httpClient: w.relay.httpClient)
        ..token = phoneDevice.token,
      deviceId: phoneId,
      userId: userId,
      identity: keys.phone,
      pinned: pins,
      appVersion: '1.0.0',
      deviceName: 'Test Phone',
      platform: DevicePlatform.ios,
    );
    await w.phone.start();
    await until(() => w.phone.isOnline(agentId));
    w.machine = w.phone.machine(agentId);
    await w.machine.connect();
    return w;
  }

  Future<void> stop() async {
    proxy.close();
    await phone.stop();
    await agent.stop();
  }
}

/// V2-4 §8, end to end (the V2-2 pattern: both sides in one test, over the
/// fake relay and the real encrypted channel).
void main() {
  late TestKeys keys;
  setUpAll(() async => keys = await TestKeys.generate());

  test('list → open → page → WebSocket echo → turned off', () async {
    final tool = await TestTool.samePort();
    final w = await _World.start(keys);
    final webview = Webview();
    addTearDown(() async {
      webview.close();
      await w.stop();
      await tool.close();
    });
    w.proxy.serve(catalogOf([tool.entry()]));

    // The phone sees the flag, then the list.
    await w.machine.listSessions(includeDesktop: true);
    expect(w.machine.tools.supported, isTrue);
    await w.machine.tools.watch();
    await until(() => w.machine.tools.listing?.tools.isNotEmpty ?? false);
    final info = w.machine.tools.listing!.tools.single;
    expect(
      (info.name, info.ws, info.port),
      ('Bảng việc', 'shop-web', tool.port),
    );

    // Open: the page through the tunnel.
    final session = ToolSession(
      tool: info.id,
      port: info.port,
      path: info.path,
      link: w.machine.tools,
    );
    addTearDown(session.close);
    final events = <ToolPageEvent>[];
    session.events.listen(events.add);
    session.start();
    await until(() => events.whereType<ToolLoad>().isNotEmpty);
    // Same-port mode (E2): the tool's own port, no alias.
    final served = session.servedPort!;
    expect(served, tool.port);
    expect(session.alias, isNull);
    final page = await webview.enter(events.whereType<ToolLoad>().single.url);
    expect(page.status, 200);
    expect(page.text, '<h1>/</h1>');

    // A WebSocket echo.
    final ws = await webview.socket(
      Uri.parse('ws://localhost:$served/ws'),
      protocols: ['vite-hmr'],
      origin: 'http://localhost:$served',
    );
    final got = <Object?>[];
    ws.listen(got.add);
    ws.add('xin chào');
    await until(() => got.isNotEmpty);
    expect(got.single, 'xin chào');

    // Turned off on the computer: the page says so within a second and the
    // WebSocket is gone; nothing reaches the tool any more.
    final clock = Stopwatch()..start();
    w.proxy.serve(catalogOf([], off: [_id]));
    await until(() => session.phase == ToolPhase.disabled);
    expect(clock.elapsed, lessThan(const Duration(seconds: 1)));
    // Nothing is served on the phone any more: the port it served is shut on
    // both loopback addresses (the webview tries ::1 first).
    for (final address in [
      InternetAddress.loopbackIPv4,
      InternetAddress.loopbackIPv6,
    ]) {
      await expectLater(
        Socket.connect(address, served),
        throwsA(isA<SocketException>()),
        reason: address.address,
      );
    }
    await ws.done.timeout(const Duration(seconds: 5));
    await session.close();
  });

  test('8 MB through the tunnel: whole (RF 3), no frame over 64 KiB (RF 1) '
      'and a terminal still answers while it runs (criterion 7); the frame '
      'rates only record headroom', () async {
    const size = 8 * 1000 * 1000;
    final body = Uint8List.fromList(
      List.generate(size, (i) => (i * 131 + (i >> 9)) & 0xFF),
    );
    final tool = await TestTool.samePort(
      routes: {
        '/big': (request) async {
          request.response.contentLength = size;
          for (var at = 0; at < size; at += 65536) {
            request.response.add(
              Uint8List.sublistView(body, at, min(at + 65536, size)),
            );
            await request.response.flush();
          }
          await request.response.close();
        },
      },
    );
    final w = await _World.start(keys);
    final webview = Webview();
    addTearDown(() async {
      webview.close();
      await w.stop();
      await tool.close();
    });
    w.proxy.serve(catalogOf([tool.entry()]));
    final tab = await w.machine.openSession(cols: 80, rows: 24);
    final terminal = TabRecorder(tab);
    final session = ToolSession(
      tool: _id,
      port: tool.port,
      path: '/',
      link: w.machine.tools,
    );
    addTearDown(session.close);
    final events = <ToolPageEvent>[];
    session.events.listen(events.add);
    session.start();
    await until(() => events.whereType<ToolLoad>().isNotEmpty);
    // Same-port mode (E2): the tool's own port, no alias.
    expect(session.servedPort, tool.port);
    expect(session.alias, isNull);
    await webview.enter(events.whereType<ToolLoad>().single.url);

    final agentStart = w.agentWire.frames.length;
    final phoneStart = w.phoneWire.frames.length;
    var downloaded = false;
    final downloading = webview
        .request(Uri.parse('http://localhost:${session.servedPort}/big'))
        .whenComplete(() => downloaded = true);
    // The download is under way (a few of its frames are on the wire).
    await until(() => w.agentWire.frames.length - agentStart >= 20);
    w.ptys.ptys.last.emit('still here\r\n');
    await until(() => terminal.text.contains('still here'));
    final answeredWhileDownloading = !downloaded;
    final page = await downloading;
    expect(
      answeredWhileDownloading,
      isTrue,
      reason: 'the terminal answered only after the download was over',
    );

    // Whole: every byte, in order.
    expect(page.status, 200);
    expect(page.body.length, size);
    expect(_firstDifference(page.body, body), -1);

    // Frames, as the relay would see them. RF 1 is pinned here: no frame over
    // 64 KiB, measured at the socket. The rates only record headroom, they
    // cannot catch a regression of a limiter: one stream moves about 3 MB/s
    // through this channel (about 60 frames a second), under the desktop's
    // 150 frames and 8 MiB a second and the phone's 100 frames a second, and
    // small messages go out at most once in 16 ms on both sides, so no
    // workload here comes near 250 a second, with the limiters or without.
    // RF 2 is pinned where it can fail: the pacer (Task 3,
    // shellx_core/test/protocol/tool_flow_test.dart), the 50 MB proxy test
    // (Task 5, shellx_agent/test/tool/tool_proxy_http_test.dart: at most 150
    // frames and 8 MiB a second), the phone's outbox (Task 8,
    // shellx_client/test/tools_test.dart: at most 100 frames a second) and,
    // from a page down to the wire, the last test of this file.
    final sent = w.agentWire.frames.skip(agentStart).toList();
    final sentByPhone = w.phoneWire.frames.skip(phoneStart).toList();
    // The tap saw the download: 8 MB cannot go in fewer.
    expect(sent.length, greaterThan(100));
    expect(sentByPhone, isNotEmpty);
    expect(_largest(sent), lessThanOrEqualTo(kMaxFrameBytes));
    expect(_largest(sentByPhone), lessThanOrEqualTo(kMaxFrameBytes));
    expect(
      _busiestSecond(sent),
      lessThan(250),
      reason: 'headroom: the relay closes the computer at 500 a second',
    );
    expect(
      _busiestSecond(sentByPhone),
      lessThan(250),
      reason: 'headroom: the relay closes the phone at 500 a second',
    );
    await session.close();
  });

  test('a page of 120 small requests: every answer right, none refused, and '
      'the phone puts no more than 110 frames in any second on the wire '
      '(E8, E10, RF 2)', () async {
    const requests = 120; // E10: 120 stream opens at once, then 60 a second
    const parallel = 24; // under the phone's 32 HTTP streams (E10)
    final tool = await TestTool.samePort(
      routes: {
        for (var i = 0; i < requests; i++)
          '/api/$i': (request) async {
            final sent = await utf8.decodeStream(request);
            request.response
              ..headers.contentType = ContentType.text
              ..write('${request.uri.path}:$sent');
            await request.response.close();
          },
      },
    );
    final w = await _World.start(keys);
    final webview = Webview();
    addTearDown(() async {
      webview.close();
      await w.stop();
      await tool.close();
    });
    w.proxy.serve(catalogOf([tool.entry()]));
    final session = ToolSession(
      tool: _id,
      port: tool.port,
      path: '/',
      link: w.machine.tools,
    );
    addTearDown(session.close);
    final events = <ToolPageEvent>[];
    session.events.listen(events.add);
    session.start();
    await until(() => events.whereType<ToolLoad>().isNotEmpty);
    // Same-port mode (E2): the tool's own port, no alias.
    final served = session.servedPort!;
    expect(served, tool.port);
    expect(session.alias, isNull);
    await webview.enter(events.whereType<ToolLoad>().single.url);

    // The page calls its API [requests] times, [parallel] at a time, each
    // with a small JSON body: the phone sends three tool messages for each
    // (tool.req, the body, its end) as fast as the computer answers.
    final phoneStart = w.phoneWire.frames.length;
    final messagesStart = w.counted.arrivals.length;
    final answers = <int, Page>{};
    var next = 0;
    Future<void> client() async {
      while (next < requests) {
        final i = next++;
        final body = utf8.encode('{"n":$i}');
        answers[i] = await webview.request(
          Uri.parse('http://localhost:$served/api/$i'),
          method: 'POST',
          headers: {
            'origin': 'http://localhost:$served',
            'content-type': 'application/json',
            'content-length': '${body.length}',
          },
          body: body,
        );
      }
    }

    await Future.wait([for (var c = 0; c < parallel; c++) client()]);

    // Every answer is its own: the right status, the path and the body it
    // sent (one stream is never taken for another), none refused as busy.
    final wrong = [
      for (var i = 0; i < requests; i++)
        if (answers[i]?.status != 200 || answers[i]?.text != '/api/$i:{"n":$i}')
          '#$i: ${answers[i]?.status} ${answers[i]?.text}',
    ];
    expect(wrong, isEmpty);
    expect(
      tool.hits.where((h) => h.uri.path.startsWith('/api/')).length,
      requests,
    );

    // The bound can bind: in one second the page made the phone send more
    // tool messages (counted as they reach the computer) than the relay's
    // budget lets it send frames. The frames that carried them stay within 100
    // a second and a burst of 10 (R10): the outbox collects messages for
    // 16 ms and sends the lot as one frame. This pins the outbox as a whole,
    // from a page to the wire: it fails when the outbox is bypassed, not when
    // only its 16 ms collection or only its frame budget goes (the other
    // still holds the rate here); Task 8's tools_test.dart pins each.
    final messages = w.counted.arrivals.skip(messagesStart).toList();
    final frames = w.phoneWire.frames.skip(phoneStart).toList();
    expect(
      _busiestSecond(messages),
      greaterThan(110),
      reason: 'the page was too slow for the bound to bind',
    );
    expect(
      _busiestSecond(frames),
      lessThanOrEqualTo(110),
      reason: 'the phone sent more frames in one second than its budget',
    );
    expect(_largest(frames), lessThanOrEqualTo(kMaxFrameBytes));
    await session.close();
  });
}
