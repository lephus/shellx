import 'dart:io';

import 'process_table.dart';

/// Terminates a shell and every process it started.
abstract interface class ProcessTreeKiller {
  Future<void> killTree(int rootPid);
}

typedef SignalSender = bool Function(int pid, ProcessSignal signal);
typedef CommandRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

/// macOS: SIGHUP to the shell and all its descendants (what closing a
/// terminal window does), wait [grace], then SIGKILL whatever from that tree is
/// still alive plus anything the shell spawned meanwhile.
///
/// Processes that detached themselves (double fork, re-parented to launchd)
/// before the first snapshot are outside the tree and survive; so do
/// `nohup`/`disown`ed jobs that ignore SIGHUP if they were re-parented.
final class PosixProcessTreeKiller implements ProcessTreeKiller {
  PosixProcessTreeKiller({
    ProcessTable table = const PsProcessTable(),
    SignalSender? signal,
    this.grace = const Duration(seconds: 2),
    int? ownPid,
  }) : _table = table,
       _signal = signal ?? Process.killPid,
       _ownPid = ownPid ?? pid;

  final ProcessTable _table;
  final SignalSender _signal;
  final int _ownPid;
  final Duration grace;

  bool _safe(int target) => target > 1 && target != _ownPid;

  @override
  Future<void> killTree(int rootPid) async {
    if (!_safe(rootPid)) return;
    final before = await _table.snapshot();
    final victims = <int>{rootPid, ...descendantsOf(rootPid, before)}
      ..removeWhere((p) => !_safe(p));
    for (final target in victims) {
      _signal(target, ProcessSignal.sighup);
    }
    await Future<void>.delayed(grace);
    final after = await _table.snapshot();
    final alive = after.map((e) => e.pid).toSet();
    final survivors = <int>{
      ...victims.where(alive.contains),
      ...descendantsOf(rootPid, after),
    }..removeWhere((p) => !_safe(p));
    for (final target in survivors) {
      _signal(target, ProcessSignal.sigkill);
    }
  }
}

/// Windows: `taskkill /PID <pid> /T /F` terminates the shell and every
/// descendant still linked to it by parent PID (TerminateProcess, no graceful
/// signal exists for console processes started under ConPTY).
final class WindowsProcessTreeKiller implements ProcessTreeKiller {
  WindowsProcessTreeKiller({CommandRunner? run}) : _run = run ?? Process.run;

  final CommandRunner _run;

  @override
  Future<void> killTree(int rootPid) async {
    await _run('taskkill', ['/PID', '$rootPid', '/T', '/F']);
  }
}
