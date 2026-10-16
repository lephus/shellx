import 'dart:math';
import 'dart:typed_data';

import '../util/bytes.dart';

/// 8-byte identifier of one Noise channel between a mobile and an agent.
final class ChannelId {
  /// Throws [ArgumentError] if [bytes] is not exactly 8 bytes long.
  ChannelId(Uint8List bytes) : bytes = _checked(bytes);

  /// A fresh random id. Uses [Random.secure] unless [random] is given.
  factory ChannelId.random([Random? random]) {
    final source = random ?? Random.secure();
    return ChannelId(
      Uint8List.fromList(List<int>.generate(8, (_) => source.nextInt(256))),
    );
  }

  /// All-zero id, used by relay ERROR frames that are not tied to a channel.
  static final ChannelId zero = ChannelId(Uint8List(8));

  /// Unmodifiable: an in-place write (`channelId.bytes[0] = 7`) would
  /// otherwise corrupt every [ChannelId] built from the same source bytes —
  /// most notably [ChannelId.zero], a single shared instance every
  /// zero-channel [ErrorFrame] defaults to.
  final Uint8List bytes;

  static Uint8List _checked(Uint8List bytes) {
    if (bytes.length != 8) {
      throw ArgumentError.value(
        bytes.length,
        'bytes',
        'ChannelId must be 8 bytes',
      );
    }
    return Uint8List.fromList(bytes).asUnmodifiableView();
  }

  @override
  bool operator ==(Object other) =>
      other is ChannelId && constantTimeEquals(bytes, other.bytes);

  @override
  int get hashCode => Object.hashAll(bytes);

  @override
  String toString() => bytesToHex(bytes);
}
