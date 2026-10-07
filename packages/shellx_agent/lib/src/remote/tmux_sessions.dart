import 'command_runner.dart';
import 'session_launch.dart' show isValidTmuxName;

/// A8 D25: one line per session, tab-separated.
const String tmuxListFormat =
    '#{session_name}\t#{session_windows}\t#{session_attached}\t'
    '#{session_activity}';

final class TmuxSessionInfo {
  const TmuxSessionInfo({
    required this.name,
    required this.windows,
    required this.attached,
    this.activity,
  });

  final String name;
  final int windows;

  /// Clients attached right now (another terminal, another computer).
  final int attached;
  final DateTime? activity;

  bool get attachedElsewhere => attached > 0;

  @override
  bool operator ==(Object other) =>
      other is TmuxSessionInfo &&
      other.name == name &&
      other.windows == windows &&
      other.attached == attached &&
      other.activity == activity;

  @override
  int get hashCode => Object.hash(name, windows, attached, activity);

  @override
  String toString() => 'TmuxSessionInfo(…)';
}

/// Lines of [tmuxListFormat]; anything else (a login banner) is skipped.
List<TmuxSessionInfo> parseTmuxSessions(String stdout) => [
  for (final line in stdout.split('\n')) ?_parse(line.replaceAll('\r', '')),
];

TmuxSessionInfo? _parse(String line) {
  final parts = line.split('\t');
  if (parts.length != 4 || !isValidTmuxName(parts[0])) return null;
  final windows = int.tryParse(parts[1]);
  final attached = int.tryParse(parts[2]);
  final activity = int.tryParse(parts[3]);
  if (windows == null || attached == null) return null;
  return TmuxSessionInfo(
    name: parts[0],
    windows: windows,
    attached: attached,
    activity: activity == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(activity * 1000),
  );
}

sealed class TmuxListResult {
  const TmuxListResult();
}

final class TmuxSessions extends TmuxListResult {
  const TmuxSessions(this.sessions);
  final List<TmuxSessionInfo> sessions;
}

final class TmuxUnavailable extends TmuxListResult {
  const TmuxUnavailable();
}

enum TmuxListFailure { auth, timeout, other }

final class TmuxListFailed extends TmuxListResult {
  const TmuxListFailed(this.reason);
  final TmuxListFailure reason;
}

/// D25: "no server running" is an empty list, 127 / "not found" means no
/// tmux, 255 over ssh means the server wants a password (BatchMode).
TmuxListResult classifyTmuxList(CommandResult r, {required bool remote}) {
  if (r.timedOut) return const TmuxListFailed(TmuxListFailure.timeout);
  if (r.exitCode == 0) return TmuxSessions(parseTmuxSessions(r.stdout));
  if (remote && r.exitCode == 255) {
    return const TmuxListFailed(TmuxListFailure.auth);
  }
  final err = r.stderr.toLowerCase();
  if (err.contains('no server running') ||
      err.contains('error connecting to') ||
      err.contains('no sessions')) {
    return const TmuxSessions([]);
  }
  if (r.exitCode == 127 || err.contains('not found')) {
    return const TmuxUnavailable();
  }
  return const TmuxListFailed(TmuxListFailure.other);
}
