import 'dart:async';
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
  var kills = 0;
  var killSucceeds = true;

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
  @override
  bool kill() {
    kills++;
    return killSucceeds;
  }
}

final class _RecordingKiller implements ProcessTreeKiller {
  final killed = <int>[];
  @override
  Future<void> killTree(int rootPid) async => killed.add(rootPid);
}

final class _FailingKiller implements ProcessTreeKiller {
  _FailingKiller(this.error);
  final Object error;
  @override
  Future<void> killTree(int rootPid) async {
    await Future<void>.delayed(Duration.zero);
    throw error;
  }
}

const _zsh = ShellCommand(
  executable: '/bin/zsh',
  arguments: ['-l'],
  name: 'zsh',
);
const _pwsh = ShellCommand(
  executable: r'C:\Program Files\PowerShell\7\pwsh.exe',
  arguments: ['-NoLogo', '-Command', 'echo a b'],
  name: 'pwsh',
);

const _launch = PtyLaunch(
  executable: 'x',
  arguments: [],
  workingDirectory: '/',
  environment: {},
  columns: 80,
  rows: 24,
);

void main() {
  group('windowsQuoteArg', () {
    test('leaves simple arguments alone', () {
      expect(windowsQuoteArg('pwsh.exe'), 'pwsh.exe');
      expect(windowsQuoteArg('-NoLogo'), '-NoLogo');
      expect(windowsQuoteArg(r'C:\Users\Nguyễn'), r'C:\Users\Nguyễn');
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
      expect(native.launch.environment, {'SHELLX': '1'});
      expect(native.launch.columns, 120);
      expect(native.launch.rows, 40);
    });

    test('Windows quotes the executable and arguments, and passes paths and '
        'environment through unchanged', () {
      late _FakeNativePty native;
      final factory = FlutterPtyFactory(
        isWindows: true,
        start: (launch) => native = _FakeNativePty(launch),
      );
      factory.spawn(
        _pwsh,
        workingDirectory: r'C:\Users\Nguyễn Văn',
        environment: {'USERPROFILE': r'C:\Users\Nguyễn Văn'},
        cols: 80,
        rows: 24,
      );
      expect(
        native.launch.executable,
        r'"C:\Program Files\PowerShell\7\pwsh.exe"',
      );
      expect(native.launch.arguments, ['-NoLogo', '-Command', '"echo a b"']);
      expect(native.launch.workingDirectory, r'C:\Users\Nguyễn Văn');
      expect(native.launch.environment, {
        'USERPROFILE': r'C:\Users\Nguyễn Văn',
      });
    });

    test('spawn rethrows when the shell cannot start', () {
      final factory = FlutterPtyFactory(
        isWindows: false,
        killer: _RecordingKiller(),
        start: (launch) => throw StateError('Failed to create PTY'),
      );
      expect(
        () => factory.spawn(
          _zsh,
          workingDirectory: '/',
          environment: {},
          cols: 80,
          rows: 24,
        ),
        throwsStateError,
      );
    });

    test('resize swaps to flutter_pty (rows, cols) order; macOS kill runs the '
        'tree killer once', () async {
      late _FakeNativePty native;
      final killer = _RecordingKiller();
      final pty = FlutterPtyFactory(
        isWindows: false,
        killer: killer,
        start: (launch) => native = _FakeNativePty(launch),
      ).spawn(_zsh, workingDirectory: '/', environment: {}, cols: 80, rows: 24);

      pty.resize(132, 50);
      pty.kill();
      pty.kill();
      await Future<void>.delayed(Duration.zero);

      expect(native.resizes, [(50, 132)]);
      expect(killer.killed, [4321]);
      expect(native.kills, 0);
    });

    test('Windows kill terminates the job through the plugin, once', () async {
      late _FakeNativePty native;
      final pty =
          FlutterPtyFactory(
            isWindows: true,
            start: (launch) => native = _FakeNativePty(launch),
          ).spawn(
            _pwsh,
            workingDirectory: r'C:\',
            environment: {},
            cols: 80,
            rows: 24,
          );

      pty.kill();
      pty.kill();
      await Future<void>.delayed(Duration.zero);

      expect(native.kills, 1);
    });
  });

  group('FlutterPtyAdapter output', () {
    test('forwards data and closes when the native stream closes', () async {
      final native = _FakeNativePty(_launch);
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
        final native = _FakeNativePty(_launch);
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

  group('FlutterPtyAdapter kill', () {
    test(
      'macOS: kill after the shell exited leaves the stale pid alone',
      () async {
        final native = _FakeNativePty(_launch);
        final killer = _RecordingKiller();
        final pty = FlutterPtyAdapter(native, killer: killer);
        native.exit.complete(0);
        await Future<void>.delayed(Duration.zero);

        pty.kill();
        await Future<void>.delayed(Duration.zero);

        expect(killer.killed, isEmpty);
        expect(native.kills, 0);
      },
    );

    test(
      'Windows: kill after the shell exited still terminates the job',
      () async {
        final native = _FakeNativePty(_launch);
        final pty = FlutterPtyAdapter(native);
        native.exit.complete(0);
        await Future<void>.delayed(Duration.zero);

        pty.kill();

        expect(native.kills, 1);
      },
    );

    test('a failing tree kill is reported with the pid, not thrown', () async {
      final errors = <String>[];
      final pty = FlutterPtyAdapter(
        _FakeNativePty(_launch),
        killer: _FailingKiller(
          const ProcessTableException('ps exited with code 1'),
        ),
        onError: errors.add,
      );

      pty.kill();
      await pumpEventQueue();

      expect(errors, ['kill of pid 4321 failed: ps exited with code 1']);
    });

    test('other kill errors are reported by type only', () async {
      final errors = <String>[];
      final pty = FlutterPtyAdapter(
        _FakeNativePty(_launch),
        killer: _FailingKiller(StateError('/bin/zsh -l SECRET=1')),
        onError: errors.add,
      );

      pty.kill();
      await pumpEventQueue();

      expect(errors, ['kill of pid 4321 failed: StateError']);
    });

    test('Windows: a failed job kill is reported', () {
      final errors = <String>[];
      final native = _FakeNativePty(_launch)..killSucceeds = false;
      final pty = FlutterPtyAdapter(native, onError: errors.add);

      pty.kill();

      expect(errors, [
        'kill of pid 4321 failed: could not terminate the job object',
      ]);
    });

    test('the factory hands onError to its ptys', () async {
      final errors = <String>[];
      final pty = FlutterPtyFactory(
        isWindows: false,
        killer: _FailingKiller(
          const ProcessTableException('cannot run ps (OS error 2)'),
        ),
        start: _FakeNativePty.new,
        onError: errors.add,
      ).spawn(_zsh, workingDirectory: '/', environment: {}, cols: 80, rows: 24);

      pty.kill();
      await pumpEventQueue();

      expect(errors, ['kill of pid 4321 failed: cannot run ps (OS error 2)']);
    });
  });
}
