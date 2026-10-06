import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';

/// Scriptable [Pty]: tests push output with [emit] and end it with [exit].
final class FakePty implements Pty {
  FakePty({required this.initialCols, required this.initialRows});

  final int initialCols;
  final int initialRows;
  final _output = StreamController<Uint8List>();
  final _exitCode = Completer<int>();
  final writes = <Uint8List>[];
  final resizes = <(int, int)>[];
  bool killed = false;

  static const int killExitCode = -15;

  @override
  Stream<Uint8List> get output => _output.stream;
  @override
  Future<int> get exitCode => _exitCode.future;
  @override
  void write(Uint8List data) => writes.add(Uint8List.fromList(data));
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

  void exit(int code) {
    if (_exitCode.isCompleted) return;
    _output.close();
    _exitCode.complete(code);
  }

  String get writtenText => utf8.decode([for (final w in writes) ...w]);
}

final class FakePtyFactory implements PtyFactory {
  final ptys = <FakePty>[];
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
    final pty = FakePty(initialCols: cols, initialRows: rows);
    ptys.add(pty);
    return pty;
  }
}

final class FixedShellResolver implements ShellResolver {
  const FixedShellResolver();
  @override
  Future<ShellCommand> resolve() async => const ShellCommand(
    executable: '/bin/zsh',
    arguments: ['-l'],
    name: 'zsh',
  );
}
