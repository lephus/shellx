import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'frames.dart';

/// Minimal WebSocket surface used by [RelayConnection]; faked in tests.
abstract interface class RelaySocket {
  /// [String] for text frames, [Uint8List] for binary frames.
  Stream<Object> get messages;
  void sendText(String text);
  void sendBytes(Uint8List bytes);
  Future<void> close([int? code, String? reason]);

  /// Close code received from the server; set once [messages] is done.
  int? get closeCode;
}

typedef RelaySocketConnector =
    Future<RelaySocket> Function(Uri uri, Map<String, String> headers);

/// Connects with `dart:io` [WebSocket]. A rejected upgrade (for example
/// HTTP 401 for a bad token) throws [WebSocketException] whose
/// `httpStatusCode` is the HTTP status.
Future<RelaySocket> ioRelaySocketConnector(
  Uri uri,
  Map<String, String> headers,
) async {
  final socket = await WebSocket.connect(uri.toString(), headers: headers);
  return _IoRelaySocket(socket);
}

final class _IoRelaySocket implements RelaySocket {
  _IoRelaySocket(this._socket);

  final WebSocket _socket;

  @override
  late final Stream<Object> messages = _socket.map<Object>(
    (event) => switch (event) {
      String text => text,
      Uint8List bytes => bytes,
      List<int> bytes => Uint8List.fromList(bytes),
      _ => throw StateError('Unexpected WebSocket event ${event.runtimeType}'),
    },
  );

  @override
  void sendText(String text) => _socket.add(text);

  @override
  void sendBytes(Uint8List bytes) => _socket.add(bytes);

  @override
  Future<void> close([int? code, String? reason]) =>
      _socket.close(code, reason);

  @override
  int? get closeCode => _socket.closeCode;
}

/// Exponential backoff with "equal jitter".
final class Backoff {
  Backoff({
    Duration initial = const Duration(seconds: 1),
    Duration max = const Duration(seconds: 30),
    Random? random,
  }) : _initialMs = initial.inMilliseconds,
       _maxMs = max.inMilliseconds,
       _random = random ?? Random();

  final int _initialMs;
  final int _maxMs;
  final Random _random;
  int _attempt = 0;

  /// base = min(max, initial * 2^attempt); returns base/2 + random(0..base/2).
  Duration next() {
    final base = min(_maxMs, _initialMs * (1 << min(_attempt, 30)));
    _attempt++;
    final half = base ~/ 2;
    return Duration(milliseconds: base - half + _random.nextInt(half + 1));
  }

  void reset() {
    _attempt = 0;
  }
}

enum RelayConnectionState {
  disconnected,
  connecting,
  connected,
  revoked,
  replaced,
  stopped,
}

/// One reconnecting WebSocket to the relay hub (spec sections 6.1, 12).
///
/// * Sends text `ping` right after connecting and then every [pingInterval];
///   if no `pong` arrives within [pongTimeout] the socket is dropped and a
///   reconnect is scheduled.
/// * Close code 4002 -> [RelayConnectionState.revoked], 4001 ->
///   [RelayConnectionState.replaced]; neither reconnects. A rejected upgrade
///   with HTTP 401, or a null token, is treated as revoked too.
/// * Any other close, error, connect failure or connect attempt that takes
///   longer than 15 seconds -> [RelayConnectionState.disconnected] and a
///   reconnect after [Backoff.next]. The backoff resets when a `pong` is
///   received, so a relay that accepts and immediately drops us is not
///   hammered.
/// * Binary frames that fail [RelayFrame.decode] are dropped silently.
final class RelayConnection {
  RelayConnection({
    required Uri wsUri,
    required String? Function() token,
    RelaySocketConnector connector = ioRelaySocketConnector,
    Backoff? backoff,
    Duration pingInterval = const Duration(seconds: 30),
    Duration pongTimeout = const Duration(seconds: 10),
  }) : _wsUri = wsUri,
       _token = token,
       _connector = connector,
       _backoff = backoff ?? Backoff(),
       _pingInterval = pingInterval,
       _pongTimeout = pongTimeout;

  static const Duration connectTimeout = Duration(seconds: 15);

  final Uri _wsUri;
  final String? Function() _token;
  final RelaySocketConnector _connector;
  final Backoff _backoff;
  final Duration _pingInterval;
  final Duration _pongTimeout;

  final StreamController<RelayConnectionState> _states =
      StreamController.broadcast();
  final StreamController<RelayFrame> _frames = StreamController.broadcast();

  RelayConnectionState _state = RelayConnectionState.disconnected;
  RelaySocket? _socket;
  StreamSubscription<Object>? _subscription;
  Timer? _pingTimer;
  Timer? _pongTimer;
  Timer? _reconnectTimer;

  /// Incremented whenever the current attempt/socket is abandoned, so late
  /// callbacks from an old socket are ignored.
  int _generation = 0;

  RelayConnectionState get state => _state;
  Stream<RelayConnectionState> get states => _states.stream;
  Stream<RelayFrame> get frames => _frames.stream;

  /// Starts connecting. No-op while connecting or connected. May be called
  /// again after [stop], revoked or replaced (for example after a new login).
  void start() {
    if (_state == RelayConnectionState.connecting ||
        _state == RelayConnectionState.connected) {
      return;
    }
    _backoff.reset();
    unawaited(_connect());
  }

  /// Disconnects for good (until [start] is called again).
  Future<void> stop() async {
    if (_state == RelayConnectionState.stopped) {
      return;
    }
    final socket = _abandonSocket();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _setState(RelayConnectionState.stopped);
    if (socket != null) {
      await _closeQuietly(socket, 1000);
    }
  }

  /// Sends a frame; false (nothing sent) unless connected.
  bool send(RelayFrame frame) {
    final socket = _socket;
    if (_state != RelayConnectionState.connected || socket == null) {
      return false;
    }
    try {
      socket.sendBytes(frame.encode());
      return true;
    } on Object {
      return false;
    }
  }

  /// Skips the pending backoff delay (mobile returning to the foreground).
  /// Only acts while disconnected.
  void reconnectNow() {
    if (_state != RelayConnectionState.disconnected) {
      return;
    }
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    unawaited(_connect());
  }

  Future<void> _connect() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    final generation = ++_generation;
    final token = _token();
    if (token == null) {
      _setState(RelayConnectionState.revoked);
      return;
    }
    _setState(RelayConnectionState.connecting);
    final pending = _connector(_wsUri, {'Authorization': 'Bearer $token'});
    final RelaySocket socket;
    try {
      socket = await pending.timeout(connectTimeout);
    } on Object catch (error) {
      if (error is TimeoutException) {
        unawaited(
          pending.then(
            (late) => _closeQuietly(late, 1000),
            onError: (Object _) {},
          ),
        );
      }
      if (generation != _generation) {
        return;
      }
      if (error is WebSocketException &&
          error.httpStatusCode == HttpStatus.unauthorized) {
        _setState(RelayConnectionState.revoked);
        return;
      }
      _scheduleReconnect();
      return;
    }
    if (generation != _generation) {
      await _closeQuietly(socket, 1000);
      return;
    }
    _socket = socket;
    _subscription = socket.messages.listen(
      (message) => _onMessage(generation, message),
      onError: (Object _) => _onClosed(generation, socket),
      onDone: () => _onClosed(generation, socket),
      cancelOnError: true,
    );
    _setState(RelayConnectionState.connected);
    _sendPing(generation);
    _pingTimer = Timer.periodic(_pingInterval, (_) => _sendPing(generation));
  }

  void _sendPing(int generation) {
    final socket = _socket;
    if (generation != _generation || socket == null) {
      return;
    }
    try {
      socket.sendText('ping');
    } on Object {
      _dropAndReconnect();
      return;
    }
    _pongTimer ??= Timer(_pongTimeout, () {
      if (generation == _generation) {
        _dropAndReconnect();
      }
    });
  }

  void _onMessage(int generation, Object message) {
    if (generation != _generation) {
      return;
    }
    if (message is String) {
      if (message == 'pong') {
        _pongTimer?.cancel();
        _pongTimer = null;
        _backoff.reset();
      }
      return;
    }
    if (message is Uint8List) {
      final RelayFrame frame;
      try {
        frame = RelayFrame.decode(message);
      } on FrameFormatException {
        return;
      }
      _frames.add(frame);
    }
  }

  void _onClosed(int generation, RelaySocket socket) {
    if (generation != _generation) {
      return;
    }
    _abandonSocket();
    switch (socket.closeCode) {
      case RelayCloseCode.revoked:
        _setState(RelayConnectionState.revoked);
      case RelayCloseCode.replaced:
        _setState(RelayConnectionState.replaced);
      default:
        _scheduleReconnect();
    }
  }

  void _dropAndReconnect() {
    final socket = _abandonSocket();
    if (socket != null) {
      unawaited(_closeQuietly(socket, 1000));
    }
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _setState(RelayConnectionState.disconnected);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_backoff.next(), () => unawaited(_connect()));
  }

  /// Detaches from the current socket (if any) and invalidates callbacks.
  RelaySocket? _abandonSocket() {
    _generation++;
    _pingTimer?.cancel();
    _pingTimer = null;
    _pongTimer?.cancel();
    _pongTimer = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
    final socket = _socket;
    _socket = null;
    return socket;
  }

  static Future<void> _closeQuietly(RelaySocket socket, int code) async {
    try {
      await socket.close(code);
    } on Object {
      // The socket is being discarded; errors while closing do not matter.
    }
  }

  void _setState(RelayConnectionState next) {
    if (_state == next) {
      return;
    }
    _state = next;
    _states.add(next);
  }
}
