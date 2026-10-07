import 'dart:async';
import 'dart:io';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

final class FakeRunner {
  final calls = <List<String>>[];
  CommandResult Function(List<String> args) answer = (args) =>
      const CommandResult(0, '', '');

  Future<CommandResult> call(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    calls.add(arguments);
    return answer(arguments);
  }
}

final class FakePorts implements LocalPorts {
  final busy = <int>{};
  int next = 53012;
  @override
  Future<bool> isFree(int port) async => !busy.contains(port);
  @override
  Future<int> ephemeral() async => next++;
}

final class FakeForward implements ForwardProcess {
  final exit = Completer<int>();
  bool killed = false;
  @override
  Future<int> get exitCode => exit.future;
  @override
  void kill() {
    killed = true;
    if (!exit.isCompleted) exit.complete(-9);
  }
}

void main() {
  final devbox = SshTarget.parse('devbox')!;
  late FakeRunner runner;
  late FakePorts ports;
  final started = <List<String>>[];
  late FakeForward process;
  var now = DateTime(2026, 10, 7, 9);

  SshControl control({String? dir = '/tmp/shellx-ssh-501'}) => SshControl(
    sshPath: '/usr/bin/ssh',
    controlDirectory: dir,
    run: runner.call,
    ports: ports,
    now: () => now,
    sleep: (d) async => now = now.add(d),
    startForward: (exe, args) async {
      started.add(args);
      return process;
    },
  );

  setUp(() {
    runner = FakeRunner();
    ports = FakePorts();
    started.clear();
    process = FakeForward();
  });

  test('keepalive comes from ssh -G and is remembered 60 s (D13)', () async {
    final c = control();
    runner.answer = (_) =>
        const CommandResult(0, 'user me\nserveraliveinterval 0\n', '');
    expect(await c.keepaliveNeeded(devbox), isTrue);
    runner.answer = (_) =>
        const CommandResult(0, 'serveraliveinterval 30\n', '');
    expect(await c.keepaliveNeeded(devbox), isTrue); // cached
    now = now.add(const Duration(seconds: 61));
    expect(await c.keepaliveNeeded(devbox), isFalse);
    expect(runner.calls.first, ['-G', '--', 'devbox']);
    runner.answer = (_) => const CommandResult(255, '', '');
    now = now.add(const Duration(seconds: 61));
    expect(await c.keepaliveNeeded(devbox), isTrue);
  });

  test('master check and wait (D8, D9)', () async {
    final c = control();
    runner.answer = (_) => const CommandResult(255, '', '');
    expect(await c.masterAlive(devbox), isFalse);
    expect(runner.calls.single, [
      '-o',
      'ControlPath=/tmp/shellx-ssh-501/%C',
      '-O',
      'check',
      '--',
      'devbox',
    ]);
    runner.calls.clear();
    await c.awaitMaster(devbox, stillWaiting: () => true);
    expect(runner.calls, hasLength(30)); // 3 s at 100 ms
    runner.calls.clear();
    var checks = 0;
    runner.answer = (_) => CommandResult(++checks >= 3 ? 0 : 255, '', '');
    await c.awaitMaster(devbox, stillWaiting: () => true);
    expect(runner.calls, hasLength(3));
    runner.calls.clear();
    await c.awaitMaster(devbox, stillWaiting: () => false);
    expect(runner.calls, isEmpty);
    final windows = control(dir: null);
    expect(await windows.masterAlive(devbox), isFalse);
    await windows.awaitMaster(devbox, stillWaiting: () => true);
    expect(runner.calls, isEmpty);
  });

  test(
    'runRemote: BatchMode, never a master, the script wrapped (D18, D38g)',
    () async {
      final c = control();
      await c.runRemote(devbox, 'echo hi', timeout: const Duration(seconds: 4));
      final args = runner.calls.single;
      expect(args.sublist(0, 7), [
        '-T',
        '-o',
        'BatchMode=yes',
        '-o',
        'ConnectTimeout=4',
        '-o',
        'ControlMaster=no',
      ]);
      expect(
        args,
        containsAllInOrder([
          '-o',
          'ControlPath=/tmp/shellx-ssh-501/%C',
          '--',
          'devbox',
        ]),
      );
      expect(args.last, remoteExecCommand('echo hi'));
      expect(args, isNot(contains('ControlPersist=60')));
      expect(args, containsAllInOrder(['-o', 'ClearAllForwardings=yes']));
    },
  );

  test('forward over the master: same port when free, another when not, '
      'reused (D19)', () async {
    final c = control();
    expect(await c.forward(devbox, 8000), 8000);
    expect(
      runner.calls.last,
      containsAllInOrder([
        '-O',
        'forward',
        '-L',
        '127.0.0.1:8000:localhost:8000',
        '--',
        'devbox',
      ]),
    );
    final before = runner.calls.length;
    expect(await c.forward(devbox, 8000), 8000);
    expect(runner.calls.length, before + 1); // the master is checked (M3)
    ports.busy.add(3000);
    expect(await c.forward(devbox, 3000), 53012);
    expect(c.forwardedPort(devbox, 3000), 53012);
    runner.answer = (args) =>
        CommandResult(args.contains('forward') ? 1 : 0, '', '');
    await expectLater(
      c.forward(devbox, 9000),
      throwsA(isA<ForwardFailedException>()),
    );
  });

  test(
    'forward without a master: a BatchMode -N process; its exit fails it',
    () async {
      final c = control(dir: null);
      var polls = 0;
      ports.busy.clear();
      final free = FakePorts();
      final probe = SshControl(
        sshPath: 'ssh.exe',
        run: runner.call,
        ports: _Bound(free, after: () => ++polls > 2),
        sleep: (_) async {},
        startForward: (exe, args) async {
          started.add(args);
          return process;
        },
      );
      expect(await probe.forward(devbox, 8000), 8000);
      expect(started.single, [
        '-N',
        '-T',
        '-o',
        'BatchMode=yes',
        '-o',
        'ExitOnForwardFailure=yes',
        '-o',
        'ControlMaster=no',
        '-o',
        'ControlPath=none',
        '-L',
        '127.0.0.1:8000:localhost:8000',
        '--',
        'devbox',
      ]);
      final dead = FakeForward()..exit.complete(255);
      final failing = SshControl(
        sshPath: 'ssh.exe',
        run: runner.call,
        ports: FakePorts(),
        sleep: (_) async {},
        startForward: (exe, args) async => dead,
      );
      await expectLater(
        failing.forward(devbox, 8000),
        throwsA(isA<ForwardFailedException>()),
      );
      expect(c.controlPath, isNull);
    },
  );

  test(
    'cancel and exit: -O cancel / -O exit, processes killed (D40)',
    () async {
      final c = control();
      await c.forward(devbox, 8000);
      await c.cancelForwards(devbox);
      expect(
        runner.calls.last,
        containsAllInOrder([
          '-O',
          'cancel',
          '-L',
          '127.0.0.1:8000:localhost:8000',
        ]),
      );
      expect(c.forwardedPort(devbox, 8000), isNull);
      c.noteMaster(devbox);
      c.noteMaster(SshTarget.parse('me@other')!);
      await c.exitMasters(c.mastersUsed);
      final exits = runner.calls.where((a) => a.contains('exit')).toList();
      expect(exits, hasLength(2));
    },
  );

  test('exitAllMasters exits every socket in the directory, also ones this '
      'instance never noted (A5b D40)', () async {
    final c = SshControl(
      sshPath: '/usr/bin/ssh',
      controlDirectory: '/tmp/shellx-ssh-501',
      run: runner.call,
      ports: ports,
      listSockets: (dir) async => ['$dir/aaaa', '$dir/bbbb'],
    );
    await c.exitAllMasters();
    final exits = runner.calls.where((a) => a.contains('exit')).toList();
    expect(exits, hasLength(2));
    expect(exits.map((a) => a[a.indexOf('-o') + 1]), [
      'ControlPath=/tmp/shellx-ssh-501/aaaa',
      'ControlPath=/tmp/shellx-ssh-501/bbbb',
    ]);
    // No multiplexing: nothing to exit.
    runner.calls.clear();
    await control(dir: null).exitAllMasters();
    expect(runner.calls, isEmpty);
  });

  test('exitAllMasters survives an unreadable directory', () async {
    final c = SshControl(
      sshPath: '/usr/bin/ssh',
      controlDirectory: '/tmp/gone',
      run: runner.call,
      listSockets: (_) => throw const FileSystemException('gone'),
    );
    await c.exitAllMasters();
    expect(runner.calls, isEmpty);
  });

  test(
    'every helper runs BatchMode or only talks to the socket (D38g)',
    () async {
      final c = control();
      await c.keepaliveNeeded(devbox);
      await c.masterAlive(devbox);
      await c.runRemote(devbox, 'x');
      await c.forward(devbox, 8000);
      await c.cancelForwards(devbox);
      for (final args in runner.calls) {
        final safe =
            args.contains('BatchMode=yes') ||
            args.contains('-O') ||
            args.first == '-G';
        expect(safe, isTrue, reason: '$args');
      }
    },
  );

  test('awaitMaster is bounded by a 3 s deadline, not a count (M2)', () async {
    final c = control();
    runner.answer = (_) => const CommandResult(255, '', '');
    final start = now;
    await c.awaitMaster(devbox, stillWaiting: () => true);
    expect(now.difference(start), const Duration(seconds: 3));
  });

  test('a master forward is reused only while the master lives (M3)', () async {
    final c = control();
    expect(await c.forward(devbox, 8000), 8000);
    runner.calls.clear();
    runner.answer = (_) => const CommandResult(255, '', '');
    ports.busy.addAll([8000, 53012]); // 8000 taken; the new forward listens
    expect(await c.forward(devbox, 8000), 53012);
    // The master is gone: checked, then a standalone process took over.
    expect(runner.calls.first, contains('check'));
    expect(started, hasLength(1));
  });

  test('dead forwards do not count toward the 32 per server (cap)', () async {
    final listening = <int>{};
    final ports = FakePorts();
    final procs = <FakeForward>[];
    final c = SshControl(
      sshPath: 'ssh.exe', // no master: one process per forward
      run: runner.call,
      ports: _Listening(listening, ports),
      sleep: (_) async {},
      startForward: (exe, args) async {
        listening.add(int.parse(args[args.indexOf('-L') + 1].split(':')[1]));
        final f = FakeForward();
        procs.add(f);
        return f;
      },
    );
    for (var i = 0; i < 32; i++) {
      await c.forward(devbox, 9000 + i);
    }
    await expectLater(
      c.forward(devbox, 9100),
      throwsA(isA<ForwardFailedException>()),
    );
    procs.first.kill(); // one ended: its slot is free again
    await pumpEventQueue();
    expect(await c.forward(devbox, 9100), 9100);
  });

  test('ports outside 1..65535 fail (M6)', () async {
    final c = control();
    for (final port in [0, -1, 65536]) {
      await expectLater(
        c.forward(devbox, port),
        throwsA(isA<ForwardFailedException>()),
      );
    }
    expect(runner.calls, isEmpty);
  });

  group('prepareControlDirectory (D8)', () {
    // A base that does not exist: nothing is created on disk.
    const base = '/nx';

    test(
      'owned 0700 directory → used; anything else → off, logged without the path',
      () async {
        final r = FakeRunner()
          ..answer = (args) => switch (args) {
            ['-u'] => const CommandResult(0, '501\n', ''),
            ['700', _] => const CommandResult(0, '', ''),
            ['-f', _, _] => const CommandResult(0, '501 700 Directory\n', ''),
            _ => const CommandResult(1, '', ''),
          };
        expect(
          await prepareControlDirectory(base: base, run: r.call),
          '$base/shellx-ssh-501',
        );
        final logs = <String>[];
        r.answer = (args) => switch (args) {
          ['-u'] => const CommandResult(0, '501\n', ''),
          ['-f', _, _] => const CommandResult(0, '0 755 Directory\n', ''),
          _ => const CommandResult(0, '', ''),
        };
        expect(
          await prepareControlDirectory(base: base, run: r.call, log: logs.add),
          isNull,
        );
        expect(logs, ['ssh: control dir unsafe']);
      },
    );

    test(
      'a too-long socket path and a failing id are refused, logged without paths (M7)',
      () async {
        final r = FakeRunner()
          ..answer = (args) => switch (args) {
            ['-u'] => const CommandResult(0, '501\n', ''),
            _ => const CommandResult(0, '501 700 Directory\n', ''),
          };
        final logs = <String>[];
        expect(
          await prepareControlDirectory(
            base: '/${'x' * 60}',
            run: r.call,
            log: logs.add,
          ),
          isNull,
        );
        expect(logs, ['ssh: control dir path too long']);
        expect(
          await prepareControlDirectory(
            base: base,
            run: r.call,
            maxSocketPath: 60,
            log: logs.add,
          ),
          isNull,
        );
        logs.clear();
        r.answer = (_) => const CommandResult(1, '', '');
        expect(
          await prepareControlDirectory(base: base, run: r.call, log: logs.add),
          isNull,
        );
        expect(logs, ['ssh: control dir user unknown']);
      },
    );

    test(
      'a 755 directory of ours is fixed by chmod; a link is refused before chmod',
      () async {
        final r = FakeRunner();
        var chmods = 0;
        var stats = 0;
        r.answer = (args) {
          if (args.first == '-u') return const CommandResult(0, '501\n', '');
          if (args.first == '700') {
            chmods++;
            return const CommandResult(0, '', '');
          }
          return CommandResult(
            0,
            ++stats == 1 ? '501 755 Directory\n' : '501 700 Directory\n',
            '',
          );
        };
        expect(
          await prepareControlDirectory(base: base, run: r.call),
          '$base/shellx-ssh-501',
        );
        expect(chmods, 1);
        chmods = 0;
        r.answer = (args) {
          if (args.first == '-u') return const CommandResult(0, '501\n', '');
          if (args.first == '700') {
            chmods++;
            return const CommandResult(0, '', '');
          }
          return const CommandResult(0, '501 755 Symbolic Link\n', '');
        };
        expect(await prepareControlDirectory(base: base, run: r.call), isNull);
        expect(chmods, 0);
      },
    );

    test(
      'real directory 0755 → 0700; a real link is refused untouched',
      () async {
        final tmp = await Directory.systemTemp.createTemp('shellx');
        addTearDown(() => tmp.deleteSync(recursive: true));
        final uid = (await Process.run('/usr/bin/id', [
          '-u',
        ])).stdout.toString().trim();
        final dir = '${tmp.path}/shellx-ssh-$uid';
        await Directory(dir).create();
        await Process.run('/bin/chmod', ['755', dir]);
        expect(
          await prepareControlDirectory(base: tmp.path, maxSocketPath: 4096),
          dir,
        );
        final mode = (await Process.run('/usr/bin/stat', [
          '-f',
          '%Lp',
          dir,
        ])).stdout.toString().trim();
        expect(mode, '700');

        final other = await Directory.systemTemp.createTemp('shellx');
        addTearDown(() => other.deleteSync(recursive: true));
        await Process.run('/bin/chmod', ['755', other.path]);
        final tmp2 = await Directory.systemTemp.createTemp('shellx');
        addTearDown(() => tmp2.deleteSync(recursive: true));
        await Link('${tmp2.path}/shellx-ssh-$uid').create(other.path);
        expect(
          await prepareControlDirectory(base: tmp2.path, maxSocketPath: 4096),
          isNull,
        );
        final after = (await Process.run('/usr/bin/stat', [
          '-f',
          '%Lp',
          other.path,
        ])).stdout.toString().trim();
        expect(after, '755');
      },
      testOn: 'mac-os',
    );
  });
}

/// Free until [after] says the forward bound it.
final class _Bound implements LocalPorts {
  _Bound(this.inner, {required this.after});
  final LocalPorts inner;
  final bool Function() after;
  var _chosen = false;
  @override
  Future<bool> isFree(int port) async {
    if (!_chosen) {
      _chosen = true;
      return true;
    }
    return !after();
  }

  @override
  Future<int> ephemeral() => inner.ephemeral();
}

final class _Listening implements LocalPorts {
  _Listening(this.listening, this.inner);
  final Set<int> listening;
  final LocalPorts inner;
  @override
  Future<bool> isFree(int port) async => !listening.contains(port);
  @override
  Future<int> ephemeral() => inner.ephemeral();
}
