import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shellx_core/shellx_core.dart';

/// A device registered with the [FakeRelay].
final class FakeDevice {
  FakeDevice({
    required this.id,
    required this.userId,
    required this.kind,
    required this.name,
    required this.platform,
  }) : token = 'token-$id';

  final String id;
  final String userId;
  final DeviceKind kind;
  final String name;
  final DevicePlatform platform;
  final String token;
}

/// Thrown by the fake connector while a device is marked unreachable.
final class FakeRelayUnreachable implements Exception {
  const FakeRelayUnreachable(this.deviceId);
  final String deviceId;
  @override
  String toString() => 'FakeRelayUnreachable($deviceId)';
}

/// In-memory relay: the `UserHub` routing of overview §4.1 behind fake
/// [RelaySocket]s, plus the REST endpoints the agent and client call
/// (`GET /v1/devices`, `POST /v1/pairings`, `DELETE /v1/pairings/:a/:m`)
/// behind a `MockClient`.
final class FakeRelay {
  final Uri wsUri = Uri.parse('ws://relay.test/v1/ws');
  final Uri baseUri = Uri.parse('http://relay.test');

  final _devices = <String, FakeDevice>{};
  final _connections = <String, FakeRelaySocket>{};
  final _unreachable = <String>{};

  /// Device ids whose token has been revoked (spec: password change, logout,
  /// account deletion): the next connect attempt for that device is rejected
  /// pre-upgrade with HTTP 401, like the real relay's `authenticate()`.
  final _revokedDevices = <String>{};

  /// Durable, deduplicated per-agent `pairing_removed` tombstones, mirroring
  /// the real hub's `pending_pairing_removed` table: mobile ids are added at
  /// most once per agent (a `LinkedHashSet` keeps first-insertion order
  /// without moving a re-added entry, matching `INSERT OR IGNORE ... ORDER BY
  /// rowid`). Every tombstone is replayed on EVERY connect of its agent and
  /// is never cleared on send; only `POST /v1/pairings` for that exact
  /// (agent, mobile) pair clears it. (The real hub also purges them on the
  /// agent's logout and on account deletion; this fake models neither.)
  final _pendingPairingRemoved = <String, LinkedHashSet<String>>{};

  /// Display-only pairing records: (agentId, mobileId).
  final pairings = <(String, String)>{};

  /// Every HTTP request served, as "METHOD /path".
  final requests = <String>[];

  /// Every DATA frame delivered: (from, to, payload).
  final delivered = <({String from, String to, Uint8List payload})>[];

  /// Optional hook applied to each DATA frame before delivery. It receives
  /// the frame as the target would see it (peer = source) and returns the
  /// frame to deliver, or null to drop it.
  DataFrame? Function(String from, String to, DataFrame frame)? onData;

  FakeDevice addDevice({
    required String id,
    required String userId,
    required DeviceKind kind,
    String? name,
    DevicePlatform? platform,
  }) {
    final device = FakeDevice(
      id: id,
      userId: userId,
      kind: kind,
      name: name ?? (kind == DeviceKind.agent ? 'Test Mac' : 'Test Phone'),
      platform:
          platform ??
          (kind == DeviceKind.agent
              ? DevicePlatform.macos
              : DevicePlatform.ios),
    );
    _devices[id] = device;
    return device;
  }

  RelaySocketConnector get connector => _connect;

  http.Client get httpClient => MockClient(_handleHttp);

  bool isOnline(String deviceId) => _connections.containsKey(deviceId);

  /// Closes the device's socket from the hub side (network drop by default).
  void dropConnection(String deviceId, {int code = 1006}) =>
      _connections[deviceId]?.serverClose(code);

  /// While unreachable, connection attempts from the device fail.
  void setReachable(String deviceId, bool reachable) {
    if (reachable) {
      _unreachable.remove(deviceId);
    } else {
      _unreachable.add(deviceId);
    }
  }

  /// Invalidates [deviceId]'s token: its next connect attempt is rejected
  /// pre-upgrade with HTTP 401 (`RelayConnection` maps that to `revoked`),
  /// like a password change or logout on the real relay. Does not affect an
  /// already-open connection; combine with `dropConnection(id, code:
  /// RelayCloseCode.revoked)` to also end its live socket with 4002.
  void revokeToken(String deviceId) => _revokedDevices.add(deviceId);

  /// Sends an EVENT frame to one device (if online).
  void sendEvent(String deviceId, Map<String, String> event) =>
      _connections[deviceId]?.deliver(EventFrame(event).encode());

  /// Sends an ERROR frame to one device (if online), as the hub would for a
  /// frame it could not route (for example `peer_offline` for a peer whose
  /// socket died before its PRESENCE offline was sent).
  void sendError(String deviceId, ErrorFrame error) =>
      _connections[deviceId]?.deliver(error.encode());

  /// Mirrors the real hub's `notifyPairingRemoved`: sends the EVENT live to
  /// both devices of the pairing (if connected), and always records a
  /// tombstone for the agent — even when the agent looks live — so every
  /// later connect replays it (a live socket can be silently dead) until the
  /// pair is re-created.
  void _notifyPairingRemoved(String agentId, String mobileId) {
    (_pendingPairingRemoved[agentId] ??= LinkedHashSet<String>()).add(mobileId);
    final event = {
      'event': 'pairing_removed',
      'agent_id': agentId,
      'mobile_id': mobileId,
    };
    sendEvent(agentId, event);
    if (mobileId != agentId) sendEvent(mobileId, event);
  }

  Future<RelaySocket> _connect(Uri uri, Map<String, String> headers) async {
    final authorization =
        headers['Authorization'] ?? headers['authorization'] ?? '';
    final token = authorization.replaceFirst('Bearer ', '');
    final device = _devices.values.where((d) => d.token == token).firstOrNull;
    // A missing/unknown/revoked token is refused with a plain pre-upgrade
    // HTTP 401, exactly like the real relay's `webSocketRoute` (`shellx_core`
    // maps that to `RelayConnectionState.revoked`).
    if (device == null || _revokedDevices.contains(device.id)) {
      throw const WebSocketException('unauthorized', 401);
    }
    if (_unreachable.contains(device.id)) {
      throw FakeRelayUnreachable(device.id);
    }
    // One connection per device: register the new socket *before* closing
    // the old one, so the old socket's own disconnect handling (below) sees
    // itself already superseded and stays silent — the real hub achieves the
    // same thing by marking the old socket `closing` before it ever closes.
    // The old connection still gets 4001 (`replaced`); it just never causes
    // a spurious PRESENCE offline for a device that in fact stayed online.
    final previous = _connections[device.id];
    final socket = FakeRelaySocket._(this, device);
    _connections[device.id] = socket;
    previous?.serverClose(RelayCloseCode.replaced);
    for (final other in _connections.values) {
      if (identical(other, socket) || other.device.userId != device.userId) {
        continue;
      }
      socket.deliver(
        PresenceFrame(deviceId: other.device.id, online: true).encode(),
      );
      other.deliver(PresenceFrame(deviceId: device.id, online: true).encode());
    }
    // Replay this device's pairing_removed tombstones (if any; in practice
    // only ever recorded for an agent) right after the PRESENCE snapshot,
    // keeping them — mirroring the real hub's `deliverPending`.
    final pending = _pendingPairingRemoved[device.id];
    if (pending != null) {
      for (final mobileId in pending) {
        socket.deliver(
          EventFrame({
            'event': 'pairing_removed',
            'agent_id': device.id,
            'mobile_id': mobileId,
          }).encode(),
        );
      }
    }
    return socket;
  }

  void _onClientFrame(FakeRelaySocket from, Uint8List bytes) {
    // Decode before checking the size limit, like the real hub (parses the
    // DATA header first, then checks length): a too-large DATA frame's
    // ERROR still carries the sender's intended peer/channel when the
    // header itself decodes cleanly.
    RelayFrame? decoded;
    try {
      decoded = RelayFrame.decode(bytes);
    } on FrameFormatException {
      decoded = null;
    }
    if (bytes.length > kMaxFrameBytes) {
      final probe = decoded is DataFrame ? decoded : null;
      from.deliver(
        ErrorFrame(
          code: RelayErrorCode.frameTooLarge,
          deviceId: probe?.peer ?? nilUuid,
          channel: probe?.channel,
        ).encode(),
      );
      return;
    }
    if (decoded == null) {
      from.deliver(ErrorFrame(code: RelayErrorCode.badFrame).encode());
      return;
    }
    final frame = decoded;
    if (frame is! DataFrame) {
      from.deliver(ErrorFrame(code: RelayErrorCode.badFrame).encode());
      return;
    }
    final target = _connections[frame.peer];
    if (target == null || target.device.userId != from.device.userId) {
      from.deliver(
        ErrorFrame(
          code: RelayErrorCode.peerOffline,
          deviceId: frame.peer,
          channel: frame.channel,
        ).encode(),
      );
      return;
    }
    DataFrame? outgoing = DataFrame(
      peer: from.device.id,
      channel: frame.channel,
      payload: frame.payload,
    );
    final hook = onData;
    if (hook != null) outgoing = hook(from.device.id, frame.peer, outgoing);
    if (outgoing == null) return;
    delivered.add((
      from: from.device.id,
      to: frame.peer,
      payload: outgoing.payload,
    ));
    target.deliver(outgoing.encode());
  }

  void _onDisconnected(FakeRelaySocket socket) {
    final id = socket.device.id;
    if (!identical(_connections[id], socket)) return;
    _connections.remove(id);
    for (final other in _connections.values) {
      if (other.device.userId != socket.device.userId) continue;
      other.deliver(PresenceFrame(deviceId: id, online: false).encode());
    }
  }

  Future<http.Response> _handleHttp(http.Request request) async {
    requests.add('${request.method} ${request.url.path}');
    final authorization =
        request.headers['authorization'] ??
        request.headers['Authorization'] ??
        '';
    final token = authorization.replaceFirst('Bearer ', '');
    final caller = _devices.values.where((d) => d.token == token).firstOrNull;
    if (caller == null) {
      return _error(401, 'unauthorized', 'Missing or invalid token');
    }
    final segments = request.url.pathSegments;
    if (request.method == 'GET' && request.url.path == '/v1/devices') {
      return http.Response(
        jsonEncode([
          for (final d in _devices.values)
            if (d.userId == caller.userId)
              {
                'id': d.id,
                'kind': d.kind.name,
                'name': d.name,
                'platform': d.platform.name,
                'online': isOnline(d.id),
                'last_seen_at': null,
                'paired_with_me':
                    pairings.contains((d.id, caller.id)) ||
                    pairings.contains((caller.id, d.id)),
              },
        ]),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (request.method == 'POST' && request.url.path == '/v1/pairings') {
      if (caller.kind != DeviceKind.agent) {
        return _error(403, 'agent_only', 'Only an agent can create pairings');
      }
      final body = jsonDecode(request.body) as Map<String, Object?>;
      final mobile = _devices[body['mobile_id']];
      if (mobile == null ||
          mobile.userId != caller.userId ||
          mobile.kind != DeviceKind.mobile) {
        return _error(404, 'device_not_found', 'Device not found');
      }
      // Re-pairing clears that pair's tombstone first, like the real route
      // (`clearPairingRemoved` before the upsert).
      _pendingPairingRemoved[caller.id]?.remove(mobile.id);
      pairings.add((caller.id, mobile.id));
      return http.Response('', 201);
    }
    if (request.method == 'DELETE' &&
        segments.length == 4 &&
        segments[0] == 'v1' &&
        segments[1] == 'pairings') {
      final agentId = segments[2];
      final mobileId = segments[3];
      if (caller.id != agentId && caller.id != mobileId) {
        return _error(403, 'forbidden', 'Not part of this pairing');
      }
      // Notify (and durably queue) only if the pairing actually existed,
      // exactly like the real relay's DELETE route; the request itself is
      // idempotent either way.
      if (pairings.remove((agentId, mobileId))) {
        _notifyPairingRemoved(agentId, mobileId);
      }
      return http.Response('', 204);
    }
    return _error(404, 'not_found', 'Not found');
  }

  http.Response _error(int status, String code, String message) =>
      http.Response(
        jsonEncode({
          'error': {'code': code, 'message': message},
        }),
        status,
        headers: {'content-type': 'application/json'},
      );
}

/// Client end of a fake WebSocket. Answers `ping` with `pong` like the hub's
/// auto-response.
final class FakeRelaySocket implements RelaySocket {
  FakeRelaySocket._(this._relay, this.device);

  final FakeRelay _relay;
  final FakeDevice device;
  final _incoming = StreamController<Object>();
  int? _closeCode;
  bool _closed = false;

  @override
  Stream<Object> get messages => _incoming.stream;

  @override
  int? get closeCode => _closeCode;

  @override
  void sendText(String text) {
    if (_closed) return;
    if (text == 'ping') _incoming.add('pong');
  }

  @override
  void sendBytes(Uint8List bytes) {
    if (_closed) return;
    _relay._onClientFrame(this, Uint8List.fromList(bytes));
  }

  @override
  Future<void> close([int? code, String? reason]) async =>
      _terminate(code ?? 1005);

  void serverClose(int code) => _terminate(code);

  void deliver(Uint8List bytes) {
    if (!_closed) _incoming.add(bytes);
  }

  void _terminate(int code) {
    if (_closed) return;
    _closed = true;
    _closeCode = code;
    _incoming.close();
    _relay._onDisconnected(this);
  }
}
