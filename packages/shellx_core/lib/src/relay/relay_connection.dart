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
/// `httpStatusCode` is the HTTP status. Uses a fresh [HttpClient] per
/// attempt with a bounded `connectionTimeout` so a stalled TCP/TLS connect
/// settles instead of hanging indefinitely, plus an overall deadline on
/// the whole upgrade (`connectionTimeout` only covers DNS/TCP/TLS, not a
/// slow or silent HTTP response — for example a stuck HTTPS proxy
/// `CONNECT` — so the upgrade GET/response is bounded separately): on
/// expiry the in-flight connection is force-closed so it can never
/// register with the relay later, and the returned future fails with a
/// [TimeoutException]. [RelayConnection] relies on every dial eventually
/// completing to keep at most one upgrade attempt outstanding at a time.
Future<RelaySocket> ioRelaySocketConnector(
  Uri uri,
  Map<String, String> headers,
) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final socket =
        await WebSocket.connect(
          uri.toString(),
          headers: headers,
          customClient: client,
        ).timeout(
          const Duration(seconds: 12),
          onTimeout: () {
            // Destroy the in-flight connection so it cannot complete the
            // upgrade and register with the relay after we've moved on.
            client.close(force: true);
            throw TimeoutException(
              'WebSocket upgrade to $uri did not complete in time',
            );
          },
        );
    return _IoRelaySocket(socket);
  } finally {
    client.close();
  }
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
/// * Never has two upgrade attempts outstanding at once: the relay keeps
///   only the newest connection per device, so a new attempt (a backoff
///   retry, [reconnectNow], or [start] after [stop]) waits for any attempt
///   still outstanding at the network level to settle — and lets it be
///   closed — before dialing again, instead of racing it and risking the
///   live connection being replaced by a stale one that registers late.
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

  /// The raw connector call currently in flight, if any. A new attempt
  /// waits for this to settle before dialing again, so at most one
  /// upgrade is ever outstanding (see [_connect]).
  Future<RelaySocket>? _dialing;

  /// Set to the [_dialing] value we already waited out a full
  /// [connectTimeout] for, without it settling. Once a specific stale
  /// dial is marked this way, later attempts stop waiting on it (see
  /// [_connect]) instead of blocking forever on a dial that never settles.
  Future<RelaySocket>? _dialGivenUpOn;

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

    // Never have two upgrade attempts outstanding at once: if an attempt
    // we already gave up on locally (after `connectTimeout`, or because
    // `stop()`/a fresh `start()` superseded it) hasn't actually settled at
    // the network level yet, wait for it here before dialing again.
    // Whoever gave up on that attempt remains responsible for closing
    // whatever it eventually produces (see the two `_closeQuietly` calls
    // below) — this wait only stops a second upgrade from racing it.
    //
    // The wait itself is bounded by `connectTimeout`: a dial that never
    // settles (the real connector is bounded — see `ioRelaySocketConnector`
    // — but a test double might not be) would otherwise wedge every future
    // attempt forever, and `reconnectNow`/`start` would stay no-ops since
    // `state` would never leave `connecting`. If the stale dial still
    // hasn't settled after one full `connectTimeout`, treat this attempt
    // as failed (disconnected + backoff, so `reconnectNow` works again),
    // and remember it so the *next* attempt stops waiting on it entirely
    // and dials fresh instead — the relay's newest-wins behavior then
    // favors the new dial, and the stale socket, if it ever arrives, is
    // still closed by the existing stale-generation cleanup below.
    final stale = _dialing;
    if (stale != null && !identical(stale, _dialGivenUpOn)) {
      // We're genuinely attempting a (re)connection even though we haven't
      // dialed yet, so reflect that immediately instead of leaving `state`
      // on whatever it was while we wait for the stale dial to clear.
      _setState(RelayConnectionState.connecting);
      final cleared = await stale
          .then<bool>((_) => true, onError: (Object _) => true)
          .timeout(connectTimeout, onTimeout: () => false);
      if (generation != _generation) {
        return;
      }
      if (!cleared) {
        _dialGivenUpOn = stale;
        _scheduleReconnect();
        return;
      }
    }

    final String? token;
    try {
      token = _token();
    } on Object {
      _scheduleReconnect();
      return;
    }
    if (token == null) {
      _setState(RelayConnectionState.revoked);
      return;
    }
    // Reached only once we're actually about to dial: a null token never
    // flashes through `connecting` on its way to `revoked` (no-op if the
    // stale-dial wait above already set it).
    _setState(RelayConnectionState.connecting);
    final pending = Future.sync(
      () => _connector(_wsUri, {'Authorization': 'Bearer $token'}),
    );
    _dialing = pending;
    void clearDialing(Object? _) {
      if (identical(_dialing, pending)) {
        _dialing = null;
      }
    }

    unawaited(pending.then(clearDialing, onError: clearDialing));
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
    // Only keep pinging if the first ping actually went out for this
    // generation; a throw already dropped and rescheduled the connection.
    if (generation == _generation) {
      _pingTimer = Timer.periodic(_pingInterval, (_) => _sendPing(generation));
    }
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
      } on Object {
        // Any failure to decode (not just FrameFormatException) means the
        // frame is dropped rather than crashing the connection: a same-
        // account device or a compromised relay controls these bytes.
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
    unawaited(_closeQuietly(socket, 1000));
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
