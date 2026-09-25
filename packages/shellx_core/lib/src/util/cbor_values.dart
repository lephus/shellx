import 'dart:typed_data';

import 'package:cbor/cbor.dart';

/// Deepest array/map/tag nesting accepted by [decodeCbor]. Every wire shape
/// this package decodes tops out at depth 4 (batch array -> message map ->
/// `session.list.result`'s `sessions` array -> session map), so 8 leaves
/// comfortable headroom while still closing off the attack in
/// [_rejectExcessiveNesting]'s doc comment.
const int _maxCborDepth = 8;

/// Encodes plain Dart values as CBOR.
///
/// Supported: `null`, [bool], [int], [String], [Uint8List] (byte string),
/// [List] (array) and [Map] (map). Anything else throws [ArgumentError].
Uint8List encodeCbor(Object? value) =>
    Uint8List.fromList(cbor.encode(_toCborValue(value)));

/// Decodes a single CBOR item into plain Dart values.
///
/// Byte strings become [Uint8List], arrays become `List<Object?>`, maps
/// become `Map<Object?, Object?>`, integers become [int].
/// Throws [FormatException] for malformed input, unsupported item types,
/// integers that do not fit in 64 bits, or nesting deeper than 8 levels.
Object? decodeCbor(Uint8List bytes) {
  // Reject pathological nesting before `cbor.decode` (quadratic in depth)
  // or our own recursive `_fromCborValue` (linear stack depth) ever see the
  // bytes: a ~10 KB input nested 10,000 arrays deep makes `cbor.decode` burn
  // about a second of CPU and makes `_fromCborValue` overflow the native
  // call stack. This pre-scan is iterative (an explicit heap-allocated
  // stack, not the Dart call stack), so it cannot itself overflow, and it
  // rejects the input in a single linear pass long before either recursive
  // step runs.
  _rejectExcessiveNesting(bytes);
  try {
    final value = cbor.decode(bytes);
    return _fromCborValue(value);
  } on FormatException {
    rethrow;
  } on Object catch (error) {
    throw FormatException('Malformed CBOR: $error');
  }
}

CborValue _toCborValue(Object? value) {
  return switch (value) {
    null => const CborNull(),
    bool b => CborBool(b),
    int i => CborSmallInt(i),
    String s => CborString(s),
    Uint8List b => CborBytes(b),
    List<Object?> list => CborList([
      for (final item in list) _toCborValue(item),
    ]),
    Map<Object?, Object?> map => CborMap({
      for (final entry in map.entries)
        _toCborValue(entry.key): _toCborValue(entry.value),
    }),
    _ => throw ArgumentError.value(value, 'value', 'Unsupported CBOR type'),
  };
}

Object? _fromCborValue(CborValue value) {
  return switch (value) {
    CborNull() => null,
    CborBool(:final value) => value,
    CborInt() => _toInt64(value),
    CborString() => value.toString(),
    CborBytes(:final bytes) => Uint8List.fromList(bytes),
    CborList() => <Object?>[for (final item in value) _fromCborValue(item)],
    CborMap() => <Object?, Object?>{
      for (final entry in value.entries)
        _fromCborValue(entry.key): _fromCborValue(entry.value),
    },
    _ => throw FormatException('Unsupported CBOR item: ${value.runtimeType}'),
  };
}

/// [CborInt.toInt] silently clamps a bignum/uint64 outside the 64-bit signed
/// range to the nearest representable [int] instead of failing, which would
/// let a value like a session id or sequence number silently corrupt to the
/// wrong number. Reject it instead.
int _toInt64(CborInt value) {
  final big = value.toBigInt();
  if (!big.isValidInt) {
    throw FormatException('CBOR integer does not fit in 64 bits: $big');
  }
  return big.toInt();
}

/// Walks the CBOR header bytes iteratively (an explicit stack, not
/// recursion) to reject:
///  * arrays/maps/tags nested deeper than [_maxCborDepth];
///  * indefinite-length items and reserved additional-info values (28-31),
///    which this wire format never produces.
///
/// This never builds any value or reads byte/text string content beyond
/// skipping over it, so it is linear in the input length regardless of how
/// it is shaped.
void _rejectExcessiveNesting(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  var pos = 0;
  // remaining[i]: CBOR data items still expected at nesting level i.
  // Level 0 is the single top-level item `decodeCbor` is asked to parse.
  final remaining = <int>[1];
  while (remaining.isNotEmpty) {
    if (pos >= bytes.length) {
      throw const FormatException('Truncated CBOR item');
    }
    remaining[remaining.length - 1]--;
    final head = bytes[pos];
    final majorType = head >> 5;
    final info = head & 0x1f;
    pos++;

    final int value;
    if (info < 24) {
      value = info;
    } else if (info == 24) {
      _requireBytes(pos, 1, bytes.length);
      value = bytes[pos];
      pos += 1;
    } else if (info == 25) {
      _requireBytes(pos, 2, bytes.length);
      value = data.getUint16(pos);
      pos += 2;
    } else if (info == 26) {
      _requireBytes(pos, 4, bytes.length);
      value = data.getUint32(pos);
      pos += 4;
    } else if (info == 27) {
      _requireBytes(pos, 8, bytes.length);
      final raw = data.getUint64(pos);
      // A top-bit-set 64-bit length reads back as negative; treat it as
      // "too large" rather than let it wrap the bounds checks below.
      value = raw < 0 ? -1 : raw;
      pos += 8;
    } else {
      // 28-30 are reserved; 31 is indefinite-length / the "break" code.
      // This wire format only ever emits definite-length items, so treat
      // all of them as malformed.
      throw const FormatException(
        'Indefinite-length or reserved CBOR encoding is not supported',
      );
    }

    if (majorType == 2 || majorType == 3) {
      // byte string / text string: `value` content bytes follow.
      if (value < 0 || pos + value > bytes.length) {
        throw const FormatException('Truncated CBOR string');
      }
      pos += value;
    } else if (majorType == 4) {
      // array: `value` items follow.
      if (value > 0) {
        _pushLevel(remaining, value);
      }
    } else if (majorType == 5) {
      // map: `value` key/value pairs, i.e. 2 * `value` items, follow.
      if (value > 0) {
        _pushLevel(remaining, value > (1 << 62) ? -1 : value * 2);
      }
    } else if (majorType == 6) {
      // tag: exactly one item follows.
      _pushLevel(remaining, 1);
    }
    // majorType 0 (uint), 1 (negative int) and 7 (simple/float) are leaves:
    // the header is the whole item, nothing more to skip or nest.

    while (remaining.isNotEmpty && remaining.last == 0) {
      remaining.removeLast();
    }
  }
}

void _pushLevel(List<int> remaining, int count) {
  if (remaining.length > _maxCborDepth) {
    throw const FormatException('CBOR nested too deep');
  }
  remaining.add(count);
}

void _requireBytes(int pos, int count, int length) {
  if (pos + count > length) {
    throw const FormatException('Truncated CBOR header');
  }
}
