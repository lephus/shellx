@TestOn('mac-os || linux')
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import 'support/e2e_world.dart';

final String? relayUrl = Platform.environment['SHELLX_E2E_RELAY'];

Uint8List keys(String text) => Uint8List.fromList(utf8.encode(text));

Matcher pairingFails(PairingFailure failure) => throwsA(
  isA<PairingException>().having((e) => e.failure, 'failure', failure),
);

Matcher connectFails(MachineConnectionFailure failure) => throwsA(
  isA<MachineConnectionException>().having(
    (e) => e.failure,
    'failure',
    failure,
  ),
);

/// A fresh account and devices for one test, torn down afterwards.
Future<E2eWorld> newWorld() async {
  final world = await E2eWorld.create(Uri.parse(relayUrl!));
  addTearDown(world.dispose);
  return world;
}

void main() {
  group(
    'end-to-end over a real relay',
    () {
      test('pair → open session → echo → drop connection → re-attach replays '
          'missed output', () async {
        final world = await newWorld();
        final device = await world.pair(world.phone, registered: false);
        expect(device.mobileId, world.phone.deviceId);

        final machine = world.phone.service.machine(world.agentId);
        await machine.connect();
        final tab = await machine.openSession(cols: 80, rows: 24);
        final output = TabText(tab);
        machine.input(tab.id, keys('echo hello\n'));
        await waitUntil(
          () => output.text.contains('hello'),
          reason: 'no "hello" in ${jsonEncode(output.text)}',
        );

        machine.input(tab.id, keys('echo started; sleep 1; echo after-drop\n'));
        await waitUntil(() => output.text.contains('started'));
        world.phone.connector.blocked = true;
        await world.phone.connector.drop();
        await waitUntil(
          () => world.agent.activeChannelCount == 0,
          reason: 'agent did not notice the phone going offline',
        );
        await Future<void>.delayed(const Duration(seconds: 2));
        expect(output.text, isNot(contains('after-drop')));

        world.phone.connector.blocked = false;
        world.phone.relay.reconnectNow();
        await waitUntil(
          () => output.text.contains('after-drop'),
          timeout: const Duration(seconds: 40),
          reason: 'missed output was not replayed: ${jsonEncode(output.text)}',
        );
        expect(tab.isAttached, isTrue);
        expect(
          world.sessions.sessions.single.attachedMobileId,
          world.phone.deviceId,
        );
      });

      test('a phone whose key the agent does not trust is rejected', () async {
        final world = await newWorld();
        final machine = world.intruder.service.machine(world.agentId);
        await expectLater(
          machine.connect(),
          connectFails(MachineConnectionFailure.untrusted),
        );
        expect(await world.intruder.pinned.find(world.agentId), isNull);
        expect(await world.trusted.find(world.intruder.deviceId), isNull);
      });

      test('an expired pairing code is rejected', () async {
        final world = await newWorld();
        final uri = world.agent.startPairing();
        world.clockSkew += const Duration(minutes: 6);
        await expectLater(
          world.intruder.service.pair(uri),
          pairingFails(PairingFailure.invalidOrExpired),
        );
        expect(await world.trusted.find(world.intruder.deviceId), isNull);
      });

      test('a wrong pairing secret is rejected', () async {
        final world = await newWorld();
        final real = world.agent.startPairing();
        final forged = PairingUri(
          agentDeviceId: real.agentDeviceId,
          agentPublicKey: real.agentPublicKey,
          secret: Uint8List.fromList(List.filled(32, 7)),
        );
        await expectLater(
          world.intruder.service.pair(forged),
          pairingFails(PairingFailure.invalidOrExpired),
        );
        expect(await world.trusted.find(world.intruder.deviceId), isNull);
      });

      test('deleting the account revokes the agent (AgentRevoked)', () async {
        final world = await newWorld();
        final revoked = world.agent.events.firstWhere((e) => e is AgentRevoked);
        await world.phone.api.deleteAccount(E2eWorld.password);
        await revoked.timeout(const Duration(seconds: 10));
        expect(world.agent.activeChannelCount, 0);
      });

      test('unpair, re-pair, agent reconnects: the old pairing\'s tombstone '
          'does not remove the new pairing', () async {
        final world = await newWorld();
        final phoneId = world.phone.deviceId;
        final first = await world.pair(world.phone);
        await world.phone.service.unpair(world.agentId);
        await waitUntil(
          () async => await world.trusted.find(phoneId) == null,
          reason: 'the agent kept trusting the unpaired phone',
        );

        // Re-pair while the relay still keeps the first pairing's tombstone
        // (the agent's POST of the new pairing is held), then reconnect
        // the agent: the hub replays that tombstone on connect.
        world.agentHttp.hold();
        final second = await world.pair(world.phone, registered: false);
        expect(second.pairingId, isNot(first.pairingId));
        final replayed = world.agentRelay.frames.firstWhere(
          (frame) =>
              frame is EventFrame &&
              frame.event['event'] == 'pairing_removed' &&
              frame.event['mobile_id'] == phoneId &&
              frame.event['pairing_id'] == first.pairingId,
        );
        await world.agentConnector.drop();
        await replayed.timeout(const Duration(seconds: 15));

        // The agent answers this handshake after handling the replay.
        await world.phone.service.machine(world.agentId).connect();
        expect(
          (await world.trusted.find(phoneId))?.pairingId,
          second.pairingId,
        );

        // Once the POST lands the relay records the new pairing too.
        world.agentHttp.release();
        await waitUntil(
          () => world.isPairingRecorded(world.phone),
          reason: 'the relay did not record the new pairing',
        );
        await waitUntil(
          () async => (await world.trusted.unregistered()).isEmpty,
          reason: 'the agent did not see its POST acknowledged',
        );
        expect(
          (await world.trusted.find(phoneId))?.pairingId,
          second.pairingId,
        );
      });

      test('revoked on the agent: the phone\'s next connect is untrusted and '
          'forgets the pin', () async {
        final world = await newWorld();
        await world.pair(world.phone);
        final machine = world.phone.service.machine(world.agentId);
        await machine.connect();

        await world.agent.revoke(world.phone.deviceId);
        expect(await world.trusted.find(world.phone.deviceId), isNull);
        expect(await world.isPairingRecorded(world.phone), isFalse);

        // The relay's pairing_removed only drops the phone's channel: the
        // pin goes when the agent itself answers `untrusted` (spec §12).
        await waitUntil(
          () => machine.state is! MachineReady,
          reason: 'the phone kept its channel after the revoke',
        );
        expect(await world.phone.pinned.find(world.agentId), isNotNull);
        await expectLater(
          machine.connect(),
          connectFails(MachineConnectionFailure.untrusted),
        );
        expect(await world.phone.pinned.find(world.agentId), isNull);
      });
    },
    skip: relayUrl == null
        ? 'Set SHELLX_E2E_RELAY=http://127.0.0.1:8787 (npm run dev in relay/) '
              'to run'
        : null,
  );
}
