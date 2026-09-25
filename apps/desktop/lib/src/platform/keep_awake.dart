import 'dart:async';
import 'dart:io';

import 'package:win32/win32.dart' show SetThreadExecutionState;

/// Prevents idle system sleep while enabled. Never prevents lid-close sleep.
abstract interface class KeepAwake {
  Future<void> setEnabled(bool enabled);
}

typedef ProcessStarter =
    Future<Process> Function(String executable, List<String> arguments);

/// macOS: child process `caffeinate -i -w <agent pid>`. `-i` blocks idle
/// sleep only; `-w` makes caffeinate exit on its own if the agent dies.
final class CaffeinateKeepAwake implements KeepAwake {
  CaffeinateKeepAwake({ProcessStarter? start, int? agentPid})
    : _start = start ?? Process.start,
      _agentPid = agentPid ?? pid;

  final ProcessStarter _start;
  final int _agentPid;
  Process? _process;
  Future<void> _queue = Future<void>.value();

  @override
  Future<void> setEnabled(bool enabled) {
    // Each call gets its own result so a caller can observe a failure, but
    // the queue itself must never stay poisoned by a past error, or every
    // later call would rethrow the same stale error forever (keep-awake is
    // default-on per spec §8).
    final next = _queue.then((_) => _apply(enabled));
    _queue = next.catchError((Object _) {});
    return next;
  }

  Future<void> _apply(bool enabled) async {
    if (enabled) {
      if (_process != null) return;
      final process = await _start('/usr/bin/caffeinate', [
        '-i',
        '-w',
        '$_agentPid',
      ]);
      _process = process;
      unawaited(
        process.exitCode.then((_) {
          if (identical(_process, process)) _process = null;
        }),
      );
    } else {
      _process?.kill();
      _process = null;
    }
  }
}

typedef ExecutionStateSetter = int Function(int flags);

/// Windows: SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED) on the
/// Dart UI thread, which lives as long as the app.
final class WindowsKeepAwake implements KeepAwake {
  WindowsKeepAwake({ExecutionStateSetter? setState})
    : _setState = setState ?? SetThreadExecutionState;

  static const int esContinuous = 0x80000000;
  static const int esSystemRequired = 0x00000001;

  final ExecutionStateSetter _setState;

  @override
  Future<void> setEnabled(bool enabled) async {
    final result = _setState(
      enabled ? (esContinuous | esSystemRequired) : esContinuous,
    );
    if (result == 0) {
      throw StateError('SetThreadExecutionState failed');
    }
  }
}
