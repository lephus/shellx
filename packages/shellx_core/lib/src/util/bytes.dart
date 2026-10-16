import 'dart:convert';
import 'dart:typed_data';

/// The nil UUID, used for relay ERROR frames that are not tied to a peer.
const String nilUuid = '00000000-0000-0000-0000-000000000000';

final RegExp _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
final RegExp _base64UrlPattern = RegExp(r'^[A-Za-z0-9_-]*$');
final RegExp _hexPattern = RegExp(r'^(?:[0-9a-fA-F]{2})*$');

/// Parses a `8-4-4-4-12` UUID string (any case) into its 16 raw bytes.
///
/// Throws [FormatException] if [uuid] is not a well-formed UUID.
Uint8List uuidToBytes(String uuid) {
  if (!_uuidPattern.hasMatch(uuid)) {
    throw FormatException('Invalid UUID', uuid);
  }
  return hexToBytes(uuid.replaceAll('-', ''));
}

/// Formats 16 raw bytes as a lowercase `8-4-4-4-12` UUID string.
///
/// Throws [ArgumentError] if [bytes] is not exactly 16 bytes long.
String uuidFromBytes(Uint8List bytes) {
  if (bytes.length != 16) {
    throw ArgumentError.value(bytes.length, 'bytes', 'UUID must be 16 bytes');
  }
  final hex = bytesToHex(bytes);
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Encodes [bytes] as base64url without `=` padding.
String base64UrlNoPad(Uint8List bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

/// Decodes base64url text. Trailing `=` padding is tolerated but not required.
///
/// Throws [FormatException] for characters outside the base64url alphabet
/// (including `+` and `/`) or for an impossible length.
Uint8List fromBase64UrlNoPad(String input) {
  var body = input;
  while (body.endsWith('=')) {
    body = body.substring(0, body.length - 1);
  }
  if (!_base64UrlPattern.hasMatch(body) || body.length % 4 == 1) {
    throw FormatException('Invalid base64url', input);
  }
  final padded = body.padRight((body.length + 3) ~/ 4 * 4, '=');
  return base64Url.decode(padded);
}

/// Compares two byte arrays in time that depends only on their lengths.
bool constantTimeEquals(Uint8List a, Uint8List b) {
  if (a.length != b.length) {
    return false;
  }
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// Lowercase hexadecimal representation of [bytes].
String bytesToHex(List<int> bytes) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

/// Parses an even-length hexadecimal string. Throws [FormatException].
Uint8List hexToBytes(String hex) {
  if (!_hexPattern.hasMatch(hex)) {
    throw FormatException('Invalid hex', hex);
  }
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

/// Concatenates byte chunks into a new [Uint8List].
Uint8List concatBytes(List<List<int>> chunks) {
  final builder = BytesBuilder(copy: false);
  for (final chunk in chunks) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}
