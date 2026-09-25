import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/platform/pty/flutter_pty_factory.dart';
import 'package:shellx_desktop/src/platform/pty/process_table.dart';
import 'package:shellx_desktop/src/platform/pty/process_tree_killer.dart';
import 'package:shellx_desktop/src/platform/pty/windows_text.dart';

final class _FakeNativePty implements NativePty {
  _FakeNativePty(this.launch);
  final PtyLaunch launch;
  final exit = Completer<int>();
  final StreamController<Uint8List> out = StreamController<Uint8List>();
  final resizes = <(int, int)>[];
  final writes = <Uint8List>[];

  @override
  int get pid => 4321;
  @override
  Stream<Uint8List> get output => out.stream;
  @override
  Future<int> get exitCode => exit.future;
  @override
  void write(Uint8List data) => writes.add(data);
  @override
  void resize(int rows, int columns) => resizes.add((rows, columns));
}

final class _RecordingKiller implements ProcessTreeKiller {
  final killed = <int>[];
  @override
  Future<void> killTree(int rootPid) async => killed.add(rootPid);
}

const _zsh = ShellCommand(
  executable: '/bin/zsh',
  arguments: ['-l'],
  name: 'zsh',
);
const _pwsh = ShellCommand(
  executable: r'C:\Program Files\PowerShell\7\pwsh.exe',
  arguments: ['-NoLogo'],
  name: 'pwsh',
);

void main() {
  group('windowsQuoteArg', () {
    test('leaves simple arguments alone', () {
      expect(windowsQuoteArg('pwsh.exe'), 'pwsh.exe');
      expect(windowsQuoteArg('-NoLogo'), '-NoLogo');
    });
    test('quotes spaces, escapes quotes and trailing backslashes', () {
      expect(
        windowsQuoteArg(r'C:\Program Files\x.exe'),
        r'"C:\Program Files\x.exe"',
      );
      expect(windowsQuoteArg('a"b'), r'"a\"b"');
      expect(windowsQuoteArg(r'C:\dir with space\'), r'"C:\dir with space\\"');
      expect(windowsQuoteArg(''), '""');
    });
  });

  group('asciiSafe*', () {
    String shorten(String p) => p.replaceAll('Nguyễn', 'NGUYEN~1');

    test('only non-ASCII list elements are shortened', () {
      expect(
        asciiSafePathList(r'C:\Windows;C:\Users\Nguyễn\bin', shorten),
        r'C:\Windows;C:\Users\NGUYEN~1\bin',
      );
      expect(asciiSafePathList(r'C:\Windows', (_) => 'never'), r'C:\Windows');
    });

    test('environment values are rewritten, keys kept', () {
      final env = asciiSafeEnvironment({
        'USERPROFILE': r'C:\Users\Nguyễn',
        'TERM': 'xterm-256color',
      }, shorten);
      expect(env, {
        'USERPROFILE': r'C:\Users\NGUYEN~1',
        'TERM': 'xterm-256color',
      });
    });
  });

  group('FlutterPtyFactory', () {
    test('macOS passes the command through unchanged', () {
      late _FakeNativePty native;
      final factory = FlutterPtyFactory(
        isWindows: false,
        killer: _RecordingKiller(),
        start: (launch) => native = _FakeNativePty(launch),
      );
      factory.spawn(
        _zsh,
        workingDirectory: '/Users/phú',
        environment: {'SHELLX': '1'},
        cols: 120,
        rows: 40,
      );
      expect(native.launch.executable, '/bin/zsh');
      expect(native.launch.arguments, ['-l']);
      expect(native.launch.workingDirectory, '/Users/phú');
      expect(native.launch.columns, 120);
      expect(native.launch.rows, 40);
    });

    test('Windows quotes the executable and shortens non-ASCII paths', () {
      late _FakeNativePty native;
      final factory = FlutterPtyFactory(
        isWindows: true,
        killer: _RecordingKiller(),
        start: (launch) => native = _FakeNativePty(launch),
        shortPath: (p) => p.replaceAll('Nguyễn', 'NGUYEN~1'),
      );
      factory.spawn(
        _pwsh,
        workingDirectory: r'C:\Users\Nguyễn',
        environment: {'HOME': r'C:\Users\Nguyễn'},
        cols: 80,
        rows: 24,
      );
      expect(
        native.launch.executable,
        r'"C:\Program Files\PowerShell\7\pwsh.exe"',
      );
      expect(native.launch.workingDirectory, r'C:\Users\NGUYEN~1');
      expect(native.launch.environment['HOME'], r'C:\Users\NGUYEN~1');
    });

    test(
      'resize swaps to flutter_pty (rows, cols) order; kill runs once',
      () async {
        late _FakeNativePty native;
        final killer = _RecordingKiller();
        final pty =
            FlutterPtyFactory(
              isWindows: false,
              killer: killer,
              start: (launch) => native = _FakeNativePty(launch),
            ).spawn(
              _zsh,
              workingDirectory: '/',
              environment: {},
              cols: 80,
              rows: 24,
            );

        pty.resize(132, 50);
        pty.kill();
        pty.kill();
        await Future<void>.delayed(Duration.zero);

        expect(native.resizes, [(50, 132)]);
        expect(killer.killed, [4321]);
      },
    );

    test(
      'Windows terminates the conhost that appeared during spawn once the shell exits',
      () async {
        var table = [
          const ProcessEntry(pid: 10, parentPid: 1, name: 'conhost.exe'),
        ];
        final taskkills = <List<String>>[];
        late _FakeNativePty native;
        final factory = FlutterPtyFactory(
          isWindows: true,
          killer: _RecordingKiller(),
          outputGrace: Duration.zero,
          start: (launch) {
            table = [
              ...table,
              const ProcessEntry(pid: 11, parentPid: 1, name: 'conhost.exe'),
              const ProcessEntry(pid: 12, parentPid: 1, name: 'pwsh.exe'),
            ];
            return native = _FakeNativePty(launch);
          },
          consoleHosts: ConsoleHostTracker(
            snapshot: () => table,
            ownPid: 1,
            run: (exe, args) async {
              taskkills.add([exe, ...args]);
              return ProcessResult(0, 0, '', '');
            },
          ),
        );
        factory.spawn(
          _pwsh,
          workingDirectory: r'C:\',
          environment: {},
          cols: 80,
          rows: 24,
        );
        expect(taskkills, isEmpty);

        native.exit.complete(0);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(taskkills, [
          ['taskkill', '/PID', '11', '/F'],
        ]);
      },
    );
  });

  group('FlutterPtyAdapter output', () {
    const launch = PtyLaunch(
      executable: 'x',
      arguments: [],
      workingDirectory: '/',
      environment: {},
      columns: 80,
      rows: 24,
    );

    test('forwards data and closes when the native stream closes', () async {
      final native = _FakeNativePty(launch);
      final pty = FlutterPtyAdapter(native, killer: _RecordingKiller());
      final received = pty.output.toList();
      native.out.add(Uint8List.fromList([104, 105]));
      await native.out.close();
      expect(await received, [
        [104, 105],
      ]);
    });

    test(
      'closes within the grace period after exit even if native stays open',
      () async {
        final native = _FakeNativePty(launch);
        final pty = FlutterPtyAdapter(
          native,
          killer: _RecordingKiller(),
          outputGrace: const Duration(milliseconds: 10),
        );
        final done = Completer<void>();
        pty.output.listen((_) {}, onDone: done.complete);
        native.exit.complete(0);
        await done.future.timeout(const Duration(seconds: 2));
      },
    );
  });
}
