import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_desktop/src/agent/agent_controller_base.dart';
import 'package:shellx_desktop/src/agent/agent_runtime.dart';
import 'package:shellx_desktop/src/agent/agent_state.dart';
import 'package:shellx_desktop/src/agent/agent_state_codec.dart';
import 'package:shellx_desktop/src/agent/remote_agent_controller.dart';
import 'package:shellx_desktop/src/terminal_sharing/config_file_editor.dart';
import 'package:shellx_desktop/src/terminal_sharing/terminal_sharing_setup.dart';

/// The daemon side of the wire, by hand: records every `agent.call`,
/// answers `agent.get`, and lets a test push `agent.state`.
final class FakeAgentDaemon {
  FakeAgentDaemon(this.conn) {
    conn.messages.listen(_onMessage);
  }

  final MuxConnection conn;
  final calls = <(String, Map<Object?, Object?>)>[];
  AgentViewState state = const AgentViewState();
  Object? Function(String m)? valueFor;
  String? failWith;
  int gets = 0;

  void _onMessage(MuxMessage m) {
    switch (m.type) {
      case MuxType.agentGet:
        gets++;
        conn.send(
          MuxMessage(
            MuxType.result,
            q: m.q,
            fields: {'state': agentStateToWire(state)},
          ),
        );
      case MuxType.agentCall:
        final name = m.get<String>('m')!;
        calls.add((name, m.get<Map<Object?, Object?>>('a') ?? const {}));
        if (failWith case final code?) {
          conn.send(MuxMessage(MuxType.error, q: m.q, fields: {'code': code}));
        } else {
          conn.send(
            MuxMessage(
              MuxType.result,
              q: m.q,
              fields: {'value': valueFor?.call(name)},
            ),
          );
        }
    }
  }

  void push(AgentViewState s) {
    state = s;
    conn.send(
      MuxMessage(MuxType.agentState, fields: {'state': agentStateToWire(s)}),
    );
  }
}

SharingPlan _plan() => const SharingPlan(
  files: [
    PlannedFile(
      ConfigTarget(
        path: '/h/.zshrc',
        block: 'b\n',
        create: true,
        newFileEol: '\n',
      ),
      exists: true,
    ),
  ],
  bashSkipped: false,
  powerShells: [],
);

void main() {
  late FakeAgentDaemon daemon;
  late MuxClient client;
  late ProviderContainer container;

  setUp(() {
    final (ui, d) = MemoryMuxTransport.pair();
    daemon = FakeAgentDaemon(d);
    client = MuxClient(ui);
    container = ProviderContainer.test(
      overrides: [
        agentControllerProvider.overrideWith(
          () => RemoteAgentController(client),
        ),
      ],
    );
  });

  RemoteAgentController controller() =>
      container.read(agentControllerProvider.notifier) as RemoteAgentController;

  /// Every command of [AgentControllerBase] except the two that stay local
  /// (`bootstrap`, `shutdown`; see their own tests): the name the daemon
  /// must receive, the call, and the arguments it must carry.
  final table =
      <
        String,
        (Future<Object?> Function(AgentControllerBase), Map<String, Object?>)
      >{
        'signIn': (
          (c) => c.signIn(email: 'a@b.c', password: 'pw', register: true),
          {'email': 'a@b.c', 'password': 'pw', 'register': true},
        ),
        'signOut': ((c) => c.signOut(), {}),
        'changePassword': (
          (c) => c.changePassword('new'),
          {'newPassword': 'new'},
        ),
        'setRemoteAccess': (
          (c) => c.setRemoteAccess(false),
          {'enabled': false},
        ),
        'setNotifyThreshold': (
          (c) => c.setNotifyThreshold(30),
          {'seconds': 30},
        ),
        'setDesktopNotifications': (
          (c) => c.setDesktopNotifications(false),
          {'enabled': false},
        ),
        'setDesktopNotificationsOnlyUnfocused': (
          (c) => c.setDesktopNotificationsOnlyUnfocused(false),
          {'enabled': false},
        ),
        'setKeepAwake': ((c) => c.setKeepAwake(false), {'enabled': false}),
        'setLaunchAtStartup': (
          (c) => c.setLaunchAtStartup(false),
          {'enabled': false},
        ),
        'setCliControlEnabled': (
          (c) => c.setCliControlEnabled(false),
          {'enabled': false},
        ),
        'setCliAllowExternal': (
          (c) => c.setCliAllowExternal(true),
          {'enabled': true},
        ),
        'setSshRemoteHook': (
          (c) => c.setSshRemoteHook(false),
          {'enabled': false},
        ),
        'completeOnboarding': ((c) => c.completeOnboarding(), {}),
        'startPairing': ((c) => c.startPairing(), {}),
        'cancelPairing': ((c) => c.cancelPairing(), {}),
        'revoke': ((c) => c.revoke('m1'), {'mobileId': 'm1'}),
        'closeSession': ((c) => c.closeSession(4), {'id': 4}),
        'prepareTerminalSharing': ((c) => c.prepareTerminalSharing(), {}),
        'enableTerminalSharing': (
          (c) => c.enableTerminalSharing(_plan()),
          {'plan': sharingPlanToWire(_plan())},
        ),
        'disableTerminalSharing': ((c) => c.disableTerminalSharing(), {}),
        'disconnectDesktopPhone': (
          (c) => c.disconnectDesktopPhone(9),
          {'id': 9},
        ),
        'closeAllSessions': ((c) => c.closeAllSessions(), {}),
        'reconnect': ((c) => c.reconnect(), {}),
        'checkForUpdate': ((c) => c.checkForUpdate(), {}),
      };

  for (final MapEntry(key: name, value: (call, args)) in table.entries) {
    test('$name -> agent.call{m: $name, a: …}', () async {
      await controller().bootstrap();
      await call(controller());
      expect(daemon.calls, hasLength(1));
      expect(daemon.calls.single.$1, name);
      expect(daemon.calls.single.$2, args);
    });
  }

  test('the table names every command the base declares', () {
    // A command added to AgentControllerBase must be added to the table
    // (and so to the bridge and the wire): this list is the base's own.
    expect(
      table.keys.toSet(),
      {...AgentControllerBase.wireCommands}
        ..removeAll({'bootstrap', 'shutdown'}),
    );
  });

  test(
    'startPairing returns the decoded PairingView; a null stays null',
    () async {
      await controller().bootstrap();
      final view = PairingView(
        uri: PairingUri(
          agentDeviceId: '0198b1d2-7c3a-7b1e-8a55-1f2e3d4c5b6a',
          agentPublicKey: Uint8List(32),
          secret: Uint8List(32)..[0] = 7,
        ),
        expiresAt: DateTime.utc(2026, 10, 7, 12, 5),
      );
      daemon.valueFor = (m) => pairingToWire(view);
      final got = await controller().startPairing();
      expect(got!.uri.toUriString(), view.uri.toUriString());
      expect(got.expiresAt.isAtSameMomentAs(view.expiresAt), isTrue);
      daemon.valueFor = (m) => null;
      expect(await controller().startPairing(), isNull);
    },
  );

  test('prepareTerminalSharing and enableTerminalSharing decode their '
      'results', () async {
    await controller().bootstrap();
    daemon.valueFor = (m) => sharingPlanToWire(_plan());
    final plan = await controller().prepareTerminalSharing();
    expect(plan!.files.single.target.path, '/h/.zshrc');
    daemon.valueFor = (m) => true;
    expect(await controller().enableTerminalSharing(plan), isTrue);
    daemon.valueFor = (m) => null;
    expect(await controller().prepareTerminalSharing(), isNull);
  });

  test(
    'a daemon error{internal} makes the call throw MuxRemoteException',
    () async {
      await controller().bootstrap();
      daemon.failWith = MuxError.internal;
      await expectLater(
        controller().setKeepAwake(true),
        throwsA(
          isA<MuxRemoteException>().having((e) => e.code, 'code', 'internal'),
        ),
      );
    },
  );

  test(
    'a lost daemon makes calls throw MuxRemoteException(disconnected)',
    () async {
      await controller().bootstrap();
      await daemon.conn.close();
      await pumpEventQueue();
      await expectLater(
        controller().reconnect(),
        throwsA(
          isA<MuxRemoteException>().having(
            (e) => e.code,
            'code',
            'disconnected',
          ),
        ),
      );
    },
  );

  test('bootstrap asks agent.get once, completes when the first state is '
      'applied, and is not an agent.call', () async {
    daemon.state = const AgentViewState(
      phase: AuthPhase.signedIn,
      email: 'phu@example.com',
      notifyThresholdSeconds: 60,
    );
    expect(container.read(agentControllerProvider).phase, AuthPhase.loading);
    await controller().bootstrap(watchForWake: false);
    final s = container.read(agentControllerProvider);
    expect(s.phase, AuthPhase.signedIn);
    expect(s.email, 'phu@example.com');
    expect(s.notifyThresholdSeconds, 60);
    await controller().bootstrap();
    expect(daemon.gets, 1);
    expect(daemon.calls, isEmpty);
  });

  test('state follows agent.state events, newest wins', () async {
    await controller().bootstrap();
    daemon.push(const AgentViewState(phase: AuthPhase.signedOut));
    daemon.push(
      const AgentViewState(
        phase: AuthPhase.signedIn,
        relay: RelayConnectionState.disconnected,
        cliControlEnabled: false,
      ),
    );
    await pumpEventQueue();
    final s = container.read(agentControllerProvider);
    expect(s.phase, AuthPhase.signedIn);
    expect(s.relay, RelayConnectionState.disconnected);
    expect(s.cliControlEnabled, isFalse);
  });

  test(
    'a call does not change the state itself: only agent.state does',
    () async {
      await controller().bootstrap();
      await controller().setNotifyThreshold(0);
      await pumpEventQueue();
      expect(
        container.read(agentControllerProvider).notifyThresholdSeconds,
        const AgentViewState().notifyThresholdSeconds,
      );
      daemon.push(const AgentViewState(notifyThresholdSeconds: 0));
      await pumpEventQueue();
      expect(container.read(agentControllerProvider).notifyThresholdSeconds, 0);
    },
  );

  test(
    'a state that does not decode is ignored; the last good one stays',
    () async {
      await controller().bootstrap();
      daemon.push(const AgentViewState(phase: AuthPhase.signedIn));
      await pumpEventQueue();
      daemon.conn.send(
        const MuxMessage(MuxType.agentState, fields: {'state': 'garbage'}),
      );
      await pumpEventQueue();
      expect(container.read(agentControllerProvider).phase, AuthPhase.signedIn);
    },
  );
}
