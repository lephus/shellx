import 'dart:async';

import 'package:shellx_agent/shellx_agent.dart';

/// What [DaemonLauncher.connect] found (A5b D16, D19).
sealed class DaemonConnection {
  const DaemonConnection();
}

/// A daemon of this protocol answered and proved the secret. [started] is
/// true when this launcher had to start it.
final class Attached extends DaemonConnection {
  const Attached({
    required this.client,
    required this.info,
    this.started = false,
  });
  final MuxClient client;
  final MuxPeerInfo info;
  final bool started;
}

/// A daemon of another protocol with live sessions (D19): never attach;
/// the UI asks, then calls [DaemonLauncher.replaceIncompatible]. [client]
/// stays open for that (and is only good for `daemon.quit`).
final class Incompatible extends DaemonConnection {
  const Incompatible({required this.client, required this.info});
  final MuxClient client;
  final MuxPeerInfo info;
}

/// No daemon after the retries (D16): "Không khởi động được phiên nền".
final class StartFailed extends DaemonConnection {
  const StartFailed();
}

/// A5b D16, D19: the UI's way to a daemon: connect to the one that runs,
/// start one when none does, and never attach across protocols. Never
/// sends a message on a connection whose peer has not proven the secret,
/// and never logs.
final class DaemonLauncher {
  DaemonLauncher({
    required this.transport,
    required this.endpoint,
    required this.daemonLockFree,
    required this.spawn,
    required this.appVersion,
    this.attempt = const Duration(seconds: 1),
    this.retryEvery = const Duration(milliseconds: 100),
    this.retryFor = const Duration(seconds: 5),
    this.quitWait = const Duration(seconds: 4),
    DateTime Function()? now,
    Future<void> Function(Duration)? sleep,
  }) : _now = now ?? DateTime.now,
       _sleep = sleep ?? ((d) => Future<void>.delayed(d));

  final MuxTransport transport;
  final MuxEndpointFile endpoint;

  /// `mux.lock` is not held: no daemon runs or is starting.
  final Future<bool> Function() daemonLockFree;

  /// Starts a detached daemon.
  final Future<void> Function() spawn;
  final String appVersion;
  final Duration attempt, retryEvery, retryFor, quitWait;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _sleep;

  Future<DaemonConnection> connect() => _connect(replaceEmpty: true);

  /// [replaceEmpty]: a daemon of another protocol with no sessions is
  /// stopped without asking, at most once per [connect] (a daemon that will
  /// not go away is then reported as [Incompatible], not retried forever).
  Future<DaemonConnection> _connect({required bool replaceEmpty}) async {
    final first = await _tryAttach();
    if (first != null) {
      return _classify(first, started: false, replaceEmpty: replaceEmpty);
    }
    var started = false;
    if (await daemonLockFree()) {
      await spawn();
      started = true;
    }
    // A held lock is a daemon that is starting (or one whose endpoint we
    // could not use): wait for it the same way.
    final deadline = _now().add(retryFor);
    while (_now().isBefore(deadline)) {
      await _sleep(retryEvery);
      final next = await _tryAttach();
      if (next != null) {
        return _classify(next, started: started, replaceEmpty: replaceEmpty);
      }
    }
    return const StartFailed();
  }

  /// D19: stop the old daemon (it closes its shells) and start ours.
  Future<DaemonConnection> replaceIncompatible(Incompatible old) async {
    try {
      await old.client.request(MuxType.daemonQuit).timeout(quitWait);
    } on Object {
      // Gone or unresponsive: its lock frees when it exits.
    }
    try {
      await old.client.done.timeout(quitWait);
    } on Object {
      // Still there: the retries below find out.
    }
    try {
      await old.client.close();
    } on Object {
      // Already closed.
    }
    return _connect(replaceEmpty: false);
  }

  Future<(MuxClient, MuxPeerInfo)?> _tryAttach() async {
    final ep = await endpoint.read();
    if (ep == null) return null;
    MuxConnection? c;
    try {
      c = await transport.connect(ep.address, timeout: attempt);
      // Verifies the daemon's proof before the client sends anything but
      // `hello` (and its own proof, which the secret holder alone can check).
      final info = await clientHandshake(
        c,
        secret: ep.secret,
        app: appVersion,
        role: 'ui',
        timeout: attempt,
      );
      return (MuxClient(c, early: info.early), info);
    } on Object {
      try {
        await c?.close();
      } on Object {
        // Nothing more to do with it.
      }
      return null;
    }
  }

  Future<DaemonConnection> _classify(
    (MuxClient, MuxPeerInfo) found, {
    required bool started,
    required bool replaceEmpty,
  }) async {
    final (client, info) = found;
    if (info.protocol == kMuxProtocol) {
      return Attached(client: client, info: info, started: started);
    }
    final old = Incompatible(client: client, info: info);
    if (replaceEmpty && (info.sessions ?? 0) == 0) {
      return replaceIncompatible(old);
    }
    return old;
  }
}
