import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

const _agentId = '11111111-2222-3333-4444-555555555555';
const _mobileId = '66666666-7777-8888-9999-aaaaaaaaaaaa';

/// Runs a full handshake the way mobile (initiator) and agent (responder)
/// will, passing every Noise message through ChannelPayload encoding.
Future<(SecureChannel mobile, SecureChannel agent, NoiseTransport mobileRaw)>
_connect({NoisePattern pattern = NoisePattern.ik, Uint8List? psk}) async {
  final mobileKeys = await NoiseKeyPair.generate();
  final agentKeys = await NoiseKeyPair.generate();
  final prologue = buildPrologue(
    agentDeviceId: _agentId,
    mobileDeviceId: _mobileId,
  );
  final initiator = NoiseHandshake.initiator(
    pattern: pattern,
    localStatic: mobileKeys,
    remoteStatic: agentKeys.publicKey,
    prologue: prologue,
    psk: psk,
  );
  final responder = NoiseHandshake.responder(
    pattern: pattern,
    localStatic: agentKeys,
    prologue: prologue,
    psk: psk,
  );

  final hs1Kind = pattern == NoisePattern.ik
      ? PayloadKind.hs1Ik
      : PayloadKind.hs1IkPsk2;
  final hs1 = ChannelPayload(
    hs1Kind,
    await initiator.writeMessage(
      Hs1Payload(
        proto: kAppProtocolVersion,
        app: '1.0.0',
        name: 'Pixel',
        platform: DevicePlatform.android,
      ).encode(),
    ),
  ).encode();

  final received1 = ChannelPayload.decode(hs1);
  expect(received1.kind, hs1Kind);
  final hs1Payload = Hs1Payload.decode(
    await responder.readMessage(received1.noiseMessage),
  );
  expect(hs1Payload.name, 'Pixel');
  expect(responder.remoteStatic, mobileKeys.publicKey);

  final hs2 = ChannelPayload(
    PayloadKind.hs2,
    await responder.writeMessage(
      Hs2Payload(
        proto: kAppProtocolVersion,
        app: '1.0.0',
        status: HandshakeStatus.ok,
      ).encode(),
    ),
  ).encode();
  final received2 = ChannelPayload.decode(hs2);
  expect(received2.kind, PayloadKind.hs2);
  final hs2Payload = Hs2Payload.decode(
    await initiator.readMessage(received2.noiseMessage),
  );
  expect(hs2Payload.status, HandshakeStatus.ok);

  final mobileTransport = initiator.split();
  return (
    SecureChannel(mobileTransport),
    SecureChannel(responder.split()),
    mobileTransport,
  );
}

void main() {
  group('ChannelPayload', () {
    test('kind wire values', () {
      expect(PayloadKind.values.map((k) => k.wire), [1, 2, 3, 4]);
    });

    test('encode prefixes the kind byte and decode splits it', () {
      for (final kind in PayloadKind.values) {
        final payload = ChannelPayload(kind, Uint8List.fromList([9, 8, 7]));
        final bytes = payload.encode();
        expect(bytes, [kind.wire, 9, 8, 7]);
        final decoded = ChannelPayload.decode(bytes);
        expect(decoded.kind, kind);
        expect(decoded.noiseMessage, [9, 8, 7]);
      }
    });

    test('rejects empty payloads and unknown kinds', () {
      expect(
        () => ChannelPayload.decode(Uint8List(0)),
        throwsA(isA<FrameFormatException>()),
      );
      expect(
        () => ChannelPayload.decode(Uint8List.fromList([0])),
        throwsA(isA<FrameFormatException>()),
      );
      expect(
        () => ChannelPayload.decode(Uint8List.fromList([5, 1])),
        throwsA(isA<FrameFormatException>()),
      );
    });
  });

  group('buildPrologue', () {
    test('is "shellx/1" || agent uuid || mobile uuid', () {
      final prologue = buildPrologue(
        agentDeviceId: _agentId,
        mobileDeviceId: _mobileId,
      );
      expect(prologue, hasLength(40));
      expect(
        bytesToHex(prologue),
        '7368656c6c782f31'
        '11111111222233334444555555555555'
        '66666666777788889999aaaaaaaaaaaa',
      );
    });

    test('order matters and bad uuids throw', () {
      expect(
        buildPrologue(agentDeviceId: _mobileId, mobileDeviceId: _agentId),
        isNot(
          buildPrologue(agentDeviceId: _agentId, mobileDeviceId: _mobileId),
        ),
      );
      expect(
        () => buildPrologue(agentDeviceId: 'x', mobileDeviceId: _mobileId),
        throwsFormatException,
      );
    });
  });

  group('SecureChannel', () {
    test('seal produces a TRANSPORT payload that the peer opens', () async {
      final (mobile, agent, _) = await _connect();
      final sealed = await mobile.seal([
        const SessionOpen(cols: 80, rows: 24),
        InputMessage(id: 1, data: Uint8List.fromList([0x03])),
      ]);
      final payload = ChannelPayload.decode(sealed);
      expect(payload.kind, PayloadKind.transport);
      expect(await agent.open(payload.noiseMessage), [
        const SessionOpen(cols: 80, rows: 24),
        InputMessage(id: 1, data: Uint8List.fromList([0x03])),
      ]);

      final reply = ChannelPayload.decode(
        await agent.seal([const SessionOpened(id: 1, index: 1, shell: 'zsh')]),
      );
      expect(await mobile.open(reply.noiseMessage), [
        const SessionOpened(id: 1, index: 1, shell: 'zsh'),
      ]);
    });

    test('pairing flow: IKpsk2 then pair.confirm', () async {
      final psk = Uint8List.fromList(List.generate(32, (i) => i));
      final (mobile, agent, _) = await _connect(
        pattern: NoisePattern.ikPsk2,
        psk: psk,
      );
      final sealed = ChannelPayload.decode(
        await mobile.seal([const PairConfirm()]),
      );
      expect(await agent.open(sealed.noiseMessage), [const PairConfirm()]);
    });

    test('three full 16 KiB output chunks fit one relay frame', () async {
      final (_, agent, _) = await _connect();
      final sealed = await agent.seal([
        for (var i = 0; i < 3; i++)
          OutputMessage(id: i, seq: 0, data: Uint8List(kMaxOutputChunk)),
      ]);
      final frame = DataFrame(
        peer: _mobileId,
        channel: ChannelId.random(),
        payload: sealed,
      );
      expect(frame.encode().length, lessThanOrEqualTo(kMaxFrameBytes));
    });

    test('rejects batches that would not fit one relay frame', () async {
      final (_, agent, _) = await _connect();
      expect(kMaxSealedBatchBytes, 65493);
      await expectLater(
        agent.seal([
          for (var i = 0; i < 4; i++)
            OutputMessage(id: i, seq: 0, data: Uint8List(kMaxOutputChunk)),
        ]),
        throwsArgumentError,
      );
    });

    test('tampered ciphertext throws NoiseException', () async {
      final (mobile, agent, _) = await _connect();
      final payload = ChannelPayload.decode(
        await mobile.seal([const SessionList()]),
      );
      final tampered = Uint8List.fromList(payload.noiseMessage)..[3] ^= 0x80;
      await expectLater(agent.open(tampered), throwsA(isA<NoiseException>()));
    });

    test('authentic but non-batch plaintext throws FormatException', () async {
      final (_, agent, mobileRaw) = await _connect();
      final ciphertext = await mobileRaw.encrypt(
        Uint8List.fromList([0x01]),
      ); // CBOR int 1
      await expectLater(agent.open(ciphertext), throwsFormatException);
    });
  });
}
