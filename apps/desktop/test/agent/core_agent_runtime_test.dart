import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_desktop/src/agent/agent_runtime.dart';

final class FakeRelaySocket implements RelaySocket {
  final StreamController<Object> incoming = StreamController<Object>();
  final List<String> sentText = [];
  final List<Uint8List> sentBytes = [];
  int? _closeCode;

  @override
  Stream<Object> get messages => incoming.stream;
  @override
  void sendText(String text) => sentText.add(text);
  @override
  void sendBytes(Uint8List bytes) => sentBytes.add(bytes);
  @override
  Future<void> close([int? code, String? reason]) async {
    _closeCode ??= code;
    if (!incoming.isClosed) await incoming.close();
  }

  @override
  int? get closeCode => _closeCode;

  /// The hub closes the socket with [code].
  Future<void> serverClose(int code) async {
    _closeCode = code;
    await incoming.close();
  }
}

final class _NoPty implements PtyFactory {
  @override
  Pty spawn(
    ShellCommand command, {
    required String workingDirectory,
    required Map<String, String> environment,
    required int cols,
    required int rows,
  }) => throw UnsupportedError('no sessions in this test');
}

void main() {
  late FakeRelaySocket socket;
  late List<(Uri, Map<String, String>)> connects;
  late NoiseKeyPair identity;
  final now = DateTime(2026, 9, 25, 12);

  Future<CoreAgentRuntime> build() async {
    identity = await NoiseKeyPair.generate();
    final store = InMemoryKeyValueStore();
    return CoreAgentRuntime(
      RuntimeParams(
        credentials: const AgentCredentials(
          token: 'agent-token',
          deviceId: '22222222-2222-4222-8222-222222222222',
          userId: '11111111-1111-4111-8111-111111111111',
          email: 'phu@example.com',
        ),
        identity: identity,
        trusted: TrustedStore(store),
        api: ShellxApi(baseUri: Uri.parse('https://relay.shellx.pro')),
      ),
      relayBaseUri: Uri.parse('https://relay.shellx.pro'),
      appVersion: '1.0.0',
      ptyFactory: _NoPty(),
      shellResolver: PlatformShellResolver(
        operatingSystem: 'macos',
        environment: const {'HOME': '/Users/phu'},
      ),
      homeDirectory: '/Users/phu',
      baseEnvironment: const {'HOME': '/Users/phu'},
      connector: (uri, headers) async {
        connects.add((uri, headers));
        return socket = FakeRelaySocket();
      },
      now: () => now,
    );
  }

  setUp(() => connects = []);

  test(
    'start() connects to wss://relay.shellx.pro/v1/ws with the bearer token',
    () async {
      final runtime = await build();
      await runtime.start();
      await pumpEventQueue();
      expect(connects, hasLength(1));
      expect(connects.single.$1.toString(), 'wss://relay.shellx.pro/v1/ws');
      final auth = connects.single.$2.entries.firstWhere(
        (e) => e.key.toLowerCase() == 'authorization',
      );
      expect(auth.value, 'Bearer agent-token');
      await runtime.stop();
    },
  );

  test('a 4002 close is reported as revoked', () async {
    final runtime = await build();
    final states = <RelayConnectionState>[];
    runtime.relayStates.listen(states.add);
    await runtime.start();
    await pumpEventQueue();
    await socket.serverClose(RelayCloseCode.revoked);
    await pumpEventQueue();
    expect(states, contains(RelayConnectionState.revoked));
    await runtime.stop();
  });

  test(
    'pairing QR carries this agent, expires in 5 minutes, and cancel invalidates it',
    () async {
      final runtime = await build();
      await runtime.start();
      final view = runtime.startPairing();
      expect(view.uri.agentDeviceId, '22222222-2222-4222-8222-222222222222');
      expect(view.uri.agentPublicKey, identity.publicKey);
      expect(view.uri.secret, hasLength(32));
      expect(view.expiresAt, now.add(const Duration(minutes: 5)));
      expect(runtime.pairingCodes.activeSecret, isNotNull);

      runtime.cancelPairing();
      expect(runtime.pairingCodes.activeSecret, isNull);
      await runtime.stop();
    },
  );

  test('stop() leaves the relay stopped', () async {
    final runtime = await build();
    await runtime.start();
    await pumpEventQueue();
    await runtime.stop();
    expect(runtime.relayState, RelayConnectionState.stopped);
  });

  test(
    'after stop() a 4002 from the hub (logout) surfaces no AgentRevoked',
    () async {
      final runtime = await build();
      final events = <AgentEvent>[];
      final states = <RelayConnectionState>[];
      runtime.events.listen(events.add);
      runtime.relayStates.listen(states.add);
      await runtime.start();
      await pumpEventQueue();
      final live = socket;

      await runtime.stop();
      expect(live.closeCode, 1000); // Closed by the agent, not the hub.
      await live.serverClose(RelayCloseCode.revoked);
      await pumpEventQueue();
      expect(states.last, RelayConnectionState.stopped);
      expect(events.whereType<AgentRevoked>(), isEmpty);
    },
  );

  group('reconnectNow()', () {
    test('skips the backoff after a dropped connection', () async {
      final runtime = await build();
      await runtime.start();
      await pumpEventQueue();
      await socket.serverClose(1011);
      await pumpEventQueue();
      expect(runtime.relayState, RelayConnectionState.disconnected);
      expect(connects, hasLength(1)); // The backoff is at least 500 ms.

      runtime.reconnectNow();
      await pumpEventQueue();
      expect(connects, hasLength(2));
      expect(runtime.relayState, RelayConnectionState.connected);
      await runtime.stop();
    });

    test(
      'connects again after a 4001 close (tray "Reconnect"), which the relay '
      'never does on its own',
      () async {
        final runtime = await build();
        await runtime.start();
        await pumpEventQueue();
        await socket.serverClose(RelayCloseCode.replaced);
        await pumpEventQueue();
        expect(runtime.relayState, RelayConnectionState.replaced);
        expect(connects, hasLength(1));

        runtime.reconnectNow();
        await pumpEventQueue();
        expect(connects, hasLength(2));
        expect(runtime.relayState, RelayConnectionState.connected);
        await runtime.stop();
        expect(runtime.relayState, RelayConnectionState.stopped);
      },
    );

    test('never reconnects after a 4002 close', () async {
      final runtime = await build();
      await runtime.start();
      await pumpEventQueue();
      await socket.serverClose(RelayCloseCode.revoked);
      await pumpEventQueue();

      runtime.reconnectNow();
      await pumpEventQueue();
      expect(connects, hasLength(1));
      expect(runtime.relayState, RelayConnectionState.revoked);
      await runtime.stop();
    });

    test('does nothing before start() or after stop()', () async {
      final runtime = await build();
      runtime.reconnectNow();
      await pumpEventQueue();
      expect(connects, isEmpty);

      await runtime.start();
      await pumpEventQueue();
      await runtime.stop();
      runtime.reconnectNow();
      await pumpEventQueue();
      expect(connects, hasLength(1));
      expect(runtime.relayState, RelayConnectionState.stopped);
    });
  });
}
