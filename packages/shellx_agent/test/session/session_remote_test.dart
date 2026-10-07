import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

import '../support/session_rig.dart';

final devbox = SshTarget.parse('devbox')!;

String osc(String body) => '\x1b]$body\x07';

/// ssh -G says "no keepalive"; -O check says "no master" unless [master].
RemoteTools tools({
  List<List<String>>? calls,
  bool Function()? master,
  String? tmux = '/usr/local/bin/tmux',
  String keepalive = '0',
}) {
  Future<CommandResult> run(
    String exe,
    List<String> args, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    calls?.add(args);
    if (args.first == '-G') {
      return CommandResult(0, 'serveraliveinterval $keepalive\n', '');
    }
    if (args.contains('check')) {
      return CommandResult((master?.call() ?? false) ? 0 : 255, '', '');
    }
    return const CommandResult(255, '', '');
  }

  // The master wait is bounded by the clock: sleeping advances a fake one.
  var clock = DateTime(2026, 10, 7);
  return RemoteTools(
    sshPath: '/usr/bin/ssh',
    tmuxPath: tmux,
    control: SshControl(
      sshPath: '/usr/bin/ssh',
      controlDirectory: '/tmp/shellx-ssh-501',
      run: run,
      now: () => clock,
      sleep: (d) async => clock = clock.add(d),
    ),
  );
}

final class _Heads implements GitBranchLookup {
  final asked = <String>[];
  @override
  Future<String?> branchFor(String directory, {bool refresh = false}) async {
    asked.add(directory);
    return 'local';
  }
}

void main() {
  test(
    'an SSH launch spawns ssh, not the shell, without the local hook (D2, D12)',
    () async {
      final rig = SessionRig(remoteTools: tools());
      final id = await rig.manager.open(
        cols: 80,
        rows: 24,
        launch: SshLaunch(devbox, remoteCwd: '/srv'),
      );
      final pty = rig.pty(0);
      expect(pty.command.executable, '/usr/bin/ssh');
      expect(pty.command.arguments.first, '-t');
      expect(
        pty.command.arguments,
        containsAllInOrder(['ServerAliveInterval=15', '--', 'devbox']),
      );
      expect(pty.command.arguments.last, startsWith("/bin/sh -c 'eval"));
      expect(pty.workingDirectory, '/Users/test');
      expect(pty.environment['TERM'], 'xterm-256color');
      expect(pty.environment.containsKey('ZDOTDIR'), isFalse);
      final s = rig.manager.sessions.single;
      expect(s.id, id);
      expect(s.shell, 'ssh');
      expect(
        s.remote,
        SessionRemote(launch: SshLaunch(devbox, remoteCwd: '/srv')),
      );
    },
  );

  test('ids for the CLI are set, the control-socket secrets are not '
      '(A7 D29, A8 ruling)', () async {
    final rig = SessionRig(
      remoteTools: tools(),
      baseEnvironment: const {
        'PATH': '/usr/bin',
        'SHELLX_CLI_TOKEN': 'secret',
        'SHELLX_SOCKET': '/tmp/s',
      },
    );
    final id = await rig.manager.open(
      cols: 80,
      rows: 24,
      tabId: 77,
      launch: SshLaunch(devbox),
    );
    final env = rig.pty(0).environment;
    expect(env['SHELLX_PANE_ID'], '$id');
    expect(env['SHELLX_TAB_ID'], '77');
    expect(env.containsKey('SHELLX_CLI_TOKEN'), isFalse);
    expect(env.containsKey('SHELLX_SOCKET'), isFalse);
    await rig.manager.open(
      cols: 80,
      rows: 24,
      launch: const TmuxLaunch('main'),
    );
    expect(rig.pty(1).environment.containsKey('SHELLX_CLI_TOKEN'), isFalse);
    expect(rig.pty(1).environment.containsKey('SHELLX_SOCKET'), isFalse);
  });

  test('hello, pid, home, cwd, branch from the server; no local git lookup '
      '(D14, D15, D16)', () async {
    final heads = _Heads();
    final rig = SessionRig(remoteTools: tools(), gitHeads: heads);
    await rig.manager.open(cols: 80, rows: 24, launch: SshLaunch(devbox));
    rig
        .pty(0)
        .emit(
          '${osc('6973;hello=1')}${osc('6973;pid=4242')}${osc('6973;home=/home/me')}'
          '${osc('7;file://devbox/home/me/work%20x')}${osc('6973;branch=feat/x')}',
        );
    await pumpEventQueue();
    final s = rig.manager.sessions.single;
    expect(s.remote!.connected, isTrue);
    expect(s.remote!.home, '/home/me');
    expect(s.cwd, '/home/me/work x');
    expect(s.gitBranch, 'feat/x');
    expect(heads.asked, isEmpty);
    rig.pty(0).emit(osc('6973;branch='));
    rig.pty(0).emit('\x1b]133;D;0\x07');
    await pumpEventQueue();
    expect(rig.manager.sessions.single.gitBranch, isNull);
    expect(heads.asked, isEmpty);
  });

  test('bad values from the server are dropped (D16)', () async {
    final rig = SessionRig(remoteTools: tools());
    await rig.manager.open(cols: 80, rows: 24, launch: SshLaunch(devbox));
    rig
        .pty(0)
        .emit(
          '${osc('6973;hello=1')}${osc('6973;home=relative')}'
          '${osc('6973;home=/${'h' * 5000}')}${osc('6973;pid=12x')}'
          '${osc('6973;branch=${'b' * 201}')}${osc('6973;nonsense=1')}',
        );
    await pumpEventQueue();
    var s = rig.manager.sessions.single;
    expect(s.remote!.home, isNull);
    expect(s.gitBranch, isNull);
    rig
        .pty(0)
        .emit('${osc('6973;home=/ok')}${osc('6973;branch=${'b' * 200}')}');
    await pumpEventQueue();
    s = rig.manager.sessions.single;
    expect(s.remote!.home, '/ok');
    expect(s.gitBranch, 'b' * 200);
  });

  test('a local shell ignores OSC 6973 and still forgets a remote OSC 7 '
      '(A2 D2)', () async {
    final rig = SessionRig(remoteTools: tools());
    await rig.manager.open(cols: 80, rows: 24);
    rig
        .pty(0)
        .emit(
          '${osc('7;file:///Users/test/w')}${osc('6973;branch=evil')}'
          '${osc('6973;hello=1')}',
        );
    await pumpEventQueue();
    expect(rig.manager.sessions.single.gitBranch, isNull);
    expect(rig.manager.sessions.single.remote, isNull);
    rig.pty(0).emit(osc('7;file://elsewhere/x'));
    await pumpEventQueue();
    expect(rig.manager.sessions.single.cwd, isNull);
  });

  test('without the hook the session counts as connected after 10 s (D11)', () {
    fakeAsync((async) {
      final rig = SessionRig(remoteTools: tools());
      unawaited(
        rig.manager.open(
          cols: 80,
          rows: 24,
          launch: SshLaunch(devbox, hook: false),
        ),
      );
      async.flushMicrotasks();
      expect(rig.pty(0).command.arguments.last, 'devbox');
      expect(rig.manager.sessions.single.remote!.connected, isFalse);
      async.elapse(const Duration(seconds: 10));
      expect(rig.manager.sessions.single.remote!.connected, isTrue);
    });
  });

  test('no ssh / no tmux → named spawn failures (D3, D25)', () async {
    final none = SessionRig();
    await expectLater(
      none.manager.open(cols: 80, rows: 24, launch: SshLaunch(devbox)),
      throwsA(
        isA<SpawnFailedException>().having(
          (e) => e.message,
          'message',
          'ssh_unavailable',
        ),
      ),
    );
    final noTmux = SessionRig(remoteTools: tools(tmux: null));
    await expectLater(
      noTmux.manager.open(cols: 80, rows: 24, launch: const TmuxLaunch('main')),
      throwsA(
        isA<SpawnFailedException>().having(
          (e) => e.message,
          'message',
          'tmux_unavailable',
        ),
      ),
    );
    await expectLater(
      noTmux.manager.open(
        cols: 80,
        rows: 24,
        launch: TmuxLaunch('a b', host: devbox, hook: false),
      ),
      throwsA(
        isA<SpawnFailedException>().having(
          (e) => e.message,
          'message',
          'bad_launch',
        ),
      ),
    );
  });

  test(
    'local tmux: argv, connected at once, a stable title (D25, D26)',
    () async {
      final rig = SessionRig(remoteTools: tools());
      await rig.manager.open(
        cols: 80,
        rows: 24,
        launch: const TmuxLaunch('main'),
      );
      expect(rig.pty(0).command.executable, '/usr/local/bin/tmux');
      expect(rig.pty(0).command.arguments, ['attach-session', '-t', '=main']);
      rig.pty(0).emit('\x1b]0;tmux set-titles\x07');
      await pumpEventQueue();
      final s = rig.manager.sessions.single;
      expect(s.remote!.connected, isTrue);
      expect(s.title, 'tmux: main');
    },
  );

  test('a second pane to a server still signing in waits for its master '
      '(D9)', () async {
    final calls = <List<String>>[];
    final rig = SessionRig(remoteTools: tools(calls: calls));
    await rig.manager.open(cols: 80, rows: 24, launch: SshLaunch(devbox));
    expect(calls.where((a) => a.contains('check')), isEmpty);
    calls.clear();
    await rig.manager.open(cols: 80, rows: 24, launch: SshLaunch(devbox));
    expect(calls.where((a) => a.contains('check')), hasLength(30));
    rig.pty(0).emit(osc('6973;hello=1'));
    rig.pty(1).emit(osc('6973;hello=1'));
    await pumpEventQueue();
    calls.clear();
    await rig.manager.open(cols: 80, rows: 24, launch: SshLaunch(devbox));
    expect(calls.where((a) => a.contains('check')), isEmpty);
    var up = 0;
    final quick = SessionRig(
      remoteTools: tools(calls: calls, master: () => ++up > 2),
    );
    await quick.manager.open(cols: 80, rows: 24, launch: SshLaunch(devbox));
    calls.clear();
    await quick.manager.open(cols: 80, rows: 24, launch: SshLaunch(devbox));
    expect(calls.where((a) => a.contains('check')), hasLength(3));
  });

  test('a configured keepalive is left alone (D13)', () async {
    final rig = SessionRig(remoteTools: tools(keepalive: '30'));
    await rig.manager.open(cols: 80, rows: 24, launch: SshLaunch(devbox));
    expect(
      rig.pty(0).command.arguments,
      isNot(contains('ServerAliveInterval=15')),
    );
  });

  test('phones see the folder as host:path (D36)', () async {
    final rig = SessionRig(remoteTools: tools());
    await rig.manager.open(cols: 80, rows: 24, launch: SshLaunch(devbox));
    rig.pty(0).emit('${osc('6973;hello=1')}${osc('7;file://devbox/home/me')}');
    await pumpEventQueue();
    final info = rig.manager.sessionInfosWithContext.single;
    expect(info.cwd, 'devbox:/home/me');
    expect(rig.manager.sessionInfos.single.cwd, '');
  });

  test('logs and spawn errors never carry the host, path or branch '
      '(D37)', () async {
    final logs = <String>[];
    final rig = SessionRig(remoteTools: tools(), log: logs.add);
    await rig.manager.open(
      cols: 80,
      rows: 24,
      launch: SshLaunch(devbox, remoteCwd: '/srv/secret'),
    );
    rig
        .pty(0)
        .emit(
          '${osc('6973;hello=1')}${osc('7;file://devbox/srv/secret')}'
          '${osc('6973;branch=topsecret')}',
        );
    rig.pty(0).exit(255);
    await pumpEventQueue();
    for (final line in logs) {
      expect(line, isNot(anyOf(contains('devbox'), contains('secret'))));
    }
    rig.factory.failWith = Exception('ssh -t devbox /srv/secret');
    await expectLater(
      rig.manager.open(
        cols: 80,
        rows: 24,
        launch: SshLaunch(devbox, remoteCwd: '/srv/secret'),
      ),
      throwsA(
        isA<SpawnFailedException>().having(
          (e) => e.message,
          'message',
          'spawn_failed',
        ),
      ),
    );
  });
}
