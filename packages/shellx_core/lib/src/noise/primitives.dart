// Noise crypto functions for 25519 / ChaChaPoly / BLAKE2s (Noise rev 34, §4).
//
// HMAC is implemented here on purpose: in package:cryptography 2.9.0
// `Blake2s.blockLengthInBytes` is 32, so `Hmac.blake2s()` is not RFC 2104
// HMAC-BLAKE2s (which needs the 64-byte BLAKE2s block). Noise needs the
// RFC 2104 construction with BLOCKLEN = 64.
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

import '../util/bytes.dart';
import 'noise_key_pair.dart';

const int dhLen = 32;
const int hashLen = 32;
const int blockLen = 64;
const int tagLen = 16;

final X25519 _x25519 = X25519();
final Cipher _chachaPoly = Chacha20.poly1305Aead();
final DartBlake2s _blake2s = DartBlake2s();

/// BLAKE2s-256 of [data].
Uint8List noiseHash(List<int> data) =>
    Uint8List.fromList(_blake2s.hashSync(data).bytes);

/// RFC 2104 HMAC with BLAKE2s and a 64-byte block.
Uint8List hmacBlake2s(List<int> key, List<int> data) {
  final normalizedKey = key.length > blockLen ? noiseHash(key) : key;
  final ipad = Uint8List(blockLen);
  final opad = Uint8List(blockLen);
  for (var i = 0; i < blockLen; i++) {
    final k = i < normalizedKey.length ? normalizedKey[i] : 0;
    ipad[i] = k ^ 0x36;
    opad[i] = k ^ 0x5c;
  }
  final inner = noiseHash(concatBytes([ipad, data]));
  return noiseHash(concatBytes([opad, inner]));
}

/// Noise HKDF returning 2 or 3 outputs of [hashLen] bytes.
List<Uint8List> hkdf(
  Uint8List chainingKey,
  List<int> inputKeyMaterial,
  int numOutputs,
) {
  if (numOutputs != 2 && numOutputs != 3) {
    throw ArgumentError.value(numOutputs, 'numOutputs', 'must be 2 or 3');
  }
  final tempKey = hmacBlake2s(chainingKey, inputKeyMaterial);
  final output1 = hmacBlake2s(tempKey, [0x01]);
  final output2 = hmacBlake2s(
    tempKey,
    concatBytes([
      output1,
      [0x02],
    ]),
  );
  if (numOutputs == 2) {
    return [output1, output2];
  }
  final output3 = hmacBlake2s(
    tempKey,
    concatBytes([
      output2,
      [0x03],
    ]),
  );
  return [output1, output2, output3];
}

/// X25519 DH. Throws [NoiseException] if the result is all zeros
/// (low-order public key).
Future<Uint8List> dh(NoiseKeyPair keyPair, Uint8List publicKey) async {
  if (publicKey.length != dhLen) {
    throw const NoiseException('Public key must be 32 bytes');
  }
  final secret = await _x25519.sharedSecretKey(
    keyPair: SimpleKeyPairData(
      keyPair.privateKey,
      publicKey: SimplePublicKey(keyPair.publicKey, type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    ),
    remotePublicKey: SimplePublicKey(publicKey, type: KeyPairType.x25519),
  );
  final bytes = Uint8List.fromList(await secret.extractBytes());
  if (constantTimeEquals(bytes, Uint8List(dhLen))) {
    throw const NoiseException('Invalid DH public key');
  }
  return bytes;
}

/// ChaChaPoly nonce: 4 zero bytes followed by the 64-bit little-endian counter.
Uint8List noiseNonce(int n) {
  final nonce = Uint8List(12);
  ByteData.sublistView(nonce).setUint64(4, n, Endian.little);
  return nonce;
}

/// ChaCha20-Poly1305 encryption; returns ciphertext || 16-byte tag.
Future<Uint8List> aeadEncrypt(
  Uint8List key,
  int n,
  List<int> ad,
  List<int> plaintext,
) async {
  final box = await _chachaPoly.encrypt(
    plaintext,
    secretKey: SecretKey(key),
    nonce: noiseNonce(n),
    aad: ad,
  );
  return concatBytes([box.cipherText, box.mac.bytes]);
}

/// ChaCha20-Poly1305 decryption of ciphertext || tag.
/// Throws [NoiseException] on authentication failure.
Future<Uint8List> aeadDecrypt(
  Uint8List key,
  int n,
  List<int> ad,
  Uint8List ciphertext,
) async {
  if (ciphertext.length < tagLen) {
    throw const NoiseException('Ciphertext shorter than the tag');
  }
  final split = ciphertext.length - tagLen;
  final box = SecretBox(
    Uint8List.sublistView(ciphertext, 0, split),
    nonce: noiseNonce(n),
    mac: Mac(Uint8List.sublistView(ciphertext, split)),
  );
  try {
    final plaintext = await _chachaPoly.decrypt(
      box,
      secretKey: SecretKey(key),
      aad: ad,
    );
    return Uint8List.fromList(plaintext);
  } on SecretBoxAuthenticationError {
    throw const NoiseException('Decryption failed');
  }
}
