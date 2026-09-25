import 'dart:async';
import 'dart:convert';
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

  /// Sends an EVENT frame to one device (if online).
  void sendEvent(String deviceId, Map<String, String> event) =>
      _connections[deviceId]?.deliver(EventFrame(event).encode());

  Future<RelaySocket> _connect(Uri uri, Map<String, String> headers) async {
    final authorization =
        headers['Authorization'] ?? headers['authorization'] ?? '';
    final token = authorization.replaceFirst('Bearer ', '');
    final device = _devices.values.where((d) => d.token == token).firstOrNull;
    if (device == null) throw StateError('unknown token');
    if (_unreachable.contains(device.id)) {
      throw FakeRelayUnreachable(device.id);
    }
    _connections[device.id]?.serverClose(RelayCloseCode.replaced);
    final socket = FakeRelaySocket._(this, device);
    _connections[device.id] = socket;
    for (final other in _connections.values) {
      if (identical(other, socket) || other.device.userId != device.userId) {
        continue;
      }
      socket.deliver(
        PresenceFrame(deviceId: other.device.id, online: true).encode(),
      );
      other.deliver(PresenceFrame(deviceId: device.id, online: true).encode());
    }
    return socket;
  }

  void _onClientFrame(FakeRelaySocket from, Uint8List bytes) {
    if (bytes.length > kMaxFrameBytes) {
      from.deliver(ErrorFrame(code: RelayErrorCode.frameTooLarge).encode());
      return;
    }
    final RelayFrame frame;
    try {
      frame = RelayFrame.decode(bytes);
    } on FrameFormatException {
      from.deliver(ErrorFrame(code: RelayErrorCode.badFrame).encode());
      return;
    }
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
      pairings.remove((agentId, mobileId));
      final other = caller.id == agentId ? mobileId : agentId;
      sendEvent(other, {
        'event': 'pairing_removed',
        'agent_id': agentId,
        'mobile_id': mobileId,
      });
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
