import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';

/// Reads the agent's `endpoint` file: (port, secret).
(int, Uint8List) readEndpoint(String path) {
  final lines = File(path).readAsLinesSync();
  return (
    int.parse(lines[1].substring('port='.length)),
    Uint8List.fromList([
      for (var i = 0; i < 64; i += 2)
        int.parse(lines[2].substring(7 + i, 9 + i), radix: 16),
    ]),
  );
}

TermInfo termInfo({int id = 1, String app = 'Terminal'}) => TermInfo(
  termId: Uint8List.fromList(List.filled(16, id)),
  app: app,
  shell: 'zsh',
  pid: 4242,
  cols: 80,
  rows: 24,
  startedAt: 1759276800000,
);

/// Plays `shellx-term` over a real socket with the real codec.
final class FakeTerm {
  FakeTerm._(this._socket) {
    // Writes after the agent hung up fail asynchronously; that is expected.
    unawaited(_socket.done.then((_) {}, onError: (Object _) {}));
    _socket.listen(
      (chunk) {
        for (final payload in _reader.add(chunk)) {
          _received.add(AgentToTerm.decode(payload));
        }
      },
      onDone: () {
        if (!_closed.isCompleted) _closed.complete();
        _received.close();
      },
      onError: (Object _) {},
    );
  }

  static Future<FakeTerm> connect(int port) async =>
      FakeTerm._(await Socket.connect(InternetAddress.loopbackIPv4, port));

  final Socket _socket;
  final _reader = TermFrameReader();
  final _received = StreamController<AgentToTerm?>();
  late final _next = StreamIterator(_received.stream);
  final _closed = Completer<void>();

  /// Completes when the agent closes the connection.
  Future<void> get closed => _closed.future;

  void send(TermToAgent message) => sendRaw(termFrame(message.encode()));

  void sendRaw(List<int> bytes) => _socket.add(bytes);

  /// The next message from the agent, or null when the connection ended.
  Future<AgentToTerm?> next({
    Duration timeout = const Duration(seconds: 5),
  }) async => await _next.moveNext().timeout(timeout) ? _next.current : null;

  /// Runs the full handshake; returns the agent's answer to `auth`.
  Future<AgentToTerm?> handshake(
    Uint8List secret, {
    TermInfo? info,
    bool wrongProof = false,
  }) async {
    final nonce = Uint8List.fromList(List.generate(32, (i) => i + 1));
    send(TermHello(v: 1, nonce: nonce));
    final challenge = await next();
    if (challenge is! AgentChallenge) return challenge;
    final proof = termProof(
      wrongProof ? Uint8List(32) : secret,
      challenge.nonce,
      nonce,
    );
    send(TermAuth(mac: proof, info: info ?? termInfo()));
    return next();
  }

  void destroy() => _socket.destroy();
}

/// Whether something on [port] still completes the agent handshake.
Future<bool> stillServes(int port, Uint8List secret) async {
  FakeTerm term;
  try {
    term = await FakeTerm.connect(port);
  } on SocketException {
    return false;
  }
  try {
    final answer = await term
        .handshake(secret)
        .timeout(const Duration(seconds: 2));
    return answer is AgentReady;
  } on Object {
    return false;
  }
}
