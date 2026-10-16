import 'dart:math';

final _pairingIdPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

/// True for a canonical lower-case UUIDv7 (version 7, variant `10`), the
/// only form the relay accepts as a pairing id (overview §4.3).
bool isPairingId(String value) => _pairingIdPattern.hasMatch(value);

/// Generates pairing ids (spec §5.3): lower-case canonical UUIDv7 (RFC 9562)
/// made of the 48-bit Unix-millisecond timestamp of [now], version 7,
/// variant `10` and 74 bits from [random] (`Random.secure()` by default).
///
/// The relay orders the pairings of one phone by id, so ids from one
/// generator strictly increase: when the clock stands still or steps back,
/// the last timestamp plus 1 ms is used instead.
final class PairingIdGenerator {
  PairingIdGenerator({DateTime Function()? now, Random? random})
    : _now = now ?? DateTime.now,
      _random = random ?? Random.secure();

  final DateTime Function() _now;
  final Random _random;
  int _lastMillis = -1;

  String next() {
    var millis = _now().millisecondsSinceEpoch;
    if (millis <= _lastMillis) millis = _lastMillis + 1;
    _lastMillis = millis;
    final bytes = List<int>.filled(16, 0);
    // Division instead of shifts keeps the 48-bit timestamp exact on every
    // platform.
    var rest = millis;
    for (var i = 5; i >= 0; i--) {
      bytes[i] = rest % 256;
      rest ~/= 256;
    }
    for (var i = 6; i < 16; i++) {
      bytes[i] = _random.nextInt(256);
    }
    bytes[6] = 0x70 | (bytes[6] & 0x0f); // Version 7.
    bytes[8] = 0x80 | (bytes[8] & 0x3f); // Variant 10.
    final hex = [
      for (final byte in bytes) byte.toRadixString(16).padLeft(2, '0'),
    ].join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}
