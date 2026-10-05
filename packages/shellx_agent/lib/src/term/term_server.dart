import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';

import 'term_auth.dart';
import 'term_endpoint.dart';
import 'term_frames.dart';
import 'term_link.dart';
import 'term_messages.dart';

/// The agent's loopback port for `shellx-term` (spec §6.1, §6.3). [start]
/// binds `127.0.0.1` on a port the OS picks, makes a fresh 32-byte secret
/// and writes the `endpoint` file; [stop] closes the port, every pending
/// handshake and every link, and deletes the file if it is still ours.
///
/// Each connection must finish the handshake within [handshakeTimeout]
/// (counted over the whole handshake, so a byte-by-byte trickle cannot hold
/// it open). `admit` decides `reject limit` once `auth` is verified (spec
/// §7.8 step 3: a reconnecting window must never be turned away).
///
/// [start] and [stop] must not overlap: the caller serializes them
/// (`TerminalSharing` queues both).
final class TermServer {
  TermServer({
    required String endpointPath,
    required bool Function(TermInfo info) admit,
    required void Function(TermLink link) onLink,
    Duration handshakeTimeout = const Duration(seconds: 5),
    Random? random,
    bool? posix,
  }) : _endpoint = EndpointFile(endpointPath, posix: posix),
       _admit = admit,
       _onLink = onLink,
       _handshakeTimeout = handshakeTimeout,
       _random = random ?? Random.secure();

  final EndpointFile _endpoint;
  final bool Function(TermInfo info) _admit;
  final void Function(TermLink link) _onLink;
  final Duration _handshakeTimeout;
  final Random _random;

  ServerSocket? _server;
  String? _contents;
  final _connections = <_Connection>{};

  bool get running => _server != null;
  int? get port => _server?.port;

  /// Throws when the port cannot be opened or the file cannot be written;
  /// nothing stays open then.
  Future<void> start() async {
    if (_server != null) return;
    final secret = Uint8List.fromList(
      List.generate(32, (_) => _random.nextInt(256)),
    );
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((socket) => _accept(socket, secret), onError: (Object _) {});
    try {
      _contents = await _endpoint.write(server.port, secret);
    } catch (_) {
      await server.close();
      rethrow;
    }
    _server = server;
  }

  Future<void> stop() async {
    final server = _server;
    if (server == null) return;
    _server = null;
    final contents = _contents!;
    _contents = null;
    for (final connection in _connections.toList()) {
      connection.close();
    }
    await server.close();
    await _endpoint.deleteIfOwned(contents);
  }

  void _accept(Socket socket, Uint8List secret) {
    final connection = _Connection(
      socket: socket,
      secret: secret,
      admit: _admit,
      random: _random,
      timeout: _handshakeTimeout,
      onReady: (link) {
        if (_server == null) {
          link.close();
          return;
        }
        _onLink(link);
      },
    );
    _connections.add(connection);
    connection.done.then((_) => _connections.remove(connection));
  }
}

enum _Stage { hello, auth, ready }

/// One accepted socket: the handshake, then the [TermLink].
final class _Connection implements TermLink {
  _Connection({
    required Socket socket,
    required Uint8List secret,
    required bool Function(TermInfo info) admit,
    required Random random,
    required Duration timeout,
    required void Function(TermLink link) onReady,
  }) : _socket = socket,
       _secret = secret,
       _admit = admit,
       _random = random,
       _onReady = onReady {
    _deadline = Timer(timeout, close);
    _subscription = socket.listen(
      _onBytes,
      onDone: close,
      onError: (Object _) => close(),
      cancelOnError: true,
    );
  }

  final Socket _socket;
  final Uint8List _secret;
  final bool Function(TermInfo info) _admit;
  final Random _random;
  final void Function(TermLink link) _onReady;
  final _reader = TermFrameReader();
  final _messages = StreamController<TermToAgent>();
  final _done = Completer<void>();
  late final Timer _deadline;
  late final StreamSubscription<Uint8List> _subscription;

  _Stage _stage = _Stage.hello;
  Uint8List? _nonceTerm;
  Uint8List? _nonceAgent;
  TermInfo? _info;
  bool _closed = false;

  final _queue = <Uint8List>[];
  int _queued = 0;
  bool _flushing = false;
  bool _closeWhenFlushed = false;

  Future<void> get done => _done.future;

  @override
  TermInfo get info => _info!;

  @override
  Stream<TermToAgent> get messages => _messages.stream;

  @override
  void send(AgentToTerm message) {
    if (_stage == _Stage.ready) _write(message);
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _deadline.cancel();
    _queue.clear();
    unawaited(_subscription.cancel());
    _socket.destroy();
    unawaited(_messages.close());
    _done.complete();
  }

  void _onBytes(Uint8List chunk) {
    final List<Uint8List> payloads;
    try {
      payloads = _reader.add(chunk);
    } on FormatException {
      close();
      return;
    }
    for (final payload in payloads) {
      if (_closed || _closeWhenFlushed) return;
      _onPayload(payload);
    }
  }

  void _onPayload(Uint8List payload) {
    final TermToAgent? message;
    try {
      message = TermToAgent.decode(payload);
    } on FormatException {
      close();
      return;
    }
    switch (_stage) {
      case _Stage.hello:
        if (message is! TermHello) return close();
        if (message.v != kTermProtocolVersion) {
          return _rejectAndClose(AgentReject.version);
        }
        final nonceAgent = Uint8List.fromList(
          List.generate(32, (_) => _random.nextInt(256)),
        );
        _nonceTerm = message.nonce;
        _nonceAgent = nonceAgent;
        _stage = _Stage.auth;
        _write(
          AgentChallenge(
            nonce: nonceAgent,
            mac: agentProof(_secret, message.nonce, nonceAgent),
          ),
        );
      case _Stage.auth:
        if (message is! TermAuth) return close();
        final expected = termProof(_secret, _nonceAgent!, _nonceTerm!);
        if (!constantTimeEquals(message.mac, expected)) return close();
        if (!_admit(message.info)) return _rejectAndClose(AgentReject.limit);
        _info = message.info;
        _deadline.cancel();
        _stage = _Stage.ready;
        _write(const AgentReady());
        _onReady(this);
      case _Stage.ready:
        if (message != null) _messages.add(message);
    }
  }

  void _rejectAndClose(String reason) {
    _write(AgentReject(reason: reason));
    _closeWhenFlushed = true;
    if (!_flushing) close();
  }

  void _write(AgentToTerm message) {
    if (_closed) return;
    final frame = termFrame(message.encode());
    _queued += frame.length;
    if (_queued > kTermMaxQueuedBytes) return close();
    _queue.add(frame);
    unawaited(_flush());
  }

  Future<void> _flush() async {
    if (_flushing) return;
    _flushing = true;
    try {
      while (_queue.isNotEmpty && !_closed) {
        final frame = _queue.removeAt(0);
        _socket.add(frame);
        await _socket.flush();
        _queued -= frame.length;
      }
    } catch (_) {
      close();
    } finally {
      _flushing = false;
      if (_closeWhenFlushed) close();
    }
  }
}
