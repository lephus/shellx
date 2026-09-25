import 'dart:typed_data';

import '../util/cbor_values.dart';

const int kAppProtocolVersion = 1;

/// Wire value is [name].
enum DevicePlatform {
  macos,
  windows,
  ios,
  android;

  /// Throws [FormatException] for an unknown value.
  static DevicePlatform fromWire(String wire) =>
      _byName(values, wire, 'platform');
}

/// Wire value is [name].
enum DeviceKind {
  agent,
  mobile;

  /// Throws [FormatException] for an unknown value.
  static DeviceKind fromWire(String wire) =>
      _byName(values, wire, 'device kind');
}

enum HandshakeStatus {
  ok('ok'),
  untrusted('untrusted'),
  pairingInvalid('pairing_invalid'),
  protoUnsupported('proto_unsupported');

  const HandshakeStatus(this.wire);
  final String wire;

  /// Throws [FormatException] for an unknown value.
  static HandshakeStatus fromWire(String wire) {
    for (final status in values) {
      if (status.wire == wire) {
        return status;
      }
    }
    throw FormatException('Unknown handshake status', wire);
  }
}

/// CBOR `{proto, app, name, platform}` carried in Noise message 1.
final class Hs1Payload {
  Hs1Payload({
    required this.proto,
    required this.app,
    required this.name,
    required this.platform,
  });

  final int proto;
  final String app;
  final String name;
  final DevicePlatform platform;

  Uint8List encode() => encodeCbor(<String, Object?>{
    'proto': proto,
    'app': app,
    'name': name,
    'platform': platform.name,
  });

  /// Throws [FormatException] for malformed CBOR or missing/mistyped fields.
  static Hs1Payload decode(Uint8List bytes) {
    final map = _decodeMap(bytes, 'HS1');
    return Hs1Payload(
      proto: _field<int>(map, 'proto', 'HS1'),
      app: _field<String>(map, 'app', 'HS1'),
      name: _field<String>(map, 'name', 'HS1'),
      platform: DevicePlatform.fromWire(_field<String>(map, 'platform', 'HS1')),
    );
  }
}

/// CBOR `{proto, app, status}` carried in Noise message 2.
final class Hs2Payload {
  Hs2Payload({required this.proto, required this.app, required this.status});

  final int proto;
  final String app;
  final HandshakeStatus status;

  Uint8List encode() => encodeCbor(<String, Object?>{
    'proto': proto,
    'app': app,
    'status': status.wire,
  });

  /// Throws [FormatException] for malformed CBOR or missing/mistyped fields.
  static Hs2Payload decode(Uint8List bytes) {
    final map = _decodeMap(bytes, 'HS2');
    return Hs2Payload(
      proto: _field<int>(map, 'proto', 'HS2'),
      app: _field<String>(map, 'app', 'HS2'),
      status: HandshakeStatus.fromWire(_field<String>(map, 'status', 'HS2')),
    );
  }
}

T _byName<T extends Enum>(List<T> values, String wire, String what) {
  for (final value in values) {
    if (value.name == wire) {
      return value;
    }
  }
  throw FormatException('Unknown $what', wire);
}

Map<Object?, Object?> _decodeMap(Uint8List bytes, String what) {
  final decoded = decodeCbor(bytes);
  if (decoded is! Map<Object?, Object?>) {
    throw FormatException('$what payload must be a CBOR map');
  }
  return decoded;
}

T _field<T>(Map<Object?, Object?> map, String key, String what) {
  final value = map[key];
  if (value is T) {
    return value;
  }
  throw FormatException('$what payload: "$key" missing or not a $T');
}
