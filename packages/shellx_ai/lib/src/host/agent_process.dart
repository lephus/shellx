import 'dart:async';
import 'dart:io';

import 'agent_catalog.dart';
import 'byte_ring.dart';

/// A running agent: its stdio and lifetime. [AgentProcess] in the app; an
/// in-process fake in tests.
abstract interface class AgentChannel {
  Stream<List<int>> get stdout;
  StreamSink<List<int>> get stdin;
  Future<int> get exitCode;

  /// The last 256 KiB of stderr ("Xem log", spec D20).
  String get stderrTail;

  /// Close stdin, wait, then kill the tree (spec D6).
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

/// An agent process: no shell, exactly the command's environment, stderr
/// kept in a ring (spec D6, D20).
final class AgentProcess implements AgentChannel {
  AgentProcess._(this._process, this._killTree, this._grace) {
    _process.stderr.listen(_stderr.add, onError: (Object _) {});
  }

  static Future<AgentProcess> start(
    AgentCommand command, {
    required String cwd,
    KillTree killTree = killOnly,
    Duration grace = const Duration(seconds: 2),
  }) async {
    final process = await Process.start(
      command.executable,
      command.args,
      workingDirectory: cwd,
      environment: command.environment,
      includeParentEnvironment: false,
    );
    return AgentProcess._(process, killTree, grace);
  }

  final Process _process;
  final KillTree _killTree;
  final Duration _grace;
  final _stderr = ByteRing(256 * 1024);
  Future<void>? _stopping;

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
    unawaited(
      _process.stdin.close().then<void>((_) {}, onError: (Object _) {}),
    );
    try {
      await _process.exitCode.timeout(_grace);
    } on TimeoutException {
      await _killTree(_process);
    }
  }

  @override
  Future<void> kill() => _killTree(_process);

  @override
  String toString() => '…';
}
