import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

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
