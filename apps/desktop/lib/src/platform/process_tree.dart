import 'dart:async';
import 'dart:io';

import 'pty/process_tree_killer.dart';

/// Stops [process] and everything it started, for the helpers ShellX runs
/// itself (`gh`, the user's event command). Windows: `taskkill /T` (3 s at
/// most). Elsewhere the A10 [PosixProcessTreeKiller] (freeze, pid guard,
/// children found even when reparented), with a short grace; then the
/// process itself is killed. Never throws.
Future<void> killProcessTree(
  Process process, {
  ProcessTreeKiller? killer,
}) async {
  await _killTreeOf(process.pid, killer);
  process.kill(ProcessSignal.sigkill);
}

/// [killProcessTree] by pid, for a process this run did not start: an AI
/// agent a crash left behind (V2-1 §6, `running.json`). Never throws.
Future<void> killProcessTreeByPid(int pid, {ProcessTreeKiller? killer}) async {
  await _killTreeOf(pid, killer);
  Process.killPid(pid, ProcessSignal.sigkill);
}

Future<void> _killTreeOf(int pid, ProcessTreeKiller? killer) async {
  try {
    if (Platform.isWindows) {
      await Process.run('taskkill', [
        '/F',
        '/T',
        '/PID',
        '$pid',
      ]).timeout(const Duration(seconds: 3));
    } else {
      await (killer ??
              PosixProcessTreeKiller(grace: const Duration(milliseconds: 300)))
          .killTree(pid);
    }
  } on Object {
    // Best effort: the process itself is killed after.
  }
}
