import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

import '../support/cli_api_contract.dart';
import '../support/fake_ui_api.dart';

/// Hands out [MemoryMuxTransport] pairs: `connect` gives the client side,
/// the listener yields the server side.
final class PairTransport implements MuxTransport {
  final _incoming = StreamController<MuxConnection>();

  /// Lets a test hand the host any server-side connection.
  void accept(MuxConnection server) => _incoming.add(server);

  @override
  Future<MuxListener> listen(String address) async =>
      _Listener(_incoming.stream, address);
  @override
  Future<MuxConnection> connect(
    String address, {
    Duration timeout = const Duration(seconds: 1),
  }) async {
    final (client, server) = MemoryMuxTransport.pair();
    _incoming.add(server);
    return client;
  }
}

final class _Listener implements MuxListener {
  _Listener(this.connections, this.address);
  @override
  final Stream<MuxConnection> connections;
  @override
  final String address;
  @override
  Future<void> close() async {}
}

/// A server-side connection whose `send` throws something that is not a
/// handshake failure.
final class _ThrowingConnection implements MuxConnection {
  final _in = StreamController<MuxMessage>.broadcast();
  final _done = Completer<void>();
  @override
  Stream<MuxMessage> get messages => _in.stream;
  @override
  void send(MuxMessage message) => throw StateError('broken');
  @override
  int get pendingBytes => 0;
  @override
  Future<void> get drained async {}
  @override
  void pauseInput() {}
  @override
  void resumeInput() {}
  @override
  Future<void> close() async {
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future<void> get done => _done.future;
}

/// A server-side connection whose reader the test drives frame by frame,
/// like a socket peer that reads slowly: [pendingBytes] counts what was
/// sent once [counting] and not yet [take]n.
final class _SlowReader implements MuxConnection {
  _SlowReader(this._inner);
  final MuxConnection _inner;
  final _unread = Queue<int>();
  Completer<void>? _drain;
  int _pending = 0;
  bool counting = false;

  int get unreadFrames => _unread.length;

  /// The reader takes [frames] frames (all when null).
  void take([int? frames]) {
    var n = frames ?? _unread.length;
    while (n-- > 0 && _unread.isNotEmpty) {
      _pending -= _unread.removeFirst();
    }
    if (_pending == 0) {
      final d = _drain;
      _drain = null;
      d?.complete();
    }
  }

  @override
  Stream<MuxMessage> get messages => _inner.messages;
  @override
  void send(MuxMessage message) {
    _inner.send(message);
    if (!counting) return;
    final bytes = encodeMux(message).length;
    _unread.add(bytes);
    _pending += bytes;
  }

  @override
  int get pendingBytes => _pending;
  @override
  Future<void> get drained => _pending == 0
      ? Future<void>.value()
      : (_drain ??= Completer<void>()).future;
  @override
  void pauseInput() => _inner.pauseInput();
  @override
  void resumeInput() => _inner.resumeInput();
  @override
  Future<void> close() => _inner.close();
  @override
  Future<void> get done => _inner.done;
}

final class InUiHost implements CliTestHost {
  InUiHost._(this._host, this._transport);
  final CliHost _host;
  final PairTransport _transport;
  @override
  late final Uint8List secret;
  @override
  final String token = 'a1b2c3d4' * 8;

  static Future<InUiHost> start(
    FakeUiApi ui,
    bool Function() enabled,
    Directory dir, {
    bool Function()? allowExternal,
  }) async {
    final t = PairTransport();
    final file = MuxEndpointFile('${dir.path}/mux/endpoint');
    final host = CliHost(
      transport: t,
      address: 'mem',
      endpointFile: file,
      ui: ui,
      enabled: enabled,
      token: 'a1b2c3d4' * 8,
      allowExternal: allowExternal ?? () => false,
      appVersion: '1.7.0',
    );
    await host.start();
    final h = InUiHost._(host, t);
    h.secret = (await file.read())!.secret;
    return h;
  }

  @override
  Future<MuxConnection> connect({String role = 'cli', String? token}) async {
    final c = await _transport.connect('mem');
    await clientHandshake(
      c,
      secret: secret,
      app: 'test',
      role: role,
      token: token,
    );
    return c;
  }

  @override
  Future<void> close() => _host.stop();
}

Uint8List _nonce() {
  final r = Random.secure();
  return Uint8List.fromList(List.generate(32, (_) => r.nextInt(256)));
}

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('cli_host'));
  tearDown(() => dir.delete(recursive: true));

  cliApiContract(
    'in-UI host',
    (ui, enabled, allowExternal) =>
        InUiHost.start(ui, enabled, dir, allowExternal: allowExternal),
  );

  test('endpoint written with a fresh secret; stop deletes it', () async {
    final h = await InUiHost.start(FakeUiApi(), () => true, dir);
    final info = (await MuxEndpointFile('${dir.path}/mux/endpoint').read())!;
    expect(info.address, 'mem');
    expect(info.protocol, 1);
    expect(info.secret, h.secret);
    await h.close();
    expect(File('${dir.path}/mux/endpoint').existsSync(), isFalse);
  });

  test('role ui is refused with unsupported_role (D2)', () async {
    final h = await InUiHost.start(FakeUiApi(), () => true, dir);
    final c = await h._transport.connect('mem');
    // Listen before the handshake: the refusal follows `ready` at once.
    final refusal = c.messages.firstWhere((m) => m.type == 'error');
    final info = await clientHandshake(
      c,
      secret: h.secret,
      app: 't',
      role: 'ui',
      token: h.token,
    );
    expect(info.protocol, 1);
    final e = await refusal.timeout(const Duration(seconds: 1));
    expect([e.type, e.get<String>('code')], ['error', 'unsupported_role']);
    await c.done.timeout(const Duration(seconds: 1));
    await h.close();
  });

  test('a wrong secret never reaches the UI', () async {
    final ui = FakeUiApi();
    final h = await InUiHost.start(ui, () => true, dir);
    final c = await h._transport.connect('mem');
    await expectLater(
      clientHandshake(
        c,
        secret: Uint8List(32),
        app: 't',
        role: 'cli',
        token: h.token,
      ),
      throwsA(isA<MuxHandshakeException>()),
    );
    expect(ui.requests, isEmpty);
    await h.close();
  });

  test(
    'a ninth client gets busy; a closed client frees its slot (D32)',
    () async {
      final h = await InUiHost.start(FakeUiApi(), () => true, dir);
      final clients = [
        for (var i = 0; i < 8; i++) await h.connect(token: h.token),
      ];
      final ninth = await h._transport.connect('mem');
      final refusal = ninth.messages.firstWhere((m) => m.type == 'error');
      await clientHandshake(
        ninth,
        secret: h.secret,
        app: 't',
        role: 'cli',
        token: h.token,
      );
      final e = await refusal.timeout(const Duration(seconds: 1));
      expect(e.get<String>('code'), 'busy');
      await ninth.done.timeout(const Duration(seconds: 1));
      expect(h._host.clientCount, 8);
      await clients.first.close();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final tenth = await h.connect(token: h.token);
      final ok = tenth.messages.firstWhere((m) => m.q == 1);
      tenth.send(const MuxMessage('api.version', q: 1));
      expect((await ok).type, 'result');
      await h.close();
    },
  );

  test('a client closing mid-request does not throw into the host', () async {
    final ui = FakeUiApi()..gate = Completer<void>();
    final h = await InUiHost.start(ui, () => true, dir);
    final c = await h.connect(token: h.token);
    c.send(const MuxMessage('ui.ls', q: 1));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await c.close();
    ui.gate!.complete();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(h._host.clientCount, 0);
    await h.close();
  });

  test('requests sent right behind auth are answered, in order', () async {
    final h = await InUiHost.start(FakeUiApi(), () => true, dir);
    final c = await h._transport.connect('mem');
    final got = <MuxMessage>[];
    c.messages.listen(got.add);
    final nonceClient = _nonce();
    c.send(
      MuxMessage(
        MuxType.hello,
        fields: {
          'protocol': kMuxProtocol,
          'app': 't',
          'role': 'cli',
          'nonce': nonceClient,
        },
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final nonceDaemon = got.single.get<Uint8List>('nonce')!;
    // Pipelined: the host reads these with `auth`, before its own listener.
    c.send(
      MuxMessage(
        MuxType.auth,
        fields: {
          'proof': clientProof(h.secret, nonceDaemon, nonceClient),
          'token': h.token,
        },
      ),
    );
    c.send(const MuxMessage('api.version', q: 1));
    c.send(const MuxMessage('ui.ls', q: 2));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(
      [for (final m in got.skip(1)) '${m.type}${m.q ?? ''}'],
      ['ready', 'result1', 'result2'],
    );
    await h.close();
  });

  test('a failure outside the handshake still closes the connection', () async {
    final h = await InUiHost.start(FakeUiApi(), () => true, dir);
    final c = _ThrowingConnection();
    h._transport.accept(c);
    await Future<void>.delayed(Duration.zero);
    c._in.add(
      MuxMessage(
        MuxType.hello,
        fields: {
          'protocol': kMuxProtocol,
          'app': 't',
          'role': 'cli',
          'nonce': _nonce(),
        },
      ),
    );
    await c.done.timeout(const Duration(seconds: 1));
    expect(h._host.clientCount, 0);
    await h.close();
  });

  group('A7 Task 5 review leftovers', () {
    Future<MuxMessage> ask(
      MuxConnection c,
      String t, [
      Map<String, Object?> f = const {},
    ]) {
      final answer = c.messages.firstWhere((m) => m.q == 77);
      c.send(MuxMessage(t, q: 77, fields: f));
      return answer.timeout(const Duration(seconds: 2));
    }

    test('the 1000-event limit counts events the reader has not taken, '
        'even when it never quite catches up', () async {
      final ui = FakeUiApi();
      final h = await InUiHost.start(ui, () => true, dir);
      final (client, server) = MemoryMuxTransport.pair();
      final slow = _SlowReader(server);
      h._transport.accept(slow);
      await clientHandshake(
        client,
        secret: h.secret,
        app: 't',
        role: 'cli',
        token: h.token,
      );
      slow.counting = true;
      expect((await ask(client, 'cli.events.subscribe')).type, 'result');
      final events = <MuxMessage>[];
      client.messages.where((m) => m.type == 'event').listen(events.add);
      // Steady load: 100 events a round, the reader takes 90 — it never
      // drains, its backlog only grows to about 300.
      var tab = 0;
      for (var round = 0; round < 30; round++) {
        for (var i = 0; i < 100; i++) {
          ui.eventsOut.add({'kind': 'tab.opened', 'tab': tab++});
        }
        await Future<void>.delayed(Duration.zero);
        slow.take(90);
        expect(slow.pendingBytes, greaterThan(0));
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(events, hasLength(3000));
      expect(events.any((e) => e.get<String>('kind') == 'overflow'), isFalse);
      // Now it stops reading: only 1000 may wait in all.
      final backlog = slow.unreadFrames;
      for (var i = 0; i < 1500; i++) {
        ui.eventsOut.add({'kind': 'tab.opened', 'tab': tab++});
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final passed = 1000 - backlog;
      expect(events, hasLength(3000 + passed));
      slow.take();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        [events.last.get<String>('kind'), events.last.get<int>('dropped')],
        ['overflow', 1500 - passed],
      );
      // Behind again; room returns before it fully catches up: the
      // overflow notice goes out ahead of the next event.
      for (var i = 0; i < 1100; i++) {
        ui.eventsOut.add({'kind': 'tab.opened', 'tab': tab++});
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
      slow.take(500);
      final before = events.length;
      ui.eventsOut.add({'kind': 'tab.opened', 'tab': tab});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        [
          for (final e in events.skip(before))
            [e.get<String>('kind'), e.get<int>('dropped') ?? e.get<int>('tab')],
        ],
        [
          ['overflow', 101],
          ['tab.opened', tab],
        ],
      );
      await client.close();
      await h.close();
    });

    test('recheck: unticking "Allow other terminals" ends token-less '
        'connections that used the full API at once', () async {
      final ui = FakeUiApi();
      var external = true;
      final h = await InUiHost.start(
        ui,
        () => true,
        dir,
        allowExternal: () => external,
      );
      final subscribed = await h.connect();
      expect((await ask(subscribed, 'cli.events.subscribe')).type, 'result');
      final asked = await h.connect();
      expect((await ask(asked, 'ui.ls')).type, 'result');
      final limited = await h.connect();
      expect((await ask(limited, 'api.version')).type, 'result');
      final shell = await h.connect(token: h.token);
      expect((await ask(shell, 'cli.events.subscribe')).type, 'result');
      final refusals = [
        for (final c in [subscribed, asked]) c.messages.first,
      ];
      external = false;
      h._host.recheck();
      for (final r in refusals) {
        final e = await r.timeout(const Duration(seconds: 2));
        expect(
          [e.type, e.q, e.get<String>('code')],
          ['error', null, 'forbidden'],
        );
      }
      await subscribed.done.timeout(const Duration(seconds: 2));
      await asked.done.timeout(const Duration(seconds: 2));
      // A limited client and a ShellX shell keep their connection.
      expect((await ask(limited, 'api.version')).type, 'result');
      final next = shell.messages.firstWhere((m) => m.type == 'event');
      ui.eventsOut.add({'kind': 'tab.opened', 'tab': 1});
      expect(
        (await next.timeout(const Duration(seconds: 2))).get<int>('tab'),
        1,
      );
      await h.close();
    });

    test('recheck: switching command-line control off ends subscriptions '
        'with cli_disabled at once; the connection stays', () async {
      final ui = FakeUiApi();
      var enabled = true;
      final h = await InUiHost.start(ui, () => enabled, dir);
      final c = await h.connect(token: h.token);
      expect((await ask(c, 'cli.events.subscribe')).type, 'result');
      final seen = <MuxMessage>[];
      c.messages.listen(seen.add);
      enabled = false;
      h._host.recheck();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        [
          for (final m in seen) [m.type, m.q, m.get<String>('code')],
        ],
        [
          ['error', null, 'cli_disabled'],
        ],
      );
      enabled = true;
      ui.eventsOut.add({'kind': 'tab.opened', 'tab': 2});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(seen, hasLength(1)); // the subscription is over
      expect((await ask(c, 'api.version')).type, 'result');
      await h.close();
    });
  });
}
