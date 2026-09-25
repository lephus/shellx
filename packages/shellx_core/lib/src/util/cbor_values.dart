import 'dart:typed_data';

import 'package:cbor/cbor.dart';

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
/// Throws [FormatException] for malformed input or unsupported item types.
Object? decodeCbor(Uint8List bytes) {
  final CborValue value;
  try {
    value = cbor.decode(bytes);
  } on FormatException {
    rethrow;
  } on Object catch (error) {
    throw FormatException('Malformed CBOR: $error');
  }
  return _fromCborValue(value);
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
    CborInt() => value.toInt(),
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
