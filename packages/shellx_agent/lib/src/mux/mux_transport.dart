import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'mux_messages.dart';

/// A5b D4: one authenticated-later link. [messages] is a broadcast stream
/// (the handshake listens first, the session layer after it).
abstract interface class MuxConnection {
  Stream<MuxMessage> get messages;
  void send(MuxMessage message);

  /// Bytes given to [send] that the peer has not taken yet (A7 D24/D32
  /// back-pressure; additive to A5b D4). 0 when the transport cannot tell
  /// (the Windows pipe) and once closed.
  int get pendingBytes;

  /// Completes once [pendingBytes] is 0, or the link is closed.
  Future<void> get drained;

  /// Stops reading from the peer until [resumeInput]: the peer's writes
  /// then back up (in the OS buffer, for a socket). Messages already
  /// decoded are still delivered.
  void pauseInput();
  void resumeInput();

  Future<void> close();
  Future<void> get done;
}

/// Waiters for "nothing pending".
final class _Drain {
  Completer<void>? _waiting;

  Future<void> wait({required bool idle}) =>
      idle ? Future<void>.value() : (_waiting ??= Completer<void>()).future;

  void settle() {
    final c = _waiting;
    _waiting = null;
    c?.complete();
  }
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

/// A frame is pending for its sender until the receiver takes it: at once,
/// or on [resumeInput] when the receiver paused its input. Closing delivers
/// what was sent before it, like a socket.
final class _MemoryConnection implements MuxConnection {
  late _MemoryConnection _peer;
  final _in = StreamController<MuxMessage>.broadcast();
  final _decoder = MuxFrameDecoder();
  final _done = Completer<void>();
  final _inbox = Queue<Uint8List>();
  final _drain = _Drain();
  bool _closed = false;
  bool _paused = false;
  bool _closeWhenRead = false;
  int _pending = 0;

  @override
  Stream<MuxMessage> get messages => _in.stream;

  @override
  void send(MuxMessage message) {
    if (_closed || _peer._closed) return;
    final frame = encodeMux(message);
    _pending += frame.length;
    scheduleMicrotask(() => _peer._arrive(frame));
  }

  @override
  int get pendingBytes => _closed ? 0 : _pending;

  @override
  Future<void> get drained => _drain.wait(idle: _closed || _pending == 0);

  @override
  void pauseInput() => _paused = true;

  @override
  void resumeInput() {
    if (!_paused) return;
    _paused = false;
    while (_inbox.isNotEmpty && !_paused && !_closed) {
      _take(_inbox.removeFirst());
    }
    if (_closeWhenRead && _inbox.isEmpty) unawaited(close());
  }

  void _arrive(Uint8List frame) {
    if (_closed) {
      _peer._taken(frame.length);
    } else if (_paused) {
      _inbox.add(frame);
    } else {
      _take(frame);
    }
  }

  void _take(Uint8List frame) {
    _peer._taken(frame.length);
    try {
      for (final m in _decoder.add(frame)) {
        _in.add(m);
      }
    } on FormatException {
      unawaited(close());
    }
  }

  void _taken(int bytes) {
    _pending -= bytes;
    if (_pending == 0) _drain.settle();
  }

  /// The peer closed: read what it sent first (scheduled before this).
  void _peerClosed() {
    if (_closed) return;
    if (_inbox.isNotEmpty) {
      _closeWhenRead = true;
    } else {
      unawaited(close());
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final frame in _inbox) {
      _peer._taken(frame.length);
    }
    _inbox.clear();
    _drain.settle();
    // Not awaited: a paused listener (a handshake's StreamIterator between
    // moveNext calls) would hold the done event, and the close, forever.
    unawaited(_in.close());
    if (!_done.isCompleted) _done.complete();
    // After the frames this side already sent (FIFO microtasks).
    scheduleMicrotask(_peer._peerClosed);
  }

  @override
  Future<void> get done => _done.future;
}

abstract interface class MuxListener {
  Stream<MuxConnection> get connections;
  String get address;
  Future<void> close();
}

abstract interface class MuxTransport {
  Future<MuxListener> listen(String address);
  Future<MuxConnection> connect(
    String address, {
    Duration timeout = const Duration(seconds: 1),
  });
}

/// `sun_path` is 104 bytes on macOS (103 + NUL).
String socketPathFor({
  required String muxDirectory,
  required String tmpDirectory,
  required int uid,
}) {
  final preferred = '$muxDirectory/mux.sock';
  if (utf8.encode(preferred).length <= 103) return preferred;
  final tmp = tmpDirectory.endsWith('/') ? tmpDirectory : '$tmpDirectory/';
  return '${tmp}shellx-mux-$uid.sock';
}

/// Frames over any byte stream (Unix socket, Windows pipe isolate).
final class StreamMuxConnection implements MuxConnection {
  /// [flush] (optional) completes once everything written so far left the
  /// process; with it, [send] queues frames and [pendingBytes] counts them
  /// until flushed. Without it (the Windows pipe) nothing is counted.
  StreamMuxConnection(
    Stream<Uint8List> input,
    this._write,
    this._closeSink, {
    Future<void> Function()? flush,
  }) : _flush = flush {
    _sub = input.listen(
      (bytes) {
        try {
          for (final m in _decoder.add(bytes)) {
            _in.add(m);
          }
        } on FormatException {
          unawaited(close()); // D26: garbage closes the link
        }
      },
      onDone: () => unawaited(close()),
      onError: (Object _) => unawaited(close()),
    );
  }

  final void Function(Uint8List bytes) _write;
  final Future<void> Function() _closeSink;
  final Future<void> Function()? _flush;
  final _in = StreamController<MuxMessage>.broadcast();
  final _decoder = MuxFrameDecoder();
  final _done = Completer<void>();
  final _queue = Queue<Uint8List>();
  final _drain = _Drain();
  late final StreamSubscription<Uint8List> _sub;
  bool _closed = false;
  bool _paused = false;
  int _pending = 0;
  Future<void>? _pumping;

  /// How long [close] lets queued frames go out first.
  static const _flushOnClose = Duration(seconds: 1);

  @override
  Stream<MuxMessage> get messages => _in.stream;

  @override
  int get pendingBytes => _pending;

  @override
  Future<void> get drained => _drain.wait(idle: _pending == 0);

  @override
  void pauseInput() {
    if (_paused || _closed) return;
    _paused = true;
    _sub.pause();
  }

  @override
  void resumeInput() {
    if (!_paused) return;
    _paused = false;
    _sub.resume();
  }

  @override
  void send(MuxMessage message) {
    if (_closed) return;
    // Encoding errors (over 64 KiB, an unsupported value) are the caller's
    // bug: they propagate.
    final frame = encodeMux(message);
    if (_flush == null) {
      _writeNow(frame);
      return;
    }
    _queue.add(frame);
    _pending += frame.length;
    _pumping ??= _pump();
  }

  /// False when the sink is dead.
  bool _writeNow(Uint8List frame) {
    try {
      _write(frame);
      return true;
    } on StateError {
      // The sink is closed (peer vanished): the read side closes the link.
    } on SocketException {
      // Same, reported by the socket.
    }
    return false;
  }

  /// Writes what is queued, waits for the flush, repeats. Never throws.
  Future<void> _pump() async {
    try {
      while (_queue.isNotEmpty) {
        var bytes = 0;
        var alive = true;
        while (_queue.isNotEmpty && alive) {
          final frame = _queue.removeFirst();
          bytes += frame.length;
          alive = _writeNow(frame);
        }
        if (alive) {
          try {
            await _flush!();
          } on Object {
            // Peer gone (broken pipe) or the sink closed under the flush.
            alive = false;
          }
        }
        _pending -= bytes;
        if (!alive) {
          _queue.clear();
          _pending = 0;
          unawaited(close());
        }
      }
    } finally {
      _pumping = null;
      if (_pending == 0) _drain.settle();
    }
  }

  /// Always completes [done], even when the peer vanished with writes
  /// pending; never throws.
  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    // Frames sent before the close still go out (bounded).
    if (_pumping case final pump?) {
      try {
        await pump.timeout(_flushOnClose);
      } on TimeoutException {
        // Peer not reading: what is left is dropped below.
      }
    }
    Object? unexpected;
    StackTrace? trace;
    try {
      // Neither awaited: a cancel's future may belong to the root zone,
      // and a paused listener would hold `_in`'s done event (see
      // _MemoryConnection.close).
      unawaited(_sub.cancel().then((_) {}, onError: (Object _) {}));
      await _closeSink();
    } on StateError {
      // Closing a dead link: nothing left to release.
    } on SocketException {
      // Same.
    } on TimeoutException {
      // Same.
    } catch (e, s) {
      unexpected = e;
      trace = s;
    } finally {
      _queue.clear();
      _pending = 0;
      _drain.settle();
      unawaited(_in.close());
      if (!_done.isCompleted) _done.complete();
    }
    // A bug, not a dead peer: reported once `done` has completed.
    if (unexpected != null) {
      Zone.current.handleUncaughtError(unexpected, trace!);
    }
  }

  @override
  Future<void> get done => _done.future;
}

final class UnixMuxTransport implements MuxTransport {
  @override
  Future<MuxListener> listen(String address) async {
    // A socket left by a host that died is replaced. This relies on the
    // 0700 mux directory: no other account can plant a file here. Anything
    // that is not a socket is never deleted — bind then fails.
    if (await FileSystemEntity.type(address, followLinks: false) ==
        FileSystemEntityType.unixDomainSock) {
      await File(address).delete();
    }
    final server = await ServerSocket.bind(
      InternetAddress(address, type: InternetAddressType.unix),
      0,
    );
    final chmod = await Process.run('/bin/chmod', ['600', address]);
    if (chmod.exitCode != 0) {
      await server.close();
      throw FileSystemException('chmod 600 failed', address);
    }
    return _UnixListener(server, address);
  }

  @override
  Future<MuxConnection> connect(
    String address, {
    Duration timeout = const Duration(seconds: 1),
  }) async {
    final socket = await Socket.connect(
      InternetAddress(address, type: InternetAddressType.unix),
      0,
      timeout: timeout,
    );
    return _wrap(socket);
  }

  /// Pending writes get [_flushFor] to drain on close; then the socket is
  /// destroyed. Write errors (peer gone: broken pipe) surface on `done`,
  /// which is always handled here.
  static MuxConnection _wrap(Socket s) {
    unawaited(s.done.then((_) {}, onError: (Object _) {}));
    return StreamMuxConnection(s, s.add, flush: s.flush, () async {
      try {
        await s.close().timeout(_flushFor);
      } on SocketException {
        // Peer gone: drop what is left.
      } on TimeoutException {
        // Peer not reading: drop what is left.
      } finally {
        s.destroy();
      }
    });
  }

  static const _flushFor = Duration(seconds: 1);
}

final class _UnixListener implements MuxListener {
  _UnixListener(this._server, this.address);
  final ServerSocket _server;
  @override
  final String address;
  @override
  Stream<MuxConnection> get connections => _server.map(UnixMuxTransport._wrap);
  @override
  Future<void> close() async {
    await _server.close();
    try {
      await File(address).delete();
    } on FileSystemException {
      /* gone */
    }
  }
}
