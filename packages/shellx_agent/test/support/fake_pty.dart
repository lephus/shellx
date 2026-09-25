import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';

/// Scriptable [Pty]: tests push output with [emit] and end it with [exit].
final class FakePty implements Pty {
  FakePty({
    required this.command,
    required this.workingDirectory,
    required this.environment,
    required this.initialCols,
    required this.initialRows,
  });

  final ShellCommand command;
  final String workingDirectory;
  final Map<String, String> environment;
  final int initialCols;
  final int initialRows;

  final _output = StreamController<Uint8List>();
  final _exitCode = Completer<int>();
  final writes = <Uint8List>[];
  final resizes = <(int, int)>[];
  bool killed = false;

  /// When set, [write] throws this.
  Object? failWrites;

  /// Exit code reported when the session is killed (SIGTERM on POSIX).
  static const int killExitCode = -15;

  @override
  Stream<Uint8List> get output => _output.stream;

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  void write(Uint8List data) {
    final error = failWrites;
    if (error != null) throw error;
    writes.add(Uint8List.fromList(data));
  }

  @override
  void resize(int cols, int rows) => resizes.add((cols, rows));

  @override
  void kill() {
    killed = true;
    exit(killExitCode);
  }

  void emit(String text) => emitBytes(utf8.encode(text));

  void emitBytes(List<int> bytes) {
    if (!_output.isClosed) _output.add(Uint8List.fromList(bytes));
  }

  /// Ends the process with [code]. With [closeOutput] false the exit code is
  /// known while the output stream stays open (a PTY whose output drains
  /// late) until [closeOutputStream] is called.
  void exit(int code, {bool closeOutput = true}) {
    if (_exitCode.isCompleted) return;
    if (closeOutput) _output.close();
    _exitCode.complete(code);
  }

  void closeOutputStream() => _output.close();

  /// Everything written to the shell, decoded as UTF-8.
  String get writtenText => utf8.decode([for (final w in writes) ...w]);
}

final class FakePtyFactory implements PtyFactory {
  final ptys = <FakePty>[];

  /// When set, the next [spawn] calls throw this.
  Object? failWith;

  @override
  Pty spawn(
    ShellCommand command, {
    required String workingDirectory,
    required Map<String, String> environment,
    required int cols,
    required int rows,
  }) {
    final error = failWith;
    if (error != null) throw error;
    final pty = FakePty(
      command: command,
      workingDirectory: workingDirectory,
      environment: environment,
      initialCols: cols,
      initialRows: rows,
    );
    ptys.add(pty);
    return pty;
  }
}

final class FixedShellResolver implements ShellResolver {
  const FixedShellResolver([
    this.command = const ShellCommand(
      executable: '/bin/zsh',
      arguments: ['-l'],
      name: 'zsh',
    ),
  ]);

  final ShellCommand command;

  @override
  Future<ShellCommand> resolve() async => command;
}
