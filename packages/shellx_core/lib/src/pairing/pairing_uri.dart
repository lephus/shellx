import 'dart:typed_data';

import '../util/bytes.dart';

/// QR content: `shellx://pair?v=1&d=<uuid>&k=<base64url 32 bytes>&s=<base64url 32 bytes>`.
final class PairingUri {
  /// Throws [ArgumentError] if the key or secret is not 32 bytes or the
  /// device id is not a UUID.
  PairingUri({
    required this.agentDeviceId,
    required this.agentPublicKey,
    required this.secret,
  }) {
    try {
      uuidToBytes(agentDeviceId);
    } on FormatException {
      throw ArgumentError.value(
        agentDeviceId,
        'agentDeviceId',
        'must be a UUID',
      );
    }
    if (agentPublicKey.length != 32 || secret.length != 32) {
      throw ArgumentError('Pairing key and secret must be 32 bytes');
    }
  }

  static const String scheme = 'shellx';
  static const String host = 'pair';
  static const String version = '1';

  final String agentDeviceId;
  final Uint8List agentPublicKey;
  final Uint8List secret;

  String toUriString() =>
      '$scheme://$host?v=$version'
      '&d=$agentDeviceId'
      '&k=${base64UrlNoPad(agentPublicKey)}'
      '&s=${base64UrlNoPad(secret)}';

  /// Throws [FormatException] unless [input] is a version 1 ShellX pairing
  /// URI with a UUID `d` and 32-byte `k` and `s`. Surrounding whitespace is
  /// ignored; the device id is returned lowercase.
  static PairingUri parse(String input) {
    final Uri uri;
    try {
      uri = Uri.parse(input.trim());
    } on FormatException {
      throw FormatException('Not a ShellX pairing code', input);
    }
    if (uri.scheme != scheme ||
        uri.host != host ||
        (uri.path != '' && uri.path != '/')) {
      throw FormatException('Not a ShellX pairing code', input);
    }
    final query = uri.queryParameters;
    if (query['v'] != version) {
      throw FormatException('Unsupported pairing code version', query['v']);
    }
    final deviceId = query['d'];
    if (deviceId == null) {
      throw const FormatException('Pairing code without device id');
    }
    uuidToBytes(deviceId);
    final key = _decode32(query['k'], 'k');
    final secret = _decode32(query['s'], 's');
    return PairingUri(
      agentDeviceId: deviceId.toLowerCase(),
      agentPublicKey: key,
      secret: secret,
    );
  }

  static Uint8List _decode32(String? value, String name) {
    if (value == null) {
      throw FormatException('Pairing code without "$name"');
    }
    final bytes = fromBase64UrlNoPad(value);
    if (bytes.length != 32) {
      throw FormatException('Pairing code "$name" must be 32 bytes', value);
    }
    return bytes;
  }
}
