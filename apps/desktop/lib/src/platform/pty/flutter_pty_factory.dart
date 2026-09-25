import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_pty/flutter_pty.dart' as fp;
import 'package:shellx_agent/shellx_agent.dart';

import 'process_table.dart';
import 'process_tree_killer.dart';
import 'windows_text.dart';

/// Arguments handed to the native PTY, after platform fix-ups.
final class PtyLaunch {
  const PtyLaunch({
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
    required this.environment,
    required this.columns,
    required this.rows,
  });

  final String executable;
  final List<String> arguments;
  final String workingDirectory;
  final Map<String, String> environment;
  final int columns;
  final int rows;
}

/// The subset of `flutter_pty`'s `Pty` this adapter uses; faked in unit tests.
abstract interface class NativePty {
  int get pid;
  Stream<Uint8List> get output;
  Future<int> get exitCode;

  /// Never blocks (vendored flutter_pty). False when the input was dropped:
  /// the shell has not read the input already queued (1 MiB), or the pty
  /// is gone.
  bool write(Uint8List data);

  /// Note the flutter_pty argument order: rows first.
  void resize(int rows, int columns);

  /// Windows (vendored flutter_pty): terminates the job object holding the
  /// shell and every process it started, or only the shell when it runs
  /// without one (see [jobError]). False when that failed.
  bool kill();

  /// Windows: 0 when the shell runs in the plugin's job object; otherwise
  /// the Win32 error that prevented it, and [kill] ends the shell only.
  int get jobError;
}

typedef NativePtyStarter = NativePty Function(PtyLaunch launch);

final class _FlutterNativePty implements NativePty {
  _FlutterNativePty(this._pty);

  final fp.Pty _pty;

  @override
  int get pid => _pty.pid;
  @override
  Stream<Uint8List> get output => _pty.output;
  @override
  Future<int> get exitCode => _pty.exitCode;
  @override
  bool write(Uint8List data) => _pty.write(data);
  @override
  void resize(int rows, int columns) => _pty.resize(rows, columns);
  @override
  bool kill() => _pty.kill();
  @override
  int get jobError => _pty.jobError;
}

NativePty startFlutterPty(PtyLaunch launch) {
  return _FlutterNativePty(
    fp.Pty.start(
      launch.executable,
      arguments: launch.arguments,
      workingDirectory: launch.workingDirectory,
      environment: launch.environment,
      columns: launch.columns,
      rows: launch.rows,
    ),
  );
}

/// [PtyFactory] backed by the vendored flutter_pty
/// (`third_party/flutter_pty`, see its SHELLX_PATCHES.md).
///
/// What `kill()` does:
/// * macOS: [PosixProcessTreeKiller] — freeze the shell's process tree,
///   SIGHUP it, SIGKILL what is left after 2 s.
/// * Windows: the plugin's job object — TerminateJobObject ends the shell and
///   every process it started. Should the job object be unavailable, the
///   shell still starts and `kill()` ends the shell only; that is reported
///   once through `onError`.
final class FlutterPtyFactory implements PtyFactory {
  /// [killer] is used on macOS only (default [PosixProcessTreeKiller]).
  /// [onError] receives kill failures (pid and reason only; default:
  /// `debugPrint`). [onProblem] receives the same events as just the shell's
  /// pid, for telling the user that processes may be left behind.
  FlutterPtyFactory({
    required bool isWindows,
    ProcessTreeKiller? killer,
    NativePtyStarter start = startFlutterPty,
    Duration outputGrace = const Duration(milliseconds: 500),
    void Function(String message)? onError,
    void Function(int pid)? onProblem,
  }) : _isWindows = isWindows,
       _killer = isWindows ? null : killer ?? PosixProcessTreeKiller(),
       _start = start,
       _outputGrace = outputGrace,
       _onError = onError ?? FlutterPtyAdapter.debugPrintError,
       _onProblem = onProblem;

  factory FlutterPtyFactory.forCurrentPlatform({
    void Function(String message)? onError,
    void Function(int pid)? onProblem,
  }) => FlutterPtyFactory(
    isWindows: Platform.isWindows,
    onError: onError,
    onProblem: onProblem,
  );

  final bool _isWindows;
  final ProcessTreeKiller? _killer;
  final NativePtyStarter _start;
  final Duration _outputGrace;
  final void Function(String message) _onError;
  final void Function(int pid)? _onProblem;
  bool _reportedNoJob = false;

  /// Tree kills started by this factory's ptys that have not finished yet.
  final Set<Future<void>> _kills = {};

  /// Completes once every process-tree kill started by this factory's ptys
  /// has finished (successfully or not) — including kills that start while
  /// it waits. Never throws; failures went to `onError` already.
  ///
  /// The agent awaits this (bounded) before it signs out or exits, so it
  /// never dies halfway through a macOS tree kill (a frozen survivor would
  /// stay stopped). Windows kills (job object) are synchronous: nothing to
  /// wait for.
  Future<void> killsSettled() async {
    while (_kills.isNotEmpty) {
      await Future.wait(_kills.toList());
    }
  }

  void _trackKill(Future<void> kill) {
    final settled = kill.catchError((Object _) {});
    _kills.add(settled);
    unawaited(settled.whenComplete(() => _kills.remove(settled)));
  }

  /// Windows: the plugin writes the executable and the arguments into the
  /// command line as given, so each is quoted. Paths and environment values
  /// are passed as they are (the plugin converts UTF-8 to UTF-16).
  PtyLaunch launchFor(
    ShellCommand command, {
    required String workingDirectory,
    required Map<String, String> environment,
    required int cols,
    required int rows,
  }) {
    return PtyLaunch(
      executable: _isWindows
          ? windowsQuoteArg(command.executable)
          : command.executable,
      arguments: _isWindows
          ? [for (final a in command.arguments) windowsQuoteArg(a)]
          : command.arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      columns: cols,
      rows: rows,
    );
  }

  /// Throws (e.g. `StateError` from flutter_pty) when the shell cannot be
  /// started; SessionManager reports that as `spawn_failed`.
  @override
  Pty spawn(
    ShellCommand command, {
    required String workingDirectory,
    required Map<String, String> environment,
    required int cols,
    required int rows,
  }) {
    final launch = launchFor(
      command,
      workingDirectory: workingDirectory,
      environment: environment,
      cols: cols,
      rows: rows,
    );
    final native = _start(launch);
    if (_isWindows && native.jobError != 0 && !_reportedNoJob) {
      _reportedNoJob = true;
      _onError(
        'pid ${native.pid} started without a job object '
        '(error ${native.jobError}): kill() ends the shell only',
      );
      _onProblem?.call(native.pid);
    }
    return FlutterPtyAdapter(
      native,
      killer: _killer,
      outputGrace: _outputGrace,
      onError: _onError,
      onProblem: _onProblem,
      onKillStarted: _trackKill,
    );
  }
}

/// Adapts a [NativePty] to the `shellx_agent` [Pty] contract.
///
/// `output` closes when the native stream ends (the vendored flutter_pty ends
/// it once every process holding the terminal has closed it, after the last
/// chunk), and at the latest [outputGrace] after the process exits — a
/// background process can keep the terminal open (SessionManager waits up to
/// 2 s for it).
///
/// `kill()` runs [killer]'s tree kill on the shell's pid (macOS) or, without
/// a killer, the plugin's job-object kill (Windows). Once the shell has
/// exited it is a no-op on both (overview §5.6 Pty contract): the pid may
/// already belong to another process, and what the shell left behind is
/// not killed (on Windows only what is still attached to the closed pseudo
/// console ends with it). Kill failures never throw: they go to
/// [onError] as `kill of pid <pid> failed: <reason>` — never output,
/// arguments or environment — and to [onProblem] as the pid alone (what the
/// user is shown). Each tree kill (a Future that never fails) is
/// handed to [onKillStarted] so its owner can wait for it
/// ([FlutterPtyFactory.killsSettled]).
final class FlutterPtyAdapter implements Pty {
  FlutterPtyAdapter(
    this._native, {
    ProcessTreeKiller? killer,
    this.outputGrace = const Duration(milliseconds: 500),
    void Function(String message)? onError,
    void Function(int pid)? onProblem,
    void Function(Future<void> kill)? onKillStarted,
  }) : _killer = killer,
       _onError = onError ?? debugPrintError,
       _onProblem = onProblem,
       _onKillStarted = onKillStarted {
    _nativeSubscription = _native.output.listen(
      _output.add,
      onError: _output.addError,
      onDone: _closeOutput,
    );
    unawaited(
      _native.exitCode.then((_) async {
        _exited = true;
        await Future<void>.delayed(outputGrace);
        _closeOutput();
      }),
    );
  }

  /// The default error reporter.
  static void debugPrintError(String message) =>
      debugPrint('ShellX PTY: $message');

  final NativePty _native;
  final ProcessTreeKiller? _killer;
  final void Function(String message) _onError;
  final void Function(int pid)? _onProblem;
  final void Function(Future<void> kill)? _onKillStarted;
  final Duration outputGrace;
  final StreamController<Uint8List> _output = StreamController<Uint8List>();
  late final StreamSubscription<Uint8List> _nativeSubscription;
  bool _killed = false;
  bool _exited = false;
  bool _reportedDroppedInput = false;

  int get pid => _native.pid;

  void _closeOutput() {
    if (_output.isClosed) return;
    unawaited(_nativeSubscription.cancel());
    unawaited(_output.close());
  }

  @override
  Stream<Uint8List> get output => _output.stream;

  @override
  Future<int> get exitCode => _native.exitCode;

  /// Never blocks. Input the shell does not read piles up in the plugin's
  /// queue; what does not fit is dropped and reported once per pty through
  /// `onError` (the pid only, never the input).
  @override
  void write(Uint8List data) {
    if (_native.write(data) || _exited || _reportedDroppedInput) return;
    _reportedDroppedInput = true;
    _onError('pid ${_native.pid}: input dropped: the shell is not reading it');
  }

  @override
  void resize(int cols, int rows) => _native.resize(rows, cols);

  /// A no-op once the shell has exited (overview §5.6), on both paths.
  @override
  void kill() {
    if (_killed || _exited) return;
    _killed = true;
    final killer = _killer;
    if (killer == null) {
      _killJob();
    } else {
      final target = _native.pid;
      final kill = killer
          .killTree(target)
          .catchError((Object error) => _reportKillError(target, error));
      _onKillStarted?.call(kill);
      unawaited(kill);
    }
  }

  void _killJob() {
    try {
      // False once the shell has exited is expected (the plugin no longer
      // signals then): it can race the exit.
      if (!_native.kill() && !_exited) {
        _report(
          _native.pid,
          'kill of pid ${_native.pid} failed: '
          'could not terminate the job object',
        );
      }
    } catch (error) {
      _reportKillError(_native.pid, error);
    }
  }

  void _reportKillError(int target, Object error) {
    final reason = error is ProcessTableException
        ? error.message
        : '${error.runtimeType}';
    _report(target, 'kill of pid $target failed: $reason');
  }

  void _report(int target, String message) {
    _onError(message);
    _onProblem?.call(target);
  }
}
