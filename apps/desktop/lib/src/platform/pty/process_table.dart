import 'dart:convert';
import 'dart:io';

import 'package:shellx_agent/shellx_agent.dart' show ProcessRunner;

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

/// A process-table snapshot could not be taken. [message] never contains
/// process output or arguments.
final class ProcessTableException implements Exception {
  const ProcessTableException(this.message);

  final String message;

  @override
  String toString() => 'ProcessTableException: $message';
}

/// Source of process-table snapshots (macOS: `ps`).
abstract interface class ProcessTable {
  /// Throws [ProcessTableException] when no snapshot can be taken.
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
  const PsProcessTable({ProcessRunner run = Process.run}) : _run = run;

  final ProcessRunner _run;

  @override
  Future<List<ProcessEntry>> snapshot() async {
    final ProcessResult result;
    try {
      result = await _run('/bin/ps', ['-A', '-o', 'pid=,ppid=,comm=']);
    } on ProcessException catch (error) {
      throw ProcessTableException(
        'cannot run ps (OS error ${error.errorCode})',
      );
    }
    if (result.exitCode != 0) {
      throw ProcessTableException('ps exited with code ${result.exitCode}');
    }
    return parsePsOutput(result.stdout as String);
  }
}
