import 'dart:convert';
import 'dart:io';

import 'package:shellx_acp/shellx_acp.dart' show Redacted;

import 'probe.dart';
import 'running_agents.dart' show parseEtime, sameProgram;

/// One row of the operating system's process table: enough to know a process
/// again a few seconds later (its pid alone is not: a pid is reused).
final class ProcessRow with Redacted {
  const ProcessRow({
    required this.pid,
    required this.parentPid,
    required this.command,
    required this.startedAt,
  });

  final int pid;
  final int parentPid;

  /// The program: a path on macOS and Windows, a name on Linux.
  final String command;
  final DateTime startedAt;
}

/// The process table as it is now; null when it cannot be read (no `ps`, a
/// PowerShell that does not answer in time).
typedef ProcessTableReader = Future<List<ProcessRow>?> Function();

final _psRow = RegExp(r'^\s*(\d+)\s+(\d+)\s+(\S+)\s+(.+?)\s*$');

/// The rows of `ps -A -o pid=,ppid=,etime=,comm=` read at [now]: the start of
/// a process is [now] less its age. A line that is no row is skipped.
List<ProcessRow> parsePsRows(String output, {required DateTime now}) {
  final rows = <ProcessRow>[];
  for (final line in const LineSplitter().convert(output)) {
    final m = _psRow.firstMatch(line);
    final age = m == null ? null : parseEtime(m[3]!);
    if (m == null || age == null) continue;
    rows.add(
      ProcessRow(
        pid: int.parse(m[1]!),
        parentPid: int.parse(m[2]!),
        command: m[4]!,
        startedAt: now.subtract(age),
      ),
    );
  }
  return rows;
}

/// The rows of the Windows script [_cimScript]: `pid|ppid|created|path`, the
/// time as ISO 8601 UTC. (A path holds no `|`.) A line that is no row is
/// skipped.
List<ProcessRow> parseCimRows(String output) {
  final rows = <ProcessRow>[];
  for (final line in const LineSplitter().convert(output)) {
    final parts = line.trim().split('|');
    if (parts.length < 3) continue;
    final pid = int.tryParse(parts[0]);
    final parent = int.tryParse(parts[1]);
    final created = DateTime.tryParse(parts[2]);
    if (pid == null || parent == null || created == null) continue;
    rows.add(
      ProcessRow(
        pid: pid,
        parentPid: parent,
        command: parts.skip(3).join('|'),
        startedAt: created,
      ),
    );
  }
  return rows;
}

/// Every process with its parent, its creation time and its program. The
/// ones without a creation time (the system's own) are left out.
const _cimScript =
    r'Get-CimInstance Win32_Process -Property ProcessId,ParentProcessId,CreationDate,ExecutablePath | '
    r'Where-Object { $_.CreationDate } | '
    r"ForEach-Object { '{0}|{1}|{2}|{3}' -f $_.ProcessId, $_.ParentProcessId, "
    r"$_.CreationDate.ToUniversalTime().ToString('o'), $_.ExecutablePath }";

/// The real [ProcessTableReader]: `ps` on macOS and Linux, CIM through
/// PowerShell on Windows. Gives up after a few seconds, so a stop never waits
/// on it for long.
Future<List<ProcessRow>?> readProcessTable() async {
  if (Platform.isWindows) {
    final r = await runProbe('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      _cimScript,
    ], timeout: const Duration(seconds: 3));
    return r == null || r.exitCode != 0 ? null : parseCimRows(r.stdout);
  }
  final r = await runProbe('/bin/ps', [
    '-A',
    '-o',
    'pid=,ppid=,etime=,comm=',
  ], timeout: const Duration(seconds: 2));
  if (r == null || r.exitCode != 0) return null;
  return parsePsRows(r.stdout, now: DateTime.now().toUtc());
}

/// Everything [root] started that is in [rows]: children, their children…
/// (not [root] itself), parents before children. A row that says it is its
/// own parent is no child, and neither is one that began before the parent it
/// names: Windows does not clear the parent of a process that has left, so
/// that pid may since belong to another process. [slack] is how much earlier
/// than its parent a child may seem to begin (ages are rounded to seconds).
List<ProcessRow> descendantsIn(
  int root,
  List<ProcessRow> rows, {
  Duration slack = const Duration(seconds: 2),
}) {
  if (root <= 1) return const [];
  final byPid = {for (final r in rows) r.pid: r};
  final children = <int, List<ProcessRow>>{};
  for (final r in rows) {
    if (r.pid == r.parentPid) continue;
    final parent = byPid[r.parentPid];
    if (parent != null &&
        r.startedAt.isBefore(parent.startedAt.subtract(slack))) {
      continue;
    }
    children.putIfAbsent(r.parentPid, () => []).add(r);
  }
  final found = <ProcessRow>[];
  final seen = <int>{root};
  final queue = [root];
  while (queue.isNotEmpty) {
    for (final child in children[queue.removeAt(0)] ?? const <ProcessRow>[]) {
      if (!seen.add(child.pid)) continue;
      found.add(child);
      queue.add(child.pid);
    }
  }
  return found;
}

/// Whether [now] is [then] still: the same pid, the same program, begun at
/// the same time to within [tolerance] (ages are rounded to seconds, and the
/// two readings are not at the same moment). A pid that was reused is not.
bool isSameProcess(
  ProcessRow then,
  ProcessRow now, {
  Duration tolerance = const Duration(seconds: 5),
}) =>
    then.pid == now.pid &&
    sameProgram(then.command, now.command) &&
    now.startedAt.difference(then.startedAt).abs() <= tolerance;
