import '../notify/command_tracker.dart';

/// What asked for the user (A4 N1).
enum SessionNoticeKind { message, command, bell }

/// A session asked for attention (A4 D4): a program's message (OSC 9, 777,
/// 99), a long command that ended, or a bell. The desktop decides what is
/// read; the agent only reports. [toString] never shows the text (N9).
final class SessionNotice {
  const SessionNotice({
    required this.sessionId,
    required this.kind,
    required this.at,
    this.title,
    this.body,
    this.command,
  });

  final int sessionId;
  final SessionNoticeKind kind;
  final DateTime at;

  /// The program's title (OSC 777 / 99), if it gave one.
  final String? title;

  /// The message text ([SessionNoticeKind.message] only).
  final String? body;

  /// The command that ended ([SessionNoticeKind.command] only).
  final CompletedCommand? command;

  @override
  String toString() => 'SessionNotice($sessionId, ${kind.name})';
}

/// Per-session flood guard (A4 D3, D6): one bell per [bellGap]; at most
/// [maxPerWindow] messages and commands in any [window].
final class NoticeLimiter {
  NoticeLimiter({
    this.bellGap = const Duration(seconds: 5),
    this.maxPerWindow = 30,
    this.window = const Duration(seconds: 60),
  });

  final Duration bellGap;
  final int maxPerWindow;
  final Duration window;
  final _recent = <DateTime>[];
  DateTime? _lastBell;
  int _dropped = 0;

  /// Notices refused so far.
  int get dropped => _dropped;

  bool allow(SessionNoticeKind kind, DateTime now) {
    if (kind == SessionNoticeKind.bell) {
      final last = _lastBell;
      if (last != null && now.difference(last) < bellGap) {
        _dropped++;
        return false;
      }
      _lastBell = now;
      return true;
    }
    _recent.removeWhere((t) => now.difference(t) >= window);
    if (_recent.length >= maxPerWindow) {
      _dropped++;
      return false;
    }
    _recent.add(now);
    return true;
  }
}
