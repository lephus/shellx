import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/cli/ui_command_handler.dart';
import 'package:shellx_desktop/src/cli/ui_ssh_commands.dart';
import 'package:shellx_desktop/src/remote/remote_tools_provider.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/agent/agent_controller_base.dart';
import '../support/state_only_agent.dart';

import '../support/fake_local_sessions.dart';
import 'support/cli_container.dart';

void main() {
  late ProviderContainer c;
  late FakeLocalSessions local;
  late UiCommandHandler h;
  late List<List<String>> runs;
  late Future<CommandResult> Function(String exe, List<String> args) answer;

  Future<Map<String, Object?>> call(
    String t, [
    Map<String, Object?> f = const {},
  ]) => h.handle(MuxMessage(t, q: 1, fields: f));

  Matcher fails(String code) =>
      throwsA(isA<CliFailure>().having((e) => e.code, 'code', code));

  TerminalTabsState tabs() => c.read(terminalTabsProvider);
  SidebarState side() => c.read(sidebarWorkspacesProvider);

  setUp(() async {
    local = FakeLocalSessions()..notifyOnOpen = true; // as the real manager
    runs = [];
    answer = (_, _) async =>
        const CommandResult(0, 'SXTMUX\tmain\t3\t0\t1759831200\n', '');
    Future<CommandResult> run(
      String exe,
      List<String> args, {
      Duration timeout = const Duration(seconds: 5),
    }) {
      runs.add([exe, ...args]);
      return answer(exe, args);
    }

    c = cliContainer(
      local,
      overrides: [
        commandRunnerProvider.overrideWithValue(run),
        remoteToolsProvider.overrideWithValue(
          RemoteTools(
            sshPath: '/usr/bin/ssh',
            tmuxPath: '/opt/homebrew/bin/tmux',
            control: SshControl(sshPath: '/usr/bin/ssh', run: run),
          ),
        ),
        sshConfigHostsProvider.overrideWithValue(() async => ['devbox']),
        uiCommandHandlerProvider.overrideWith(
          (ref) => UiCommandHandler(
            ref,
            tmuxBound: const Duration(milliseconds: 100),
          ),
        ),
      ],
    );
    h = c.read(uiCommandHandlerProvider);
    await c.read(terminalTabsProvider.notifier).openTab(); // user's tab 100
  });

  test('ui.ssh.open from a pane in a local workspace: the server still gets '
      'its own workspace, the caller\'s is untouched (A8 D23)', () async {
    final api = c
        .read(sidebarWorkspacesProvider.notifier)
        .createFor(name: 'api');
    await call('ui.tab.new', {'workspace': 'api'}); // tab 101 in `api`
    final before = side().tabsOf(api).toList();
    final r = await call('ui.ssh.open', {
      'target': 'devbox',
      'fromPane': 101,
      'fromTab': 101,
    });
    final home = side().workspaceOf(r['tab']! as int)!;
    expect(side().workspace(home)!.ssh, 'devbox');
    expect(home, isNot(api));
    expect(side().tabsOf(api), before);
  });

  test('ui.ssh.open: validates, lands in the SSH workspace, no focus, '
      '--cmd types once ready (D33)', () async {
    final r = await call('ui.ssh.open', {
      'target': 'devbox',
      'cwd': '/srv',
      'cmd': 'make',
      'hook': true,
    });
    expect(r['tab'], isA<int>());
    expect(r['pane'], r['tab']);
    expect(
      local.openLaunches.last,
      SshLaunch(SshTarget.parse('devbox')!, remoteCwd: '/srv'),
    );
    expect(tabs().selectedId, 100);
    expect(side().workspaceOf(r['tab']! as int), isNot(kDefaultWorkspaceId));
    final id = r['tab']! as int;
    await pumpEventQueue();
    expect(local.views[id]!.writes, isEmpty); // no hello yet
    final plain = await call('ui.ssh.open', {
      'target': 'devbox',
      'hook': false,
      'focus': true,
    });
    expect(
      local.openLaunches.last,
      SshLaunch(SshTarget.parse('devbox')!, hook: false),
    );
    expect(tabs().selectedId, plain['tab']);
    expect(side().workspaces.where((w) => w.ssh == 'devbox'), hasLength(1));
    for (final bad in [
      {'target': '-oProxyCommand=x'},
      {'target': 'dev box'},
      {'target': 7},
      <String, Object?>{},
      {'target': 'devbox', 'cwd': 'relative'},
      {'target': 'devbox', 'cwd': '/a\u0007b'},
      {'target': 'devbox', 'workspace': 5},
    ]) {
      await expectLater(call('ui.ssh.open', bad), fails('bad_request'));
    }
    await expectLater(
      call('ui.ssh.open', {'target': 'devbox', 'workspace': 'nope'}),
      fails('not_found'),
    );
    expect(local.openLaunches, hasLength(3)); // the user tab and two opens
    local.openError = const SpawnFailedException('ssh_unavailable');
    await expectLater(
      call('ui.ssh.open', {'target': 'devbox'}),
      fails('ssh_unavailable'),
    );
    local.openError = const SpawnFailedException('/Users/me/secret path');
    await expectLater(
      call('ui.ssh.open', {'target': 'devbox'}),
      throwsA(
        isA<CliFailure>()
            .having((e) => e.code, 'code', 'spawn_failed')
            .having((e) => e.message, 'message', isNot(contains('secret'))),
      ),
    );
  });

  test('ui.ssh.open into a named workspace', () async {
    final ws = c
        .read(sidebarWorkspacesProvider.notifier)
        .createFor(name: 'api');
    final r = await call('ui.ssh.open', {
      'target': 'devbox',
      'workspace': 'api',
    });
    expect(side().workspaceOf(r['tab']! as int), ws);
  });

  test('ui.tmux.list / ui.tmux.attach', () async {
    final list = await call('ui.tmux.list');
    expect(list['sessions'], [
      {'name': 'main', 'windows': 3, 'attached': 0, 'activity': 1759831200},
    ]);
    final there = await call('ui.tmux.list', {'host': 'devbox'});
    expect((there['sessions']! as List), hasLength(1));
    expect(runs.last, containsAll(['BatchMode=yes', '--', 'devbox']));
    final a = await call('ui.tmux.attach', {'name': 'main'});
    expect(local.openLaunches.last, const TmuxLaunch('main'));
    expect(a['pane'], a['tab']);
    expect(tabs().selectedId, 100);
    await call('ui.tmux.attach', {
      'name': 'work',
      'host': 'devbox',
      'create': true,
      'focus': true,
    });
    expect(
      local.openLaunches.last,
      TmuxLaunch('work', host: SshTarget.parse('devbox'), create: true),
    );
    for (final bad in [
      {'name': 'a:b'},
      {'name': 'a.b'},
      {'name': ''},
      <String, Object?>{},
      {'name': 'main', 'host': '-oProxyCommand=x'},
    ]) {
      await expectLater(call('ui.tmux.attach', bad), fails('bad_request'));
    }
    await expectLater(
      call('ui.tmux.list', {'host': 'a b'}),
      fails('bad_request'),
    );
    local.openError = const SpawnFailedException('tmux_unavailable');
    await expectLater(
      call('ui.tmux.attach', {'name': 'main'}),
      fails('tmux_unavailable'),
    );
  });

  test('ui.tmux.list: unavailable, failed, and a hang is bounded', () async {
    answer = (_, _) async => const CommandResult(127, '', 'tmux: not found');
    await expectLater(call('ui.tmux.list'), fails('tmux_unavailable'));
    answer = (_, _) async => const CommandResult(255, '', '');
    await expectLater(
      call('ui.tmux.list', {'host': 'devbox'}),
      throwsA(
        isA<CliFailure>()
            .having((e) => e.code, 'code', 'tmux_failed')
            .having((e) => e.message, 'message', contains('password')),
      ),
    );
    answer = (_, _) async => const CommandResult(1, '', 'boom');
    await expectLater(call('ui.tmux.list'), fails('tmux_failed'));
    answer = (_, _) => Completer<CommandResult>().future; // never answers
    await expectLater(
      call('ui.tmux.list', {'host': 'devbox'}),
      fails('tmux_failed'),
    );
  });

  test('ls carries remote; a replaced pane id still resolves (D22)', () async {
    final opened = await call('ui.ssh.open', {'target': 'devbox'});
    final old = opened['pane']! as int;
    final ls = await call('ui.ls');
    Map<String, Object?> paneOf(int id) {
      for (final w in ls['workspaces']! as List) {
        for (final t in (w as Map)['tabs'] as List) {
          for (final p in (t as Map)['panes'] as List) {
            if ((p as Map)['id'] == id) return p.cast<String, Object?>();
          }
        }
      }
      throw StateError('no pane');
    }

    expect(paneOf(100).containsKey('remote'), isFalse);
    expect(paneOf(old)['remote'], {
      'kind': 'ssh',
      'host': 'devbox',
      'state': 'connecting',
    });
    local.summaries.removeWhere((s) => s.id == old); // an ended session
    local.views[old]!.end(255);
    await pumpEventQueue();
    final fresh = (await c.read(terminalTabsProvider.notifier).reconnect(old))!;
    expect(fresh, isNot(old));
    await call('ui.pane.send', {'pane': old, 'text': 'ls'});
    expect(local.views[fresh]!.writes.join(), contains('ls'));
    await call('ui.pane.send', {'pane': 'p$old', 'text': 'pwd'});
    expect(local.views[fresh]!.writes.join(), contains('pwd'));
    final split = await call('ui.pane.split', {'pane': old});
    expect(tabs().tabOfSession(split['pane']! as int)!.id, opened['tab']);
    await call('ui.focus', {'pane': old});
    expect(tabs().tabOfSession(old), isNull);
    await expectLater(
      call('ui.pane.send', {'pane': 99999, 'text': 'x'}),
      fails('not_found'),
    );
  });

  test('a tmux pane lists as tmux with its session', () async {
    await call('ui.tmux.attach', {'name': 'main', 'host': 'devbox'});
    final ls = await call('ui.ls');
    final remotes = [
      for (final w in ls['workspaces']! as List)
        for (final t in (w as Map)['tabs'] as List)
          for (final p in (t as Map)['panes'] as List)
            if ((p as Map)['remote'] != null) p['remote'],
    ];
    expect(remotes, [
      {'kind': 'tmux', 'host': 'devbox', 'tmux': 'main', 'state': 'connecting'},
    ]);
  });

  test(
    'new-tab --workspace <SSH workspace> opens SSH there (D5, D33)',
    () async {
      final first = await call('ui.ssh.open', {'target': 'devbox'});
      final ws = side().workspaceOf(first['tab']! as int)!;
      final r = await call('ui.tab.new', {'workspace': ws, 'cwd': '~/app'});
      expect(
        local.openLaunches.last,
        SshLaunch(SshTarget.parse('devbox')!, remoteCwd: '~/app'),
      );
      expect(side().workspaceOf(r['tab']! as int), ws);
      await call('ui.tab.new', {'workspace': ws});
      expect(local.openLaunches.last, SshLaunch(SshTarget.parse('devbox')!));
      await expectLater(
        call('ui.tab.new', {'workspace': ws, 'cwd': 'relative'}),
        fails('bad_request'),
      );
      // A local workspace stays local.
      await call('ui.tab.new', {'cwd': '/w'});
      expect(local.openLaunches.last, isNull);
      expect(local.openCwds.last, '/w');
    },
  );

  group('--cmd on a server pane (review 1)', () {
    void hello(int id, SshTarget target) => local.replace(
      local.summary(
        id,
        origin: SessionOrigin.desktop,
        remote: SessionRemote(launch: SshLaunch(target), connected: true),
      ),
    );

    test('typed once, after the server shell said hello; never before, '
        'however quiet the sign-in prompt is', () async {
      final target = SshTarget.parse('devbox')!;
      final r = await call('ui.ssh.open', {'target': 'devbox', 'cmd': 'make'});
      final id = r['tab']! as int;
      local.views[id]!.emit('devbox password: ');
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 1700));
      expect(local.views[id]!.writes, isEmpty);
      hello(id, target);
      await pumpEventQueue();
      expect(local.views[id]!.writes.join(), contains('make'));
      hello(id, target); // another change: not typed twice
      await pumpEventQueue();
      expect('make'.allMatches(local.views[id]!.writes.join()), hasLength(1));
    });

    test('a pane that ends first gets nothing', () async {
      final r = await call('ui.ssh.open', {'target': 'devbox', 'cmd': 'make'});
      final id = r['tab']! as int;
      local.summaries.removeWhere((s) => s.id == id);
      local.views[id]!.end(255);
      await pumpEventQueue();
      expect(local.views[id]!.writes, isEmpty);
    });

    test('without the hook --cwd is refused up front, nothing opens', () async {
      final before = local.openLaunches.length;
      await expectLater(
        call('ui.ssh.open', {'target': 'devbox', 'cwd': '/srv', 'hook': false}),
        throwsA(
          isA<CliFailure>()
              .having((e) => e.code, 'code', 'bad_request')
              .having((e) => e.message, 'message', kCwdNeedsHook),
        ),
      );
      expect(local.openLaunches, hasLength(before));
      // The per-server setting switches the hook off too, and so does a
      // tab made in such a server's workspace.
      (c.read(agentControllerProvider.notifier) as StateOnlyAgent).set(
        (s) => s.copyWith(sshRemoteHook: false),
      );
      await expectLater(
        call('ui.ssh.open', {'target': 'devbox', 'cwd': '/srv'}),
        fails('bad_request'),
      );
      final first = await call('ui.ssh.open', {'target': 'devbox'});
      final id = side().workspaceOf(first['tab']! as int)!;
      await expectLater(
        call('ui.tab.new', {'workspace': id, 'cwd': '/srv'}),
        fails('bad_request'),
      );
    });

    test('without the hook --cmd is refused up front, nothing opens', () async {
      final before = local.openLaunches.length;
      await expectLater(
        call('ui.ssh.open', {'target': 'devbox', 'cmd': 'x', 'hook': false}),
        throwsA(
          isA<CliFailure>()
              .having((e) => e.code, 'code', 'bad_request')
              .having((e) => e.message, 'message', kCmdNeedsHook),
        ),
      );
      expect(local.openLaunches, hasLength(before));
      final ws = side().workspaces.where((w) => w.ssh != null).map((w) => w.id);
      expect(ws, isEmpty);
      // The same refusal for a tab made in a server's workspace.
      (c.read(agentControllerProvider.notifier) as StateOnlyAgent).set(
        (s) => s.copyWith(sshRemoteHook: false),
      );
      final first = await call('ui.ssh.open', {'target': 'devbox'});
      final id = side().workspaceOf(first['tab']! as int)!;
      await expectLater(
        call('ui.tab.new', {'workspace': id, 'cmd': 'x'}),
        fails('bad_request'),
      );
    });

    test('new-tab in a server workspace waits for hello too', () async {
      final first = await call('ui.ssh.open', {'target': 'devbox'});
      final ws = side().workspaceOf(first['tab']! as int)!;
      final r = await call('ui.tab.new', {'workspace': ws, 'cmd': 'ls'});
      final id = r['tab']! as int;
      await pumpEventQueue();
      expect(local.views[id]!.writes, isEmpty);
      hello(id, SshTarget.parse('devbox')!);
      await pumpEventQueue();
      expect(local.views[id]!.writes.join(), contains('ls'));
    });

    test('the new pane has its remote at once; a server launch whose pane '
        'has none yet types nothing until hello (fails closed)', () async {
      final first = await call('ui.ssh.open', {'target': 'devbox'});
      final ws = side().workspaceOf(first['tab']! as int)!;
      final typed = <String>[];
      h.onCommand = (_, cmd) => typed.add(cmd);
      final ok = await call('ui.tab.new', {'workspace': ws});
      expect(
        tabs().tabOfSession(ok['tab']! as int)!.panes[ok['tab']!]!.remote,
        isNotNull,
      );
      local.openWithoutRemote = true;
      final r = await call('ui.tab.new', {'workspace': ws, 'cmd': 'ls'});
      final id = r['tab']! as int;
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 1700));
      expect(typed, isEmpty);
      expect(local.views[id]!.writes, isEmpty);
      hello(id, SshTarget.parse('devbox')!);
      await pumpEventQueue();
      expect(local.views[id]!.writes.join(), contains('ls'));
    });

    test('typeWhenHello: no typing at 1.5 s, 5 s or 10 s; 60 s drops it', () {
      fakeAsync((async) {
        final changes = StreamController<void>.broadcast(sync: true);
        var connected = false;
        var typed = 0;
        typeWhenHello(
          changes: changes.stream,
          view: () => (exited: false, connected: connected),
          type: () => typed++,
        );
        for (final s in [2, 4, 5]) {
          async.elapse(Duration(seconds: s)); // 2, 6, 11 s
          expect(typed, 0);
        }
        async.elapse(const Duration(seconds: 50)); // past 60 s
        connected = true;
        changes.add(null);
        expect(typed, 0); // dropped, still not typed
        changes.close();
      });
      fakeAsync((async) {
        final changes = StreamController<void>.broadcast(sync: true);
        var connected = false;
        var typed = 0;
        typeWhenHello(
          changes: changes.stream,
          view: () => (exited: false, connected: connected),
          type: () => typed++,
        );
        async.elapse(const Duration(seconds: 30));
        connected = true;
        changes.add(null);
        changes.add(null);
        expect(typed, 1);
        changes.close();
      });
      fakeAsync((async) {
        final changes = StreamController<void>.broadcast(sync: true);
        var exited = false;
        var typed = 0;
        typeWhenHello(
          changes: changes.stream,
          view: () => (exited: exited, connected: exited),
          type: () => typed++,
        );
        exited = true;
        changes.add(null);
        expect(typed, 0);
        changes.close();
      });
    });
  });

  test('a pane id two reconnects old still resolves (chain)', () async {
    final opened = await call('ui.ssh.open', {'target': 'devbox'});
    final first = opened['pane']! as int;
    final notifier = c.read(terminalTabsProvider.notifier);
    var current = first;
    for (var i = 0; i < 2; i++) {
      local.summaries.removeWhere((s) => s.id == current);
      local.views[current]!.end(255);
      await pumpEventQueue();
      current = (await notifier.reconnect(current))!;
    }
    expect(current, isNot(first));
    await call('ui.pane.send', {'pane': first, 'text': 'hop'});
    expect(local.views[current]!.writes.join(), contains('hop'));
  });
}
