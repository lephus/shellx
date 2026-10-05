import 'dart:typed_data';

/// Largest local-link frame payload (spec §6.2).
const int kTermMaxFrame = 65536;

/// Largest `data` piece of `snapshot`/`out` (spec §6.2).
const int kTermMaxChunk = 61440;

/// 4-byte big-endian length + [payload].
Uint8List termFrame(Uint8List payload) {
  if (payload.length > kTermMaxFrame) {
    throw ArgumentError.value(payload.length, 'payload', 'over 64 KiB');
  }
  final frame = Uint8List(4 + payload.length);
  ByteData.sublistView(frame).setUint32(0, payload.length);
  frame.setRange(4, frame.length, payload);
  return frame;
}

/// Splits the bytes read from a local-link socket into frame payloads.
final class TermFrameReader {
  Uint8List _pending = Uint8List(0);

  /// Adds [chunk] and returns every payload now complete, in order. Throws
  /// [FormatException] as soon as a length over [kTermMaxFrame] is seen.
  List<Uint8List> add(List<int> chunk) {
    final joined = Uint8List(_pending.length + chunk.length)
      ..setAll(0, _pending)
      ..setAll(_pending.length, chunk);
    final payloads = <Uint8List>[];
    var offset = 0;
    while (joined.length - offset >= 4) {
      final length = ByteData.sublistView(
        joined,
        offset,
        offset + 4,
      ).getUint32(0);
      if (length > kTermMaxFrame) {
        throw const FormatException('local-link frame over 64 KiB');
      }
      if (joined.length - offset - 4 < length) break;
      payloads.add(
        Uint8List.fromList(
          Uint8List.sublistView(joined, offset + 4, offset + 4 + length),
        ),
      );
      offset += 4 + length;
    }
    _pending = Uint8List.fromList(Uint8List.sublistView(joined, offset));
    return payloads;
  }
}
