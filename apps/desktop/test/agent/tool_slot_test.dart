import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_desktop/daemon_main.dart' show kDaemonCaps;
import 'package:shellx_desktop/src/agent/agent_runtime.dart';
import 'package:shellx_desktop/src/agent/daemon_tools.dart';
import 'package:shellx_desktop/src/agent/session_core.dart';

import '../mux/mux_test_support.dart';
import '../support/fake_pty.dart';

const _phone = '33333333-3333-4333-8333-333333333333';

/// V2-4 E5, E6: every runtime's router sends `tool.*` to the process's slot;
/// the background service hosts the proxy and takes the window's list.
void main() {
  SessionCore core() => SessionCore(
    ptyFactory: FakePtyFactory(),
    shellResolver: const FixedShellResolver(),
    homeDirectory: '/Users/phu',
    baseEnvironment: const {'HOME': '/Users/phu'},
    api: ShellxApi(baseUri: Uri.parse('https://relay.test')),
  );

  test('no target: not serving (no tools flag), the phone hears '
      'unavailable', () {
    final c = core();
    final out = <OutboundMessage>[];
    c.tools.outbound.listen(out.add);
    expect(c.tools.serving, isFalse);
    c.tools.handle(_phone, const ToolList());
    expect((out.single.message as ToolListResult).available, isFalse);
  });

  test('every runtime built on the core uses its slot: a revoked phone and '
      'a stopped runtime reach the slot\'s target', () async {
    final c = core();
    final target = _Endpoint();
    c.tools.target = target;
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
  });

  test('the background service: it says it has tools; its proxy serves the '
      'window\'s list and keeps it when the window goes', () async {
    expect(kDaemonCaps, contains('tools'));
    final c = core();
    final listener = TestListener();
    final server = MuxServer(
      sessions: c.sessions,
      secret: testSecret,
      self: const MuxPeerInfo(protocol: kMuxProtocol, app: 't', instance: 'i'),
      onQuit: () async {},
    )..serve(listener);
    addTearDown(server.close);
    final proxy = installDaemonTools(server, c); // What daemon_main calls.
    addTearDown(proxy.close);
    expect(c.tools.serving, isTrue);
    final toPhone = <ToolMessage>[];
    c.tools.outbound.listen((o) => toPhone.add(o.message as ToolMessage));

    // No window has said anything yet: the list is unavailable.
    c.tools.handle(_phone, const ToolList());
    expect((toPhone.single as ToolListResult).available, isFalse);

    final (client, daemonSide) = MemoryMuxTransport.pair();
    listener.push(daemonSide);
    await clientHandshake(client, secret: testSecret, app: 't', role: 'ui');
    client.send(
      MuxMessage(
        MuxType.toolServe,
        fields: {
          'b': ToolCatalog.serveBody([
            {
              'id': 'k3f9za7q1m',
              'name': 'Bảng việc',
              'ws': 'shop-web',
              'group': 'ws:a',
              'url': 'http://localhost:5173/',
            },
          ]),
        },
      ),
    );
    await pumpEventQueue();
    final listed = toPhone.last as ToolListResult;
    expect(listed.available, isTrue);
    expect(utf8.decode(listed.body), contains('Bảng việc'));
    await client.close();
    await pumpEventQueue();
    expect(proxy.catalog?.tools.single.id, 'k3f9za7q1m');
  });
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

/// A [ToolEndpoint] that only records what the slot passes on.
final class _Endpoint implements ToolEndpoint {
  final gone = <String>[];
  var allGone = 0;

  @override
  Stream<OutboundMessage> get outbound => const Stream.empty();

  @override
  bool get serving => true;

  @override
  void handle(String mobileId, ToolMessage message) {}

  @override
  void phoneGone(String mobileId) => gone.add(mobileId);

  @override
  void allPhonesGone() => allGone++;
}
