import 'dart:async';
import 'dart:io';

/// The descendants of [root] in a `ps -A -o pid=,ppid=` listing, every
/// parent before its children (kill from the end: leaves first).
List<int> descendantPids(int root, String psOutput) {
  final children = <int, List<int>>{};
  for (final line in psOutput.split('\n')) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length != 2) continue;
    final pid = int.tryParse(parts[0]);
    final parent = int.tryParse(parts[1]);
    if (pid == null || parent == null) continue;
    (children[parent] ??= []).add(pid);
  }
  final order = <int>[];
  final queue = [root];
  final seen = {root};
  while (queue.isNotEmpty) {
    final next = queue.removeAt(0);
    for (final child in children[next] ?? const <int>[]) {
      if (seen.add(child)) {
        order.add(child);
        queue.add(child);
      }
    }
  }
  return order;
}

/// Stops [process] and everything it started. Windows: `taskkill /T`. Elsewhere
/// the descendants are read from `ps` first (fixed arguments, no shell, so
/// nothing is reparented yet), killed leaves first, then the process.
/// Never throws.
Future<void> killProcessTree(Process process) async {
  try {
    if (Platform.isWindows) {
      await Process.run('taskkill', ['/F', '/T', '/PID', '${process.pid}']);
    } else {
      final ps = await Process.run('/bin/ps', [
        '-A',
        '-o',
        'pid=,ppid=',
      ], runInShell: false).timeout(const Duration(seconds: 2));
      if (ps.exitCode == 0) {
        for (final pid in descendantPids(
          process.pid,
          '${ps.stdout}',
        ).reversed) {
          Process.killPid(pid, ProcessSignal.sigkill);
        }
      }
    }
  } on Object {
    // Best effort: the process itself is killed below.
  }
  process.kill(ProcessSignal.sigkill);
}
