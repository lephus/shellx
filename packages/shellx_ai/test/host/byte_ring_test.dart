import 'dart:convert';

import 'package:shellx_ai/host.dart';
import 'package:test/test.dart';

void main() {
  test('keeps the last bytes only', () {
    final r = ByteRing(10)
      ..add([1, 2, 3, 4])
      ..add([5, 6, 7, 8])
      ..add([9, 10, 11, 12]);
    expect(r.bytes, [3, 4, 5, 6, 7, 8, 9, 10, 11, 12]);
    r.add(List.generate(15, (i) => 100 + i));
    expect(r.bytes, List.generate(10, (i) => 105 + i));
    expect(r.length, 10);
  });

  test('text decodes leniently when the cut splits a character', () {
    final r = ByteRing(4)..add(utf8.encode('aé✓'));
    expect(r.text, endsWith('✓'));
  });
}
