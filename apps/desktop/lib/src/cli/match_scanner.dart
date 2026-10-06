import 'dart:async';
import 'dart:isolate';

import 'package:shellx_agent/shellx_agent.dart';

/// Where a pattern first matched a text.
typedef MatchSpan = ({int start, int end});

/// Runs a `wait --match` pattern over pane text (A7 D21).
abstract interface class MatchScanner {
  /// The first match in [text], or null. Throws [CliFailure].
  Future<MatchSpan?> scan(String text);

  /// Ends the scanner; later [scan]s are not allowed.
  void close();
}

/// A7 Task 7 review M1: a client's pattern never runs on the UI isolate.
/// Each wait gets its own worker isolate, started at the first [scan]; a
/// scan that takes longer than [limit] (catastrophic backtracking) kills
/// the worker and fails with `bad_request` "pattern is too slow".
final class IsolateMatchScanner implements MatchScanner {
  IsolateMatchScanner(this.pattern, {this.limit = const Duration(seconds: 1)});

  /// The client's pattern, already known to compile.
  final String pattern;
  final Duration limit;

  Isolate? _isolate;
  SendPort? _toWorker;
  ReceivePort? _fromWorker;
  StreamIterator<Object?>? _replies;
  bool _closed = false;

  static const _tooSlow = CliFailure(
    MuxError.badRequest,
    'pattern is too slow',
  );

  @override
  Future<MatchSpan?> scan(String text) async {
    if (_closed) throw StateError('closed');
    final replies = await _start();
    _toWorker!.send(text);
    final bool got;
    try {
      got = await replies.moveNext().timeout(limit);
    } on TimeoutException {
      close();
      throw _tooSlow;
    }
    if (!got) throw StateError('closed');
    final reply = replies.current;
    if (reply is List && reply.length == 2) {
      return (start: reply[0] as int, end: reply[1] as int);
    }
    return null;
  }

  Future<StreamIterator<Object?>> _start() async {
    final ready = _replies;
    if (ready != null) return ready;
    final port = _fromWorker = ReceivePort();
    final replies = _replies = StreamIterator<Object?>(port);
    _isolate = await Isolate.spawn(_worker, (
      port.sendPort,
      pattern,
    ), debugName: 'shellx wait --match');
    if (_closed) {
      _isolate?.kill(priority: Isolate.immediate);
      throw StateError('closed');
    }
    if (!await replies.moveNext() || replies.current is! SendPort) {
      throw StateError('closed');
    }
    _toWorker = replies.current! as SendPort;
    return replies;
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _fromWorker?.close();
    unawaited(_replies?.cancel());
  }
}

/// Worker: compiles the pattern once, then answers each text with
/// `[start, end]` of the first match, or null.
void _worker((SendPort, String) args) {
  final (reply, pattern) = args;
  final re = RegExp(pattern, multiLine: true);
  final inbox = ReceivePort();
  reply.send(inbox.sendPort);
  inbox.listen((text) {
    final m = re.firstMatch(text as String);
    reply.send(m == null ? null : [m.start, m.end]);
  });
}
