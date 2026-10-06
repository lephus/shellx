import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show visibleForTesting;
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
  IsolateMatchScanner(
    this.pattern, {
    this.limit = const Duration(seconds: 1),
    @visibleForTesting MatchWorker worker = _worker,
  }) : _entry = worker;

  /// The client's pattern, already known to compile.
  final String pattern;
  final Duration limit;
  final MatchWorker _entry;

  Isolate? _isolate;
  SendPort? _toWorker;
  ReceivePort? _fromWorker;
  StreamIterator<Object?>? _replies;
  bool _closed = false;

  static const _tooSlow = CliFailure(
    MuxError.badRequest,
    'pattern is too slow',
  );

  /// The worker failed (Task 7 review): not the client's fault, and never
  /// reported as a slow pattern.
  static const _failed = CliFailure(
    MuxError.internal,
    'the pattern could not be run',
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
    return switch (replies.current) {
      null => null,
      [final int start, final int end] => (start: start, end: end),
      // `_failedReply`, or an uncaught error `[message, stack]` (onError).
      _ => () {
        close();
        throw _failed;
      }(),
    };
  }

  Future<StreamIterator<Object?>> _start() async {
    final ready = _replies;
    if (ready != null) return ready;
    final port = _fromWorker = ReceivePort();
    final replies = _replies = StreamIterator<Object?>(port);
    _isolate = await Isolate.spawn(
      _entry,
      (port.sendPort, pattern),
      onError: port.sendPort,
      debugName: 'shellx wait --match',
    );
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

/// A worker isolate's entry: gets the reply port and the pattern, sends
/// its own inbox port, then answers each text.
typedef MatchWorker = void Function((SendPort, String) args);

/// What a worker answers when a scan threw.
const _failedReply = 'failed';

/// Worker: compiles the pattern once, then answers each text with
/// `[start, end]` of the first match, null, or [_failedReply].
void _worker((SendPort, String) args) {
  final (reply, pattern) = args;
  final inbox = ReceivePort();
  reply.send(inbox.sendPort);
  final RegExp re;
  try {
    re = RegExp(pattern, multiLine: true);
  } on Object {
    inbox.listen((_) => reply.send(_failedReply));
    return;
  }
  inbox.listen((text) {
    try {
      final m = re.firstMatch(text as String);
      reply.send(m == null ? null : [m.start, m.end]);
    } on Object {
      reply.send(_failedReply);
    }
  });
}
