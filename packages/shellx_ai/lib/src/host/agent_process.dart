import 'dart:async';
import 'dart:io';

import 'agent_catalog.dart';
import 'byte_ring.dart';
import 'process_snapshot.dart';
import 'running_agents.dart' show KillPid, killPidOnly;

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
/// `killProcessTree` (the A10 POSIX tree killer; taskkill /T on Windows).
/// [AgentProcess] uses it on macOS and Linux only: on Windows nothing is
/// killed by walking a tree (see [AgentProcess]).
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
/// killed.
///
/// On macOS and Linux a tree is killed through [killTree]. On Windows
/// ([isWindows]) no tree is ever walked when a kill is made: a parent id
/// outlives its process there and a pid is reused at once, so the tree of a
/// pid (taskkill /T) can take a process that is not the agent's, ShellX itself
/// or what is above it. The agent is killed by its own handle, and the
/// processes the table showed it had started, each on its own through
/// [killPid], after the check that it is still the same process. What the
/// agent starts after the table is read is left.
///
/// Every request for the table says when the agent was spawned, so that a read
/// that began before ([SharedProcessTable]) is never taken for one about it.
final class AgentProcess implements AgentChannel {
  AgentProcess._(
    this._process,
    this._killTree,
    this._killPid,
    this._windows,
    this._grace,
    this._processTable,
    this._firstReadLimit,
    this._spawned,
  ) {
    _process.stderr.listen(_stderr.add, onError: (Object _) {});
    unawaited(_process.exitCode.then((_) => _exited = true));
  }

  static Future<AgentProcess> start(
    AgentCommand command, {
    required String cwd,
    KillTree killTree = killOnly,
    KillPid killPid = killPidOnly,
    bool? isWindows,
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
      killPid,
      isWindows ?? Platform.isWindows,
      grace,
      processTable,
      firstReadLimit ?? firstTableReadLimit(),
      // After the process exists: a table read before is not about it.
      processClock(),
    );
  }

  final Process _process;
  final KillTree _killTree;
  final KillPid _killPid;
  final bool _windows;
  final Duration _grace;
  final ProcessTableReader _processTable;
  final Duration? _firstReadLimit;

  /// When the agent came into being, on the [processClock].
  final Duration _spawned;
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
      await _killAgent();
    }
    await _killLeftovers(started);
  }

  /// The agent that did not leave: with its tree elsewhere, by itself on
  /// Windows (what it started is in the list the caller holds).
  Future<void> _killAgent() async {
    if (_windows) {
      _process.kill(ProcessSignal.sigkill);
    } else {
      await _killTree(_process);
    }
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
      final slack = startSlack(isWindows: _windows);
      final above = ancestorsIn(
        _ownPid,
        rows,
        slack: slack,
      ).takeWhile((p) => p != me.pid);
      return descendantsIn(
        me.pid,
        rows,
        slack: slack,
        never: {_ownPid, ...above},
      );
    } on Object {
      return const [];
    }
  }

  /// Kills what of [started] is still there and still the same process.
  /// What no longer is (it left, or its pid went to another process) is left
  /// alone, and so is anything that was not in [started]. Elsewhere each top
  /// of what is left is killed with its tree, and what that did not take one
  /// by one; on Windows every one of them on its own, and no tree. Best
  /// effort: the stop has been done.
  Future<void> _killLeftovers(List<ProcessRow> started) async {
    if (started.isEmpty) return;
    try {
      final left = await _stillThere(started);
      if (left.isEmpty) return;
      if (_windows) {
        await Future.wait([for (final r in left) _killOne(r.pid)]);
        return;
      }
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
    // Made again as a Future that can hold null: a reader written the plain
    // way (`async => rows`) gives a Future<List<ProcessRow>> at run time,
    // whatever its type says, and its onTimeout could not give null.
    final read = Future<List<ProcessRow>?>.value(
      _processTable(limit: limit, after: _spawned),
    );
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
      if (_windows) {
        await _killPid(pid);
      } else {
        await _killTree(_Stranger(pid));
      }
    } on Object {
      // The others still go.
    }
  }

  @override
  Future<void> kill() async {
    if (!_windows) return _killTree(_process);
    // Windows: who the agent has started, as the table shows it now (it is
    // here, hung or not). The agent goes at once, by its handle; then each of
    // them that is still the same process, one by one, as in a stop: the table
    // took time to come, and a pid is reused at once there.
    final started = await _descendants();
    _process.kill(ProcessSignal.sigkill);
    await _killLeftovers(started);
  }

  @override
  String toString() => '…';
}
