import 'dart:convert';
import 'dart:io';

import 'probe.dart';
import 'process_snapshot.dart';
import 'serial_queue.dart';

/// This process's own pid (inside [RunningRecord], `pid` is the agent's).
final int _ownPid = pid;

/// One agent process this app started.
final class RunningRecord {
  const RunningRecord({
    required this.pid,
    required this.command,
    required this.startedAt,
  });

  final int pid;

  /// The executable that was started.
  final String command;
  final DateTime startedAt;

  Map<String, Object?> toJson() => {
    'pid': pid,
    'command': command,
    'startedAt': startedAt.millisecondsSinceEpoch,
  };

  static RunningRecord? fromJson(Object? j) {
    if (j is! Map) return null;
    final pid = j['pid'];
    final command = j['command'];
    final at = j['startedAt'];
    if (pid is! int || command is! String || at is! int) return null;
    return RunningRecord(
      pid: pid,
      command: command,
      startedAt: DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
    );
  }

  @override
  String toString() => '…';
}

/// The executable and start time of a live process; null when gone.
/// (Not `ProcessInfo`: `dart:io` exports a class of that name.)
typedef ProcessLookup =
    Future<({String command, DateTime startedAt})?> Function(int pid);

typedef KillPid = Future<void> Function(int pid);

/// A [KillPid] that kills the process whose pid it is, and nothing it
/// started: the way where a tree must not be walked (Windows).
Future<void> killPidOnly(int pid) async {
  Process.killPid(pid, ProcessSignal.sigkill);
}

/// The OS view of [pid]: `ps` on macOS/Linux, CIM through PowerShell on
/// Windows.
Future<({String command, DateTime startedAt})?> lookupProcess(int pid) async {
  if (Platform.isWindows) {
    final r = await runProbe('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      "\$p = Get-CimInstance Win32_Process -Filter 'ProcessId=$pid'; "
          "if (\$p) { \$p.ExecutablePath; \$p.CreationDate.ToUniversalTime().ToString('o') }",
    ], timeout: const Duration(seconds: 15));
    final lines = const LineSplitter()
        .convert(r?.stdout ?? '')
        .where((l) => l.trim().isNotEmpty)
        .toList();
    if (lines.length < 2) return null;
    final at = DateTime.tryParse(lines[1].trim());
    return at == null ? null : (command: lines[0].trim(), startedAt: at);
  }
  final r = await runProbe('/bin/ps', [
    '-o',
    'etime=',
    '-o',
    'comm=',
    '-p',
    '$pid',
  ]);
  final line = (r?.stdout ?? '').trim();
  if (r == null || r.exitCode != 0 || line.isEmpty) return null;
  final space = line.indexOf(RegExp(r'\s'));
  if (space < 0) return null;
  final age = parseEtime(line.substring(0, space));
  if (age == null) return null;
  return (
    command: line.substring(space).trim(),
    startedAt: DateTime.now().toUtc().subtract(age),
  );
}

/// The fallback [KillPid]: the process itself (`taskkill /T` on Windows).
Future<void> killProcessByPid(int pid) async {
  if (Platform.isWindows) {
    await runProbe('taskkill', ['/F', '/T', '/PID', '$pid']);
  } else {
    Process.killPid(pid, ProcessSignal.sigkill);
  }
}

/// `<support>/ai/running.json`: the agents this app runs. After a crash
/// the next launch stops the ones left behind, but only when both the
/// command and the start time still match: a reused pid is left alone
/// (spec §6). Writes run one at a time.
///
/// Elsewhere a leftover goes through [killPid], the tree killer. On Windows
/// ([isWindows]) no tree is walked when the kill is made: `taskkill /T`
/// follows the ParentProcessId of every process, Windows keeps that id after
/// the parent has left, and a stale one can make a process that has nothing
/// to do with the agent (an explorer.exe whose parent id is the pid the
/// leftover got since, a process above ShellX) look like its child. There the
/// leftover is checked again against one read of the process table
/// ([processTable]), and it and the processes that table shows under it (a
/// child is not older than its parent; never this process or what is above
/// it; never pid 0 or 1) are killed, each on its own, through [killAlone].
final class RunningAgents {
  RunningAgents(
    this.file, {
    ProcessLookup? info,
    KillPid? killPid,
    this.tolerance = const Duration(seconds: 5),
    bool? isWindows,
    ProcessTableReader? processTable,
    KillPid? killAlone,
  }) : _info = info ?? lookupProcess,
       _killPid = killPid ?? killProcessByPid,
       _windows = isWindows ?? Platform.isWindows,
       _processTable = processTable ?? readProcessTable,
       _killAlone = killAlone ?? killPidOnly;

  final File file;
  final Duration tolerance;
  final ProcessLookup _info;
  final KillPid _killPid;
  final bool _windows;
  final ProcessTableReader _processTable;
  final KillPid _killAlone;
  final _queue = SerialQueue();

  Future<void> add(RunningRecord record) => _queue.run(() async {
    _write([..._readNow().where((r) => r.pid != record.pid), record]);
  });

  Future<void> remove(int pid) => _queue.run(() async {
    _write(_readNow().where((r) => r.pid != pid).toList());
  });

  /// At app start: stops matching leftovers and clears the file; returns
  /// how many were stopped.
  Future<int> sweep() => _queue.run(() async {
    var stopped = 0;
    for (final r in _readNow()) {
      final now = await _info(r.pid);
      if (now == null || !sameProgram(now.command, r.command)) continue;
      if (now.startedAt.difference(r.startedAt).abs() > tolerance) continue;
      if (_windows) {
        if (await _stopOnWindows(r)) stopped++;
      } else {
        await _killPid(r.pid);
        stopped++;
      }
    }
    _write(const []);
    return stopped;
  });

  /// Windows: the leftover [r], whose identity has been checked, and what one
  /// read of the process table shows it started, each on its own. False, and
  /// nothing killed, when that read disagrees about who the process is, when
  /// it does not show it, or when it is this process, pid 0 or 1, or above
  /// this process (the leftover may be what started it): the table is not
  /// believed against that. A table that cannot be read leaves the leftover
  /// alone to be killed, as the check found it.
  Future<bool> _stopOnWindows(RunningRecord r) async {
    if (r.pid <= 1 || r.pid == _ownPid) return false;
    List<ProcessRow>? rows;
    try {
      rows = await _processTable();
    } on Object {
      rows = null;
    }
    var below = const <ProcessRow>[];
    if (rows != null) {
      final me = rows.where((x) => x.pid == r.pid).firstOrNull;
      if (me == null ||
          !sameProgram(me.command, r.command) ||
          me.startedAt.difference(r.startedAt).abs() > tolerance) {
        return false;
      }
      final slack = startSlack(isWindows: _windows);
      final above = ancestorsIn(_ownPid, rows, slack: slack);
      if (above.contains(r.pid)) return false;
      below = descendantsIn(
        r.pid,
        rows,
        slack: slack,
        never: {_ownPid, ...above},
      );
    }
    // The agent first: it can start nothing more.
    await _killOne(r.pid);
    await Future.wait([for (final d in below) _killOne(d.pid)]);
    return true;
  }

  Future<void> _killOne(int pid) async {
    try {
      await _killAlone(pid);
    } on Object {
      // The others still go.
    }
  }

  /// The records as they are on disk.
  List<RunningRecord> read() => _readNow();

  List<RunningRecord> _readNow() {
    try {
      final j = jsonDecode(file.readAsStringSync());
      final agents = j is Map ? j['agents'] : null;
      if (agents is! List) return [];
      return agents.map(RunningRecord.fromJson).nonNulls.toList();
    } on Object {
      return [];
    }
  }

  void _write(List<RunningRecord> records) {
    file.parent.createSync(recursive: true);
    final tmp = File('${file.path}.tmp')
      ..writeAsStringSync(
        jsonEncode({
          'v': 1,
          'agents': [for (final r in records) r.toJson()],
        }),
      );
    tmp.renameSync(file.path);
  }
}
