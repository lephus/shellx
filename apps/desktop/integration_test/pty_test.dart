import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/platform/pty/flutter_pty_factory.dart';
import 'package:shellx_desktop/src/platform/pty/windows_native.dart';

final RegExp _ansi = RegExp(
  r'\x1B(?:\[[0-?]*[ -/]*[@-~]|\][^\x07\x1B]*(?:\x07|\x1B\\)|[@-Z\\-_])',
);

/// Accumulates PTY output (ANSI stripped) and waits for a whole line.
final class Transcript {
  Transcript(Stream<Uint8List> output) {
    _subscription = output.listen(
      (chunk) {
        _raw.write(utf8.decode(chunk, allowMalformed: true));
        _changes.add(null);
      },
      onDone: () {
        if (!_done.isCompleted) _done.complete();
      },
    );
  }

  final Completer<void> _done = Completer<void>();

  /// Completes when the PTY closes its output stream.
  Future<void> get done => _done.future;

  final StringBuffer _raw = StringBuffer();
  final StreamController<void> _changes = StreamController<void>.broadcast();
  late final StreamSubscription<Uint8List> _subscription;

  List<String> get lines => _raw
      .toString()
      .replaceAll(_ansi, '')
      .split(RegExp(r'\r?\n|\r'))
      .map((line) => line.trim())
      .toList();

  Future<void> waitForLine(
    bool Function(String line) test, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!lines.any(test)) {
      final left = deadline.difference(DateTime.now());
      if (left <= Duration.zero) {
        fail('Timed out. Transcript:\n${lines.join('\n')}');
      }
      await _changes.stream.first.timeout(left, onTimeout: () {});
    }
  }

  Future<void> close() => _subscription.cancel();
}

List<ShellCommand> _shells() {
  if (!Platform.isWindows) {
    return const [
      ShellCommand(executable: '/bin/zsh', arguments: ['-f'], name: 'zsh'),
    ];
  }
  final shells = <ShellCommand>[
    const ShellCommand(
      executable: 'powershell.exe',
      arguments: ['-NoLogo', '-NoProfile'],
      name: 'powershell',
    ),
  ];
  final hasPwsh = Process.runSync('where.exe', ['pwsh.exe']).exitCode == 0;
  if (hasPwsh) {
    shells.add(
      const ShellCommand(
        executable: 'pwsh.exe',
        arguments: ['-NoLogo', '-NoProfile'],
        name: 'pwsh',
      ),
    );
  }
  return shells;
}

Map<String, String> _environment() => {
  ...Platform.environment,
  'TERM': 'xterm-256color',
  'SHELLX': '1',
};

String get _home =>
    Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME']!;

void _type(Pty pty, String line) =>
    pty.write(Uint8List.fromList(utf8.encode('$line\r')));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final factory = FlutterPtyFactory.forCurrentPlatform();

  for (final shell in _shells()) {
    testWidgets('${shell.name}: echo shellx-ok comes back on its own line', (
      tester,
    ) async {
      final pty = factory.spawn(
        shell,
        workingDirectory: _home,
        environment: _environment(),
        cols: 80,
        rows: 24,
      );
      final transcript = Transcript(pty.output);
      _type(pty, 'echo shellx-ok');
      await transcript.waitForLine((line) => line == 'shellx-ok');
      pty.kill();
      await pty.exitCode.timeout(const Duration(seconds: 15));
      await transcript.close();
    });
  }

  final shell = _shells().first;

  testWidgets('environment and a Vietnamese working directory reach the shell', (
    tester,
  ) async {
    final dir = await Directory.systemTemp.createTemp('shellx-thư-mục-');
    await File(
      '${dir.path}${Platform.pathSeparator}marker.txt',
    ).writeAsString('x');
    final pty = factory.spawn(
      shell,
      workingDirectory: dir.path,
      environment: _environment(),
      cols: 80,
      rows: 24,
    );
    final transcript = Transcript(pty.output);
    if (Platform.isWindows) {
      _type(
        pty,
        r"if (Test-Path marker.txt) { 'marker-' + 'ok' }; 'env-' + $env:SHELLX",
      );
    } else {
      _type(
        pty,
        r'test -f marker.txt && echo marker-$((1+0)); echo env-$SHELLX',
      );
    }
    await transcript.waitForLine(
      (line) => line == (Platform.isWindows ? 'marker-ok' : 'marker-1'),
    );
    await transcript.waitForLine((line) => line == 'env-1');
    pty.kill();
    await pty.exitCode.timeout(const Duration(seconds: 15));
    await transcript.close();
    await dir.delete(recursive: true);
  });

  testWidgets('output closes within 2 s after the shell exits', (tester) async {
    final pty = factory.spawn(
      shell,
      workingDirectory: _home,
      environment: _environment(),
      cols: 80,
      rows: 24,
    );
    final transcript = Transcript(pty.output);
    _type(pty, 'exit');
    await pty.exitCode.timeout(const Duration(seconds: 15));
    await transcript.done.timeout(const Duration(seconds: 2));
  });

  testWidgets('output written right before the shell exits is delivered', (
    tester,
  ) async {
    final pty = factory.spawn(
      shell,
      workingDirectory: _home,
      environment: _environment(),
      cols: 80,
      rows: 24,
    );
    addTearDown(pty.kill);
    final transcript = Transcript(pty.output);
    if (Platform.isWindows) {
      _type(pty, r"1..2000 | % { 'line-' + $_ }; 'tail-' + (6*7); exit");
    } else {
      _type(
        pty,
        r'i=0; while [ $i -lt 2000 ]; do echo line-$i; i=$((i+1)); done; '
        r'echo tail-$((6*7)); exit',
      );
    }
    await pty.exitCode.timeout(const Duration(seconds: 15));
    await transcript.done.timeout(const Duration(seconds: 2));
    expect(transcript.lines, contains('tail-42'));
  });

  testWidgets(
    'exitCode completes while a dart:io child process is running',
    (tester) async {
      // dart:io reaps any child while a Process it started runs (the agent
      // keeps `caffeinate` running), which can take the shell's exit status.
      final other = await Process.start('/bin/sleep', ['30']);
      addTearDown(other.kill);
      final pty = factory.spawn(
        shell,
        workingDirectory: _home,
        environment: _environment(),
        cols: 80,
        rows: 24,
      );
      addTearDown(pty.kill);
      final transcript = Transcript(pty.output);
      _type(pty, 'exit 3');
      final code = await pty.exitCode.timeout(const Duration(seconds: 15));
      expect(code, anyOf(3, -1));
      await transcript.done.timeout(const Duration(seconds: 2));
    },
    skip: Platform.isWindows,
  );

  testWidgets('finished sessions leave no file descriptors behind', (
    tester,
  ) async {
    // Pseudo-terminal descriptors of this process as "fd name" (lsof): the
    // master is /dev/ptmx, a slave /dev/ttysNNN or, once its session has
    // ended, "(revoked)".
    Set<String> ptyFds() {
      final result = Process.runSync('/usr/sbin/lsof', [
        '-p',
        '$pid',
        '-F',
        'fn',
      ]);
      final fds = <String>{};
      String? fd;
      for (final line in const LineSplitter().convert(
        result.stdout as String,
      )) {
        if (line.startsWith('f')) {
          fd = int.tryParse(line.substring(1)) == null
              ? null
              : line.substring(1);
        } else if (line.startsWith('n') && fd != null) {
          final name = line.substring(1);
          if (name == '/dev/ptmx' ||
              name.startsWith('/dev/tty') ||
              name == '(revoked)') {
            fds.add('$fd $name');
          }
        }
      }
      return fds;
    }

    Future<void> runOne() async {
      final pty = factory.spawn(
        shell,
        workingDirectory: _home,
        environment: _environment(),
        cols: 80,
        rows: 24,
      );
      addTearDown(pty.kill);
      final transcript = Transcript(pty.output);
      _type(pty, 'exit');
      await pty.exitCode.timeout(const Duration(seconds: 15));
      await transcript.done.timeout(const Duration(seconds: 2));
    }

    await runOne();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final before = ptyFds();
    for (var i = 0; i < 5; i++) {
      await runOne();
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final added = ptyFds().difference(before);
    expect(added, isEmpty);
  }, skip: Platform.isWindows);

  testWidgets('resize(cols, rows) reaches the terminal', (tester) async {
    final pty = factory.spawn(
      shell,
      workingDirectory: _home,
      environment: _environment(),
      cols: 80,
      rows: 24,
    );
    final transcript = Transcript(pty.output);
    pty.resize(100, 30);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (Platform.isWindows) {
      _type(pty, r"'cols-' + [Console]::WindowWidth");
      await transcript.waitForLine((line) => line == 'cols-100');
    } else {
      _type(pty, r'echo size-$(stty size | tr " " x)');
      await transcript.waitForLine((line) => line == 'size-30x100');
    }
    pty.kill();
    await pty.exitCode.timeout(const Duration(seconds: 15));
    await transcript.close();
  });

  testWidgets('kill() ends the shell and the processes it started', (
    tester,
  ) async {
    final hostsBefore = Platform.isWindows
        ? consoleHostChildren(pid, WindowsProcessTable().snapshotSync())
        : <int>{};
    final pty = factory.spawn(
      shell,
      workingDirectory: _home,
      environment: _environment(),
      cols: 80,
      rows: 24,
    );
    final transcript = Transcript(pty.output);
    if (Platform.isWindows) {
      _type(
        pty,
        r"$p = Start-Process -PassThru -NoNewWindow ping.exe -ArgumentList '-n','300','127.0.0.1'; 'child=' + $p.Id",
      );
    } else {
      _type(pty, r'sleep 300 & echo child=$!');
    }
    late int childPid;
    await transcript.waitForLine((line) {
      final match = RegExp(r'^child=(\d+)$').firstMatch(line);
      if (match == null) return false;
      childPid = int.parse(match[1]!);
      return true;
    });

    pty.kill();
    await pty.exitCode.timeout(const Duration(seconds: 15));
    await Future<void>.delayed(const Duration(seconds: 4));

    if (Platform.isWindows) {
      final table = WindowsProcessTable().snapshotSync();
      expect(
        table.any((e) => e.pid == childPid),
        isFalse,
        reason: 'child process survived kill()',
      );
      expect(
        consoleHostChildren(pid, table).difference(hostsBefore),
        isEmpty,
        reason: 'conhost.exe of the closed PTY is still running',
      );
    } else {
      final probe = await Process.run('/bin/kill', ['-0', '$childPid']);
      expect(probe.exitCode, isNot(0), reason: 'child process survived kill()');
    }
    await transcript.close();
  });

  final vim = Platform.isWindows
      ? r'C:\Program Files\Git\usr\bin\vim.exe'
      : '/usr/bin/vim';
  testWidgets(
    'a full-screen program (vim) runs, takes keys and exits',
    (tester) async {
      final pty = factory.spawn(
        shell,
        workingDirectory: _home,
        environment: _environment(),
        cols: 80,
        rows: 24,
      );
      final transcript = Transcript(pty.output);
      _type(
        pty,
        Platform.isWindows ? "& '$vim' -u NONE -N" : '$vim -u NONE -N',
      );
      await Future<void>.delayed(const Duration(seconds: 2));
      pty.resize(90, 30);
      pty.write(Uint8List.fromList(utf8.encode('\x1b:q!\r')));
      await Future<void>.delayed(const Duration(seconds: 1));
      _type(
        pty,
        Platform.isWindows ? "'after-' + 'vim'" : r'echo after-$((0))vim',
      );
      await transcript.waitForLine(
        (line) => line == (Platform.isWindows ? 'after-vim' : 'after-0vim'),
      );
      pty.kill();
      await pty.exitCode.timeout(const Duration(seconds: 15));
      await transcript.close();
    },
    skip: !File(vim).existsSync(),
  );
}
