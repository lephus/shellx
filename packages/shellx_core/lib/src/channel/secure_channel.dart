import 'dart:typed_data';

import '../noise/handshake.dart';
import '../noise/primitives.dart' show tagLen;
import '../protocol/messages.dart';
import '../relay/frames.dart';
import 'payload.dart';

/// Maximum `data` bytes in one `output` or `input` message.
const int kMaxOutputChunk = 16 * 1024;

/// Largest CBOR batch that still fits one relay frame:
/// 65536 - 26 (DATA header) - 1 (kind byte) - 16 (Poly1305 tag) = 65493.
const int kMaxSealedBatchBytes =
    kMaxFrameBytes - kDataFrameHeaderBytes - 1 - tagLen;

/// Encrypts/decrypts batches of [AppMessage] with an established transport.
final class SecureChannel {
  SecureChannel(NoiseTransport transport) : _transport = transport;

  final NoiseTransport _transport;

  /// Returns `ChannelPayload(PayloadKind.transport, ciphertext).encode()`,
  /// ready to be the payload of a [DataFrame]. Throws [ArgumentError] if
  /// the encoded batch is larger than [kMaxSealedBatchBytes]; split it.
  /// Results complete in call order (see [NoiseTransport]).
  Future<Uint8List> seal(List<AppMessage> messages) async {
    final plaintext = encodeBatch(messages);
    if (plaintext.length > kMaxSealedBatchBytes) {
      throw ArgumentError.value(
        plaintext.length,
        'messages',
        'batch exceeds $kMaxSealedBatchBytes bytes',
      );
    }
    final ciphertext = await _transport.encrypt(plaintext);
    return ChannelPayload(PayloadKind.transport, ciphertext).encode();
  }

  /// [noiseMessage] is `ChannelPayload.noiseMessage` of a TRANSPORT payload.
  /// Throws [NoiseException] if decryption fails and [FormatException] if
  /// the plaintext is not a valid batch. Either way the channel must be
  /// dropped and a new handshake started.
  Future<List<AppMessage>> open(Uint8List noiseMessage) async {
    final plaintext = await _transport.decrypt(noiseMessage);
    return decodeBatch(plaintext);
  }
}
