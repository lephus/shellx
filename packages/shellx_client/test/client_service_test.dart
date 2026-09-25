import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:http/http.dart' as http;
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import 'support/drive.dart';
import 'support/harness.dart';

Matcher pairingFailure(PairingFailure failure) =>
    isA<PairingException>().having((e) => e.failure, 'failure', failure);

Matcher pairingFails(PairingFailure failure) =>
    throwsA(pairingFailure(failure));

Matcher apiFails(int status) =>
    throwsA(isA<ApiException>().having((e) => e.status, 'status', status));

/// An old pairing id of the phone: older than [phonePairingId].
const oldPairingId = '01910000-0000-7000-8000-000000000000';

/// DATA payloads of [kind] the phone sent to the agent.
Iterable<Uint8List> fromPhone(Harness h, PayloadKind kind) => h.relay.delivered
    .where((d) => d.from == phoneId && d.payload.first == kind.wire)
    .map((d) => d.payload);

/// Replaces the real agent with one that answers every pairing HS1 with
/// [plaintext] as HS2 payload, encrypted under [secret] (so the phone can
/// read it).
void scriptAgent(Harness h, Uint8List secret, Uint8List plaintext) {
  h.agent.stop();
  settle(h.async);
  final raw = RelayConnection(
    wsUri: h.relay.wsUri,
    token: () => h.agentDevice.token,
    connector: h.relay.connector,
  );
  raw.frames.listen((frame) async {
    if (frame is! DataFrame) return;
    final hello = ChannelPayload.decode(frame.payload);
    if (hello.kind != PayloadKind.hs1IkPsk2) return;
    final responder = NoiseHandshake.responder(
      pattern: NoisePattern.ikPsk2,
      localStatic: h.keys.agent,
      prologue: buildPrologue(
        agentDeviceId: agentId,
        mobileDeviceId: frame.peer,
      ),
      psk: secret,
    );
    await responder.readMessage(hello.noiseMessage);
    final reply = await responder.writeMessage(plaintext);
    raw.send(
      DataFrame(
        peer: frame.peer,
        channel: frame.channel,
        payload: ChannelPayload(PayloadKind.hs2, reply).encode(),
      ),
    );
  });
  raw.start();
  settle(h.async);
}

/// Sends `pairing_removed` for the phone's pairing [pairingId] to both ends,
/// as the hub does — with an old id, as when the agent's take-back or revoke
/// DELETE of an older pairing races a re-pair.
void sendPairingRemoved(Harness h, String pairingId) {
  final event = {
    'event': 'pairing_removed',
    'agent_id': agentId,
    'mobile_id': phoneId,
    'pairing_id': pairingId,
  };
  h.relay.sendEvent(agentId, event);
  h.relay.sendEvent(phoneId, event);
  settle(h.async);
}

http.Response relayError(int status) => http.Response(
  jsonEncode({
    'error': {'code': 'test_$status', 'message': 'Injected by the test'},
  }),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  late TestKeys keys;
  setUpAll(() async => keys = await TestKeys.generate());

  group('pair', () {
    test(
      'pair pins the agent key, the agent trusts the phone, IK then works',
      () {
        fakeAsync((async) {
          final h = Harness(async, keys, paired: false);
          final uri = h.agent.startPairing();
          h.run(h.phone.pair(uri));
          settle(async);

          final pin = h.run(h.phonePins.find(agentId))!;
          expect(pin.publicKey, keys.agent.publicKey);
          final trusted = h.run(h.trusted.find(phoneId))!;
          expect(trusted.publicKey, keys.phone.publicKey);
          expect(trusted.name, 'Test Phone');
          expect(h.agentEvents.whereType<MobilePaired>(), hasLength(1));
          expect(h.relay.pairings, {(agentId, phoneId): trusted.pairingId});
          expect(fromPhone(h, PayloadKind.hs1IkPsk2), hasLength(1));
          expect(fromPhone(h, PayloadKind.transport), hasLength(1));

          h.run(h.phoneMachine.connect());
          expect(h.phoneMachine.state, isA<MachineReady>());
        });
      },
    );

    test('a QR from a machine of another account, or naming a phone, is '
        'refused before any handshake', () {
      fakeAsync((async) {
        final h = Harness(async, keys, paired: false);
        final foreign = PairingUri(
          agentDeviceId: foreignAgentId,
          agentPublicKey: keys.other.publicKey,
          secret: Uint8List(32),
        );
        expect(
          () => h.run(h.phone.pair(foreign)),
          pairingFails(PairingFailure.notInAccount),
        );
        final aPhone = PairingUri(
          agentDeviceId: tabletId,
          agentPublicKey: keys.tablet.publicKey,
          secret: Uint8List(32),
        );
        expect(
          () => h.run(h.phone.pair(aPhone)),
          pairingFails(PairingFailure.notInAccount),
        );
        expect(h.relay.delivered, isEmpty);
      });
    });

    test('an error listing the devices propagates', () {
      fakeAsync((async) {
        final h = Harness(async, keys, paired: false);
        final uri = h.agent.startPairing();
        h.phoneHttpFault = (_) => relayError(503);
        expect(() => h.run(h.phone.pair(uri)), apiFails(503));
        expect(h.relay.delivered, isEmpty);
      });
    });

    test('a wrong pairing secret is invalidOrExpired', () {
      fakeAsync((async) {
        final h = Harness(async, keys, paired: false);
        final real = h.agent.startPairing();
        final forged = PairingUri(
          agentDeviceId: real.agentDeviceId,
          agentPublicKey: real.agentPublicKey,
          secret: Uint8List.fromList(List.filled(32, 1)),
        );
        expect(
          () => h.run(h.phone.pair(forged)),
          pairingFails(PairingFailure.invalidOrExpired),
        );
        expect(h.run(h.phonePins.list()), isEmpty);
        expect(h.run(h.trusted.find(phoneId)), isNull);
        expect(fromPhone(h, PayloadKind.transport), isEmpty);
      });
    });

    test('an expired or cancelled code is invalidOrExpired', () {
      fakeAsync((async) {
        final h = Harness(async, keys, paired: false);
        final expired = h.agent.startPairing();
        h.now = h.now.add(const Duration(minutes: 5, seconds: 1));
        expect(
          () => h.run(h.phone.pair(expired)),
          pairingFails(PairingFailure.invalidOrExpired),
        );

        final cancelled = h.agent.startPairing();
        h.agent.cancelPairing();
        expect(
          () => h.run(h.phone.pair(cancelled)),
          pairingFails(PairingFailure.invalidOrExpired),
        );
        expect(h.run(h.trusted.find(phoneId)), isNull);
      });
    });

    test('a used code cannot pair a second phone', () {
      fakeAsync((async) {
        final h = Harness(async, keys, paired: false);
        final uri = h.agent.startPairing();
        h.run(h.phone.pair(uri));
        expect(
          () => h.run(h.tablet.pair(uri)),
          pairingFails(PairingFailure.invalidOrExpired),
        );
        expect(h.run(h.tabletPins.list()), isEmpty);
        expect(h.run(h.trusted.find(tabletId)), isNull);
      });
    });

    test('pairing with an offline agent fails with agentOffline', () {
      fakeAsync((async) {
        final h = Harness(async, keys, paired: false);
        final uri = h.agent.startPairing();
        h.agent.stop();
        settle(async);
        expect(
          () => h.run(h.phone.pair(uri)),
          pairingFails(PairingFailure.agentOffline),
        );
      });
    });

    test('no answer (e.g. a QR with the wrong agent key) times out', () {
      fakeAsync((async) {
        final h = Harness(async, keys, paired: false);
        final real = h.agent.startPairing();
        final wrongKey = PairingUri(
          agentDeviceId: agentId,
          agentPublicKey: keys.other.publicKey,
          secret: real.secret,
        );
        final started = async.elapsed;
        expect(
          () => h.run(h.phone.pair(wrongKey)),
          pairingFails(PairingFailure.timeout),
        );
        expect(
          async.elapsed - started,
          greaterThanOrEqualTo(const Duration(seconds: 10)),
        );
        expect(h.run(h.phonePins.list()), isEmpty);
      });
    });

    test('with the relay down pairing fails with timeout at once', () {
      fakeAsync((async) {
        final h = Harness(async, keys, paired: false);
        final uri = h.agent.startPairing();
        h.phone.stop();
        settle(async);
        final started = async.elapsed;
        expect(
          () => h.run(h.phone.pair(uri)),
          pairingFails(PairingFailure.timeout),
        );
        expect(async.elapsed - started, lessThan(const Duration(seconds: 1)));
      });
    });

    test('the relay dropping during the pairing handshake fails at once with '
        'timeout', () {
      fakeAsync((async) {
        final h = Harness(async, keys, paired: false);
        final uri = h.agent.startPairing();
        h.relay.onData = (from, to, frame) => to == agentId ? null : frame;
        Object? error;
        h.phone.pair(uri).catchError((Object e) {
          error = e;
        });
        settle(async);
        expect(error, isNull);
        h.disconnectPhone();
        expect(error, pairingFailure(PairingFailure.timeout));
        expect(h.run(h.phonePins.list()), isEmpty);
      });
    });

    test('the agent going offline during the pairing handshake fails at once '
        'with agentOffline', () {
      fakeAsync((async) {
        final h = Harness(async, keys, paired: false);
        final uri = h.agent.startPairing();
        h.relay.onData = (from, to, frame) => to == agentId ? null : frame;
        Object? error;
        h.phone.pair(uri).catchError((Object e) {
          error = e;
        });
        settle(async);
        expect(error, isNull);
        h.agent.stop();
        settle(async);
        expect(error, pairingFailure(PairingFailure.agentOffline));
      });
    });

    final answers = <(String, Uint8List Function(), PairingFailure)>[
      (
        'proto_unsupported',
        () => Hs2Payload(
          proto: kAppProtocolVersion,
          app: '9.0.0',
          status: HandshakeStatus.protoUnsupported,
        ).encode(),
        PairingFailure.protocolUnsupported,
      ),
      (
        'ok with another protocol version',
        () => Hs2Payload(
          proto: kAppProtocolVersion + 1,
          app: '9.0.0',
          status: HandshakeStatus.ok,
        ).encode(),
        PairingFailure.protocolUnsupported,
      ),
      (
        'an undecodable payload',
        () => Uint8List.fromList([0xff, 0x00, 0x01]),
        PairingFailure.protocolUnsupported,
      ),
      (
        'pairing_invalid',
        () => Hs2Payload(
          proto: kAppProtocolVersion,
          app: '1.0.0',
          status: HandshakeStatus.pairingInvalid,
        ).encode(),
        PairingFailure.invalidOrExpired,
      ),
      (
        'untrusted',
        () => Hs2Payload(
          proto: kAppProtocolVersion,
          app: '1.0.0',
          status: HandshakeStatus.untrusted,
        ).encode(),
        PairingFailure.invalidOrExpired,
      ),
    ];
    for (final (answer, plaintext, failure) in answers) {
      test('a readable HS2 with $answer fails with ${failure.name}, sends no '
          'pair.confirm and pins nothing', () {
        fakeAsync((async) {
          final h = Harness(async, keys, paired: false);
          final secret = Uint8List.fromList(List.generate(32, (i) => i));
          scriptAgent(h, secret, plaintext());
          final uri = PairingUri(
            agentDeviceId: agentId,
            agentPublicKey: keys.agent.publicKey,
            secret: secret,
          );
          expect(() => h.run(h.phone.pair(uri)), pairingFails(failure));
          expect(fromPhone(h, PayloadKind.hs1IkPsk2), hasLength(1));
          expect(fromPhone(h, PayloadKind.transport), isEmpty);
          expect(h.run(h.phonePins.list()), isEmpty);
        });
      });
    }

    test('re-pairing a machine the phone is connected to drops the old '
        'channel: the next request handshakes again', () {
      fakeAsync((async) {
        final h = Harness(async, keys);
        h.run(h.phoneMachine.connect());
        final uri = h.agent.startPairing();
        h.run(h.phone.pair(uri));
        settle(async);
        final trusted = h.run(h.trusted.find(phoneId))!;
        expect(trusted.pairingId, isNot(phonePairingId));
        expect(h.relay.pairings[(agentId, phoneId)], trusted.pairingId);
        expect(h.phoneMachine.state, isA<MachineIdle>());

        expect(h.run(h.phoneMachine.listSessions()), isEmpty);
        expect(h.phoneMachine.state, isA<MachineReady>());
        expect(fromPhone(h, PayloadKind.hs1Ik), hasLength(2));
      });
    });

    test('re-pairing with a tab open completes the pairing, then the tab '
        're-attaches by itself on a new channel', () {
      fakeAsync((async) {
        final h = Harness(async, keys);
        final tab = h.run(h.phoneMachine.openSession(cols: 80, rows: 24));
        final recorder = TabRecorder(tab);
        h.pty.emit('before ');
        settle(async);

        h.run(h.phone.pair(h.agent.startPairing()));
        settle(async);
        // pair.confirm reached the agent before the new IK handshake.
        expect(h.agentEvents.whereType<MobilePaired>(), hasLength(1));
        expect(
          h.run(h.trusted.find(phoneId))!.pairingId,
          isNot(phonePairingId),
        );
        expect(fromPhone(h, PayloadKind.hs1Ik), hasLength(2));
        expect(h.phoneMachine.state, isA<MachineReady>());

        h.pty.emit('after');
        settle(async);
        expect(recorder.text, 'before after');
        expect(tab.isAttached, isTrue);
        expect(h.sessions.sessions.single.attachedMobileId, phoneId);
      });
    });

    test('a re-pair while the phone is still handshaking with the machine '
        'makes that handshake start over instead of installing the channel '
        'the agent replaced', () {
      fakeAsync((async) {
        final h = Harness(async, keys);
        ChannelId? firstIk;
        DataFrame? late;
        h.relay.onData = (from, to, frame) {
          final kind = frame.payload.first;
          if (from == phoneId && kind == PayloadKind.hs1Ik.wire) {
            firstIk ??= frame.channel;
          }
          if (from == agentId &&
              frame.channel == firstIk &&
              kind == PayloadKind.hs2.wire &&
              late == null) {
            late = frame; // Held back: delivered after the pairing.
            return null;
          }
          return frame;
        };
        final connecting = h.phoneMachine.connect();
        settle(async);
        expect(late, isNotNull);
        expect(h.phoneMachine.state, isA<MachineConnecting>());

        // The agent replaces the IK channel with the pairing channel, and
        // drops that one after pair.confirm.
        h.run(h.phone.pair(h.agent.startPairing()));
        h.phoneMachine.handleFrame(late!);
        h.run(connecting);

        expect(h.phoneMachine.state, isA<MachineReady>());
        expect(h.run(h.phoneMachine.listSessions()), isEmpty); // Not dead.
        expect(fromPhone(h, PayloadKind.hs1Ik), hasLength(2));
      });
    });

    test('a pairing that gets no HS2 after the agent took its HS1 still '
        'drops the machine channel; the open tab re-attaches', () {
      fakeAsync((async) {
        final h = Harness(async, keys);
        final tab = h.run(h.phoneMachine.openSession(cols: 80, rows: 24));
        final recorder = TabRecorder(tab);
        h.pty.emit('before ');
        settle(async);

        ChannelId? pairing;
        h.relay.onData = (from, to, frame) {
          if (from == phoneId &&
              frame.payload.first == PayloadKind.hs1IkPsk2.wire) {
            pairing = frame.channel;
          }
          // The agent answers (and replaces the phone's channel), but its
          // HS2 is lost on the way.
          return from == agentId && frame.channel == pairing ? null : frame;
        };
        expect(
          () => h.run(h.phone.pair(h.agent.startPairing())),
          pairingFails(PairingFailure.timeout),
        );
        h.pty.emit('after');
        settle(async);

        expect(recorder.text, 'before after');
        expect(fromPhone(h, PayloadKind.hs1Ik), hasLength(2));
        expect(h.phoneMachine.state, isA<MachineReady>());
        expect(tab.isAttached, isTrue);
        expect(h.sessions.sessions.single.attachedMobileId, phoneId);
      });
    });
  });

  test('machine() needs a pin and returns one instance per agent', () {
    fakeAsync((async) {
      final unpaired = Harness(async, keys, paired: false);
      expect(() => unpaired.phone.machine(agentId), throwsStateError);
      final h = Harness(async, keys);
      expect(h.phone.machine(agentId), same(h.phone.machine(agentId)));
    });
  });

  test('presence and isOnline follow the agent', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      final seen = <(String, bool)>[];
      h.phone.presence.listen((p) => seen.add((p.deviceId, p.online)));
      expect(h.phone.isOnline(agentId), isTrue);
      h.agent.stop();
      settle(async);
      expect(h.phone.isOnline(agentId), isFalse);
      expect(seen, [(agentId, false)]);
    });
  });

  group('unpair', () {
    test('unpair forgets the pin, deletes the pairing and the agent stops '
        'trusting the phone', () {
      fakeAsync((async) {
        final h = Harness(async, keys);
        final tab = h.run(h.phoneMachine.openSession(cols: 80, rows: 24));
        h.run(h.phone.unpair(agentId));
        settle(async);

        expect(h.run(h.phonePins.find(agentId)), isNull);
        expect(() => h.phone.machine(agentId), throwsStateError);
        expect(tab.isAttached, isFalse);
        expect(
          h.relay.requests,
          contains('DELETE /v1/pairings/$agentId/$phoneId'),
        );
        expect(h.relay.pairings.keys, [(agentId, tabletId)]);
        expect(h.run(h.trusted.find(phoneId)), isNull);
        expect(h.run(h.trusted.find(tabletId)), isNotNull);
        expect(h.sessions.sessions, hasLength(1)); // Sessions are not closed.
        expect(h.sessions.sessions.single.attachedMobileId, isNull);
      });
    });

    test('the DELETE is retried on 5xx and network errors', () {
      fakeAsync((async) {
        final h = Harness(async, keys);
        var deletes = 0;
        h.phoneHttpFault = (request) {
          if (request.method != 'DELETE') return null;
          deletes++;
          return switch (deletes) {
            1 => relayError(500),
            2 => throw http.ClientException('offline'),
            _ => null,
          };
        };
        h.run(h.phone.unpair(agentId));
        settle(async);

        expect(deletes, 3);
        expect(h.relay.pairings.keys, [(agentId, tabletId)]);
        expect(h.run(h.trusted.find(phoneId)), isNull);
      });
    });

    test(
      'the DELETE gives up after three failed attempts; the pin is gone',
      () {
        fakeAsync((async) {
          final h = Harness(async, keys);
          var deletes = 0;
          h.phoneHttpFault = (request) {
            if (request.method != 'DELETE') return null;
            deletes++;
            return relayError(503);
          };
          expect(() => h.run(h.phone.unpair(agentId)), apiFails(503));
          expect(deletes, 3);
          expect(h.run(h.phonePins.find(agentId)), isNull);
          async.elapse(const Duration(seconds: 30));
          expect(deletes, 3);
        });
      },
    );

    test('a 4xx answer to the DELETE propagates at once', () {
      fakeAsync((async) {
        final h = Harness(async, keys);
        var deletes = 0;
        h.phoneHttpFault = (request) {
          if (request.method != 'DELETE') return null;
          deletes++;
          return relayError(403);
        };
        expect(() => h.run(h.phone.unpair(agentId)), apiFails(403));
        expect(deletes, 1);
        expect(h.run(h.phonePins.find(agentId)), isNull);
      });
    });
  });

  group('pairing_removed', () {
    test('for an older pairing the agent no longer uses: the pin stays and '
        'the next connect succeeds', () {
      fakeAsync((async) {
        final h = Harness(async, keys);
        h.run(h.phoneMachine.connect());
        sendPairingRemoved(h, oldPairingId);

        expect(h.run(h.phonePins.find(agentId)), isNotNull);
        expect(h.phoneMachine.state, isA<MachineIdle>());
        h.run(h.phoneMachine.connect());
        expect(h.phoneMachine.state, isA<MachineReady>());
        expect(h.run(h.phonePins.find(agentId)), isNotNull);
        expect(h.run(h.trusted.find(phoneId)), isNotNull);
      });
    });

    test('after the agent revokes the phone the pin stays until the next '
        'connect, which answers untrusted and forgets it', () {
      fakeAsync((async) {
        final h = Harness(async, keys);
        h.run(h.phoneMachine.connect());
        h.run(h.tabletMachine.connect());
        h.run(h.agent.revoke(phoneId));
        settle(async);

        expect(h.relay.pairings.keys, [(agentId, tabletId)]);
        expect(h.phoneMachine.state, isA<MachineIdle>()); // Channel dropped.
        expect(h.run(h.phonePins.find(agentId)), isNotNull);
        expect(h.phone.machine(agentId), same(h.phoneMachine));

        expect(
          () => h.run(h.phoneMachine.connect()),
          throwsA(
            isA<MachineConnectionException>().having(
              (e) => e.failure,
              'failure',
              MachineConnectionFailure.untrusted,
            ),
          ),
        );
        expect(h.run(h.phonePins.find(agentId)), isNull);
        expect(() => h.phone.machine(agentId), throwsStateError);

        expect(h.run(h.tabletPins.find(agentId)), isNotNull);
        expect(h.tabletMachine.state, isA<MachineReady>());
      });
    });

    test('while a tab is open the channel is dropped and re-verified at '
        'once; the tab re-attaches by itself', () {
      fakeAsync((async) {
        final h = Harness(async, keys);
        final tab = h.run(h.phoneMachine.openSession(cols: 80, rows: 24));
        final recorder = TabRecorder(tab);
        h.pty.emit('before ');
        settle(async);

        sendPairingRemoved(h, oldPairingId);
        expect(fromPhone(h, PayloadKind.hs1Ik), hasLength(2));
        expect(h.phoneMachine.state, isA<MachineReady>());
        h.pty.emit('after');
        settle(async);
        expect(recorder.text, 'before after');
        expect(tab.isAttached, isTrue);
        expect(h.sessions.sessions.single.attachedMobileId, phoneId);
      });
    });

    test('after the agent revokes the phone with a tab open, the phone asks '
        'again at once and forgets the pin on untrusted', () {
      fakeAsync((async) {
        final h = Harness(async, keys);
        final machine = h.phoneMachine;
        h.run(machine.openSession(cols: 80, rows: 24));
        settle(async);
        final states = <MachineConnectionState>[];
        machine.states.listen(states.add);

        h.run(h.agent.revoke(phoneId));
        async.elapse(const Duration(minutes: 1));

        expect(fromPhone(h, PayloadKind.hs1Ik), hasLength(2));
        expect(states.whereType<MachineConnecting>(), hasLength(1));
        expect(
          machine.state,
          isA<MachineFailed>().having(
            (s) => s.failure,
            'failure',
            MachineConnectionFailure.untrusted,
          ),
        );
        expect(h.run(h.phonePins.find(agentId)), isNull);
        expect(() => h.phone.machine(agentId), throwsStateError);
      });
    });

    test('for another phone changes nothing', () {
      fakeAsync((async) {
        final h = Harness(async, keys);
        h.run(h.phoneMachine.connect());
        h.relay.sendEvent(phoneId, {
          'event': 'pairing_removed',
          'agent_id': agentId,
          'mobile_id': tabletId,
          'pairing_id': tabletPairingId,
        });
        settle(async);
        expect(h.phoneMachine.state, isA<MachineReady>());
        expect(fromPhone(h, PayloadKind.hs1Ik), hasLength(1));
      });
    });
  });
}
