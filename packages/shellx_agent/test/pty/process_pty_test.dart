@TestOn('mac-os || linux')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

const sh = ShellCommand(executable: '/bin/sh', arguments: [], name: 'sh');

Pty spawnSh() => const ProcessPtyFactory().spawn(
  sh,
  workingDirectory: Directory.systemTemp.path,
  environment: buildSessionEnvironment(Platform.environment),
  cols: 80,
  rows: 24,
);

Future<String> collect(Pty pty) async {
  final bytes = <int>[];
  await pty.output.forEach(bytes.addAll);
  return utf8.decode(bytes);
}

void main() {
  test('runs commands written before the process started', () async {
    final pty = spawnSh();
    final output = collect(pty);
    pty.write(Uint8List.fromList(utf8.encode('echo hello; exit 3\n')));
    expect(await pty.exitCode, 3);
    expect(await output, 'hello\n');
  });

  test(
    'merges stderr into output and passes the session environment',
    () async {
      final pty = spawnSh();
      final output = collect(pty);
      pty.write(
        Uint8List.fromList(
          utf8.encode(
            r'echo "$SHELLX $TERM"; echo oops 1>&2; exit 0'
            '\n',
          ),
        ),
      );
      expect(await pty.exitCode, 0);
      final text = await output;
      expect(text, contains('1 xterm-256color'));
      expect(text, contains('oops'));
    },
  );

  test('resize is a no-op and kill ends the process', () async {
    final pty = spawnSh();
    final output = collect(pty);
    pty.resize(100, 40);
    pty.kill();
    expect(await pty.exitCode.timeout(const Duration(seconds: 5)), isNot(0));
    await output;
  });

  test('a missing executable reports exit code 127 and a message', () async {
    final pty = const ProcessPtyFactory().spawn(
      const ShellCommand(
        executable: '/nonexistent/shell',
        arguments: [],
        name: 'x',
      ),
      workingDirectory: Directory.systemTemp.path,
      environment: const {},
      cols: 80,
      rows: 24,
    );
    final output = collect(pty);
    expect(await pty.exitCode, 127);
    expect(await output, contains('failed to start shell'));
  });
}
