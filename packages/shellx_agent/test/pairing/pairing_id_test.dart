import 'dart:math';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

void main() {
  final canonical = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  test('ids are lower-case canonical UUIDv7 stamped with the clock', () {
    final at = DateTime.utc(2026, 9, 25, 12, 30, 15, 123);
    final id = PairingIdGenerator(now: () => at, random: Random(1)).next();
    expect(id, matches(canonical));
    expect(isPairingId(id), isTrue);
    final millis = int.parse(
      id.substring(0, 8) + id.substring(9, 13),
      radix: 16,
    );
    expect(millis, at.millisecondsSinceEpoch);
  });

  test('ids from one generator strictly increase, even when the clock stands '
      'still or steps back', () {
    var now = DateTime.utc(2026, 9, 25, 12);
    final ids = PairingIdGenerator(now: () => now, random: Random(2));
    final seen = <String>[ids.next(), ids.next()];
    now = now.subtract(const Duration(minutes: 1));
    seen.add(ids.next());
    now = now.add(const Duration(hours: 1));
    seen.add(ids.next());
    for (var i = 1; i < seen.length; i++) {
      expect(seen[i].compareTo(seen[i - 1]), greaterThan(0));
    }
  });

  test('the 74 other bits come from the random source', () {
    final at = DateTime.utc(2026);
    String idFrom(int seed) =>
        PairingIdGenerator(now: () => at, random: Random(seed)).next();
    expect(idFrom(3), idFrom(3));
    expect(idFrom(3), isNot(idFrom(4)));
  });

  test('isPairingId accepts only lower-case canonical UUIDv7', () {
    const good = '0192abcd-0001-7abc-8def-0123456789ab';
    expect(isPairingId(good), isTrue);
    for (final bad in [
      good.toUpperCase(),
      '0192abcd-0001-4abc-8def-0123456789ab', // Version 4.
      '0192abcd-0001-7abc-cdef-0123456789ab', // Variant 110.
      '0192abcd00017abc8def0123456789ab', // No dashes.
      '0192abcd-0001-7abc-8def-0123456789a', // Too short.
      '',
    ]) {
      expect(isPairingId(bad), isFalse, reason: bad);
    }
  });
}
