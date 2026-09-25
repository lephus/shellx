import 'dart:convert';
import 'dart:io';

/// One row of the operating system process table.
final class ProcessEntry {
  const ProcessEntry({
    required this.pid,
    required this.parentPid,
    required this.name,
  });

  final int pid;
  final int parentPid;
  final String name;
}

/// Source of process-table snapshots (macOS: `ps`, Windows: Toolhelp32).
abstract interface class ProcessTable {
  Future<List<ProcessEntry>> snapshot();
}

/// Every descendant of [root] (children, grandchildren, ...), excluding [root].
List<int> descendantsOf(int root, List<ProcessEntry> table) {
  final children = <int, List<int>>{};
  for (final entry in table) {
    if (entry.pid == entry.parentPid) continue;
    children.putIfAbsent(entry.parentPid, () => <int>[]).add(entry.pid);
  }
  final result = <int>[];
  final seen = <int>{root};
  final queue = <int>[root];
  while (queue.isNotEmpty) {
    final current = queue.removeAt(0);
    for (final child in children[current] ?? const <int>[]) {
      if (seen.add(child)) {
        result.add(child);
        queue.add(child);
      }
    }
  }
  return result;
}

final RegExp _psLine = RegExp(r'^\s*(\d+)\s+(\d+)\s+(.*)$');

/// Parses the output of `ps -A -o pid=,ppid=,comm=`.
List<ProcessEntry> parsePsOutput(String output) {
  final entries = <ProcessEntry>[];
  for (final line in const LineSplitter().convert(output)) {
    final match = _psLine.firstMatch(line);
    if (match == null) continue;
    entries.add(
      ProcessEntry(
        pid: int.parse(match[1]!),
        parentPid: int.parse(match[2]!),
        name: match[3]!.trim(),
      ),
    );
  }
  return entries;
}

/// macOS process table via `/bin/ps`.
final class PsProcessTable implements ProcessTable {
  const PsProcessTable();

  @override
  Future<List<ProcessEntry>> snapshot() async {
    final result = await Process.run('/bin/ps', [
      '-A',
      '-o',
      'pid=,ppid=,comm=',
    ]);
    if (result.exitCode != 0) return const <ProcessEntry>[];
    return parsePsOutput(result.stdout as String);
  }
}
