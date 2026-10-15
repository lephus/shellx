import 'package:shellx_ai/remote.dart';

/// V2-2b B22, B23: the last listing entry of every AI session of one machine seen in this run of the app —
/// what a session was (its agent's own session id, its agent, its folder) once the computer restarted ShellX
/// and gave it another sid. In memory only, never logged; the newest [capacity] sessions.
final class AiSeenSessions {
  static const int capacity = 200;

  final Map<String, AiSessionInfo> _seen = {};

  /// Every session of [listing] is seen as it is now.
  void note(AiListing listing) {
    for (final session in listing.sessions) {
      _seen
        ..remove(session.sid)
        ..[session.sid] = session;
    }
    while (_seen.length > capacity) {
      _seen.remove(_seen.keys.first);
    }
  }

  /// The last entry seen for [sid]; null when none was.
  AiSessionInfo? of(String sid) => _seen[sid];

  int get length => _seen.length;
}
