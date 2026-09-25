import 'dart:convert';
import 'dart:typed_data';

import '../relay/frames.dart';
import '../util/bytes.dart';

/// First byte of a DATA payload (spec section 6.3).
enum PayloadKind {
  hs1Ik(0x01),
  hs1IkPsk2(0x02),
  hs2(0x03),
  transport(0x04);

  const PayloadKind(this.wire);
  final int wire;

  /// Throws [FrameFormatException] for an unknown kind byte.
  static PayloadKind fromWire(int wire) {
    for (final kind in values) {
      if (kind.wire == wire) {
        return kind;
      }
    }
    throw FrameFormatException('Unknown payload kind $wire');
  }
}

final class ChannelPayload {
  ChannelPayload(this.kind, this.noiseMessage);

  final PayloadKind kind;
  final Uint8List noiseMessage;

  Uint8List encode() => concatBytes([
    [kind.wire],
    noiseMessage,
  ]);

  /// Throws [FrameFormatException] for an empty payload or unknown kind.
  static ChannelPayload decode(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw const FrameFormatException('Empty channel payload');
    }
    return ChannelPayload(
      PayloadKind.fromWire(bytes[0]),
      Uint8List.fromList(Uint8List.sublistView(bytes, 1)),
    );
  }
}

/// Noise prologue: UTF-8 "shellx/1" || agent UUID (16 bytes) || mobile UUID
/// (16 bytes). Throws [FormatException] for malformed UUIDs.
Uint8List buildPrologue({
  required String agentDeviceId,
  required String mobileDeviceId,
}) => concatBytes([
  utf8.encode('shellx/1'),
  uuidToBytes(agentDeviceId),
  uuidToBytes(mobileDeviceId),
]);
