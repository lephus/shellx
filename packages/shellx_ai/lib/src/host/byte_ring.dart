import 'dart:collection';
import 'dart:convert';

/// The last [capacity] bytes of a stream (agent stderr, spec D20: 256 KiB
/// per session, memory only).
final class ByteRing {
  ByteRing(this.capacity);

  final int capacity;
  final _chunks = Queue<List<int>>();
  var _length = 0;

  int get length => _length;

  void add(List<int> data) {
    if (data.isEmpty) return;
    if (data.length >= capacity) {
      _chunks
        ..clear()
        ..add(data.sublist(data.length - capacity));
      _length = capacity;
      return;
    }
    _chunks.add(data);
    _length += data.length;
    while (_length > capacity) {
      final first = _chunks.removeFirst();
      final excess = _length - capacity;
      if (first.length <= excess) {
        _length -= first.length;
      } else {
        _chunks.addFirst(first.sublist(excess));
        _length -= excess;
      }
    }
  }

  List<int> get bytes => [for (final c in _chunks) ...c];

  String get text => utf8.decode(bytes, allowMalformed: true);
}
