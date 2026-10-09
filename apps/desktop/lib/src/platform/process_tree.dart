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
  try {
    if (Platform.isWindows) {
      await Process.run('taskkill', [
        '/F',
        '/T',
        '/PID',
        '${process.pid}',
      ]).timeout(const Duration(seconds: 3));
    } else {
      await (killer ??
              PosixProcessTreeKiller(grace: const Duration(milliseconds: 300)))
          .killTree(process.pid);
    }
  } on Object {
    // Best effort: the process itself is killed below.
  }
  process.kill(ProcessSignal.sigkill);
}
