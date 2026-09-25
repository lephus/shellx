import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../protocol/handshake_payloads.dart';
import 'models.dart';

/// REST client for the relay API (spec section 10.2).
///
/// Every failure is reported as [ApiException]: HTTP errors carry the relay's
/// `{"error": {"code", "message"}}`; transport failures and requests that
/// get no response within 20 seconds have status 0 and code `network`.
final class ShellxApi {
  ShellxApi({required Uri baseUri, http.Client? httpClient})
    : _baseUri = baseUri,
      _http = httpClient ?? http.Client(),
      _ownsHttp = httpClient == null;

  static const Duration _timeout = Duration(seconds: 20);

  final Uri _baseUri;
  final http.Client _http;

  /// Whether this [ShellxApi] created [_http] itself (no client was passed
  /// in), and therefore owns its lifecycle.
  final bool _ownsHttp;

  /// Bearer token for authenticated calls. [register] and [login] set it;
  /// [logout] clears it (even when the request fails).
  String? token;

  Future<AuthResult> register(
    String email,
    String password,
    DeviceInfo device,
  ) => _authenticate('/v1/auth/register', email, password, device);

  Future<AuthResult> login(String email, String password, DeviceInfo device) =>
      _authenticate('/v1/auth/login', email, password, device);

  Future<void> logout() async {
    try {
      await _send('POST', '/v1/auth/logout', authenticated: true);
    } finally {
      token = null;
    }
  }

  Future<void> changePassword(String newPassword) async {
    await _send(
      'POST',
      '/v1/auth/password',
      authenticated: true,
      body: {'new_password': newPassword},
    );
  }

  /// Permanently deletes the account after the relay re-checks [password]
  /// (`DELETE /v1/account`). The relay then closes every device's
  /// WebSocket with 4002. [token] is cleared on success and kept on failure
  /// (for example `401 invalid_credentials`).
  Future<void> deleteAccount(String password) async {
    await _send(
      'DELETE',
      '/v1/account',
      authenticated: true,
      body: {'password': password},
    );
    token = null;
  }

  /// Devices of the account. Entries with a kind or platform this version
  /// does not know are skipped.
  Future<List<RemoteDevice>> devices() async {
    final response = await _send('GET', '/v1/devices', authenticated: true);
    return _parse(response, (json) {
      final devices = <RemoteDevice>[];
      for (final item in json as List<dynamic>) {
        final map = item as Map<String, dynamic>;
        final DeviceKind kind;
        final DevicePlatform platform;
        try {
          kind = DeviceKind.fromWire(map['kind'] as String);
          platform = DevicePlatform.fromWire(map['platform'] as String);
        } on FormatException {
          continue;
        }
        final lastSeen = map['last_seen_at'] as int?;
        devices.add(
          RemoteDevice(
            id: map['id'] as String,
            kind: kind,
            name: map['name'] as String,
            platform: platform,
            online: map['online'] as bool,
            lastSeenAt: lastSeen == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(lastSeen, isUtc: true),
            pairedWithMe: map['paired_with_me'] as bool,
          ),
        );
      }
      return devices;
    });
  }

  /// Records pairing [pairingId] with the phone [mobileId]
  /// (`POST /v1/pairings`, agent token). [pairingId] must be a lower-case
  /// canonical UUIDv7 the agent generates at `pair.confirm`, one per pairing
  /// (the relay orders pairings by it and does not fold case; anything else
  /// is `400 bad_request`). Sending the same id again is idempotent. Fails
  /// with `410 pairing_removed` when the relay already removed this pairing
  /// or a newer one of the same phone (for example an earlier attempt
  /// committed, its response was lost and the phone unpaired), or when the
  /// id's timestamp is more than 24 h ahead of the relay's clock: the row is
  /// not recreated. A `500` may come after the row was recorded; retry with
  /// the same id (only while it is still the current pairing).
  Future<void> createPairing(
    String mobileId, {
    required String pairingId,
  }) async {
    await _send(
      'POST',
      '/v1/pairings',
      authenticated: true,
      body: {'mobile_id': mobileId, 'pairing_id': pairingId},
    );
  }

  /// `DELETE /v1/pairings/:agent_id/:mobile_id`. With [pairingId] (the
  /// agent's revoke) the relay removes the pairing only if it is still that
  /// pairing, otherwise nothing happens; without it (the phone's unpair)
  /// whatever pairing exists is removed. Idempotent (`204` either way). A
  /// `500` leaves the pairing in place: retry it (the phone's unpair
  /// especially, since that is how the agent learns about it).
  Future<void> deletePairing(
    String agentId,
    String mobileId, {
    String? pairingId,
  }) async {
    await _send(
      'DELETE',
      '/v1/pairings/${Uri.encodeComponent(agentId)}/${Uri.encodeComponent(mobileId)}',
      authenticated: true,
      query: pairingId == null ? null : {'pairing_id': pairingId},
    );
  }

  /// Closes the underlying [http.Client], but only if this [ShellxApi]
  /// created it itself: a client passed to the constructor is left open,
  /// since its lifecycle belongs to whoever created and passed it in.
  void close() {
    if (_ownsHttp) {
      _http.close();
    }
  }

  Future<VersionInfo> version() async {
    final response = await _send('GET', '/v1/version');
    return _parse(response, (json) {
      final map = json as Map<String, dynamic>;
      final latest = map['latest_agent'] as Map<String, dynamic>;
      return VersionInfo(
        minAgent: map['min_agent'] as String,
        minMobile: map['min_mobile'] as String,
        latestAgent: LatestAgent(
          version: latest['version'] as String,
          macUrl: Uri.parse(latest['mac_url'] as String),
          winUrl: Uri.parse(latest['win_url'] as String),
        ),
      );
    });
  }

  Future<AuthResult> _authenticate(
    String path,
    String email,
    String password,
    DeviceInfo device,
  ) async {
    final response = await _send(
      'POST',
      path,
      body: {'email': email, 'password': password, 'device': device.toJson()},
    );
    final result = _parse(response, (json) {
      final map = json as Map<String, dynamic>;
      return AuthResult(
        userId: map['user_id'] as String,
        deviceId: map['device_id'] as String,
        token: map['token'] as String,
      );
    });
    token = result.token;
    return result;
  }

  Uri _endpoint(String path, Map<String, String>? query) {
    final basePath = _baseUri.path.endsWith('/')
        ? _baseUri.path.substring(0, _baseUri.path.length - 1)
        : _baseUri.path;
    final endpoint = _baseUri.replace(path: '$basePath$path');
    return query == null ? endpoint : endpoint.replace(queryParameters: query);
  }

  Future<http.Response> _send(
    String method,
    String path, {
    bool authenticated = false,
    Map<String, Object?>? body,
    Map<String, String>? query,
  }) async {
    final request = http.Request(method, _endpoint(path, query));
    request.headers['Accept'] = 'application/json';
    if (authenticated) {
      final current = token;
      if (current == null) {
        throw const ApiException(
          status: 401,
          code: 'unauthorized',
          message: 'Not signed in',
        );
      }
      request.headers['Authorization'] = 'Bearer $current';
    }
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final http.Response response;
    try {
      final streamed = await _http.send(request).timeout(_timeout);
      response = await http.Response.fromStream(streamed).timeout(_timeout);
    } on http.ClientException catch (error) {
      throw ApiException(status: 0, code: 'network', message: error.message);
    } on IOException catch (error) {
      // Covers SocketException, HttpException, WebSocketException and TLS
      // failures (TlsException/HandshakeException): IOClient only wraps
      // SocketException/HttpException as http.ClientException, so a TLS
      // failure (an expired cert, a MITM proxy, a bad handshake) would
      // otherwise escape as a raw dart:io exception instead of the
      // ApiException the contract promises for every failure.
      throw ApiException(status: 0, code: 'network', message: error.toString());
    } on TimeoutException {
      throw const ApiException(
        status: 0,
        code: 'network',
        message: 'Request timed out',
      );
    }
    if (response.statusCode < 200 || response.statusCode > 299) {
      throw _errorFrom(response);
    }
    return response;
  }

  static T _parse<T>(http.Response response, T Function(Object? json) read) {
    try {
      return read(jsonDecode(utf8.decode(response.bodyBytes)));
    } on Object catch (error) {
      if (error is ApiException) {
        rethrow;
      }
      // Never interpolate `error` here: a jsonDecode FormatException embeds
      // a source excerpt around the parse failure, so a truncated response
      // body (for example a login/register reply cut off mid-token) would
      // otherwise leak secret text straight into this message.
      throw ApiException(
        status: response.statusCode,
        code: 'bad_response',
        message: 'Malformed response',
      );
    }
  }

  static ApiException _errorFrom(http.Response response) {
    Object? json;
    try {
      json = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      json = null;
    }
    if (json is Map<String, dynamic>) {
      final error = json['error'];
      if (error is Map<String, dynamic> && error['code'] is String) {
        final code = error['code'] as String;
        final message = error['message'];
        return ApiException(
          status: response.statusCode,
          code: code,
          message: message is String ? message : code,
        );
      }
    }
    return ApiException(
      status: response.statusCode,
      code: 'http_${response.statusCode}',
      message: response.reasonPhrase ?? 'HTTP ${response.statusCode}',
    );
  }
}
