import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';

import 'drive.dart';
import 'fake_pty.dart';
import 'fake_relay.dart';

const userId = 'user-1';
const agentId = 'a0000000-0000-4000-8000-000000000001';
const phoneId = 'b0000000-0000-4000-8000-000000000002';
const tabletId = 'b0000000-0000-4000-8000-000000000003';
const foreignAgentId = 'c0000000-0000-4000-8000-000000000009';

/// Static keys, generated once per test file in `setUpAll`.
final class TestKeys {
  TestKeys._(this.agent, this.phone, this.tablet, this.other);
  final NoiseKeyPair agent, phone, tablet, other;

  static Future<TestKeys> generate() async => TestKeys._(
    await NoiseKeyPair.generate(),
    await NoiseKeyPair.generate(),
    await NoiseKeyPair.generate(),
    await NoiseKeyPair.generate(),
  );
}

/// A real [AgentService] (fake PTYs) and two real [ClientService]s (phone and
/// tablet, same account) wired through a [FakeRelay]. With `paired: true`
/// both phones are already trusted by the agent and have its key pinned.
final class Harness {
  Harness(this.async, this.keys, {bool paired = true}) {
    agentDevice = relay.addDevice(
      id: agentId,
      userId: userId,
      kind: DeviceKind.agent,
    );
    phoneDevice = relay.addDevice(
      id: phoneId,
      userId: userId,
      kind: DeviceKind.mobile,
    );
    tabletDevice = relay.addDevice(
      id: tabletId,
      userId: userId,
      kind: DeviceKind.mobile,
      name: 'Tablet',
    );
    relay.addDevice(
      id: foreignAgentId,
      userId: 'user-2',
      kind: DeviceKind.agent,
    );
    trusted = TrustedStore(InMemoryKeyValueStore());
    if (paired) {
      run(
        trusted.add(
          TrustedDevice(
            mobileId: phoneId,
            publicKey: keys.phone.publicKey,
            name: 'Test Phone',
            pairedAt: DateTime.utc(2026),
            pairingId: '01920000-0001-7000-8000-000000000000',
          ),
        ),
      );
      run(
        trusted.add(
          TrustedDevice(
            mobileId: tabletId,
            publicKey: keys.tablet.publicKey,
            name: 'Tablet',
            pairedAt: DateTime.utc(2026),
            pairingId: '01920000-0002-7000-8000-000000000000',
          ),
        ),
      );
    }
    startAgent();
    phonePins = PinnedStore(InMemoryKeyValueStore(), userId: userId);
    tabletPins = PinnedStore(InMemoryKeyValueStore(), userId: userId);
    phone = _client(phoneDevice, keys.phone, phonePins, paired: paired);
    tablet = _client(tabletDevice, keys.tablet, tabletPins, paired: paired);
    settle(async);
  }

  final FakeAsync async;
  final TestKeys keys;
  final relay = FakeRelay();
  final agentEvents = <AgentEvent>[];
  DateTime now = DateTime.utc(2026, 9, 25, 12);
  late final FakeDevice agentDevice;
  late final FakeDevice phoneDevice;
  late final FakeDevice tabletDevice;
  late final TrustedStore trusted;
  late final PinnedStore phonePins;
  late final PinnedStore tabletPins;
  late final ClientService phone;
  late final ClientService tablet;
  late FakePtyFactory ptys;
  late SessionManager sessions;
  late AgentService agent;
  int _agentStarts = 0;

  /// Drives [future] to completion in fake time.
  T run<T>(Future<T> future) => drive(async, future);

  /// The most recently spawned fake shell.
  FakePty get pty => ptys.ptys.last;

  MachineClient get phoneMachine => phone.machine(agentId);
  MachineClient get tabletMachine => tablet.machine(agentId);

  /// Starts a fresh agent process: new session manager (its own random
  /// first session id), same identity and trust list.
  void startAgent() {
    ptys = FakePtyFactory();
    sessions = SessionManager(
      ptyFactory: ptys,
      shellResolver: const FixedShellResolver(),
      homeDirectory: '/Users/test',
      baseEnvironment: const {},
      random: Random(1000 + _agentStarts++),
    );
    agent = AgentService(
      relay: RelayConnection(
        wsUri: relay.wsUri,
        token: () => agentDevice.token,
        connector: relay.connector,
        backoff: Backoff(random: Random(11)),
      ),
      api: ShellxApi(baseUri: relay.baseUri, httpClient: relay.httpClient)
        ..token = agentDevice.token,
      deviceId: agentId,
      identity: keys.agent,
      trusted: trusted,
      sessions: sessions,
      pairing: PairingCodeManager(now: () => now),
      appVersion: '1.0.0',
    );
    agent.events.listen(agentEvents.add);
    run(agent.start());
    settle(async);
  }

  /// Simulates quitting the agent (all sessions lost) and starting it again.
  void restartAgent() {
    agent.stop();
    sessions.closeAll();
    settle(async);
    startAgent();
  }

  /// Cuts the phone off the relay; it cannot reconnect until [reconnectPhone].
  void disconnectPhone() {
    relay.setReachable(phoneId, false);
    relay.dropConnection(phoneId);
    settle(async);
  }

  /// Lets the phone reconnect (backoff ≤ 1 s) and finish re-attaching.
  void reconnectPhone() {
    relay.setReachable(phoneId, true);
    async.elapse(const Duration(seconds: 3));
  }

  ClientService _client(
    FakeDevice device,
    NoiseKeyPair identity,
    PinnedStore pins, {
    required bool paired,
  }) {
    if (paired) {
      run(
        pins.add(
          PinnedMachine(
            agentId: agentId,
            publicKey: keys.agent.publicKey,
            pairedAt: DateTime.utc(2026),
          ),
        ),
      );
    }
    final service = ClientService(
      relay: RelayConnection(
        wsUri: relay.wsUri,
        token: () => device.token,
        connector: relay.connector,
        backoff: Backoff(random: Random(21)),
      ),
      api: ShellxApi(baseUri: relay.baseUri, httpClient: relay.httpClient)
        ..token = device.token,
      deviceId: device.id,
      userId: userId,
      identity: identity,
      pinned: pins,
      appVersion: '1.0.0',
      deviceName: device.name,
      platform: DevicePlatform.ios,
    );
    run(service.start());
    return service;
  }
}

/// Records every event of a tab.
final class TabRecorder {
  TabRecorder(ClientTab tab) {
    tab.events.listen(events.add);
  }

  final events = <TabEvent>[];

  String get text => events.whereType<TabOutput>().map((e) => e.text).join();
}
