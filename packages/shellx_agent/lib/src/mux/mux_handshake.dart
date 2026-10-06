import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';

import '../term/term_auth.dart';
import 'mux_messages.dart';
import 'mux_transport.dart';

final _daemonLabel = utf8.encode('shellx-mux/daemon');
final _clientLabel = utf8.encode('shellx-mux/client');

Uint8List daemonProof(
  Uint8List secret,
  Uint8List nonceClient,
  Uint8List nonceDaemon,
) => hmacSha256(secret, concatBytes([_daemonLabel, nonceClient, nonceDaemon]));

Uint8List clientProof(
  Uint8List secret,
  Uint8List nonceDaemon,
  Uint8List nonceClient,
) => hmacSha256(secret, concatBytes([_clientLabel, nonceDaemon, nonceClient]));

final class MuxHandshakeException implements Exception {
  const MuxHandshakeException(this.reason);
  final String reason;
  @override
  String toString() => 'MuxHandshakeException: $reason';
}

final class MuxPeerInfo {
  const MuxPeerInfo({
    required this.protocol,
    required this.app,
    this.role,
    this.instance,
    this.pid,
    this.sessions,
    this.caps = const [],
    this.token,
  });
  final int protocol;
  final String app;
  final String? role;
  final String? instance;
  final int? pid;
  final int? sessions;
  final List<String> caps;

  /// A7 amendment (A5b D7 additive): the client's optional `auth.token`,
  /// as the host received it. Never logged.
  final String? token;
}

Uint8List _nonce() {
  final r = Random.secure();
  return Uint8List.fromList(List.generate(32, (_) => r.nextInt(256)));
}

bool _same(Uint8List a, Uint8List? b) {
  if (b == null || a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// D6, client side: hello → verify the daemon's proof → auth → ready.
/// [token] (A7 amendment) goes in `auth`, so only a host that proved the
/// secret ever sees it.
Future<MuxPeerInfo> clientHandshake(
  MuxConnection c, {
  required Uint8List secret,
  required String app,
  required String role,
  Duration timeout = const Duration(seconds: 2),
  String? token,
}) async {
  final nonceClient = _nonce();
  final incoming = StreamIterator(c.messages);
  try {
    c.send(
      MuxMessage(
        MuxType.hello,
        fields: {
          'protocol': kMuxProtocol,
          'app': app,
          'role': role,
          'nonce': nonceClient,
        },
      ),
    );
    final hello = await _next(incoming, MuxType.hello, timeout);
    final nonceDaemon = hello.get<Uint8List>('nonce');
    if (nonceDaemon == null ||
        !_same(
          daemonProof(secret, nonceClient, nonceDaemon),
          hello.get<Uint8List>('proof'),
        )) {
      throw const MuxHandshakeException('daemon proof');
    }
    c.send(
      MuxMessage(
        MuxType.auth,
        fields: {
          'proof': clientProof(secret, nonceDaemon, nonceClient),
          // A7: only now, after the host proved the secret.
          'token': ?token,
        },
      ),
    );
    await _next(incoming, MuxType.ready, timeout);
    return MuxPeerInfo(
      protocol: hello.get<int>('protocol') ?? -1,
      app: hello.get<String>('app') ?? '',
      instance: hello.get<String>('instance'),
      pid: hello.get<int>('pid'),
      sessions: hello.get<int>('sessions'),
      caps: [
        for (final c in hello.get<List<Object?>>('caps') ?? const []) '$c',
      ],
    );
  } on MuxHandshakeException {
    await c.close();
    rethrow;
  } finally {
    // Hands the stream back: later messages go to the caller's listener.
    // Not awaited: the cancel takes effect at once, and its future may
    // belong to the root zone (it would escape a fake clock).
    unawaited(incoming.cancel());
  }
}

/// D6, daemon side. Returns the client's info; throws (and closes) on a
/// wrong proof or timeout.
Future<MuxPeerInfo> serverHandshake(
  MuxConnection c, {
  required Uint8List secret,
  required MuxPeerInfo self,
  Duration timeout = const Duration(seconds: 2),
}) async {
  final incoming = StreamIterator(c.messages);
  try {
    final hello = await _next(incoming, MuxType.hello, timeout);
    final nonceClient = hello.get<Uint8List>('nonce');
    if (nonceClient == null || nonceClient.length != 32) {
      throw const MuxHandshakeException('client nonce');
    }
    final nonceDaemon = _nonce();
    c.send(
      MuxMessage(
        MuxType.hello,
        fields: {
          'protocol': self.protocol,
          'app': self.app,
          'nonce': nonceDaemon,
          'proof': daemonProof(secret, nonceClient, nonceDaemon),
          'instance': self.instance,
          'pid': self.pid,
          'sessions': self.sessions,
          'caps': self.caps,
        },
      ),
    );
    final auth = await _next(incoming, MuxType.auth, timeout);
    if (!_same(
      clientProof(secret, nonceDaemon, nonceClient),
      auth.get<Uint8List>('proof'),
    )) {
      throw const MuxHandshakeException('client proof');
    }
    c.send(const MuxMessage(MuxType.ready));
    return MuxPeerInfo(
      protocol: hello.get<int>('protocol') ?? -1,
      app: hello.get<String>('app') ?? '',
      role: hello.get<String>('role'),
      token: auth.get<String>('token'),
    );
  } on MuxHandshakeException {
    await c.close();
    rethrow;
  } finally {
    unawaited(incoming.cancel());
  }
}

Future<MuxMessage> _next(
  StreamIterator<MuxMessage> it,
  String type,
  Duration timeout,
) async {
  final bool more;
  try {
    more = await it.moveNext().timeout(timeout);
  } on TimeoutException {
    throw const MuxHandshakeException('timeout');
  }
  if (!more || it.current.type != type) {
    throw MuxHandshakeException('expected $type');
  }
  return it.current;
}
