import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/cli/ui_command_handler.dart';
import 'package:shellx_desktop/src/remote/remote_tools_provider.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

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

  test('ui.ssh.open: validates, lands in the SSH workspace, no focus, '
      '--cmd types once ready (D33)', () async {
    final typed = <(int, String)>[];
    h.onCommand = (pane, cmd) => typed.add((pane, cmd));
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
    expect(typed, [(r['tab'], 'make')]);
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
}
