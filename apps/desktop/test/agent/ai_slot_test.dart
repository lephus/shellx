import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_desktop/src/agent/agent_runtime.dart';
import 'package:shellx_desktop/src/agent/daemon_ai.dart';
import 'package:shellx_desktop/src/agent/session_core.dart';

import '../mux/mux_test_support.dart';
import '../support/fake_pty.dart';

const _phone = '33333333-3333-4333-8333-333333333333';

/// V2-2 D1: every runtime's router sends `ai.*` to the process's slot; it
/// answers "unavailable" until the window (or the background service's
/// forwarder) takes it.
void main() {
  SessionCore core() => SessionCore(
    ptyFactory: FakePtyFactory(),
    shellResolver: const FixedShellResolver(),
    homeDirectory: '/Users/phu',
    baseEnvironment: const {'HOME': '/Users/phu'},
    api: ShellxApi(baseUri: Uri.parse('https://relay.test')),
  );

  test(
    'no target: the phone hears unavailable; a target gets the messages',
    () {
      final c = core();
      final out = <OutboundMessage>[];
      c.ai.outbound.listen(out.add);
      c.ai.handle(_phone, const AiList());
      expect((out.single.message as AiListResult).available, isFalse);

      final forwarder = MuxAiForwarder();
      final toWindow = <MuxMessage>[];
      forwarder.serve(Object(), toWindow.add);
      c.ai.target = forwarder;
      c.ai.handle(_phone, const AiAttach(sid: 'e.-1'));
      expect(toWindow.single.type, MuxType.aiIn);
    },
  );

  test(
    'every runtime built on the core uses its slot, one after the other: '
    'a revoked phone and a stopped runtime reach the slot\'s target',
    () async {
      final c = core();
      final target = _Endpoint();
      c.ai.target = target;
      for (var run = 1; run <= 2; run++) {
        final runtime = await _runtimeOn(c);
        await runtime.revoke(_phone);
        expect(target.gone, [_phone], reason: 'revoke, runtime $run');
        await runtime.stop();
        expect(target.allGone, 1, reason: 'stop, runtime $run');
        target
          ..gone.clear()
          ..allGone = 0;
      }
    },
  );

  test('the background service: its forwarder is the server\'s and the '
      'slot\'s target — unavailable until a window serves, then both ways, '
      'and the phone hears the window leave', () async {
    final c = core();
    final listener = TestListener();
    final server = MuxServer(
      sessions: c.sessions,
      secret: testSecret,
      self: const MuxPeerInfo(protocol: kMuxProtocol, app: 't', instance: 'i'),
      onQuit: () async {},
    )..serve(listener);
    addTearDown(server.close);
    installDaemonAi(server, c); // What daemon_main.dart calls.
    final toPhone = <AppMessage>[];
    c.ai.outbound.listen((o) => toPhone.add(o.message));

    // No window serves AI yet: the phone hears unavailable, never silence.
    c.ai.handle(_phone, const AiList());
    c.ai.handle(_phone, const AiAttach(sid: 'e.-1'));
    c.ai.handle(_phone, const AiPrompt(sid: 'e.-1', rid: 1, text: 'hi'));
    expect(toPhone.map((m) => m.type), [
      'ai.list.result',
      'ai.closed',
      'ai.result',
    ]);
    expect((toPhone.first as AiListResult).available, isFalse);
    expect((toPhone.last as AiResult).code, 'unavailable');
    toPhone.clear();

    // A window serves: the phone that listed is listed again for it, its
    // next messages reach it and its answers reach the phone.
    final (window, inbox) = await _window(listener);
    window.send(const MuxMessage(MuxType.aiServe));
    await pumpEventQueue();
    c.ai.handle(_phone, const AiAttach(sid: 'e.-1'));
    await pumpEventQueue();
    expect(_aiIn(inbox), ['ai.list', 'ai.attach']);
    window.send(
      MuxMessage(
        MuxType.aiOut,
        fields: {
          'm': _phone,
          'b': encodeCbor(const AiResult(rid: 2, ok: true).toMap()),
        },
      ),
    );
    await pumpEventQueue();
    expect(toPhone, [const AiResult(rid: 2, ok: true)]);
    toPhone.clear();

    // The window goes: no list, and the mirror it served is closed.
    await window.close();
    await pumpEventQueue();
    expect(toPhone.map((m) => m.type), ['ai.list.result', 'ai.closed']);
    expect((toPhone.first as AiListResult).available, isFalse);
    expect((toPhone.last as AiClosed).reason, 'desktop_closed');
  });
}

/// The type of each `ai.*` message the service passed to the window.
List<String> _aiIn(List<MuxMessage> inbox) => [
  for (final m in inbox)
    if (m.type == MuxType.aiIn)
      (decodeCbor(m.get<Uint8List>('b')!) as Map<Object?, Object?>)['t']
          as String,
];

/// A window's `ui` link to [listener], with what it receives.
Future<(MuxConnection, List<MuxMessage>)> _window(TestListener listener) async {
  final (client, daemonSide) = MemoryMuxTransport.pair();
  listener.push(daemonSide);
  final peer = await clientHandshake(
    client,
    secret: testSecret,
    app: 't',
    role: 'ui',
  );
  final inbox = [...peer.early];
  client.messages.listen(inbox.add);
  return (client, inbox);
}

/// A runtime on [core] that never reaches a relay; nothing is started.
Future<CoreAgentRuntime> _runtimeOn(SessionCore core) async {
  final api = ShellxApi(baseUri: Uri.parse('https://relay.test'));
  return CoreAgentRuntime(
    RuntimeParams(
      credentials: const AgentCredentials(
        token: 'agent-token',
        deviceId: '22222222-2222-4222-8222-222222222222',
        userId: '11111111-1111-4111-8111-111111111111',
        email: 'phu@example.com',
      ),
      identity: await NoiseKeyPair.generate(),
      trusted: TrustedStore(InMemoryKeyValueStore()),
      api: api,
    ),
    core: core,
    relayBaseUri: Uri.parse('https://relay.test'),
    appVersion: '1.0.0',
    connector: (uri, headers) async =>
        throw const SocketException('offline in tests'),
  );
}

/// An [AiEndpoint] that only records what the slot passes on.
final class _Endpoint implements AiEndpoint {
  final gone = <String>[];
  var allGone = 0;

  @override
  Stream<OutboundMessage> get outbound => const Stream.empty();

  @override
  void handle(String mobileId, AiMessage message) {}

  @override
  void phoneGone(String mobileId) => gone.add(mobileId);

  @override
  void allPhonesGone() => allGone++;
}
