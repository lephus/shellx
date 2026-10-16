import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_core/src/noise/primitives.dart';
import 'package:shellx_core/src/noise/symmetric_state.dart';
import 'package:test/test.dart';

Uint8List _hex(String hex) => hexToBytes(hex);

Uint8List? _firstPsk(Map<String, dynamic> vector, String key) {
  final psks = vector[key] as List<dynamic>?;
  return psks == null || psks.isEmpty ? null : _hex(psks.first as String);
}

Future<(NoiseHandshake, NoiseHandshake)> _pair(
  NoisePattern pattern, {
  Uint8List? initiatorPsk,
  Uint8List? responderPsk,
  Uint8List? initiatorPrologue,
  Uint8List? responderPrologue,
  NoiseKeyPair? responderStatic,
  Uint8List? pinnedResponderKey,
}) async {
  final mobile = await NoiseKeyPair.generate();
  final agent = responderStatic ?? await NoiseKeyPair.generate();
  final prologue = Uint8List.fromList(utf8.encode('prologue'));
  final initiator = NoiseHandshake.initiator(
    pattern: pattern,
    localStatic: mobile,
    remoteStatic: pinnedResponderKey ?? agent.publicKey,
    prologue: initiatorPrologue ?? prologue,
    psk: initiatorPsk,
  );
  final responder = NoiseHandshake.responder(
    pattern: pattern,
    localStatic: agent,
    prologue: responderPrologue ?? prologue,
    psk: responderPsk,
  );
  return (initiator, responder);
}

/// Hand-crafts a Noise_IK message 1 the way `_writeMessage1` does, except the
/// `s` field claims [claimedStaticPublic] (e.g. a victim's public key) while
/// the `ss` DH is computed with [attackerStatic]'s real private key. A
/// responder must reject this: it cannot succeed unless the sender actually
/// holds the private key matching the identity it claims.
Future<Uint8List> _forgeMessage1({
  required Uint8List prologue,
  required Uint8List responderStaticPublic,
  required NoiseKeyPair attackerStatic,
  required Uint8List claimedStaticPublic,
  required NoiseKeyPair attackerEphemeral,
  Uint8List? payload,
}) async {
  final symmetric = NoiseSymmetricState(NoisePattern.ik.protocolName);
  symmetric.mixHash(prologue);
  symmetric.mixHash(responderStaticPublic); // pre-message "<- s"
  final out = BytesBuilder(copy: false);
  out.add(attackerEphemeral.publicKey);
  symmetric.mixHash(attackerEphemeral.publicKey);
  symmetric.mixKey(await dh(attackerEphemeral, responderStaticPublic)); // es
  out.add(await symmetric.encryptAndHash(claimedStaticPublic)); // forged s
  symmetric.mixKey(await dh(attackerStatic, responderStaticPublic)); // ss
  out.add(await symmetric.encryptAndHash(payload ?? Uint8List(0)));
  return out.takeBytes();
}

void main() {
  group('official cacophony vectors', () {
    final fixture =
        jsonDecode(File('test/fixtures/noise_vectors.json').readAsStringSync())
            as Map<String, dynamic>;
    final vectors = (fixture['vectors'] as List<dynamic>)
        .cast<Map<String, dynamic>>();

    test('fixture contains exactly the two ShellX protocols', () {
      expect(
        vectors.map((v) => v['protocol_name']),
        unorderedEquals(NoisePattern.values.map((p) => p.protocolName)),
      );
    });

    for (final vector in vectors) {
      test(vector['protocol_name'], () async {
        final pattern = NoisePattern.values.singleWhere(
          (p) => p.protocolName == vector['protocol_name'],
        );
        final initiatorStatic = await NoiseKeyPair.fromPrivateKey(
          _hex(vector['init_static'] as String),
        );
        final initiator = NoiseHandshake.initiator(
          pattern: pattern,
          localStatic: initiatorStatic,
          remoteStatic: _hex(vector['init_remote_static'] as String),
          prologue: _hex(vector['init_prologue'] as String),
          psk: _firstPsk(vector, 'init_psks'),
          ephemeral: await NoiseKeyPair.fromPrivateKey(
            _hex(vector['init_ephemeral'] as String),
          ),
        );
        final responderStatic = await NoiseKeyPair.fromPrivateKey(
          _hex(vector['resp_static'] as String),
        );
        final responder = NoiseHandshake.responder(
          pattern: pattern,
          localStatic: responderStatic,
          prologue: _hex(vector['resp_prologue'] as String),
          psk: _firstPsk(vector, 'resp_psks'),
          ephemeral: await NoiseKeyPair.fromPrivateKey(
            _hex(vector['resp_ephemeral'] as String),
          ),
        );
        final messages = (vector['messages'] as List<dynamic>)
            .cast<Map<String, dynamic>>();

        // Message 1: initiator -> responder.
        final payload1 = _hex(messages[0]['payload'] as String);
        final message1 = await initiator.writeMessage(payload1);
        expect(bytesToHex(message1), messages[0]['ciphertext']);
        expect(await responder.readMessage(message1), payload1);
        expect(responder.remoteStatic, initiatorStatic.publicKey);

        // Message 2: responder -> initiator.
        final payload2 = _hex(messages[1]['payload'] as String);
        final message2 = await responder.writeMessage(payload2);
        expect(bytesToHex(message2), messages[1]['ciphertext']);
        expect(await initiator.readMessage(message2), payload2);

        expect(initiator.isComplete, isTrue);
        expect(responder.isComplete, isTrue);
        expect(bytesToHex(initiator.handshakeHash), vector['handshake_hash']);
        expect(bytesToHex(responder.handshakeHash), vector['handshake_hash']);

        // Transport messages alternate, starting with the initiator.
        final initiatorTransport = initiator.split();
        final responderTransport = responder.split();
        for (var i = 2; i < messages.length; i++) {
          final fromInitiator = i.isEven;
          final sender = fromInitiator
              ? initiatorTransport
              : responderTransport;
          final receiver = fromInitiator
              ? responderTransport
              : initiatorTransport;
          final payload = _hex(messages[i]['payload'] as String);
          final ciphertext = await sender.encrypt(payload);
          expect(
            bytesToHex(ciphertext),
            messages[i]['ciphertext'],
            reason: 'message $i',
          );
          expect(
            await receiver.decrypt(ciphertext),
            payload,
            reason: 'message $i',
          );
        }
      });
    }
  });

  group('round trips with fresh keys', () {
    for (final pattern in NoisePattern.values) {
      test('${pattern.name}: handshake then transport both ways', () async {
        final psk = pattern == NoisePattern.ikPsk2 ? Uint8List(32) : null;
        final (initiator, responder) = await _pair(
          pattern,
          initiatorPsk: psk,
          responderPsk: psk,
        );
        expect(initiator.remoteStatic, isNotNull);
        expect(responder.remoteStatic, isNull);
        final m1 = await initiator.writeMessage(
          Uint8List.fromList(utf8.encode('hello')),
        );
        expect(utf8.decode(await responder.readMessage(m1)), 'hello');
        final m2 = await responder.writeMessage();
        expect(await initiator.readMessage(m2), isEmpty);
        expect(initiator.handshakeHash, responder.handshakeHash);
        expect(responder.remoteStatic, hasLength(32));

        final a = initiator.split();
        final b = responder.split();
        final c1 = await a.encrypt(Uint8List.fromList(utf8.encode('ping')));
        expect(utf8.decode(await b.decrypt(c1)), 'ping');
        final c2 = await b.encrypt(Uint8List.fromList(utf8.encode('pong')));
        expect(utf8.decode(await a.decrypt(c2)), 'pong');
      });
    }

    test('responder learns the initiator static key', () async {
      final mobile = await NoiseKeyPair.generate();
      final agent = await NoiseKeyPair.generate();
      final prologue = Uint8List(4);
      final initiator = NoiseHandshake.initiator(
        pattern: NoisePattern.ik,
        localStatic: mobile,
        remoteStatic: agent.publicKey,
        prologue: prologue,
      );
      final responder = NoiseHandshake.responder(
        pattern: NoisePattern.ik,
        localStatic: agent,
        prologue: prologue,
      );
      await responder.readMessage(await initiator.writeMessage());
      expect(responder.remoteStatic, mobile.publicKey);
    });
  });

  group('failures', () {
    test(
      'wrong pairing secret: responder reads message 1, initiator cannot read message 2',
      () async {
        final (initiator, responder) = await _pair(
          NoisePattern.ikPsk2,
          initiatorPsk: Uint8List(32),
          responderPsk: Uint8List(32)..[0] = 1,
        );
        await responder.readMessage(await initiator.writeMessage());
        final m2 = await responder.writeMessage();
        await expectLater(
          initiator.readMessage(m2),
          throwsA(isA<NoiseException>()),
        );
        expect(initiator.isComplete, isFalse);
        expect(() => initiator.split(), throwsStateError);
      },
    );

    test('prologue mismatch (swapped device ids) fails on message 1', () async {
      final (initiator, responder) = await _pair(
        NoisePattern.ik,
        initiatorPrologue: Uint8List.fromList([1]),
        responderPrologue: Uint8List.fromList([2]),
      );
      await expectLater(
        responder.readMessage(await initiator.writeMessage()),
        throwsA(isA<NoiseException>()),
      );
    });

    test(
      'initiator pinned a different agent key: responder cannot read message 1',
      () async {
        final other = await NoiseKeyPair.generate();
        final (initiator, responder) = await _pair(
          NoisePattern.ik,
          pinnedResponderKey: other.publicKey,
        );
        await expectLater(
          responder.readMessage(await initiator.writeMessage()),
          throwsA(isA<NoiseException>()),
        );
      },
    );

    test('attacker claims a victim static key it does not hold the private '
        'key for: message 1 fails and remoteStatic stays null', () async {
      final agent = await NoiseKeyPair.generate(); // responder
      final attacker = await NoiseKeyPair.generate();
      final victim = await NoiseKeyPair.generate();
      final attackerEphemeral = await NoiseKeyPair.generate();
      final prologue = Uint8List.fromList(utf8.encode('prologue'));

      final responder = NoiseHandshake.responder(
        pattern: NoisePattern.ik,
        localStatic: agent,
        prologue: prologue,
      );

      final forged = await _forgeMessage1(
        prologue: prologue,
        responderStaticPublic: agent.publicKey,
        attackerStatic: attacker,
        claimedStaticPublic: victim.publicKey,
        attackerEphemeral: attackerEphemeral,
      );

      await expectLater(
        responder.readMessage(forged),
        throwsA(isA<NoiseException>()),
      );
      expect(responder.remoteStatic, isNull);
    });

    test('tampered and truncated handshake messages', () async {
      final (initiator, responder) = await _pair(NoisePattern.ik);
      final m1 = await initiator.writeMessage();
      final tampered = Uint8List.fromList(m1)..[m1.length - 1] ^= 1;
      await expectLater(
        responder.readMessage(tampered),
        throwsA(isA<NoiseException>()),
      );
      await expectLater(
        responder.readMessage(m1),
        throwsStateError,
      ); // already failed

      final (i2, r2) = await _pair(NoisePattern.ik);
      await i2.writeMessage();
      await expectLater(
        r2.readMessage(Uint8List(95)),
        throwsA(isA<NoiseException>()),
      );
    });

    test(
      'out-of-turn calls throw StateError without breaking the handshake',
      () async {
        final (initiator, responder) = await _pair(NoisePattern.ik);
        await expectLater(responder.writeMessage(), throwsStateError);
        await expectLater(
          initiator.readMessage(Uint8List(48)),
          throwsStateError,
        );
        final m1 = await initiator.writeMessage();
        await expectLater(initiator.writeMessage(), throwsStateError);
        await responder.readMessage(m1);
        await initiator.readMessage(await responder.writeMessage());
        expect(initiator.isComplete, isTrue);
      },
    );

    test('psk is required for IKpsk2 and forbidden for IK', () async {
      final keys = await NoiseKeyPair.generate();
      expect(
        () => NoiseHandshake.initiator(
          pattern: NoisePattern.ikPsk2,
          localStatic: keys,
          remoteStatic: keys.publicKey,
          prologue: Uint8List(0),
        ),
        throwsArgumentError,
      );
      expect(
        () => NoiseHandshake.responder(
          pattern: NoisePattern.ikPsk2,
          localStatic: keys,
          prologue: Uint8List(0),
          psk: Uint8List(31),
        ),
        throwsArgumentError,
      );
      expect(
        () => NoiseHandshake.responder(
          pattern: NoisePattern.ik,
          localStatic: keys,
          prologue: Uint8List(0),
          psk: Uint8List(32),
        ),
        throwsArgumentError,
      );
      expect(
        () => NoiseHandshake.initiator(
          pattern: NoisePattern.ik,
          localStatic: keys,
          remoteStatic: Uint8List(31),
          prologue: Uint8List(0),
        ),
        throwsArgumentError,
      );
    });

    test(
      'a rejected psk never appears in the ArgumentError (only its length)',
      () async {
        final keys = await NoiseKeyPair.generate();
        final psk = Uint8List.fromList(List.generate(31, (i) => i + 1));

        try {
          NoiseHandshake.responder(
            pattern: NoisePattern.ikPsk2,
            localStatic: keys,
            prologue: Uint8List(0),
            psk: psk,
          );
          fail('expected ArgumentError');
        } on ArgumentError catch (e) {
          expect(e.invalidValue, isNot(isA<Uint8List>()));
          expect(e.invalidValue, psk.length);
        }

        try {
          NoiseHandshake.initiator(
            pattern: NoisePattern.ik,
            localStatic: keys,
            remoteStatic: keys.publicKey,
            prologue: Uint8List(0),
            psk: psk,
          );
          fail('expected ArgumentError');
        } on ArgumentError catch (e) {
          expect(e.invalidValue, isNot(isA<Uint8List>()));
          expect(e.invalidValue, psk.length);
        }

        try {
          NoiseHandshake.responder(
            pattern: NoisePattern.ikPsk2,
            localStatic: keys,
            prologue: Uint8List(0),
          );
          fail('expected ArgumentError');
        } on ArgumentError catch (e) {
          expect(e.invalidValue, isNot(isA<Uint8List>()));
          expect(e.invalidValue, isNull);
        }
      },
    );
  });

  group('transport', () {
    Future<(NoiseTransport, NoiseTransport)> transports() async {
      final (initiator, responder) = await _pair(NoisePattern.ik);
      await responder.readMessage(await initiator.writeMessage());
      await initiator.readMessage(await responder.writeMessage());
      return (initiator.split(), responder.split());
    }

    test(
      'split() is one-shot: a second call throws instead of reusing keys',
      () async {
        final (initiator, responder) = await _pair(NoisePattern.ik);
        await responder.readMessage(await initiator.writeMessage());
        await initiator.readMessage(await responder.writeMessage());

        initiator.split();
        expect(() => initiator.split(), throwsStateError);
        responder.split();
        expect(() => responder.split(), throwsStateError);
      },
    );

    test('replayed, reordered and tampered messages are rejected', () async {
      final (a, b) = await transports();
      final first = await a.encrypt(Uint8List.fromList([1]));
      final second = await a.encrypt(Uint8List.fromList([2]));
      await expectLater(
        b.decrypt(second),
        throwsA(isA<NoiseException>()),
      ); // reordered
      expect(await b.decrypt(first), [1]);
      await expectLater(
        b.decrypt(first),
        throwsA(isA<NoiseException>()),
      ); // replayed
      final tampered = Uint8List.fromList(second)..[0] ^= 1;
      await expectLater(b.decrypt(tampered), throwsA(isA<NoiseException>()));
      expect(await b.decrypt(second), [2]);
    });

    test('concurrent encrypt calls complete in call order', () async {
      final (a, b) = await transports();
      final futures = [
        for (var i = 0; i < 20; i++)
          a.encrypt(Uint8List.fromList(List.filled(i * 1000, i))),
      ];
      final ciphertexts = await Future.wait(futures);
      for (var i = 0; i < 20; i++) {
        expect((await b.decrypt(ciphertexts[i])).length, i * 1000);
      }
    });

    test('plaintext limit is 65519 bytes', () async {
      final (a, b) = await transports();
      final max = await a.encrypt(Uint8List(65519));
      expect(max, hasLength(65535));
      expect(await b.decrypt(max), hasLength(65519));
      expect(() => a.encrypt(Uint8List(65520)), throwsArgumentError);
    });
  });
}
