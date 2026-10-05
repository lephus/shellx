import 'dart:math';
import 'dart:typed_data';

/// Fixed-capacity byte ring addressed by absolute stream position (`seq`).
/// Holds the bytes `[start, end)`; appending past capacity overwrites the
/// oldest bytes and advances [start].
final class RingBuffer {
  RingBuffer(int capacity)
    : _capacity = capacity,
      _bytes = Uint8List(capacity) {
    if (capacity <= 0) throw ArgumentError.value(capacity, 'capacity');
  }

  final int _capacity;
  final Uint8List _bytes;
  int _end = 0;

  /// Positions below this were dropped by [restartWith].
  int _floor = 0;

  int get start => max(_floor, _end - _capacity);
  int get end => _end;

  void append(Uint8List data) {
    if (data.isEmpty) return;
    var source = data;
    if (source.length > _capacity) {
      source = Uint8List.sublistView(source, source.length - _capacity);
    }
    final skipped = data.length - source.length;
    var position = (_end + skipped) % _capacity;
    var offset = 0;
    while (offset < source.length) {
      final count = min(source.length - offset, _capacity - position);
      _bytes.setRange(position, position + count, source, offset);
      offset += count;
      position = (position + count) % _capacity;
    }
    _end += data.length;
  }

  /// Drops every byte held and continues the stream with [data]: positions
  /// keep increasing, and [start] becomes the old [end] (spec §7.8: a desktop
  /// terminal's snapshot after a reconnect replaces the buffer).
  void restartWith(Uint8List data) {
    _floor = _end;
    append(data);
  }

  /// Returns up to [maxBytes] bytes starting at stream position [from].
  /// Requires `start <= from <= end`.
  Uint8List read(int from, int maxBytes) {
    if (from < start || from > end) {
      throw RangeError('read from $from outside [$start, $end]');
    }
    if (maxBytes < 0) throw ArgumentError.value(maxBytes, 'maxBytes');
    final length = min(maxBytes, _end - from);
    final result = Uint8List(length);
    var position = from % _capacity;
    var offset = 0;
    while (offset < length) {
      final count = min(length - offset, _capacity - position);
      result.setRange(offset, offset + count, _bytes, position);
      offset += count;
      position = (position + count) % _capacity;
    }
    return result;
  }
}
