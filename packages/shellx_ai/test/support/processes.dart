import 'dart:io';

import 'package:shellx_ai/host.dart';

/// Kills [p] when it still runs: a test that failed midway must not leave
/// its agent behind. (A pid is only reused after the exit is reported, so
/// this cannot hit a stranger.)
Future<void> killIfRunning(AgentProcess p) async {
  final running = await p.exitCode
      .then((_) => false)
      .timeout(Duration.zero, onTimeout: () => true);
  if (!running) return;
  Process.killPid(p.pid, ProcessSignal.sigkill);
  await p.exitCode.timeout(const Duration(seconds: 10));
}
