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
  void write(Uint8List data);

  /// Note the flutter_pty argument order: rows first.
  void resize(int rows, int columns);

  /// Windows (vendored flutter_pty): terminates the job object holding the
  /// shell and every process it started. False when that failed.
  bool kill();
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
  void write(Uint8List data) => _pty.write(data);
  @override
  void resize(int rows, int columns) => _pty.resize(rows, columns);
  @override
  bool kill() => _pty.kill();
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
///   every process it started.
final class FlutterPtyFactory implements PtyFactory {
  /// [killer] is used on macOS only (default [PosixProcessTreeKiller]).
  /// [onError] receives kill failures (pid and reason only; default:
  /// `debugPrint`).
  FlutterPtyFactory({
    required bool isWindows,
    ProcessTreeKiller? killer,
    NativePtyStarter start = startFlutterPty,
    Duration outputGrace = const Duration(milliseconds: 500),
    void Function(String message)? onError,
  }) : _isWindows = isWindows,
       _killer = isWindows ? null : killer ?? PosixProcessTreeKiller(),
       _start = start,
       _outputGrace = outputGrace,
       _onError = onError;

  factory FlutterPtyFactory.forCurrentPlatform({
    void Function(String message)? onError,
  }) => FlutterPtyFactory(isWindows: Platform.isWindows, onError: onError);

  final bool _isWindows;
  final ProcessTreeKiller? _killer;
  final NativePtyStarter _start;
  final Duration _outputGrace;
  final void Function(String message)? _onError;

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
    return FlutterPtyAdapter(
      _start(launch),
      killer: _killer,
      outputGrace: _outputGrace,
      onError: _onError,
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
/// exited, the tree kill is skipped (its pid may already belong to another
/// process); the job-object kill stays valid and ends anything left in the
/// job. Kill failures never throw: they go to [onError] as
/// `kill of pid <pid> failed: <reason>` — never output, arguments or
/// environment.
final class FlutterPtyAdapter implements Pty {
  FlutterPtyAdapter(
    this._native, {
    ProcessTreeKiller? killer,
    this.outputGrace = const Duration(milliseconds: 500),
    void Function(String message)? onError,
  }) : _killer = killer,
       _onError = onError ?? _debugPrintError {
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

  static void _debugPrintError(String message) =>
      debugPrint('ShellX PTY: $message');

  final NativePty _native;
  final ProcessTreeKiller? _killer;
  final void Function(String message) _onError;
  final Duration outputGrace;
  final StreamController<Uint8List> _output = StreamController<Uint8List>();
  late final StreamSubscription<Uint8List> _nativeSubscription;
  bool _killed = false;
  bool _exited = false;

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

  @override
  void write(Uint8List data) => _native.write(data);

  @override
  void resize(int cols, int rows) => _native.resize(rows, cols);

  @override
  void kill() {
    if (_killed) return;
    _killed = true;
    final killer = _killer;
    if (killer == null) {
      _killJob();
    } else if (!_exited) {
      final target = _native.pid;
      unawaited(
        killer
            .killTree(target)
            .catchError((Object error) => _reportKillError(target, error)),
      );
    }
  }

  void _killJob() {
    try {
      // False after exit is expected: the plugin released the job, which
      // ended everything left in it.
      if (!_native.kill() && !_exited) {
        _onError(
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
    _onError('kill of pid $target failed: $reason');
  }
}
