import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/remote/remote_tools_provider.dart';
import 'package:shellx_desktop/src/remote/ssh_actions.dart';
import 'package:shellx_desktop/src/remote/ssh_settings.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/fake_local_sessions.dart';

void main() {
  late FakeLocalSessions local;
  late InMemorySettingsStore settings;
  late ProviderContainer container;
  late List<List<String>> runs;
  late CommandResult Function(String exe, List<String> args) answer;

  final devbox = SshTarget.parse('devbox')!;

  setUp(() {
    local = FakeLocalSessions();
    settings = InMemorySettingsStore();
    runs = [];
    answer = (_, _) =>
        const CommandResult(0, 'SXTMUX\tmain\t2\t0\t1759831200\n', '');
    Future<CommandResult> run(
      String exe,
      List<String> args, {
      Duration timeout = const Duration(seconds: 5),
    }) async {
      runs.add([exe, ...args]);
      return answer(exe, args);
    }

    container = ProviderContainer.test(
      overrides: [
        localSessionsProvider.overrideWithValue(local),
        settingsStoreProvider.overrideWithValue(settings),
        commandRunnerProvider.overrideWithValue(run),
        remoteToolsProvider.overrideWithValue(
          RemoteTools(
            sshPath: '/usr/bin/ssh',
            tmuxPath: '/opt/homebrew/bin/tmux',
            control: SshControl(sshPath: '/usr/bin/ssh', run: run),
          ),
        ),
        sshConfigHostsProvider.overrideWithValue(() async => ['devbox', 'db']),
      ],
    );
  });

  SshActions actions() => container.read(sshActionsProvider);
  SidebarState side() => container.read(sidebarWorkspacesProvider);

  test(
    'connect: the server\'s workspace (made once), recent targets (D23)',
    () async {
      await actions().connect(devbox, remoteCwd: '/srv');
      await actions().connect(devbox);
      final id = container
          .read(sidebarWorkspacesProvider.notifier)
          .workspaceForHost('devbox')!;
      expect(side().workspaces.where((w) => w.ssh == 'devbox'), hasLength(1));
      expect(side().tabsOf(id), [100, 101]);
      expect(local.openLaunches, [
        SshLaunch(devbox, remoteCwd: '/srv'),
        SshLaunch(devbox),
      ]);
      expect(settings.getStrings(SettingKeys.sshRecentTargets), ['devbox']);
      for (var i = 0; i < 12; i++) {
        await actions().connect(SshTarget.parse('h$i')!);
      }
      final recent = settings.getStrings(SettingKeys.sshRecentTargets);
      expect(recent, hasLength(10));
      expect(recent.first, 'h11');
    },
  );

  test(
    'connect with the box ticked remembers "no hook" for that server (D11)',
    () async {
      await actions().connect(devbox, noHook: true);
      expect(local.openLaunches.single, SshLaunch(devbox, hook: false));
      expect(actions().hookFor('devbox'), isFalse);
      await actions().connect(devbox, noHook: false);
      expect(actions().hookFor('devbox'), isTrue);
      await settings.setBool(SettingKeys.sshRemoteHook, false);
      expect(actions().hookFor('devbox'), isFalse);
    },
  );

  test('⌘T: local in a local workspace, SSH in an SSH workspace', () async {
    await actions().newTab();
    expect(local.openLaunches.last, isNull);
    await actions().connect(devbox);
    await actions().newTab();
    expect(local.openLaunches.last, SshLaunch(devbox));
  });

  test(
    'tmux: list here and on a server; attach places the tab (D25, D26)',
    () async {
      final here = await actions().listTmux(null);
      expect((here as TmuxSessions).sessions.single.name, 'main');
      expect(runs.last, [
        '/opt/homebrew/bin/tmux',
        'list-sessions',
        '-F',
        tmuxListFormat,
      ]);
      final there = await actions().listTmux(devbox);
      expect(there, isA<TmuxSessions>());
      expect(runs.last, containsAll(['BatchMode=yes', '--', 'devbox']));
      answer = (_, _) => const CommandResult(255, '', '');
      expect(await actions().listTmux(devbox), isA<TmuxListFailed>());
      await actions().attachTmux('main');
      expect(local.openLaunches.last, const TmuxLaunch('main'));
      await actions().attachTmux('main', host: devbox, create: true);
      expect(
        local.openLaunches.last,
        TmuxLaunch('main', host: devbox, create: true),
      );
      final id = container
          .read(sidebarWorkspacesProvider.notifier)
          .workspaceForHost('devbox')!;
      expect(side().tabsOf(id), contains(local.nextId - 1));
    },
  );

  test(
    'suggestions: config then recent, recent without duplicates of config',
    () async {
      await actions().connect(SshTarget.parse('me@x:2222')!);
      await actions().connect(devbox);
      final s = await actions().suggestions();
      expect(s.config, ['devbox', 'db']);
      expect(s.recent, ['me@x:2222']);
      await actions().clearRecent();
      expect((await actions().suggestions()).recent, isEmpty);
    },
  );

  test(
    'CLI connect does not move focus and lands in the server workspace',
    () async {
      local.add(
        local.summary(1, origin: SessionOrigin.desktop),
      ); // the user's tab, selected
      final tab = await actions().connectForCli(devbox, select: false);
      expect(container.read(terminalTabsProvider).selectedId, 1);
      final id = container
          .read(sidebarWorkspacesProvider.notifier)
          .workspaceForHost('devbox')!;
      expect(side().tabsOf(id), [tab]);
      expect(side().currentId, kDefaultWorkspaceId);
    },
  );

  test('CLI connect that fails leaves no empty SSH workspace (B11)', () async {
    local.openError = const SpawnFailedException('x');
    await expectLater(
      actions().connectForCli(devbox),
      throwsA(isA<SpawnFailedException>()),
    );
    expect(
      container
          .read(sidebarWorkspacesProvider.notifier)
          .workspaceForHost('devbox'),
      isNull,
    );
  });

  test(
    'CLI connect with hook false and a plain server opens without the hook',
    () async {
      await setPlainTarget(settings, 'devbox', plain: true);
      await actions().connectForCli(devbox);
      expect(local.openLaunches.last, SshLaunch(devbox, hook: false));
    },
  );
}
