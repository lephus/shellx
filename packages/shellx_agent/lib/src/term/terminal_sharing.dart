import 'desktop_session_manager.dart';
import 'term_server.dart';

/// The agent side of "Share terminals with phone" (spec §6.1, §7.9): the
/// loopback server feeding [DesktopSessionManager]. P4's switch calls
/// [start] and [stop]; [enabled] is `desktop_sharing` (spec §8).
final class TerminalSharing {
  TerminalSharing({
    required String endpointPath,
    required DesktopSessionManager sessions,
    Duration handshakeTimeout = const Duration(seconds: 5),
  }) : _sessions = sessions,
       _server = TermServer(
         endpointPath: endpointPath,
         admit: sessions.canAdmit,
         onLink: sessions.addLink,
         handshakeTimeout: handshakeTimeout,
       );

  final DesktopSessionManager _sessions;
  final TermServer _server;

  /// The tail of the [start]/[stop] queue; never completes with an error.
  Future<void> _last = Future<void>.value();

  bool get enabled => _server.running;

  /// [start] and [stop] run one at a time, in call order: a [stop] called
  /// while a [start] is in flight runs after it (so sharing ends up off and
  /// the `endpoint` file gone), and a [start] called while another is in
  /// flight finds the server running and binds nothing more. Each returned
  /// future completes when that call's own turn is done; a failed [start]
  /// throws to its caller and does not block later calls.
  Future<void> start() => _enqueue(_server.start);

  /// Desktop sessions go at once (phones get `closed_by_host`); windows keep
  /// running and keep retrying until sharing is on again.
  Future<void> stop() => _enqueue(() async {
    _sessions.clear();
    await _server.stop();
  });

  Future<void> _enqueue(Future<void> Function() operation) {
    final result = _last.then((_) => operation());
    _last = result.then((_) {}, onError: (Object _) {});
    return result;
  }
}
