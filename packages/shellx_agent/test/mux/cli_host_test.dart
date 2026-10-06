import 'dart:async';
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
  Future<void> close() async {
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future<void> get done => _done.future;
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
}
