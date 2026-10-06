import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// A child process's exit code and standard output.
final class ProbeOutput {
  const ProbeOutput(this.exitCode, this.stdout);
  final int exitCode;
  final String stdout;
}

typedef TimedCommandRunner =
    Future<ProbeOutput> Function(
      String executable,
      List<String> arguments, {
      required Duration timeout,
    });

/// Ports could not be looked up. [message] names the tool and an exit
/// code or OS error number, never output or paths.
final class PortProbeException implements Exception {
  const PortProbeException(this.message);
  final String message;
  @override
  String toString() => 'PortProbeException: $message';
}

String _tool(String executable) => executable.split(RegExp(r'[\\/]')).last;

/// Runs [executable] and kills it when it takes longer than [timeout]
/// (D5). Throws [PortProbeException] when it cannot start or is killed.
Future<ProbeOutput> runWithTimeout(
  String executable,
  List<String> arguments, {
  required Duration timeout,
}) async {
  final Process process;
  try {
    process = await Process.start(executable, arguments);
  } on ProcessException catch (error) {
    throw PortProbeException(
      'cannot run ${_tool(executable)} (OS error ${error.errorCode})',
    );
  }
  unawaited(process.stdin.close().catchError((Object _) {}));
  unawaited(process.stderr.drain<void>().catchError((Object _) {}));
  final stdout = process.stdout
      .transform(const Utf8Decoder(allowMalformed: true))
      .join();
  try {
    final code = await process.exitCode.timeout(timeout);
    return ProbeOutput(code, await stdout);
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    stdout.ignore();
    throw PortProbeException('${_tool(executable)} timed out');
  }
}

int? _portOf(String address) {
  if (address.contains('->')) return null; // a connection, not a listener
  final colon = address.lastIndexOf(':');
  if (colon < 0) return null;
  final port = int.tryParse(address.substring(colon + 1));
  return port != null && port > 0 && port <= 65535 ? port : null;
}

/// `lsof -nP -iTCP -sTCP:LISTEN -Fpn`: a `p<pid>` line, then `f<fd>` and
/// `n<address>` lines of that process (`*:3000`, `127.0.0.1:5173`,
/// `[::1]:8080`). IPv4 and IPv6 sockets of one port count once.
Map<int, Set<int>> parseLsofListen(String output) {
  final result = <int, Set<int>>{};
  int? pid;
  for (final line in const LineSplitter().convert(output)) {
    if (line.isEmpty) continue;
    switch (line[0]) {
      case 'p':
        pid = int.tryParse(line.substring(1));
      case 'n':
        final port = _portOf(line.substring(1));
        if (pid != null && port != null) {
          result.putIfAbsent(pid, () => <int>{}).add(port);
        }
    }
  }
  return result;
}

final _spaces = RegExp(r'\s+');

/// `netstat -ano` (Windows): `TCP <local> <foreign> <state> <pid>`. A
/// listening socket's foreign address ends in `:0` (`0.0.0.0:0`,
/// `[::]:0`); the state word is translated on some Windows languages, so
/// it is not read (D7). PID 0 (the system) is skipped.
Map<int, Set<int>> parseNetstatListen(String output) {
  final result = <int, Set<int>>{};
  for (final line in const LineSplitter().convert(output)) {
    final parts = line.trim().split(_spaces);
    if (parts.length != 5 || parts[0].toUpperCase() != 'TCP') continue;
    if (!parts[2].endsWith(':0')) continue;
    final port = _portOf(parts[1]);
    final pid = int.tryParse(parts[4]);
    if (port == null || pid == null || pid == 0) continue;
    result.putIfAbsent(pid, () => <int>{}).add(port);
  }
  return result;
}

/// `pid ppid` per line (`ps -axo pid=,ppid=`, and the CIM query below).
Map<int, int> parseParentTable(String output) {
  final result = <int, int>{};
  for (final line in const LineSplitter().convert(output)) {
    final parts = line.trim().split(_spaces);
    if (parts.length < 2) continue;
    final pid = int.tryParse(parts[0]);
    final parent = int.tryParse(parts[1]);
    if (pid != null && parent != null) result[pid] = parent;
  }
  return result;
}

/// The session whose shell is [pid] or its nearest ancestor (D4), walking
/// at most 64 parent links; null on a cycle, a missing or dead parent.
int? ownerOf(int pid, Map<int, int> parents, Map<int, int> shellToSession) {
  var current = pid;
  final seen = <int>{};
  for (var step = 0; step < 64; step++) {
    final session = shellToSession[current];
    if (session != null) return session;
    if (!seen.add(current)) return null;
    final parent = parents[current];
    if (parent == null || parent <= 0 || parent == current) return null;
    current = parent;
  }
  return null;
}

/// Where listening ports and the process tree come from.
abstract interface class PortProbe {
  /// Listening TCP ports by pid. Throws [PortProbeException].
  Future<Map<int, Set<int>>> listening();

  /// Parent pid by pid. Throws [PortProbeException].
  Future<Map<int, int>> parents();
}

/// macOS: `lsof` and `ps` (C3).
final class MacPortProbe implements PortProbe {
  MacPortProbe({TimedCommandRunner run = runWithTimeout}) : _run = run;
  final TimedCommandRunner _run;
  static const timeout = Duration(seconds: 2);

  @override
  Future<Map<int, Set<int>>> listening() async {
    final out = await _run('/usr/sbin/lsof', const [
      '-nP',
      '-iTCP',
      '-sTCP:LISTEN',
      '-Fpn',
    ], timeout: timeout);
    // lsof exits 1 when nothing matched (D6).
    if (out.exitCode == 1 && out.stdout.trim().isEmpty) return const {};
    if (out.exitCode != 0) {
      throw PortProbeException('lsof exited with code ${out.exitCode}');
    }
    return parseLsofListen(out.stdout);
  }

  @override
  Future<Map<int, int>> parents() async {
    final out = await _run('/bin/ps', const [
      '-axo',
      'pid=,ppid=',
    ], timeout: timeout);
    if (out.exitCode != 0) {
      throw PortProbeException('ps exited with code ${out.exitCode}');
    }
    return parseParentTable(out.stdout);
  }
}

/// Windows: `netstat -ano` for ports (fast), CIM through PowerShell for
/// the process tree (about a second, so only when D4 needs it). Not
/// `wmic`: Windows 11 24H2 removed it (D7).
final class WindowsPortProbe implements PortProbe {
  WindowsPortProbe({TimedCommandRunner run = runWithTimeout}) : _run = run;
  final TimedCommandRunner _run;
  static const timeout = Duration(seconds: 2);
  static const cimTimeout = Duration(seconds: 5);

  @override
  Future<Map<int, Set<int>>> listening() async {
    final out = await _run('netstat', const ['-ano'], timeout: timeout);
    if (out.exitCode != 0) {
      throw PortProbeException('netstat exited with code ${out.exitCode}');
    }
    return parseNetstatListen(out.stdout);
  }

  @override
  Future<Map<int, int>> parents() async {
    final out = await _run('powershell', const [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      r"Get-CimInstance Win32_Process -Property ProcessId,ParentProcessId | "
          r"ForEach-Object { '{0} {1}' -f $_.ProcessId, $_.ParentProcessId }",
    ], timeout: cimTimeout);
    if (out.exitCode != 0) {
      throw PortProbeException('powershell exited with code ${out.exitCode}');
    }
    return parseParentTable(out.stdout);
  }
}

/// Polls [PortProbe] for the sessions' listening ports (C3, D4–D6).
///
/// Runs only while [setVisible] is true **and** [shells] is not empty: no
/// child process otherwise (spec criterion 4). One scan at a time; the
/// next starts [interval] after the last one finished, twice the last gap
/// (up to [maxInterval]) when a scan took longer than [slowScan], and
/// [maxInterval] after a failure. One failure keeps the last ports; two in
/// a row clear them. Listening pids are classified once (the process
/// table is read only when one is new, or after [sessionsChanged]).
final class PortWatcher {
  PortWatcher({
    required PortProbe probe,
    required Map<int, int> Function() shells,
    required void Function(Map<int, List<int>> ports) onPorts,
    DateTime Function()? now,
    this.interval = const Duration(seconds: 3),
    this.slowScan = const Duration(milliseconds: 1500),
    this.maxInterval = const Duration(seconds: 15),
    void Function(String message)? log,
  }) : _probe = probe,
       _shells = shells,
       _onPorts = onPorts,
       _now = now ?? DateTime.now,
       _log = log ?? ((_) {}),
       _gap = interval;

  final PortProbe _probe;
  final Map<int, int> Function() _shells;
  final void Function(Map<int, List<int>> ports) _onPorts;
  final DateTime Function() _now;
  final void Function(String message) _log;
  final Duration interval;
  final Duration slowScan;
  final Duration maxInterval;

  bool _visible = false;
  bool _scanning = false;
  bool _disposed = false;
  Timer? _timer;
  Duration _gap;
  int _failures = 0;

  /// Listening pid → owning session id (null: none of ours).
  final _owners = <int, int?>{};

  void setVisible(bool visible) {
    if (_disposed || _visible == visible) return;
    _visible = visible;
    if (visible) {
      _gap = interval;
      _kick();
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  /// A session started or ended: classify again; start if idle.
  void sessionsChanged() {
    _owners.clear();
    if (_visible && !_disposed && _timer == null && !_scanning) _kick();
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }

  void _kick() {
    _timer?.cancel();
    _timer = Timer(Duration.zero, _tick);
  }

  Future<void> _tick() async {
    _timer = null;
    if (_disposed || !_visible || _scanning) return;
    final shells = _shells();
    if (shells.isEmpty) {
      _owners.clear();
      return; // sessionsChanged starts us again
    }
    _scanning = true;
    final started = _now();
    try {
      final ports = await _scan(shells);
      // A disposed owner may have closed what onPorts writes to.
      if (!_disposed) _onPorts(ports);
      _failures = 0;
    } catch (error) {
      _failures++;
      _log(
        'port scan failed: '
        '${error is PortProbeException ? error.message : error.runtimeType}',
      );
      if (_failures >= 2 && !_disposed) _onPorts(const {});
    } finally {
      _scanning = false;
    }
    if (_disposed || !_visible) return;
    final took = _now().difference(started);
    _gap = _failures > 0
        ? maxInterval
        : took > slowScan
        ? Duration(
            microseconds: min(
              (_gap * 2).inMicroseconds,
              maxInterval.inMicroseconds,
            ),
          )
        : interval;
    _timer = Timer(_gap, _tick);
  }

  Future<Map<int, List<int>>> _scan(Map<int, int> shells) async {
    final listening = await _probe.listening();
    _owners.removeWhere((pid, _) => !listening.containsKey(pid));
    if (listening.keys.any((pid) => !_owners.containsKey(pid))) {
      final parents = await _probe.parents();
      final shellToSession = {for (final e in shells.entries) e.value: e.key};
      for (final pid in listening.keys) {
        _owners.putIfAbsent(pid, () => ownerOf(pid, parents, shellToSession));
      }
    }
    final bySession = <int, Set<int>>{};
    for (final MapEntry(key: pid, value: ports) in listening.entries) {
      final session = _owners[pid];
      if (session != null && shells.containsKey(session)) {
        bySession.putIfAbsent(session, () => <int>{}).addAll(ports);
      }
    }
    return {for (final e in bySession.entries) e.key: e.value.toList()..sort()};
  }
}
