import 'dart:math';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_agent/src/service/handshake_responder.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

const agentId = 'a0000000-0000-4000-8000-000000000001';
const phoneId = 'b0000000-0000-4000-8000-000000000002';
const tabletId = 'b0000000-0000-4000-8000-000000000003';

void main() {
  late NoiseKeyPair agentKey;
  late NoiseKeyPair phoneKey;
  late NoiseKeyPair otherKey;
  late TrustedStore trusted;
  late PairingCodeManager pairing;

  setUpAll(() async {
    agentKey = await NoiseKeyPair.generate();
    phoneKey = await NoiseKeyPair.generate();
    otherKey = await NoiseKeyPair.generate();
  });

  setUp(() async {
    trusted = TrustedStore(InMemoryKeyValueStore());
    pairing = PairingCodeManager();
    await trusted.add(
      TrustedDevice(
        mobileId: phoneId,
        publicKey: phoneKey.publicKey,
        name: 'Pixel',
        pairedAt: DateTime.utc(2026),
        pairingId: '01920000-0001-7000-8000-000000000000',
      ),
    );
  });

  HandshakeResponder responder({Random? random}) => HandshakeResponder(
    deviceId: agentId,
    identity: agentKey,
    appVersion: '1.0.0',
    trusted: trusted,
    pairing: pairing,
    random: random,
  );

  /// Runs HS1 from a phone. [claimedId] is the relay peer id the agent sees;
  /// [prologueId] is the id the phone put in its prologue.
  Future<(HandshakeAnswer?, NoiseHandshake)> hello({
    HandshakeResponder? using,
    NoisePattern pattern = NoisePattern.ik,
    Uint8List? psk,
    NoiseKeyPair? key,
    String claimedId = phoneId,
    String? prologueId,
    Uint8List? agentPublicKey,
    int proto = kAppProtocolVersion,
  }) async {
    final initiator = NoiseHandshake.initiator(
      pattern: pattern,
      localStatic: key ?? phoneKey,
      remoteStatic: agentPublicKey ?? agentKey.publicKey,
      prologue: buildPrologue(
        agentDeviceId: agentId,
        mobileDeviceId: prologueId ?? claimedId,
      ),
      psk: psk,
    );
    final message = await initiator.writeMessage(
      Hs1Payload(
        proto: proto,
        app: '1.0.0',
        name: 'Pixel',
        platform: DevicePlatform.android,
      ).encode(),
    );
    final answer = await (using ?? responder()).answer(
      mobileId: claimedId,
      kind: pattern == NoisePattern.ik
          ? PayloadKind.hs1Ik
          : PayloadKind.hs1IkPsk2,
      message: message,
    );
    return (answer, initiator);
  }

  Future<Hs2Payload> readReply(
    NoiseHandshake initiator,
    HandshakeAnswer answer,
  ) async {
    final payload = ChannelPayload.decode(answer.reply);
    expect(payload.kind, PayloadKind.hs2);
    return Hs2Payload.decode(await initiator.readMessage(payload.noiseMessage));
  }

  test('a trusted phone gets ok and a working transport', () async {
    final (answer, initiator) = await hello();
    expect(answer!.status, HandshakeStatus.ok);
    expect(answer.hello.name, 'Pixel');
    expect(answer.remoteStatic, phoneKey.publicKey);
    expect(answer.pairingSecret, isNull);
    final reply = await readReply(initiator, answer);
    expect(
      (reply.proto, reply.app, reply.status),
      (1, '1.0.0', HandshakeStatus.ok),
    );

    final phoneSide = SecureChannel(initiator.split());
    final agentSide = SecureChannel(answer.transport!);
    final sealed = ChannelPayload.decode(
      await phoneSide.seal([const SessionList()]),
    );
    expect(
      (await agentSide.open(sealed.noiseMessage)).single,
      isA<SessionList>(),
    );
  });

  test('an unknown key is untrusted and gets no transport', () async {
    final (answer, initiator) = await hello(key: otherKey);
    expect(answer!.status, HandshakeStatus.untrusted);
    expect(answer.transport, isNull);
    expect(
      (await readReply(initiator, answer)).status,
      HandshakeStatus.untrusted,
    );
  });

  test('trust binds the relay peer id: a trusted key under another id is '
      'untrusted', () async {
    final (answer, _) = await hello(claimedId: tabletId);
    expect(answer!.status, HandshakeStatus.untrusted);
  });

  test(
    'trust binds the key: the trusted id with another key is untrusted',
    () async {
      final (answer, _) = await hello(key: otherKey, claimedId: phoneId);
      expect(answer!.status, HandshakeStatus.untrusted);
    },
  );

  test('another protocol version gets proto_unsupported', () async {
    final (answer, initiator) = await hello(proto: 2);
    expect(answer!.status, HandshakeStatus.protoUnsupported);
    expect(answer.transport, isNull);
    expect(
      (await readReply(initiator, answer)).status,
      HandshakeStatus.protoUnsupported,
    );
  });

  test('a relay-swapped device id breaks the prologue: no answer', () async {
    final (answer, _) = await hello(claimedId: tabletId, prologueId: phoneId);
    expect(answer, isNull);
  });

  test('HS1 addressed to another agent key cannot be answered', () async {
    final (answer, _) = await hello(agentPublicKey: otherKey.publicKey);
    expect(answer, isNull);
  });

  test('garbage and non-HS1 kinds are ignored', () async {
    expect(
      await responder().answer(
        mobileId: phoneId,
        kind: PayloadKind.hs1Ik,
        message: Uint8List.fromList([1, 2, 3]),
      ),
      isNull,
    );
    expect(
      await responder().answer(
        mobileId: phoneId,
        kind: PayloadKind.transport,
        message: Uint8List(64),
      ),
      isNull,
    );
  });

  test(
    'pairing with the active code is accepted and remembers the code',
    () async {
      final secret = pairing.create().secret;
      final (answer, initiator) = await hello(
        pattern: NoisePattern.ikPsk2,
        psk: secret,
        key: otherKey,
        claimedId: tabletId,
      );
      expect(answer!.status, HandshakeStatus.ok);
      expect(answer.pairingSecret, secret);
      expect(answer.remoteStatic, otherKey.publicKey);
      expect((await readReply(initiator, answer)).status, HandshakeStatus.ok);
    },
  );

  test('pairing with a wrong code: the phone cannot decrypt HS2', () async {
    pairing.create();
    final wrong = Uint8List.fromList(List.filled(32, 9));
    final (answer, initiator) = await hello(
      pattern: NoisePattern.ikPsk2,
      psk: wrong,
      key: otherKey,
      claimedId: tabletId,
    );
    expect(answer!.status, HandshakeStatus.ok);
    await expectLater(
      initiator.readMessage(ChannelPayload.decode(answer.reply).noiseMessage),
      throwsA(isA<NoiseException>()),
    );
  });

  test(
    'pairing without an active code uses a random PSK and pairing_invalid',
    () async {
      // HandshakeResponder draws the random PSK from the injected Random.
      final expectedPsk = Uint8List.fromList(_bytesFrom(Random(99), 32));
      final (answer, initiator) = await hello(
        using: responder(random: Random(99)),
        pattern: NoisePattern.ikPsk2,
        psk: expectedPsk,
        key: otherKey,
        claimedId: tabletId,
      );
      expect(answer!.status, HandshakeStatus.pairingInvalid);
      expect(answer.transport, isNull);
      expect(answer.pairingSecret, isNull);
      expect(
        (await readReply(initiator, answer)).status,
        HandshakeStatus.pairingInvalid,
      );
    },
  );
}

List<int> _bytesFrom(Random random, int length) =>
    List.generate(length, (_) => random.nextInt(256));
