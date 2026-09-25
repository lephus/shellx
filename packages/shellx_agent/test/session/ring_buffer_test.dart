import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

Uint8List bytes(int from, int count) =>
    Uint8List.fromList(List.generate(count, (i) => (from + i) % 256));

void main() {
  test('starts empty', () {
    final ring = RingBuffer(8);
    expect(ring.start, 0);
    expect(ring.end, 0);
    expect(ring.read(0, 10), isEmpty);
  });

  test('appends and reads by absolute position', () {
    final ring = RingBuffer(8);
    ring.append(bytes(0, 5));
    expect(ring.start, 0);
    expect(ring.end, 5);
    expect(ring.read(0, 5), bytes(0, 5));
    expect(ring.read(2, 2), bytes(2, 2));
    expect(ring.read(3, 100), bytes(3, 2));
    expect(ring.read(5, 4), isEmpty);
  });

  test('overwrites the oldest bytes and wraps around', () {
    final ring = RingBuffer(8);
    ring.append(bytes(0, 6));
    ring.append(bytes(6, 6));
    expect(ring.start, 4);
    expect(ring.end, 12);
    expect(ring.read(4, 8), bytes(4, 8));
    expect(ring.read(7, 3), bytes(7, 3));
  });

  test('a single append larger than the capacity keeps the newest bytes', () {
    final ring = RingBuffer(8);
    ring.append(bytes(0, 3));
    ring.append(bytes(3, 20));
    expect(ring.start, 15);
    expect(ring.end, 23);
    expect(ring.read(15, 8), bytes(15, 8));
  });

  test('rejects reads outside [start, end]', () {
    final ring = RingBuffer(4);
    ring.append(bytes(0, 10));
    expect(() => ring.read(5, 1), throwsRangeError);
    expect(() => ring.read(11, 1), throwsRangeError);
    expect(() => ring.read(6, -1), throwsArgumentError);
  });

  test('rejects a non-positive capacity', () {
    expect(() => RingBuffer(0), throwsArgumentError);
  });
}
