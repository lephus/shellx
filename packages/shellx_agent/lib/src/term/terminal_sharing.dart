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

  bool get enabled => _server.running;

  Future<void> start() => _server.start();

  /// Desktop sessions go at once (phones get `closed_by_host`); windows keep
  /// running and keep retrying until sharing is on again.
  Future<void> stop() async {
    _sessions.clear();
    await _server.stop();
  }
}
