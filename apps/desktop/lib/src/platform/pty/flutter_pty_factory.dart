import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_pty/flutter_pty.dart' as fp;
import 'package:shellx_agent/shellx_agent.dart';

import 'process_table.dart';
import 'process_tree_killer.dart';
import 'windows_native.dart';
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

/// Finds the ConPTY host process (`conhost.exe`) that CreatePseudoConsole
/// starts as a child of this process. flutter_pty 0.4.2 never calls
/// ClosePseudoConsole, so the adapter terminates that host itself.
final class ConsoleHostTracker {
  ConsoleHostTracker({
    required List<ProcessEntry> Function() snapshot,
    required int ownPid,
    CommandRunner? run,
  }) : _snapshot = snapshot,
       _ownPid = ownPid,
       _run = run ?? Process.run;

  final List<ProcessEntry> Function() _snapshot;
  final int _ownPid;
  final CommandRunner _run;

  Set<int> hostsNow() => consoleHostChildren(_ownPid, _snapshot());

  /// The single host that appeared since [before], or null if not exactly one.
  int? newHostSince(Set<int> before) {
    final added = hostsNow().difference(before);
    return added.length == 1 ? added.single : null;
  }

  Future<void> terminate(int hostPid) async {
    await _run('taskkill', ['/PID', '$hostPid', '/F']);
  }
}

Set<int> consoleHostChildren(int parentPid, List<ProcessEntry> table) {
  return {
    for (final entry in table)
      if (entry.parentPid == parentPid && _isConsoleHost(entry.name)) entry.pid,
  };
}

bool _isConsoleHost(String name) {
  final lower = name.toLowerCase();
  return lower == 'conhost.exe' || lower == 'openconsole.exe';
}

/// [PtyFactory] backed by package flutter_pty.
///
/// What `kill()` does:
/// * macOS: [PosixProcessTreeKiller] — SIGHUP to the shell and all
///   descendants, SIGKILL to survivors after 2 s.
/// * Windows: [WindowsProcessTreeKiller] (`taskkill /T /F`), then terminates
///   the session's conhost.exe so the pseudo console and its pipes are freed.
final class FlutterPtyFactory implements PtyFactory {
  FlutterPtyFactory({
    required bool isWindows,
    required ProcessTreeKiller killer,
    NativePtyStarter start = startFlutterPty,
    String Function(String path)? shortPath,
    ConsoleHostTracker? consoleHosts,
    Duration outputGrace = const Duration(milliseconds: 500),
  }) : _isWindows = isWindows,
       _outputGrace = outputGrace,
       _killer = killer,
       _start = start,
       _shortPath = shortPath ?? ((path) => path),
       _consoleHosts = consoleHosts;

  factory FlutterPtyFactory.forCurrentPlatform() {
    if (Platform.isWindows) {
      final table = WindowsProcessTable();
      return FlutterPtyFactory(
        isWindows: true,
        killer: WindowsProcessTreeKiller(),
        shortPath: windowsShortPath,
        consoleHosts: ConsoleHostTracker(
          snapshot: table.snapshotSync,
          ownPid: pid,
        ),
      );
    }
    return FlutterPtyFactory(
      isWindows: false,
      killer: PosixProcessTreeKiller(),
    );
  }

  final bool _isWindows;
  final ProcessTreeKiller _killer;
  final NativePtyStarter _start;
  final String Function(String path) _shortPath;
  final ConsoleHostTracker? _consoleHosts;
  final Duration _outputGrace;

  PtyLaunch launchFor(
    ShellCommand command, {
    required String workingDirectory,
    required Map<String, String> environment,
    required int cols,
    required int rows,
  }) {
    if (!_isWindows) {
      return PtyLaunch(
        executable: command.executable,
        arguments: command.arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        columns: cols,
        rows: rows,
      );
    }
    return PtyLaunch(
      executable: windowsQuoteArg(
        asciiSafePathList(command.executable, _shortPath),
      ),
      arguments: [for (final a in command.arguments) windowsQuoteArg(a)],
      workingDirectory: asciiSafePathList(workingDirectory, _shortPath),
      environment: asciiSafeEnvironment(environment, _shortPath),
      columns: cols,
      rows: rows,
    );
  }

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
    final hosts = _consoleHosts;
    final before = hosts?.hostsNow();
    final native = _start(launch);
    final hostPid = before == null ? null : hosts!.newHostSince(before);
    return FlutterPtyAdapter(
      native,
      killer: _killer,
      onExit: hostPid == null ? null : () => hosts!.terminate(hostPid),
      outputGrace: _outputGrace,
    );
  }
}

/// Adapts a [NativePty] to the `shellx_agent` [Pty] contract.
///
/// `output` is guaranteed to close at most [outputGrace] after the process
/// exits (SessionManager waits up to 2 s for it). flutter_pty 0.4.2 already
/// closes its ReceivePort when the exit code arrives; the grace timer covers
/// any native stream that stays open.
final class FlutterPtyAdapter implements Pty {
  FlutterPtyAdapter(
    this._native, {
    required ProcessTreeKiller killer,
    Future<void> Function()? onExit,
    this.outputGrace = const Duration(milliseconds: 500),
  }) : _killer = killer {
    _nativeSubscription = _native.output.listen(
      _output.add,
      onError: _output.addError,
      onDone: _closeOutput,
    );
    unawaited(
      _native.exitCode.then((_) async {
        await Future<void>.delayed(outputGrace);
        _closeOutput();
        if (onExit != null) await onExit();
      }),
    );
  }

  final NativePty _native;
  final ProcessTreeKiller _killer;
  final Duration outputGrace;
  final StreamController<Uint8List> _output = StreamController<Uint8List>();
  late final StreamSubscription<Uint8List> _nativeSubscription;
  bool _killed = false;

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
    unawaited(_killer.killTree(_native.pid));
  }
}
