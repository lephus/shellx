import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
  StreamMuxConnection(Stream<Uint8List> input, this._write, this._closeSink) {
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
  final _in = StreamController<MuxMessage>.broadcast();
  final _decoder = MuxFrameDecoder();
  final _done = Completer<void>();
  late final StreamSubscription<Uint8List> _sub;
  bool _closed = false;

  @override
  Stream<MuxMessage> get messages => _in.stream;

  @override
  void send(MuxMessage message) {
    if (_closed) return;
    // Encoding errors (over 64 KiB, an unsupported value) are the caller's
    // bug: they propagate.
    final frame = encodeMux(message);
    try {
      _write(frame);
    } on StateError {
      // The sink is closed (peer vanished): the read side closes the link.
    } on SocketException {
      // Same, reported by the socket.
    }
  }

  /// Always completes [done], even when the peer vanished with writes
  /// pending; never throws.
  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
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
    return StreamMuxConnection(s, s.add, () async {
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
