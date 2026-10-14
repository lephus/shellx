import 'dart:async';
import 'dart:io';

import 'agent_catalog.dart';
import 'byte_ring.dart';
import 'process_snapshot.dart';

/// This process's own pid (inside [AgentProcess], `pid` is the agent's).
final int _ownPid = pid;

/// A running agent: its stdio and lifetime. [AgentProcess] in the app; an
/// in-process fake in tests.
abstract interface class AgentChannel {
  Stream<List<int>> get stdout;
  StreamSink<List<int>> get stdin;
  Future<int> get exitCode;

  /// The last 256 KiB of stderr ("Xem log", spec D20).
  String get stderrTail;

  /// Close stdin, wait, then kill the tree (spec D6). Whatever the agent
  /// started and left running goes too.
  Future<void> stop();

  /// Kill the tree now ("Dừng hẳn").
  Future<void> kill();
}

/// Starts [command] in [cwd].
typedef AgentLauncher =
    Future<AgentChannel> Function(AgentCommand command, {required String cwd});

/// Kills a process and everything it started; the desktop passes its
/// `killProcessTree` (taskkill /T, or the A10 POSIX tree killer).
typedef KillTree = Future<void> Function(Process process);

/// The fallback [KillTree]: the process only.
Future<void> killOnly(Process process) async {
  process.kill(ProcessSignal.sigkill);
}

/// A process this app did not start, as far as a [KillTree] can use one: it
/// has a pid and takes a signal. What an agent left running is not ours to
/// wait for; nothing else of it works.
final class _Stranger implements Process {
  _Stranger(this.pid);

  @override
  final int pid;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) =>
      Process.killPid(pid, signal);

  @override
  Future<int> get exitCode => Future.value(-1);

  @override
  IOSink get stdin => throw UnsupportedError('not a process of this app');

  @override
  Stream<List<int>> get stdout => const Stream.empty();

  @override
  Stream<List<int>> get stderr => const Stream.empty();
}

/// An agent process: no shell, exactly the command's environment, stderr
/// kept in a ring (spec D6, D20).
///
/// [stop] also ends what the agent started and left running (a dev server
/// holding a port, a test run): an agent that leaves when stdin closes leaves
/// its children to nobody. The process table is read first, while the agent is
/// still their parent ([processTable], for at most [firstReadLimit]); after
/// the exit, or after the grace, what of them is still the same process is
/// killed through [killTree].
final class AgentProcess implements AgentChannel {
  AgentProcess._(
    this._process,
    this._killTree,
    this._grace,
    this._processTable,
    this._firstReadLimit,
  ) {
    _process.stderr.listen(_stderr.add, onError: (Object _) {});
    unawaited(_process.exitCode.then((_) => _exited = true));
  }

  static Future<AgentProcess> start(
    AgentCommand command, {
    required String cwd,
    KillTree killTree = killOnly,
    Duration grace = const Duration(seconds: 2),
    ProcessTableReader processTable = readProcessTable,
    Duration? firstReadLimit,
  }) async {
    final process = await Process.start(
      command.executable,
      command.args,
      workingDirectory: cwd,
      environment: command.environment,
      includeParentEnvironment: false,
    );
    return AgentProcess._(
      process,
      killTree,
      grace,
      processTable,
      firstReadLimit ?? firstTableReadLimit(),
    );
  }

  final Process _process;
  final KillTree _killTree;
  final Duration _grace;
  final ProcessTableReader _processTable;
  final Duration? _firstReadLimit;
  final _stderr = ByteRing(256 * 1024);
  Future<void>? _stopping;
  var _exited = false;

  int get pid => _process.pid;

  @override
  Stream<List<int>> get stdout => _process.stdout;

  @override
  StreamSink<List<int>> get stdin => _process.stdin;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  String get stderrTail => _stderr.text;

  @override
  Future<void> stop() => _stopping ??= _stop();

  Future<void> _stop() async {
    // Before the agent can leave: once it has, nothing links its children to
    // it any more (macOS and Linux hand them to the init process; Windows
    // keeps a parent id that may be reused).
    final started = await _descendants();
    unawaited(
      _process.stdin.close().then<void>((_) {}, onError: (Object _) {}),
    );
    try {
      await _process.exitCode.timeout(_grace);
    } on TimeoutException {
      await _killTree(_process);
    }
    await _killLeftovers(started);
  }

  /// What the agent has started right now: its children, theirs… Empty when
  /// it has left already (its pid may be another process's now), when the
  /// table cannot be read, and when the table does not show the agent as this
  /// process's child, so that only what it started can ever be killed.
  ///
  /// Never this process, nor what is above it in the table (as far as that
  /// does not run into the agent), nor pid 0 or 1, nor what is only under
  /// them: whatever the table says, ShellX is not something its agent left,
  /// and the tree killer ends with an unconditional `killPid`.
  Future<List<ProcessRow>> _descendants() async {
    if (_exited) return const [];
    try {
      final rows = await _table(_firstReadLimit);
      final me = rows?.where((r) => r.pid == _process.pid).firstOrNull;
      if (rows == null || me == null || me.parentPid != _ownPid) {
        return const [];
      }
      final above = ancestorsIn(_ownPid, rows).takeWhile((p) => p != me.pid);
      return descendantsIn(me.pid, rows, never: {_ownPid, ...above});
    } on Object {
      return const [];
    }
  }

  /// Kills what of [started] is still there and still the same process.
  /// What no longer is (it left, or its pid went to another process) is left
  /// alone, and so is anything that was not in [started]. Each top of what
  /// is left is killed with its tree; what that did not take is killed one by
  /// one. Best effort: the stop has been done.
  Future<void> _killLeftovers(List<ProcessRow> started) async {
    if (started.isEmpty) return;
    try {
      final left = await _stillThere(started);
      if (left.isEmpty) return;
      final pids = {for (final r in left) r.pid};
      final tops = [
        for (final r in left)
          if (!pids.contains(r.parentPid)) r,
      ];
      await Future.wait([for (final r in tops) _killOne(r.pid)]);
      final rest = [
        for (final r in left)
          if (!tops.contains(r)) r,
      ];
      if (rest.isEmpty) return;
      await Future.wait([
        for (final r in await _stillThere(rest)) _killOne(r.pid),
      ]);
    } on Object {
      // A table that cannot be read: nothing is killed on a guess.
    }
  }

  /// The table, or null when it is not there within [limit] (the reader's
  /// own when null). The wait is ended here as well as in the reader: the read
  /// may be one that was under way before ([SharedProcessTable]).
  Future<List<ProcessRow>?> _table(Duration? limit) {
    final read = _processTable(limit: limit);
    return limit == null ? read : read.timeout(limit, onTimeout: () => null);
  }

  /// The rows of [rows] that the table shows now as the same process.
  Future<List<ProcessRow>> _stillThere(List<ProcessRow> rows) async {
    final now = await _table(null);
    if (now == null) return const [];
    return [
      for (final r in rows)
        if (now.any((n) => isSameProcess(r, n))) r,
    ];
  }

  Future<void> _killOne(int pid) async {
    try {
      await _killTree(_Stranger(pid));
    } on Object {
      // The others still go.
    }
  }

  @override
  Future<void> kill() => _killTree(_process);

  @override
  String toString() => '…';
}
