import 'dart:collection';

/// A8 D18: processes and TCP listeners of the server, in one round trip.
/// `ss` (Linux) shows the pids of the user's own sockets; `lsof` (macOS,
/// BSD) the same. Run by `remoteExecCommand` under `/bin/sh`.
const String remoteProbeScript = r'''
PATH="$PATH:/usr/sbin:/sbin"; export PATH
echo '#ps'
ps -A -o pid= -o ppid= 2>/dev/null
if command -v ss >/dev/null 2>&1; then
  echo '#ss'
  ss -ltnp 2>/dev/null
elif command -v lsof >/dev/null 2>&1; then
  echo '#lsof'
  lsof -nP -iTCP -sTCP:LISTEN -F pn 2>/dev/null
fi
''';

final _spaces = RegExp(r'\s+');
final _pid = RegExp(r'pid=(\d+)');

/// Shell pid → sorted listening ports of that shell and its descendants;
/// every pid of [shellPids] gets an entry (empty when none).
Map<int, List<int>> parseRemoteProbe(String output, Iterable<int> shellPids) {
  final children = <int, List<int>>{};
  final listening = <int, Set<int>>{};
  var section = '';
  int? lsofPid;
  for (final raw in output.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#')) {
      section = line;
      lsofPid = null;
      continue;
    }
    switch (section) {
      case '#ps':
        final parts = line.split(_spaces);
        if (parts.length != 2) continue;
        final pid = int.tryParse(parts[0]);
        final parent = int.tryParse(parts[1]);
        if (pid == null || parent == null || pid == parent) continue;
        (children[parent] ??= []).add(pid);
      case '#ss':
        if (!line.startsWith('LISTEN')) continue;
        final cols = line.split(_spaces);
        if (cols.length < 5) continue;
        final port = _portOf(cols[3]);
        if (port == null) continue;
        for (final m in _pid.allMatches(line)) {
          final pid = int.tryParse(m[1]!);
          if (pid != null) (listening[pid] ??= {}).add(port);
        }
      case '#lsof':
        if (line.startsWith('p')) {
          lsofPid = int.tryParse(line.substring(1));
        } else if (line.startsWith('n') && lsofPid != null) {
          if (line.contains('->')) continue;
          final port = _portOf(line.substring(1));
          if (port != null) (listening[lsofPid] ??= {}).add(port);
        }
    }
  }
  final result = <int, List<int>>{};
  for (final shell in shellPids) {
    final ports = SplayTreeSet<int>();
    final seen = <int>{shell};
    final queue = Queue<int>()..add(shell);
    while (queue.isNotEmpty && seen.length <= 100000) {
      final pid = queue.removeFirst();
      ports.addAll(listening[pid] ?? const {});
      for (final child in children[pid] ?? const <int>[]) {
        if (seen.add(child)) queue.add(child);
      }
    }
    result[shell] = List.unmodifiable(ports);
  }
  return result;
}

int? _portOf(String address) {
  final colon = address.lastIndexOf(':');
  if (colon < 0) return null;
  final port = int.tryParse(address.substring(colon + 1));
  return port != null && port > 0 && port < 65536 ? port : null;
}
