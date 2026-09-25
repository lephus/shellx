import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

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

  static Future<NoiseKeyPair> generate() async {
    final keyPair = await X25519().newKeyPair();
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
    final keyPair = await X25519().newKeyPairFromSeed(privateKey);
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
