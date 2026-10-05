import 'osc_event_parser.dart';

/// A command that ran at least the threshold (push spec §4.2).
final class CompletedCommand {
  const CompletedCommand({
    required this.commandLine,
    required this.exitCode,
    required this.duration,
  });

  /// From the last `633;E` before `133;C`; null when there was none.
  final String? commandLine;
  final int exitCode;
  final Duration duration;

  @override
  String toString() => 'CompletedCommand($commandLine, $exitCode, $duration)';
}

/// Follows one session's commands: `633;E` (command line) → `133;C`
/// (start) → `133;D` (end, exit code). The duration is measured here.
///
/// [threshold] is read when a command ends, so a changed setting applies
/// to the next command that ends; null means "off" (nothing is reported).
/// A `D` without a `C` before it is ignored.
final class CommandTracker {
  CommandTracker({
    required Duration? Function() threshold,
    DateTime Function()? now,
  }) : _threshold = threshold,
       _now = now ?? DateTime.now;

  final Duration? Function() _threshold;
  final DateTime Function() _now;

  String? _pendingLine;
  String? _runningLine;
  DateTime? _startedAt;

  /// Forgets a command that started: its end was missed (e.g. it ended
  /// while a shared terminal was reconnecting), so a later `D` must not be
  /// taken as its end.
  void abandon() {
    _startedAt = null;
    _runningLine = null;
  }

  /// Returns a [CompletedCommand] when [event] ends a command that ran at
  /// least the threshold, else null.
  CompletedCommand? handle(OscEvent event) {
    switch (event) {
      case CommandLineSeen(:final commandLine):
        _pendingLine = commandLine.trim().isEmpty ? null : commandLine;
      case CommandStarted():
        _startedAt = _now();
        _runningLine = _pendingLine;
        _pendingLine = null;
      case CommandFinished(:final exitCode):
        final startedAt = _startedAt;
        if (startedAt == null) return null;
        _startedAt = null;
        final line = _runningLine;
        _runningLine = null;
        final duration = _now().difference(startedAt);
        final Duration? threshold;
        try {
          threshold = _threshold();
        } catch (_) {
          return null;
        }
        if (threshold == null || duration < threshold) return null;
        return CompletedCommand(
          commandLine: line,
          exitCode: exitCode,
          duration: duration,
        );
      case NotifyRequested():
        break;
    }
    return null;
  }
}
