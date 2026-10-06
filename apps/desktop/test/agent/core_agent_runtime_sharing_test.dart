import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_desktop/src/agent/agent_runtime.dart';
import 'package:shellx_desktop/src/agent/session_core.dart';

/// A relay socket that never answers: these tests need no phone.
final class _SilentRelaySocket implements RelaySocket {
  final _incoming = StreamController<Object>();
  int? _closeCode;

  @override
  Stream<Object> get messages => _incoming.stream;
  @override
  void sendText(String text) {}
  @override
  void sendBytes(Uint8List bytes) {}
  @override
  Future<void> close([int? code, String? reason]) async {
    _closeCode ??= code;
    if (!_incoming.isClosed) await _incoming.close();
  }

  @override
  int? get closeCode => _closeCode;
}

final class _NoPty implements PtyFactory {
  @override
  Pty spawn(
    ShellCommand command, {
    required String workingDirectory,
    required Map<String, String> environment,
    required int cols,
    required int rows,
  }) => throw UnsupportedError('no shell sessions in this test');
}

/// Plays `shellx-term` over a real socket with the real codec.
final class _FakeTerm {
  _FakeTerm._(this._socket) {
    unawaited(_socket.done.then((_) {}, onError: (Object _) {}));
    _socket.listen(
      (chunk) {
        for (final payload in _reader.add(chunk)) {
          final message = AgentToTerm.decode(payload);
          received.add(message);
          _messages.add(message);
        }
      },
      onDone: () {
        if (!_closed.isCompleted) _closed.complete();
        _messages.close();
      },
      onError: (Object _) {},
    );
  }

  static Future<_FakeTerm> connect(String endpointPath) async {
    final lines = File(endpointPath).readAsLinesSync();
    final port = int.parse(lines[1].substring('port='.length));
    final secret = Uint8List.fromList([
      for (var i = 0; i < 64; i += 2)
        int.parse(lines[2].substring(7 + i, 9 + i), radix: 16),
    ]);
    final term = _FakeTerm._(
      await Socket.connect(InternetAddress.loopbackIPv4, port),
    );
    await term._handshake(secret);
    return term;
  }

  final Socket _socket;
  final _reader = TermFrameReader();
  final _messages = StreamController<AgentToTerm?>();
  late final _next = StreamIterator(_messages.stream);
  final _closed = Completer<void>();
  final List<AgentToTerm?> received = [];

  Future<void> get closed => _closed.future;
  bool get isClosed => _closed.isCompleted;

  void send(TermToAgent message) => _socket.add(termFrame(message.encode()));

  Future<AgentToTerm?> _nextMessage() async =>
      await _next.moveNext().timeout(const Duration(seconds: 5))
      ? _next.current
      : null;

  Future<void> _handshake(Uint8List secret) async {
    final nonce = Uint8List.fromList(List.generate(32, (i) => i + 1));
    send(TermHello(v: 1, nonce: nonce));
    final challenge = await _nextMessage() as AgentChallenge;
    send(
      TermAuth(
        mac: termProof(secret, challenge.nonce, nonce),
        info: TermInfo(
          termId: Uint8List.fromList(List.filled(16, 7)),
          app: 'Terminal',
          shell: 'zsh',
          pid: 4242,
          cols: 80,
          rows: 24,
          startedAt: 1759276800000,
        ),
      ),
    );
    expect(await _nextMessage(), isA<AgentReady>());
    send(
      TermSnapshot(
        data: Uint8List.fromList(utf8.encode('\x1b]0;build\x07hello')),
        last: true,
      ),
    );
  }

  void destroy() => _socket.destroy();
}

void main() {
  late Directory dir;
  late String endpoint;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('shellx-runtime-');
    endpoint = '${dir.path}/term/endpoint';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<CoreAgentRuntime> build({String? endpointPath}) async {
    final identity = await NoiseKeyPair.generate();
    final api = ShellxApi(baseUri: Uri.parse('https://relay.shellx.pro'));
    return CoreAgentRuntime(
      RuntimeParams(
        credentials: const AgentCredentials(
          token: 'agent-token',
          deviceId: '22222222-2222-4222-8222-222222222222',
          userId: '11111111-1111-4111-8111-111111111111',
          email: 'phu@example.com',
        ),
        identity: identity,
        trusted: TrustedStore(InMemoryKeyValueStore()),
        api: api,
      ),
      core: SessionCore(
        ptyFactory: _NoPty(),
        shellResolver: PlatformShellResolver(
          operatingSystem: 'macos',
          environment: const {'HOME': '/Users/phu'},
        ),
        homeDirectory: '/Users/phu',
        baseEnvironment: const {'HOME': '/Users/phu'},
        api: api,
      ),
      relayBaseUri: Uri.parse('https://relay.shellx.pro'),
      appVersion: '1.0.0',
      termEndpointPath: endpointPath,
      connector: (uri, headers) async => _SilentRelaySocket(),
    );
  }

  Future<void> until(bool Function() condition) async {
    for (var i = 0; i < 200 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(condition(), isTrue);
  }

  test('setTerminalSharing starts and stops the local server', () async {
    final runtime = await build(endpointPath: endpoint);
    await runtime.start();
    expect(runtime.terminalSharing, isFalse);
    await runtime.setTerminalSharing(true);
    expect(runtime.terminalSharing, isTrue);
    expect(File(endpoint).existsSync(), isTrue);
    await runtime.setTerminalSharing(false);
    expect(runtime.terminalSharing, isFalse);
    expect(File(endpoint).existsSync(), isFalse);
    await runtime.stop();
  });

  test('without an endpoint path sharing cannot start', () async {
    final runtime = await build();
    await expectLater(runtime.setTerminalSharing(true), throwsStateError);
    await runtime.setTerminalSharing(false);
    expect(runtime.terminalSharing, isFalse);
    await runtime.stop();
  });

  test('a connected shellx-term is listed, with app and title, and '
      'sessionChanges fires', () async {
    final runtime = await build(endpointPath: endpoint);
    await runtime.start();
    await runtime.setTerminalSharing(true);
    var changes = 0;
    runtime.sessionChanges.listen((_) => changes++);
    final term = await _FakeTerm.connect(endpoint);
    await until(() => runtime.desktopSessions.isNotEmpty);
    await until(() => runtime.desktopSessions.single.title == 'build');
    final session = runtime.desktopSessions.single;
    expect(session.app, 'Terminal');
    expect(session.connected, isTrue);
    expect(changes, greaterThan(0));
    // Shell sessions stay what they were: desktop terminals are separate.
    expect(runtime.shellSessions.sessions, isEmpty);
    term.destroy();
    await runtime.stop();
  });

  // P3 ledger "Ghi cho P4": every "close" path of the app leaves the
  // terminal running (spec §7.2).
  test('closing shell sessions (the close paths of the app, A1 D7) and '
      'disconnectDesktopPhone never end a desktop terminal', () async {
    final runtime = await build(endpointPath: endpoint);
    await runtime.start();
    await runtime.setTerminalSharing(true);
    final term = await _FakeTerm.connect(endpoint);
    await until(() => runtime.desktopSessions.isNotEmpty);
    final id = runtime.desktopSessions.single.id;

    runtime.shellSessions.closeSession(id);
    runtime.shellSessions.closeAll();
    runtime.disconnectDesktopPhone(id);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(runtime.desktopSessions.single.id, id);
    expect(runtime.desktopSessions.single.connected, isTrue);
    expect(term.isClosed, isFalse);
    // Nothing but the handshake went to the terminal.
    expect(term.received, [isA<AgentChallenge>(), isA<AgentReady>()]);
    term.destroy();
    await runtime.stop();
  });

  test('stop() stops sharing: endpoint deleted, link closed, nothing sent '
      'that could end the terminal', () async {
    final runtime = await build(endpointPath: endpoint);
    await runtime.start();
    await runtime.setTerminalSharing(true);
    final term = await _FakeTerm.connect(endpoint);
    await until(() => runtime.desktopSessions.isNotEmpty);

    await runtime.stop();
    await term.closed.timeout(const Duration(seconds: 5));
    expect(File(endpoint).existsSync(), isFalse);
    expect(runtime.desktopSessions, isEmpty);
    expect(runtime.terminalSharing, isFalse);
    expect(term.received, [isA<AgentChallenge>(), isA<AgentReady>()]);
  });
}
