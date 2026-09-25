import 'dart:typed_data';

import '../protocol/handshake_payloads.dart';
import '../util/bytes.dart';

/// Device description sent with register/login.
final class DeviceInfo {
  DeviceInfo({
    required this.kind,
    required this.name,
    required this.platform,
    required this.publicKey,
  });

  final DeviceKind kind;
  final String name;
  final DevicePlatform platform;
  final Uint8List publicKey;

  /// `{"kind", "name", "platform", "public_key"}`; public_key is base64url
  /// without padding.
  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'name': name,
    'platform': platform.name,
    'public_key': base64UrlNoPad(publicKey),
  };
}

final class AuthResult {
  const AuthResult({
    required this.userId,
    required this.deviceId,
    required this.token,
  });
  final String userId, deviceId, token;
}

/// One entry of `GET /v1/devices`.
final class RemoteDevice {
  const RemoteDevice({
    required this.id,
    required this.kind,
    required this.name,
    required this.platform,
    required this.online,
    required this.lastSeenAt,
    required this.pairedWithMe,
  });

  final String id;
  final DeviceKind kind;
  final String name;
  final DevicePlatform platform;
  final bool online;

  /// UTC; null if the device never disconnected.
  final DateTime? lastSeenAt;
  final bool pairedWithMe;
}

final class LatestAgent {
  const LatestAgent({
    required this.version,
    required this.macUrl,
    required this.winUrl,
  });
  final String version;
  final Uri macUrl, winUrl;
}

/// `GET /v1/version`.
final class VersionInfo {
  const VersionInfo({
    required this.minAgent,
    required this.minMobile,
    required this.latestAgent,
  });
  final String minAgent, minMobile;
  final LatestAgent latestAgent;
}

final class ApiException implements Exception {
  const ApiException({
    required this.status,
    required this.code,
    required this.message,
  });

  /// HTTP status, or 0 when the request never got a response.
  final int status;

  /// Relay error code (e.g. `invalid_credentials`), `network` when
  /// [status] is 0, `http_<status>` when the error body is not the relay's
  /// JSON shape, `bad_response` when a success body cannot be parsed.
  final String code;
  final String message;

  @override
  String toString() => 'ApiException($status, $code): $message';
}
