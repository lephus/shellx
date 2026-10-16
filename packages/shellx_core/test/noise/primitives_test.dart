import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' show Chacha20, Hmac, SecretKey;
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_core/src/noise/primitives.dart';
import 'package:shellx_core/src/noise/symmetric_state.dart';
import 'package:test/test.dart';

Uint8List _hex(String hex) => hexToBytes(hex);

void main() {
  group('NoiseKeyPair (RFC 7748 §6.1)', () {
    const alicePrivate =
        '77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a';
    const alicePublic =
        '8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a';
    const bobPrivate =
        '5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb';
    const bobPublic =
        'de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f';
    const shared =
        '4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742';

    test(
      'fromPrivateKey derives the public key and keeps the private bytes',
      () async {
        final alice = await NoiseKeyPair.fromPrivateKey(_hex(alicePrivate));
        expect(bytesToHex(alice.publicKey), alicePublic);
        expect(bytesToHex(alice.privateKey), alicePrivate);
      },
    );

    test('dh matches the RFC shared secret from both sides', () async {
      final alice = await NoiseKeyPair.fromPrivateKey(_hex(alicePrivate));
      final bob = await NoiseKeyPair.fromPrivateKey(_hex(bobPrivate));
      expect(bytesToHex(await dh(alice, _hex(bobPublic))), shared);
      expect(bytesToHex(await dh(bob, _hex(alicePublic))), shared);
    });

    test('dh rejects a low-order (all-zero result) public key', () async {
      final alice = await NoiseKeyPair.fromPrivateKey(_hex(alicePrivate));
      expect(() => dh(alice, Uint8List(32)), throwsA(isA<NoiseException>()));
    });

    test('generate returns a consistent 32-byte pair', () async {
      final pair = await NoiseKeyPair.generate();
      expect(pair.privateKey, hasLength(32));
      expect(pair.publicKey, hasLength(32));
      final again = await NoiseKeyPair.fromPrivateKey(pair.privateKey);
      expect(again.publicKey, pair.publicKey);
    });

    test('rejects wrong key sizes', () async {
      expect(
        () => NoiseKeyPair.fromPrivateKey(Uint8List(31)),
        throwsArgumentError,
      );
      expect(
        () => NoiseKeyPair(privateKey: Uint8List(32), publicKey: Uint8List(31)),
        throwsArgumentError,
      );
    });
  });

  group(
    'HMAC-BLAKE2s (reference: Python hmac.new(key, msg, hashlib.blake2s))',
    () {
      test('short key', () {
        final mac = hmacBlake2s(
          utf8.encode('key'),
          utf8.encode('The quick brown fox jumps over the lazy dog'),
        );
        expect(
          bytesToHex(mac),
          'f93215bb90d4af4c3061cd932fb169fb8bb8a91d0b4022baea1271e1323cd9a0',
        );
      });

      test('32-byte key, empty message', () {
        final key = Uint8List.fromList(List.generate(32, (i) => i));
        expect(
          bytesToHex(hmacBlake2s(key, const [])),
          'e2641d24dfa8dd89e8cb77f1cdc77d8c006e5bebdfc4d6a3a3a6f8d5b7586fb0',
        );
      });

      test('key longer than the 64-byte block is hashed first', () {
        final key = Uint8List.fromList(List.generate(100, (i) => i));
        expect(
          bytesToHex(hmacBlake2s(key, utf8.encode('abc'))),
          'c1b751501db12b753069a918627b623179be55c8cc7ca5c4e14bdf32274ac656',
        );
      });

      test(
        'differs from package:cryptography Hmac.blake2s (32-byte block)',
        () async {
          final libraryMac = await Hmac.blake2s().calculateMac(
            utf8.encode('The quick brown fox jumps over the lazy dog'),
            secretKey: SecretKey(utf8.encode('key')),
          );
          expect(
            bytesToHex(libraryMac.bytes),
            isNot(
              'f93215bb90d4af4c3061cd932fb169fb8bb8a91d0b4022baea1271e1323cd9a0',
            ),
          );
        },
      );
    },
  );

  group('HKDF', () {
    test('follows the Noise definition', () {
      final ck = Uint8List.fromList(List.filled(32, 7));
      final ikm = utf8.encode('input');
      final outputs = hkdf(ck, ikm, 3);
      final temp = hmacBlake2s(ck, ikm);
      final o1 = hmacBlake2s(temp, [1]);
      final o2 = hmacBlake2s(temp, [...o1, 2]);
      final o3 = hmacBlake2s(temp, [...o2, 3]);
      expect(outputs, [o1, o2, o3]);
      expect(hkdf(ck, ikm, 2), [o1, o2]);
      expect(() => hkdf(ck, ikm, 4), throwsArgumentError);
    });
  });

  group('ChaChaPoly', () {
    test('nonce is 4 zero bytes then the little-endian counter', () {
      expect(bytesToHex(noiseNonce(0)), '000000000000000000000000');
      expect(bytesToHex(noiseNonce(1)), '000000000100000000000000');
      expect(
        bytesToHex(noiseNonce(0x0102030405060708)),
        '000000000807060504030201',
      );
    });

    test('NoiseCipherState uses the counter nonce and increments it', () async {
      final key = Uint8List.fromList(List.generate(32, (i) => i));
      final state = NoiseCipherState()..initializeKey(key);
      final first = await state.encryptWithAd(const [9], utf8.encode('hi'));
      final second = await state.encryptWithAd(const [9], utf8.encode('hi'));
      expect(state.nonce, 2);
      final expected = await Chacha20.poly1305Aead().encrypt(
        utf8.encode('hi'),
        secretKey: SecretKey(key),
        nonce: noiseNonce(1),
        aad: const [9],
      );
      expect(second, [...expected.cipherText, ...expected.mac.bytes]);
      expect(first, isNot(second));

      final reader = NoiseCipherState()..initializeKey(key);
      expect(utf8.decode(await reader.decryptWithAd(const [9], first)), 'hi');
      expect(utf8.decode(await reader.decryptWithAd(const [9], second)), 'hi');
    });

    test('failed decryption throws and does not advance the nonce', () async {
      final key = Uint8List(32);
      final writer = NoiseCipherState()..initializeKey(key);
      final ciphertext = await writer.encryptWithAd(const [], utf8.encode('x'));
      final tampered = Uint8List.fromList(ciphertext)..[0] ^= 1;
      final reader = NoiseCipherState()..initializeKey(key);
      await expectLater(
        reader.decryptWithAd(const [], tampered),
        throwsA(isA<NoiseException>()),
      );
      expect(reader.nonce, 0);
      expect(
        utf8.decode(await reader.decryptWithAd(const [], ciphertext)),
        'x',
      );
      await expectLater(
        reader.decryptWithAd(const [], Uint8List(5)),
        throwsA(isA<NoiseException>()),
      );
    });

    test('without a key the plaintext passes through', () async {
      final state = NoiseCipherState();
      expect(state.hasKey, isFalse);
      expect(await state.encryptWithAd(const [], [1, 2]), [1, 2]);
    });
  });

  group('NoiseSymmetricState', () {
    test('long protocol names are hashed, short ones zero-padded', () {
      const longName = 'Noise_IKpsk2_25519_ChaChaPoly_BLAKE2s';
      final long = NoiseSymmetricState(longName);
      expect(long.handshakeHash, noiseHash(utf8.encode(longName)));
      expect(long.chainingKey, long.handshakeHash);
      final short = NoiseSymmetricState('Noise_NN');
      expect(short.handshakeHash, [
        ...utf8.encode('Noise_NN'),
        ...List.filled(24, 0),
      ]);
    });

    test(
      'mixHash, mixKey, encryptAndHash and split are consistent on both sides',
      () async {
        final a = NoiseSymmetricState('Noise_IK_25519_ChaChaPoly_BLAKE2s');
        final b = NoiseSymmetricState('Noise_IK_25519_ChaChaPoly_BLAKE2s');
        for (final s in [a, b]) {
          s.mixHash(utf8.encode('prologue'));
          s.mixKey(Uint8List(32));
        }
        final ciphertext = await a.encryptAndHash(utf8.encode('payload'));
        expect(utf8.decode(await b.decryptAndHash(ciphertext)), 'payload');
        expect(a.handshakeHash, b.handshakeHash);
        a.mixKeyAndHash(Uint8List(32));
        b.mixKeyAndHash(Uint8List(32));
        final (a1, a2) = a.split();
        final (b1, b2) = b.split();
        final message = await a1.encryptWithAd(const [], utf8.encode('t'));
        expect(utf8.decode(await b1.decryptWithAd(const [], message)), 't');
        final reply = await b2.encryptWithAd(const [], utf8.encode('r'));
        expect(utf8.decode(await a2.decryptWithAd(const [], reply)), 'r');
      },
    );
  });
}
