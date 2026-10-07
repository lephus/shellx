import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';

import '../startup.dart';

/// What a daemon process is called on the wire: a fresh secret and instance
/// id for every start (A5b D5).
({Uint8List secret, String instance}) newDaemonIdentity([Random? random]) {
  final r = random ?? Random.secure();
  return (
    secret: Uint8List.fromList(List.generate(32, (_) => r.nextInt(256))),
    instance: List.generate(
      16,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join(),
  );
}

/// A5b D3, D27: the life of the `shellx-mux` process around its
/// [MuxServer]: it serves, publishes its endpoint, exits when nothing needs
/// it, and quits on `daemon.quit`.
///
/// Idle (D27): no UI attached, no sessions (a connected `cli` client counts
/// as one: [hasSessions] is the daemon's "something is using me") and no
/// phone served, for [idle]. Anything that changes that cancels the exit.
///
/// Never logs anything.
final class DaemonHost {
  DaemonHost({
    required this.server,
    required this.endpoint,
    required this.info,
    required this.hasSessions,
    required this.servingPhones,
    required this.shutdown,
    required this.exit,
    this.idle = const Duration(seconds: 10),
    this.shutdownTimeout = const Duration(seconds: 10),
    this.log,
  });

  final MuxServer server;
  final MuxEndpointFile endpoint;
  final MuxEndpointInfo info;
  final bool Function() hasSessions;
  final bool Function() servingPhones;

  /// Closes the sessions and the rest of the service (the daemon's quit:
  /// CLI host, shells, ssh masters, agent). Bounded by [shutdownTimeout].
  final Future<void> Function() shutdown;
  final void Function(int code) exit;
  final Duration idle;

  /// The PTY kill wait alone is up to 3 s (A1), so the bound is above it.
  final Duration shutdownTimeout;

  /// Error types only (the default is `debugPrint`).
  final void Function(String message)? log;

  Timer? _idle;
  String? _written;
  Future<void>? _quit;

  Future<void> start(MuxListener listener) async {
    server.serve(listener);
    _written = await endpoint.write(info);
    onStateChanged();
  }

  void onUiChanged(bool attached) => onStateChanged();

  bool get _isIdle => !server.uiAttached && !hasSessions() && !servingPhones();

  /// D27: arm the idle exit only while nothing needs the daemon; any change
  /// re-evaluates.
  void onStateChanged() {
    if (_quit != null) return;
    if (!_isIdle) {
      _idle?.cancel();
      _idle = null;
      return;
    }
    _idle ??= Timer(idle, () {
      _idle = null;
      // Whatever changed meanwhile without a notification keeps it alive.
      if (_isIdle) unawaited(quit());
    });
  }

  /// Once: repeated calls share the first. Shuts down (bounded), removes the
  /// endpoint if still ours, stops serving, then exits 0.
  Future<void> quit() => _quit ??= _quitNow();

  Future<void> _quitNow() async {
    _idle?.cancel();
    _idle = null;
    await runBounded(
      shutdown,
      timeout: shutdownTimeout,
      label: 'daemon shutdown',
      log: log,
    );
    final written = _written;
    if (written != null) await endpoint.deleteIfOwned(written);
    await runBounded(
      server.close,
      timeout: const Duration(seconds: 1),
      label: 'closing the mux server',
      log: log,
    );
    exit(0);
  }
}
