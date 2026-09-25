import 'dart:io';

import 'process_table.dart';

/// Terminates a shell and every process it started.
abstract interface class ProcessTreeKiller {
  /// Completes once the tree has been signalled. Throws (after signalling
  /// everything it could) when the tree could not be walked completely.
  Future<void> killTree(int rootPid);
}

typedef SignalSender = bool Function(int pid, ProcessSignal signal);

/// macOS: closes a terminal session the way closing a terminal window does
/// (SIGHUP), then SIGKILLs whatever from the session survived.
///
/// Processes are found by walking parent pids from every process known to
/// belong to the session ("victims"), so a process that ignores SIGHUP and is
/// re-parented to launchd when the shell dies is still found, and so are the
/// children it starts later:
///
/// 1. Freeze: snapshot the process table and SIGSTOP every running
///    descendant of every running victim, repeating until a snapshot shows
///    nothing new (at most [maxFreezeRounds] rounds). The shell itself keeps
///    running, so its children stay linked to it.
/// 2. SIGHUP the shell, then every other victim, then SIGCONT them all — in
///    one synchronous step, and even when `ps` failed.
/// 3. Wait up to [grace] (polling every [pollInterval], returning early once
///    no victim is left); children started meanwhile become victims.
/// 4. Freeze again, then SIGKILL every victim still running.
///
/// The shell is not stopped before it is hung up: were the agent to exit
/// mid-freeze, the pty hang-up still ends the shell, and the kernel then
/// continues (SIGHUP + SIGCONT) the stopped jobs it orphans. Hanging the
/// shell up before step 1 instead would let it exit before the first
/// snapshot and re-parent its children out of reach. The shell may still
/// fork between the last snapshot and its SIGHUP (a narrow race); processes
/// that left the tree before a snapshot saw them (double-forked daemons) are
/// out of reach too. Never signals pid 0, launchd (1) or this process.
final class PosixProcessTreeKiller implements ProcessTreeKiller {
  PosixProcessTreeKiller({
    ProcessTable table = const PsProcessTable(),
    SignalSender? signal,
    this.grace = const Duration(seconds: 2),
    this.pollInterval = const Duration(milliseconds: 100),
    int? ownPid,
  }) : _table = table,
       _signal = signal ?? Process.killPid,
       _ownPid = ownPid ?? pid;

  static const int maxFreezeRounds = 10;

  final ProcessTable _table;
  final SignalSender _signal;
  final int _ownPid;
  final Duration grace;
  final Duration pollInterval;

  bool _safe(int target) => target > 1 && target != _ownPid;

  @override
  Future<void> killTree(int rootPid) async {
    if (!_safe(rootPid)) return;

    final victims = <int>{rootPid};
    Object? error;
    StackTrace? errorStack;
    void record(Object e, StackTrace s) {
      error ??= e;
      errorStack ??= s;
    }

    try {
      await _freeze(victims, spare: rootPid);
    } catch (e, s) {
      record(e, s);
    }
    // No await from here to the last SIGCONT. Every victim but the shell is
    // stopped, so it is still there to signal.
    _signal(rootPid, ProcessSignal.sighup);
    for (final target in victims) {
      if (target != rootPid) _signal(target, ProcessSignal.sighup);
    }
    for (final target in victims) {
      _signal(target, ProcessSignal.sigcont);
    }

    try {
      await _awaitExit(victims);
    } catch (e, s) {
      record(e, s);
    }

    Set<int>? running;
    try {
      running = await _freeze(victims);
    } catch (e, s) {
      record(e, s);
    }
    for (final target in victims) {
      // Without a final snapshot, kill every victim rather than leave one
      // stopped or running.
      if (running == null || running.contains(target)) {
        _signal(target, ProcessSignal.sigkill);
      }
    }

    final failure = error;
    if (failure != null) Error.throwWithStackTrace(failure, errorStack!);
  }

  /// Adds every descendant of a running victim to [victims]; returns the
  /// victims running in [table].
  Set<int> _expand(Set<int> victims, List<ProcessEntry> table) {
    final present = {for (final entry in table) entry.pid};
    final running = <int>{};
    for (final victim in victims) {
      if (!present.contains(victim)) continue;
      running
        ..add(victim)
        ..addAll(descendantsOf(victim, table));
    }
    running.removeWhere((target) => !_safe(target));
    victims.addAll(running);
    return running;
  }

  /// SIGSTOPs the running victims (except [spare]) and their descendants
  /// until a snapshot shows no new process; returns the victims running in
  /// the last one.
  Future<Set<int>> _freeze(Set<int> victims, {int? spare}) async {
    final stopped = <int>{?spare};
    var running = <int>{};
    for (var round = 0; round < maxFreezeRounds; round++) {
      running = _expand(victims, await _table.snapshot());
      final fresh = running.difference(stopped);
      if (fresh.isEmpty) break;
      for (final target in fresh) {
        _signal(target, ProcessSignal.sigstop);
      }
      stopped.addAll(fresh);
    }
    return running;
  }

  /// Waits up to [grace] for every victim to exit.
  Future<void> _awaitExit(Set<int> victims) async {
    final clock = Stopwatch()..start();
    while (clock.elapsed < grace) {
      final left = grace - clock.elapsed;
      await Future<void>.delayed(left < pollInterval ? left : pollInterval);
      final List<ProcessEntry> table;
      try {
        table = await _table.snapshot();
      } catch (_) {
        // Still give the processes their grace before SIGKILL.
        final rest = grace - clock.elapsed;
        if (rest > Duration.zero) await Future<void>.delayed(rest);
        rethrow;
      }
      if (_expand(victims, table).isEmpty) return;
    }
  }
}
