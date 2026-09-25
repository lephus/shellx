import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

/// Static or ephemeral X25519 key pair.
final class NoiseKeyPair {
  NoiseKeyPair({required this.privateKey, required this.publicKey}) {
    if (privateKey.length != 32 || publicKey.length != 32) {
      throw ArgumentError('X25519 keys must be 32 bytes');
    }
  }

  /// 32-byte X25519 private key.
  final Uint8List privateKey;

  /// 32-byte X25519 public key.
  final Uint8List publicKey;

  // Pinned to the pure-Dart backend (not the platform-selected `X25519()`
  // default) so key generation/derivation behaves identically on every
  // platform, matching the pin in primitives.dart. The Flutter apps
  // otherwise swap in a native implementation via cryptography_flutter.
  static final X25519 _x25519 = DartX25519();

  static Future<NoiseKeyPair> generate() async {
    final keyPair = await _x25519.newKeyPair();
    final privateKey = await keyPair.extractPrivateKeyBytes();
    final publicKey = await keyPair.extractPublicKey();
    return NoiseKeyPair(
      privateKey: Uint8List.fromList(privateKey),
      publicKey: Uint8List.fromList(publicKey.bytes),
    );
  }

  /// Derives the public key. Throws [ArgumentError] unless 32 bytes.
  static Future<NoiseKeyPair> fromPrivateKey(Uint8List privateKey) async {
    if (privateKey.length != 32) {
      throw ArgumentError.value(
        privateKey.length,
        'privateKey',
        'must be 32 bytes',
      );
    }
    final keyPair = await _x25519.newKeyPairFromSeed(privateKey);
    final publicKey = await keyPair.extractPublicKey();
    return NoiseKeyPair(
      privateKey: Uint8List.fromList(privateKey),
      publicKey: Uint8List.fromList(publicKey.bytes),
    );
  }
}

final class NoiseException implements Exception {
  const NoiseException(this.message);
  final String message;

  @override
  String toString() => 'NoiseException: $message';
}
