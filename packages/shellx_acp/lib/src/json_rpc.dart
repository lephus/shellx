import 'dart:async';
import 'dart:convert';

/// A decoded JSON object.
typedef JsonMap = Map<String, Object?>;

/// Why a [JsonRpcConnection] stopped.
enum ConnectionCloseReason {
  /// The peer's output ended (the process exited or closed stdout).
  ended,

  /// [JsonRpcConnection.close] was called.
  closed,

  /// A line grew past `maxLineChars` (spec §6: 64 MiB).
  lineTooLong,

  /// More than `maxBadLines` lines in a row were not JSON-RPC (spec §6: 20).
  tooManyBadLines,
}

/// A JSON-RPC error: received in a response, or thrown by a handler to
/// answer a request with it.
///
/// [toString] shows only [code]: [message] and [data] come from the agent
/// and may quote the user's files or prompt (spec D20).
final class JsonRpcError implements Exception {
  const JsonRpcError(this.code, this.message, [this.data]);

  static const parseError = -32700;
  static const invalidRequest = -32600;
  static const methodNotFound = -32601;
  static const invalidParams = -32602;
  static const internalError = -32603;

  /// ACP: the agent needs the user to sign in first (spec D8).
  static const authRequired = -32000;

  /// ACP: for example `session/load` of a session the agent no longer has.
  static const resourceNotFound = -32002;

  final int code;
  final String message;
  final Object? data;

  JsonMap toJson() => {
    'code': code,
    'message': message,
    if (data != null) 'data': data,
  };

  @override
  String toString() => 'JsonRpcError($code)';
}

/// A request could not complete: the connection is closed.
final class ConnectionClosed implements Exception {
  const ConnectionClosed(this.reason);

  final ConnectionCloseReason reason;

  @override
  String toString() => 'ConnectionClosed(${reason.name})';
}

/// Answers one incoming request; throw [JsonRpcError] to answer an error.
typedef RequestHandler = FutureOr<Object?> Function(JsonMap params);

/// Receives one incoming notification.
typedef NotificationHandler = void Function(JsonMap params);

/// JSON-RPC 2.0 over newline-delimited UTF-8 (ACP's stdio transport).
///
/// Symmetric: either end may send requests and notifications. Lines that
/// are not JSON-RPC are skipped; more than [maxBadLines] in a row, or one
/// line longer than [maxLineChars], close the connection (spec §6).
/// Incoming messages are handled in order, synchronously as their line
/// completes, so a notification always reaches its handler before a later
/// response completes its request.
final class JsonRpcConnection {
  JsonRpcConnection({
    required Stream<List<int>> input,
    required StreamSink<List<int>> output,
    this.maxLineChars = 64 * 1024 * 1024,
    this.maxBadLines = 20,
  }) : _output = output {
    _sub = input
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(
          _onChunk,
          onError: (Object _) => _shutdown(ConnectionCloseReason.ended),
          onDone: () => _shutdown(ConnectionCloseReason.ended),
        );
    // A write to a process that exited fails on `done`; the input side
    // reports the end, so the error itself is dropped.
    output.done.then<void>((_) {}, onError: (Object _) {});
  }

  /// Longest accepted line, in UTF-16 code units (≈ bytes for JSON).
  final int maxLineChars;

  /// Bad lines tolerated in a row; one more closes the connection.
  final int maxBadLines;

  final StreamSink<List<int>> _output;
  late final StreamSubscription<String> _sub;
  final _requestHandlers = <String, RequestHandler>{};
  final _notificationHandlers = <String, NotificationHandler>{};
  final _pending = <int, Completer<Object?>>{};
  final _done = Completer<ConnectionCloseReason>();
  final _line = StringBuffer();
  var _lineLength = 0;
  var _badLines = 0;
  var _nextId = 0;
  ConnectionCloseReason? _reason;

  /// Completes once, with the reason, when the connection stops.
  Future<ConnectionCloseReason> get done => _done.future;

  bool get isClosed => _reason != null;

  ConnectionCloseReason? get closeReason => _reason;

  void onRequest(String method, RequestHandler handler) =>
      _requestHandlers[method] = handler;

  void onNotification(String method, NotificationHandler handler) =>
      _notificationHandlers[method] = handler;

  /// Sends a request; completes with its `result`, or fails with
  /// [JsonRpcError] or [ConnectionClosed].
  Future<Object?> request(String method, [JsonMap? params]) {
    final reason = _reason;
    if (reason != null) return Future.error(ConnectionClosed(reason));
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _send({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': ?params});
    return completer.future;
  }

  /// Sends a notification; does nothing once closed.
  void notify(String method, [JsonMap? params]) {
    if (_reason != null) return;
    _send({'jsonrpc': '2.0', 'method': method, 'params': ?params});
  }

  /// Stops reading, fails pending requests and closes the output (for an
  /// agent process: closes its stdin).
  Future<void> close() async {
    _shutdown(ConnectionCloseReason.closed);
    await _done.future;
  }

  void _onChunk(String chunk) {
    var start = 0;
    while (_reason == null) {
      final nl = chunk.indexOf('\n', start);
      final end = nl < 0 ? chunk.length : nl;
      _lineLength += end - start;
      if (_lineLength > maxLineChars) {
        _shutdown(ConnectionCloseReason.lineTooLong);
        return;
      }
      if (start == 0 && end == chunk.length) {
        _line.write(chunk);
      } else {
        _line.write(chunk.substring(start, end));
      }
      if (nl < 0) return;
      final line = _line.toString();
      _line.clear();
      _lineLength = 0;
      _handleLine(line);
      start = nl + 1;
    }
  }

  void _handleLine(String raw) {
    final line = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
    if (line.trim().isEmpty) return;
    final Object? message;
    try {
      message = jsonDecode(line);
    } on FormatException {
      _badLine();
      return;
    }
    if (message is! JsonMap) {
      _badLine();
      return;
    }
    final method = message['method'];
    if (method is String) {
      _badLines = 0;
      final params = message['params'];
      final p = params is JsonMap ? params : <String, Object?>{};
      if (message.containsKey('id')) {
        unawaited(_answer(message['id'], method, p));
      } else {
        final handler = _notificationHandlers[method];
        if (handler != null) {
          try {
            handler(p);
          } catch (e, s) {
            Zone.current.handleUncaughtError(e, s);
          }
        }
      }
      return;
    }
    if (message.containsKey('id') &&
        (message.containsKey('result') || message.containsKey('error'))) {
      _badLines = 0;
      _complete(message);
      return;
    }
    _badLine();
  }

  void _badLine() {
    if (++_badLines > maxBadLines) {
      _shutdown(ConnectionCloseReason.tooManyBadLines);
    }
  }

  Future<void> _answer(Object? id, String method, JsonMap params) async {
    final handler = _requestHandlers[method];
    if (handler == null) {
      _send({
        'jsonrpc': '2.0',
        'id': id,
        'error': const JsonRpcError(
          JsonRpcError.methodNotFound,
          'Method not found',
        ).toJson(),
      });
      return;
    }
    try {
      final result = await handler(params);
      _send({'jsonrpc': '2.0', 'id': id, 'result': result});
    } on JsonRpcError catch (e) {
      _send({'jsonrpc': '2.0', 'id': id, 'error': e.toJson()});
    } catch (e, s) {
      _send({
        'jsonrpc': '2.0',
        'id': id,
        'error': const JsonRpcError(
          JsonRpcError.internalError,
          'Internal error',
        ).toJson(),
      });
      Zone.current.handleUncaughtError(e, s);
    }
  }

  void _complete(JsonMap message) {
    final id = message['id'];
    final completer = id is int ? _pending.remove(id) : null;
    if (completer == null) return;
    if (message.containsKey('error')) {
      final error = message['error'];
      final code = error is JsonMap ? error['code'] : null;
      final text = error is JsonMap ? error['message'] : null;
      completer.completeError(
        JsonRpcError(
          code is int ? code : JsonRpcError.internalError,
          text is String ? text : '',
          error is JsonMap ? error['data'] : null,
        ),
      );
    } else {
      completer.complete(message['result']);
    }
  }

  void _send(JsonMap message) {
    if (_reason != null) return;
    final bytes = utf8.encode('${jsonEncode(message)}\n');
    try {
      _output.add(bytes);
    } on Object {
      // The pipe is gone; the input side reports the end.
    }
  }

  void _shutdown(ConnectionCloseReason reason) {
    if (_reason != null) return;
    _reason = reason;
    unawaited(_sub.cancel());
    final pending = [..._pending.values];
    _pending.clear();
    for (final c in pending) {
      c.completeError(ConnectionClosed(reason));
    }
    try {
      unawaited(_output.close().then<void>((_) {}, onError: (Object _) {}));
    } on Object {
      // Already closed.
    }
    _done.complete(reason);
  }
}
