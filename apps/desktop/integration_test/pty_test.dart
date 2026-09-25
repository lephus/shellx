import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/platform/pty/flutter_pty_factory.dart';

final RegExp _ansi = RegExp(
  r'\x1B(?:\[[0-?]*[ -/]*[@-~]|\][^\x07\x1B]*(?:\x07|\x1B\\)|[@-Z\\-_])',
);

/// Accumulates PTY output and waits for a whole line (ANSI stripped) or for
/// a raw sequence.
final class Transcript {
  Transcript(Stream<Uint8List> output) {
    // Chunked decoding: a character may be split across output chunks.
    _subscription = const Utf8Decoder(allowMalformed: true)
        .bind(output)
        .listen(
          (text) {
            _raw.write(text);
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
  late final StreamSubscription<String> _subscription;

  /// Everything received so far, escape sequences included.
  String get raw => _raw.toString();

  List<String> get lines => raw
      .replaceAll(_ansi, '')
      .split(RegExp(r'\r?\n|\r'))
      .map((line) => line.trim())
      .toList();

  Future<void> waitForLine(
    bool Function(String line) test, {
    Duration timeout = const Duration(seconds: 30),
  }) => _waitFor(() => lines.any(test), timeout);

  Future<void> waitForRaw(
    bool Function(String raw) test, {
    Duration timeout = const Duration(seconds: 30),
  }) => _waitFor(() => test(raw), timeout);

  Future<void> _waitFor(bool Function() test, Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (!test()) {
      final left = deadline.difference(DateTime.now());
      if (left <= Duration.zero) {
        fail('Timed out. Transcript:\n${lines.join('\n')}');
      }
      await _changes.stream.first.timeout(left, onTimeout: () {});
    }
  }

  /// Waits for a line ending in `<name>=<digits>` (a background job may
  /// print it after the prompt) and returns the number.
  Future<int> waitForNumber(String name) async {
    final pattern = RegExp('\\b$name=(\\d+)\$');
    late int value;
    await waitForLine((line) {
      final match = pattern.firstMatch(line);
      if (match == null) return false;
      value = int.parse(match[1]!);
      return true;
    });
    return value;
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

/// Windows: whether a process with [processId] is running.
bool _windowsProcessRunning(int processId) {
  final result = Process.runSync('tasklist.exe', [
    '/FI',
    'PID eq $processId',
    '/NH',
    '/FO',
    'CSV',
  ]);
  return (result.stdout as String).contains('"$processId"');
}

/// Whether a process with [processId] is running.
Future<bool> _running(int processId) async {
  if (Platform.isWindows) return _windowsProcessRunning(processId);
  final probe = await Process.run('/bin/kill', ['-0', '$processId']);
  return probe.exitCode == 0;
}

/// Keeps a dart:io child process running until the test ends, the way the
/// agent keeps `caffeinate` running: dart:io then reaps any child that exits.
Future<void> _keepDartIoChildRunning() async {
  final other = await Process.start('/bin/sleep', ['30']);
  addTearDown(() async {
    other.kill();
    await other.exitCode;
  });
}

/// Windows: the conhost.exe processes this process started — one per open
/// pseudo console.
Set<int> _conhostChildren() {
  final result = Process.runSync('powershell.exe', [
    '-NoProfile',
    '-NonInteractive',
    '-Command',
    "Get-CimInstance Win32_Process -Filter 'ParentProcessId=$pid' | "
        "Where-Object Name -eq 'conhost.exe' | ForEach-Object ProcessId",
  ]);
  return {
    for (final line in const LineSplitter().convert(result.stdout as String))
      ?int.tryParse(line.trim()),
  };
}

/// macOS: pseudo-terminal descriptors of this process as "fd name" (lsof):
/// the master is /dev/ptmx, a slave /dev/ttysNNN or, once its session has
/// ended, "(revoked)".
Set<String> _ptyFds() {
  final result = Process.runSync('/usr/sbin/lsof', ['-p', '$pid', '-F', 'fn']);
  final fds = <String>{};
  String? fd;
  for (final line in const LineSplitter().convert(result.stdout as String)) {
    if (line.startsWith('f')) {
      fd = int.tryParse(line.substring(1)) == null ? null : line.substring(1);
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

/// macOS: children of this process that exited but were never reaped.
Set<String> _zombieChildren() {
  final result = Process.runSync('/bin/ps', ['-A', '-o', 'pid=,ppid=,stat=']);
  return {
    for (final line in const LineSplitter().convert(result.stdout as String))
      if (line.trim().split(RegExp(r'\s+')) case [
        final child,
        final parent,
        final stat,
      ] when parent == '$pid' && stat.startsWith('Z'))
        'zombie $child',
  };
}

/// What an ended session could leave behind in this process: pty
/// descriptors and unreaped shells (macOS) or conhost.exe children
/// (Windows).
Set<String> _sessionLeftovers() => Platform.isWindows
    ? {for (final host in _conhostChildren()) 'conhost.exe $host'}
    : {..._ptyFds(), ..._zombieChildren()};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final factory = FlutterPtyFactory.forCurrentPlatform();

  /// Spawns [shell]; the pty is killed and its transcript closed when the
  /// test ends, whatever happens.
  (Pty, Transcript) open(
    ShellCommand shell, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) {
    final pty = factory.spawn(
      shell,
      workingDirectory: workingDirectory ?? _home,
      environment: environment ?? _environment(),
      cols: 80,
      rows: 24,
    );
    addTearDown(pty.kill);
    final transcript = Transcript(pty.output);
    addTearDown(transcript.close);
    return (pty, transcript);
  }

  for (final shell in _shells()) {
    testWidgets('${shell.name}: echo shellx-ok comes back on its own line', (
      tester,
    ) async {
      final (pty, transcript) = open(shell);
      _type(pty, 'echo shellx-ok');
      await transcript.waitForLine((line) => line == 'shellx-ok');
      pty.kill();
      await pty.exitCode.timeout(const Duration(seconds: 15));
    });
  }

  final shell = _shells().first;

  testWidgets('environment and a Vietnamese working directory reach the shell', (
    tester,
  ) async {
    final dir = await Directory.systemTemp.createTemp('shellx-thư-mục-');
    addTearDown(() => dir.delete(recursive: true));
    await File(
      '${dir.path}${Platform.pathSeparator}marker.txt',
    ).writeAsString('x');
    final (pty, transcript) = open(shell, workingDirectory: dir.path);
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
  });

  testWidgets(
    'a Vietnamese working directory name and environment value arrive intact',
    (tester) async {
      final dir = await Directory.systemTemp.createTemp('shellx-Nguyễn-Văn-');
      addTearDown(() => dir.delete(recursive: true));
      final name = dir.path.split(Platform.pathSeparator).last;
      final (pty, transcript) = open(
        shell,
        workingDirectory: dir.path,
        environment: {..._environment(), 'SHELLX_TEN': 'Lê Hữu Phú'},
      );
      if (Platform.isWindows) {
        _type(
          pty,
          r"'cwd=' + (Split-Path -Leaf (Get-Location).Path); "
          r"'ten=' + $env:SHELLX_TEN",
        );
      } else {
        _type(pty, r'echo "cwd=$(basename "$PWD")"; echo "ten=$SHELLX_TEN"');
      }
      await transcript.waitForLine((line) => line == 'cwd=$name');
      await transcript.waitForLine((line) => line == 'ten=Lê Hữu Phú');
    },
  );

  testWidgets('output closes within 2 s after the shell exits', (tester) async {
    final (pty, transcript) = open(shell);
    _type(pty, 'exit');
    await pty.exitCode.timeout(const Duration(seconds: 15));
    await transcript.done.timeout(const Duration(seconds: 2));
  });

  testWidgets('output written right before the shell exits is delivered', (
    tester,
  ) async {
    final (pty, transcript) = open(shell);
    if (Platform.isWindows) {
      // conhost renders on a timer: give it one frame to paint the last line
      // before the shell exits (this checks the plugin keeps what conhost
      // wrote, not how fast conhost paints).
      _type(
        pty,
        r"1..2000 | % { 'line-' + $_ }; 'tail-' + (6*7); "
        r'Start-Sleep -Milliseconds 300; exit',
      );
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
    'the exact exit code arrives while a dart:io child process is running',
    (tester) async {
      // dart:io reaps any child while a Process it started runs (the agent
      // keeps `caffeinate` running); the plugin still gets the shell's
      // status, from kqueue.
      await _keepDartIoChildRunning();
      final (pty, transcript) = open(shell);
      _type(pty, 'exit 3');
      final code = await pty.exitCode.timeout(const Duration(seconds: 15));
      expect(code, 3);
      await transcript.done.timeout(const Duration(seconds: 2));
    },
    skip: Platform.isWindows,
  );

  testWidgets('a shell that cannot be started', (tester) async {
    const missing = ShellCommand(
      executable: 'shellx-no-such-shell',
      arguments: [],
      name: 'missing',
    );
    if (Platform.isWindows) {
      // CreateProcessW fails: spawn throws and the pseudo console created
      // before it is closed again.
      final before = _conhostChildren();
      expect(
        () => factory.spawn(
          missing,
          workingDirectory: _home,
          environment: _environment(),
          cols: 80,
          rows: 24,
        ),
        throwsStateError,
      );
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(_conhostChildren().difference(before), isEmpty);
    } else {
      // execvp fails in the forked child, which must exit (127) instead of
      // running on as a copy of the agent — also while dart:io reaps.
      await _keepDartIoChildRunning();
      final (pty, transcript) = open(missing);
      expect(await pty.exitCode.timeout(const Duration(seconds: 15)), 127);
      await transcript.done.timeout(const Duration(seconds: 2));
    }
  });

  testWidgets('finished sessions leave nothing behind', (tester) async {
    Future<void> runOne() async {
      final (pty, transcript) = open(shell);
      _type(pty, 'exit');
      await pty.exitCode.timeout(const Duration(seconds: 15));
      await transcript.done.timeout(const Duration(seconds: 2));
    }

    await runOne();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final before = _sessionLeftovers();
    for (var i = 0; i < 5; i++) {
      await runOne();
    }
    await Future<void>.delayed(
      Duration(milliseconds: Platform.isWindows ? 3000 : 500),
    );
    expect(_sessionLeftovers().difference(before), isEmpty);
  });

  /// [count] lines of 63 'a's and a newline: complete lines fill the
  /// terminal's input queue (a partial line would just be dropped by the
  /// line discipline once full).
  Uint8List lines(int count) {
    final line = [...List<int>.filled(63, 0x61), 0x0a];
    return Uint8List.fromList([for (var i = 0; i < count; i++) ...line]);
  }

  /// Starts a command in [pty] that never reads the terminal and waits
  /// until it runs.
  Future<void> startNotReading(Pty pty, Transcript transcript) async {
    if (Platform.isWindows) {
      _type(pty, r"'started-' + (40+2); Start-Sleep 30");
    } else {
      _type(pty, r'echo started-$((40+2)); sleep 30');
    }
    await transcript.waitForLine((line) => line == 'started-42');
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  testWidgets('writing to a shell that is not reading never blocks the agent', (
    tester,
  ) async {
    final (pty, transcript) = open(shell);
    await startNotReading(pty, transcript);

    // 4 KB is well past what the terminal buffers for a command that
    // does not read (about 1 KB on macOS).
    final watch = Stopwatch()..start();
    pty.write(lines(64));
    expect(watch.elapsed, lessThan(const Duration(milliseconds: 100)));

    // The isolate keeps running: relay pings, the tray, Ctrl+C.
    final tick = Stopwatch()..start();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(tick.elapsed, lessThan(const Duration(seconds: 1)));
    pty.write(Uint8List.fromList([3])); // Ctrl+C is queued too
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));

    // Releasing the pty (its writer is blocked on the full terminal)
    // must not hang either.
    pty.kill();
    await pty.exitCode.timeout(const Duration(seconds: 15));
    await transcript.done.timeout(const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });

  testWidgets(
    'input beyond the write queue is dropped and reported once, pid only',
    (tester) async {
      final errors = <String>[];
      final reporting = FlutterPtyFactory(
        isWindows: Platform.isWindows,
        onError: errors.add,
      );
      final pty = reporting.spawn(
        shell,
        workingDirectory: _home,
        environment: _environment(),
        cols: 80,
        rows: 24,
      );
      addTearDown(pty.kill);
      final transcript = Transcript(pty.output);
      addTearDown(transcript.close);
      await startNotReading(pty, transcript);

      // 2 MiB in 64 KB writes: more than the 1 MiB queue.
      final chunk = lines(1024);
      final watch = Stopwatch()..start();
      for (var i = 0; i < 32; i++) {
        pty.write(chunk);
      }
      expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
      expect(errors, [
        matches(
          RegExp(r'^pid \d+: input dropped: the shell is not reading it$'),
        ),
      ]);

      pty.kill();
      await pty.exitCode.timeout(const Duration(seconds: 15));
      await transcript.done.timeout(const Duration(seconds: 5));
    },
    skip: Platform.isWindows,
  );

  testWidgets('resize(cols, rows) reaches the terminal', (tester) async {
    final (pty, transcript) = open(shell);
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
  });

  testWidgets('kill() ends the shell and the processes it started', (
    tester,
  ) async {
    final hostsBefore = Platform.isWindows ? _conhostChildren() : <int>{};
    final (pty, transcript) = open(shell);
    final children = <int>[];
    if (Platform.isWindows) {
      // One child on the session's console, and one in a console of its own
      // that closing the pseudo console would not end: only the job does.
      _type(
        pty,
        r"$p = Start-Process -PassThru -NoNewWindow ping.exe -ArgumentList '-n','300','127.0.0.1'; 'child=' + $p.Id",
      );
      children.add(await transcript.waitForNumber('child'));
      _type(
        pty,
        r"$q = Start-Process -PassThru -WindowStyle Hidden ping.exe -ArgumentList '-n','300','127.0.0.1'; 'detached=' + $q.Id",
      );
      children.add(await transcript.waitForNumber('detached'));
    } else {
      // Both ignore SIGHUP, so only the SIGKILL pass can end them.
      _type(
        pty,
        r"(trap '' HUP; sleep 300 & echo grandchild=$!; wait) & "
        r'echo child=$!',
      );
      children
        ..add(await transcript.waitForNumber('child'))
        ..add(await transcript.waitForNumber('grandchild'));
    }
    addTearDown(() async {
      for (final child in children) {
        if (await _running(child)) {
          Process.killPid(child, ProcessSignal.sigkill);
        }
      }
    });

    pty.kill();
    await pty.exitCode.timeout(const Duration(seconds: 15));
    await Future<void>.delayed(const Duration(seconds: 4));

    for (final child in children) {
      expect(
        await _running(child),
        isFalse,
        reason: 'process $child survived kill()',
      );
    }
    if (Platform.isWindows) {
      expect(
        _conhostChildren().difference(hostsBefore),
        isEmpty,
        reason: 'conhost.exe of the closed PTY is still running',
      );
    }
  });

  testWidgets(
    'a process left behind by a shell that exits on its own keeps running',
    (tester) async {
      final (pty, transcript) = open(shell);
      if (Platform.isWindows) {
        // Its own (hidden) console, so closing the pseudo console does not
        // end it; it is in the job, which must not kill it on release.
        _type(
          pty,
          r"$q = Start-Process -PassThru -WindowStyle Hidden ping.exe -ArgumentList '-n','60','127.0.0.1'; 'child=' + $q.Id",
        );
      } else {
        _type(pty, r"(trap '' HUP; sleep 60) &! echo child=$!");
      }
      final child = await transcript.waitForNumber('child');
      addTearDown(() async {
        if (await _running(child)) {
          Process.killPid(child, ProcessSignal.sigkill);
        }
      });

      _type(pty, 'exit');
      await pty.exitCode.timeout(const Duration(seconds: 15));
      await transcript.done.timeout(const Duration(seconds: 2));
      await Future<void>.delayed(const Duration(seconds: 3));

      expect(await _running(child), isTrue, reason: 'left-behind child died');
    },
  );

  testWidgets(
    'kill() also ends a child forked late by a process that ignores SIGHUP',
    (tester) async {
      // A sleep length no other process uses, to find the late child by.
      final marker = 30000 + Random().nextInt(20000);
      addTearDown(() => Process.run('/usr/bin/pkill', ['-f', 'sleep $marker']));
      final (pty, transcript) = open(shell);
      // The subshell survives SIGHUP, is re-parented to launchd when the
      // shell dies, and only forks the late child a second into the grace.
      _type(
        pty,
        "(trap '' HUP; sleep 1; sleep $marker & wait) & echo child=\$!",
      );
      final child = await transcript.waitForNumber('child');

      pty.kill();
      await pty.exitCode.timeout(const Duration(seconds: 15));
      await Future<void>.delayed(const Duration(seconds: 4));

      final ps = await Process.run('/bin/ps', ['-A', '-o', 'pid=,command=']);
      final lateChildren = const LineSplitter()
          .convert(ps.stdout as String)
          .where((line) => line.contains('sleep $marker'));
      expect(lateChildren, isEmpty, reason: 'late child survived kill()');
      expect(await _running(child), isFalse, reason: 'subshell survived');
    },
    skip: Platform.isWindows,
  );

  final vim = Platform.isWindows
      ? r'C:\Program Files\Git\usr\bin\vim.exe'
      : '/usr/bin/vim';
  testWidgets(
    'a full-screen program (vim) runs, takes keys and exits',
    (tester) async {
      final (pty, transcript) = open(shell);
      _type(
        pty,
        Platform.isWindows ? "& '$vim' -u NONE -N" : '$vim -u NONE -N',
      );
      // vim switches to the alternate screen. ConPTY before Windows 11 22H2
      // re-renders it instead of passing the switch through, so Windows also
      // accepts vim's start screen.
      await transcript.waitForRaw(
        (raw) =>
            raw.contains('\x1b[?1049h') ||
            (Platform.isWindows && raw.contains('IMproved')),
      );
      pty.resize(90, 30);
      pty.write(Uint8List.fromList(utf8.encode('\x1b:q!\r')));
      // Type the next command only once vim is gone, or vim may read it.
      if (Platform.isWindows) {
        await Future<void>.delayed(const Duration(seconds: 1));
      } else {
        await transcript.waitForRaw((raw) => raw.contains('\x1b[?1049l'));
      }
      _type(
        pty,
        Platform.isWindows ? "'after-' + 'vim'" : r'echo after-$((0))vim',
      );
      await transcript.waitForLine(
        (line) => line == (Platform.isWindows ? 'after-vim' : 'after-0vim'),
      );
      pty.kill();
      await pty.exitCode.timeout(const Duration(seconds: 15));
    },
    skip: !File(vim).existsSync(),
  );
}
