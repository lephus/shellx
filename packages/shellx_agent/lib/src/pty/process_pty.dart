import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'pty.dart';

/// [PtyFactory] backed by `dart:io` [Process] (no TTY). Used by the headless
/// end-to-end tests; the desktop app uses a real PTY adapter instead.
/// stdout and stderr are merged into [Pty.output]; [Pty.resize] is a no-op.
final class ProcessPtyFactory implements PtyFactory {
  const ProcessPtyFactory();

  @override
  Pty spawn(
    ShellCommand command, {
    required String workingDirectory,
    required Map<String, String> environment,
    required int cols,
    required int rows,
  }) {
    return _ProcessPty(
      Process.start(
        command.executable,
        command.arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        includeParentEnvironment: false,
      ),
    );
  }
}

final class _ProcessPty implements Pty {
  _ProcessPty(Future<Process> starting) {
    starting.then(_onStarted, onError: _onStartFailed);
  }

  final _output = StreamController<Uint8List>();
  final _exitCode = Completer<int>();
  final _pendingWrites = <Uint8List>[];
  Process? _process;
  bool _killRequested = false;

  @override
  Stream<Uint8List> get output => _output.stream;

  @override
  Future<int> get exitCode => _exitCode.future;

  void _onStarted(Process process) {
    _process = process;
    var openStreams = 2;
    void streamDone() {
      openStreams--;
      if (openStreams == 0) _output.close();
    }

    void forward(List<int> data) => _output.add(Uint8List.fromList(data));
    process.stdout.listen(forward, onDone: streamDone, onError: (Object _) {});
    process.stderr.listen(forward, onDone: streamDone, onError: (Object _) {});
    process.stdin.done.catchError((Object _) {});
    process.exitCode.then(_exitCode.complete);
    if (_killRequested) {
      process.kill(ProcessSignal.sigkill);
      return;
    }
    for (final data in _pendingWrites) {
      process.stdin.add(data);
    }
    _pendingWrites.clear();
  }

  void _onStartFailed(Object error) {
    _output.add(
      Uint8List.fromList(
        utf8.encode('shellx: failed to start shell: $error\r\n'),
      ),
    );
    _output.close();
    _exitCode.complete(127);
  }

  @override
  void write(Uint8List data) {
    final process = _process;
    if (process == null) {
      _pendingWrites.add(Uint8List.fromList(data));
      return;
    }
    try {
      process.stdin.add(data);
    } on StateError {
      // stdin already closed: the shell has exited.
    }
  }

  @override
  void resize(int cols, int rows) {}

  @override
  void kill() {
    _killRequested = true;
    _process?.kill(ProcessSignal.sigkill);
  }
}
