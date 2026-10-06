import 'dart:async';
import 'dart:collection';
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
    this.early = const [],
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

  /// Messages that arrived in the same read as `ready` (client) or `auth`
  /// (host), after it: the session layer handles them first, before its
  /// own listener's. Not part of the wire.
  final List<MuxMessage> early;
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
  final incoming = _HandshakeReader(c, timeout);
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
    final hello = await incoming.next(MuxType.hello);
    final nonceDaemon = hello.get<Uint8List>('nonce');
    if (nonceDaemon == null || nonceDaemon.length != 32) {
      throw const MuxHandshakeException('daemon nonce');
    }
    if (!_same(
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
    await incoming.next(MuxType.ready);
    return MuxPeerInfo(
      protocol: hello.get<int>('protocol') ?? -1,
      app: hello.get<String>('app') ?? '',
      instance: hello.get<String>('instance'),
      pid: hello.get<int>('pid'),
      sessions: hello.get<int>('sessions'),
      caps: [
        for (final c in hello.get<List<Object?>>('caps') ?? const []) '$c',
      ],
      early: await incoming.drain(),
    );
  } on MuxHandshakeException {
    await c.close();
    rethrow;
  } finally {
    // Hands the stream back: later messages go to the caller's listener.
    incoming.finish();
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
  final incoming = _HandshakeReader(c, timeout);
  try {
    final hello = await incoming.next(MuxType.hello);
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
    final auth = await incoming.next(MuxType.auth);
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
      early: await incoming.drain(),
    );
  } on MuxHandshakeException {
    await c.close();
    rethrow;
  } finally {
    incoming.finish();
  }
}

/// Reads the handshake's messages under one deadline for the whole
/// exchange (D6). Never pauses its subscription, so messages that arrive in
/// the same read after the last handshake step are kept ([finish]).
final class _HandshakeReader {
  _HandshakeReader(MuxConnection c, Duration timeout) {
    _sub = c.messages.listen(
      (m) {
        final waiter = _waiter;
        if (waiter != null) {
          _waiter = null;
          waiter.complete(m);
        } else {
          _queue.add(m);
        }
      },
      onDone: () => _end(const MuxHandshakeException('closed')),
      onError: (Object _) => _end(const MuxHandshakeException('closed')),
    );
    _deadline = Timer(
      timeout,
      () => _end(const MuxHandshakeException('timeout')),
    );
  }

  late final StreamSubscription<MuxMessage> _sub;
  late final Timer _deadline;
  final _queue = Queue<MuxMessage>();
  Completer<MuxMessage>? _waiter;
  MuxHandshakeException? _ended;
  bool _finished = false;

  void _end(MuxHandshakeException reason) {
    _ended ??= reason;
    final waiter = _waiter;
    _waiter = null;
    waiter?.completeError(reason);
  }

  Future<MuxMessage> next(String type) async {
    final MuxMessage m;
    if (_queue.isNotEmpty) {
      m = _queue.removeFirst();
    } else if (_ended case final reason?) {
      throw reason;
    } else {
      m = await (_waiter = Completer<MuxMessage>()).future;
    }
    if (m.type != type) throw MuxHandshakeException('expected $type');
    return m;
  }

  /// Lets the messages of the current read reach the queue (their
  /// delivery is scheduled after this continuation), then [finish]es.
  Future<List<MuxMessage>> drain() async {
    await Future<void>.delayed(Duration.zero);
    return finish();
  }

  /// Stops reading; returns what is left. Safe to call twice.
  List<MuxMessage> finish() {
    if (_finished) return const [];
    _finished = true;
    _deadline.cancel();
    // Not awaited: the cancel takes effect at once, and its future may
    // belong to the root zone (it would escape a fake clock).
    unawaited(_sub.cancel());
    final left = List<MuxMessage>.of(_queue);
    _queue.clear();
    return left;
  }
}
