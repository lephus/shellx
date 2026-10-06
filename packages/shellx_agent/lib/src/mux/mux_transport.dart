import 'dart:async';
import 'dart:typed_data';

import 'mux_messages.dart';

/// A5b D4: one authenticated-later link. [messages] is a broadcast stream
/// (the handshake listens first, the session layer after it).
abstract interface class MuxConnection {
  Stream<MuxMessage> get messages;
  void send(MuxMessage message);
  Future<void> close();
  Future<void> get done;
}

/// Byte-faithful in-memory pair (every message is framed and decoded).
final class MemoryMuxTransport {
  static (MuxConnection, MuxConnection) pair() {
    final a = _MemoryConnection(), b = _MemoryConnection();
    a._peer = b;
    b._peer = a;
    return (a, b);
  }
}

final class _MemoryConnection implements MuxConnection {
  late _MemoryConnection _peer;
  final _in = StreamController<MuxMessage>.broadcast();
  final _decoder = MuxFrameDecoder();
  final _done = Completer<void>();
  bool _closed = false;

  @override
  Stream<MuxMessage> get messages => _in.stream;

  @override
  void send(MuxMessage message) {
    if (_closed || _peer._closed) return;
    final frame = encodeMux(message);
    scheduleMicrotask(() => _peer._receive(frame));
  }

  void _receive(Uint8List bytes) {
    if (_closed) return;
    try {
      for (final m in _decoder.add(bytes)) {
        _in.add(m);
      }
    } on FormatException {
      unawaited(close());
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    // Not awaited: a paused listener (a handshake's StreamIterator between
    // moveNext calls) would hold the done event, and the close, forever.
    unawaited(_in.close());
    if (!_done.isCompleted) _done.complete();
    unawaited(_peer.close());
  }

  @override
  Future<void> get done => _done.future;
}
