import 'dart:convert';
import 'dart:io';

import 'probe.dart';
import 'serial_queue.dart';

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

/// Whether two commands are the same program: the file name, without folder,
/// case or `.exe` (`/opt/homebrew/bin/node` and `C:\Program Files\nodejs\NODE.EXE`
/// are `node`).
bool sameProgram(String a, String b) {
  String base(String s) {
    final name = s.replaceAll(r'\', '/').split('/').last.toLowerCase();
    return name.endsWith('.exe') ? name.substring(0, name.length - 4) : name;
  }

  return base(a) == base(b);
}

/// `ps -o etime` → age: `mm:ss`, `hh:mm:ss` or `d-hh:mm:ss`.
Duration? parseEtime(String text) {
  final m = RegExp(
    r'^(?:(\d+)-)?(?:(\d+):)?(\d+):(\d+)$',
  ).firstMatch(text.trim());
  if (m == null) return null;
  int g(int i) => int.parse(m.group(i) ?? '0');
  return Duration(days: g(1), hours: g(2), minutes: g(3), seconds: g(4));
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
final class RunningAgents {
  RunningAgents(
    this.file, {
    ProcessLookup? info,
    KillPid? killPid,
    this.tolerance = const Duration(seconds: 5),
  }) : _info = info ?? lookupProcess,
       _killPid = killPid ?? killProcessByPid;

  final File file;
  final Duration tolerance;
  final ProcessLookup _info;
  final KillPid _killPid;
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
      await _killPid(r.pid);
      stopped++;
    }
    _write(const []);
    return stopped;
  });

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
