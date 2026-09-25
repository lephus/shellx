// CipherState and SymmetricState (as NoiseCipherState / NoiseSymmetricState) from the Noise spec rev 34, §5.1 and §5.2.
import 'dart:convert';
import 'dart:typed_data';

import '../util/bytes.dart';
import 'noise_key_pair.dart';
import 'primitives.dart';

/// Largest nonce we will use. Noise reserves 2^64-1; Dart ints are signed
/// 64-bit, so we stop at 2^63-1, which is never reached in practice.
const int _maxNonce = 0x7fffffffffffffff;

final class NoiseCipherState {
  Uint8List? _k;
  int _n = 0;

  bool get hasKey => _k != null;

  /// Current nonce (exposed for tests).
  int get nonce => _n;

  void initializeKey(Uint8List? key) {
    _k = key == null ? null : Uint8List.fromList(key);
    _n = 0;
  }

  /// Encrypts with the current nonce, then increments it. Without a key the
  /// plaintext is returned unchanged (Noise §5.1).
  Future<Uint8List> encryptWithAd(List<int> ad, List<int> plaintext) {
    final k = _k;
    if (k == null) {
      return Future.value(Uint8List.fromList(plaintext));
    }
    if (_n >= _maxNonce) {
      throw const NoiseException('Nonce exhausted');
    }
    final n = _n++;
    return aeadEncrypt(k, n, ad, plaintext);
  }

  /// Decrypts with the current nonce. The nonce is incremented only on
  /// success. Throws [NoiseException] on authentication failure.
  Future<Uint8List> decryptWithAd(List<int> ad, Uint8List ciphertext) async {
    final k = _k;
    if (k == null) {
      return Uint8List.fromList(ciphertext);
    }
    if (_n >= _maxNonce) {
      throw const NoiseException('Nonce exhausted');
    }
    final plaintext = await aeadDecrypt(k, _n, ad, ciphertext);
    _n++;
    return plaintext;
  }
}

final class NoiseSymmetricState {
  NoiseSymmetricState(String protocolName) {
    final name = utf8.encode(protocolName);
    if (name.length <= hashLen) {
      _h = Uint8List(hashLen)..setAll(0, name);
    } else {
      _h = noiseHash(name);
    }
    _ck = Uint8List.fromList(_h);
  }

  late Uint8List _ck;
  late Uint8List _h;
  final NoiseCipherState cipher = NoiseCipherState();

  Uint8List get chainingKey => Uint8List.fromList(_ck);
  Uint8List get handshakeHash => Uint8List.fromList(_h);

  void mixKey(List<int> inputKeyMaterial) {
    final outputs = hkdf(_ck, inputKeyMaterial, 2);
    _ck = outputs[0];
    cipher.initializeKey(outputs[1]);
  }

  void mixHash(List<int> data) {
    _h = noiseHash(concatBytes([_h, data]));
  }

  void mixKeyAndHash(List<int> inputKeyMaterial) {
    final outputs = hkdf(_ck, inputKeyMaterial, 3);
    _ck = outputs[0];
    mixHash(outputs[1]);
    cipher.initializeKey(outputs[2]);
  }

  Future<Uint8List> encryptAndHash(List<int> plaintext) async {
    final ciphertext = await cipher.encryptWithAd(_h, plaintext);
    mixHash(ciphertext);
    return ciphertext;
  }

  Future<Uint8List> decryptAndHash(Uint8List ciphertext) async {
    final plaintext = await cipher.decryptWithAd(_h, ciphertext);
    mixHash(ciphertext);
    return plaintext;
  }

  /// Returns the two transport cipher states (initiator→responder first).
  (NoiseCipherState, NoiseCipherState) split() {
    final outputs = hkdf(_ck, const <int>[], 2);
    return (
      NoiseCipherState()..initializeKey(outputs[0]),
      NoiseCipherState()..initializeKey(outputs[1]),
    );
  }
}
