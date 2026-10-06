import 'dart:io';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_desktop/src/agent/session_core.dart';

import '../support/fake_pty.dart';

void main() {
  late FakePtyFactory ptys;

  SessionCore core({PtyFactory? factory, PortProbe? portProbe}) => SessionCore(
    ptyFactory: factory ?? ptys,
    shellResolver: const FixedShellResolver(),
    homeDirectory: '/Users/phu',
    baseEnvironment: const {'HOME': '/Users/phu'},
    api: ShellxApi(baseUri: Uri.parse('https://relay.test')),
    portProbe: portProbe,
  );

  setUp(() => ptys = FakePtyFactory());

  test(
    "an OSC 7 naming this computer's hostname is a local cwd; another "
    'host is remote (A2 C1, the hooks write file://\$HOST/…)',
    () async {
      final c = core();
      await c.sessions.open(cols: 80, rows: 24);
      final pty = ptys.ptys.single;
      pty.emit('\x1b]7;file://${Platform.localHostname}/tmp/a%20b\x07');
      await pumpEventQueue();
      expect(c.sessions.sessions.single.cwd, '/tmp/a b');
      pty.emit('\x1b]7;file://elsewhere.invalid/tmp/x\x07');
      await pumpEventQueue();
      expect(c.sessions.sessions.single.cwd, isNull);
    },
    // Windows reads a foreign host as a UNC path and needs a drive URL.
    skip: Platform.isWindows,
  );

  test('closing every session (what Quit does) stops the port lookups even '
      'while the window is shown (A2 D8)', () {
    fakeAsync((async) {
      final probe = _CountingProbe();
      final c = core(factory: _PidPtyFactory(ptys), portProbe: probe);
      c.sessions.watchPorts(true);
      c.sessions.open(cols: 80, rows: 24);
      async.elapse(const Duration(seconds: 10));
      expect(probe.calls, greaterThan(0));
      c.sessions.closeAll();
      async.flushMicrotasks();
      probe.calls = 0;
      async.elapse(const Duration(minutes: 1));
      expect(probe.calls, 0);
    });
  });
}

/// Counts every lookup; nothing listens.
final class _CountingProbe implements PortProbe {
  int calls = 0;

  @override
  Future<Map<int, Set<int>>> listening() async {
    calls++;
    return const {};
  }

  @override
  Future<Map<int, int>> parents() async {
    calls++;
    return const {};
  }
}

/// [FakePty]s that report a pid, so the port watcher has a shell to scan.
final class _PidPtyFactory implements PtyFactory {
  _PidPtyFactory(this._inner);
  final FakePtyFactory _inner;

  @override
  Pty spawn(
    ShellCommand command, {
    required String workingDirectory,
    required Map<String, String> environment,
    required int cols,
    required int rows,
  }) => _PidPty(
    _inner.spawn(
          command,
          workingDirectory: workingDirectory,
          environment: environment,
          cols: cols,
          rows: rows,
        )
        as FakePty,
    4000 + _inner.ptys.length,
  );
}

final class _PidPty implements Pty, PtyProcessId {
  _PidPty(this._pty, this.processId);
  final FakePty _pty;

  @override
  final int processId;

  @override
  Stream<Uint8List> get output => _pty.output;
  @override
  Future<int> get exitCode => _pty.exitCode;
  @override
  void write(Uint8List data) => _pty.write(data);
  @override
  void resize(int cols, int rows) => _pty.resize(cols, rows);
  @override
  void kill() => _pty.kill();
}
