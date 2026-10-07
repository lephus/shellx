import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';

import '../support/fake_local_sessions.dart';

void main() {
  test('Workspace.ssh round-trips; a bad or non-canonical value is dropped, '
      'the workspace kept (D23)', () {
    const w = Workspace(id: 'w1', name: 'devbox', ssh: 'me@devbox:2222');
    expect(Workspace.decode(w.encode()), w);
    expect(
      Workspace.decode('{"id":"w2","name":"x","ssh":"-oProxyCommand=y"}')!.ssh,
      isNull,
    );
    expect(
      Workspace.decode('{"id":"w3","name":"x","ssh":"ssh://devbox"}')!.ssh,
      isNull,
    );
    expect(Workspace.decode('{"id":"w4","name":"x","ssh":7}')!.ssh, isNull);
    expect(Workspace.decode('{"id":"w5","name":"x"}')!.ssh, isNull);
  });

  test(
    'createForHost, workspaceForHost, launchFor, openTabIn opens SSH',
    () async {
      final local = FakeLocalSessions();
      final settings = InMemorySettingsStore();
      final container = ProviderContainer.test(
        overrides: [
          localSessionsProvider.overrideWithValue(local),
          settingsStoreProvider.overrideWithValue(settings),
        ],
      );
      final side = container.read(sidebarWorkspacesProvider.notifier);
      final devbox = SshTarget.parse('devbox')!;
      expect(side.workspaceForHost('devbox'), isNull);
      final id = side.createForHost(devbox);
      final state = container.read(sidebarWorkspacesProvider);
      expect(state.currentId, id);
      expect(state.renaming, isNull);
      expect(state.workspace(id)!.name, 'devbox');
      expect(side.workspaceForHost('devbox'), id);
      expect(side.launchFor(id), SshLaunch(devbox));
      expect(side.launchFor(kDefaultWorkspaceId), isNull);
      await settings.setStrings(SettingKeys.sshPlainTargets, ['devbox']);
      expect(side.launchFor(id), SshLaunch(devbox, hook: false));
      await side.openTabIn(id);
      expect(local.openLaunches.single, SshLaunch(devbox, hook: false));
      expect(container.read(sidebarWorkspacesProvider).tabsOf(id), [100]);
      expect(
        settings.getStrings(SettingKeys.terminalWorkspaces).join(),
        contains('"ssh":"devbox"'),
      );
    },
  );

  test('renaming an SSH workspace keeps its server (B9)', () {
    final container = ProviderContainer.test(
      overrides: [
        localSessionsProvider.overrideWithValue(FakeLocalSessions()),
        settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
      ],
    );
    final side = container.read(sidebarWorkspacesProvider.notifier);
    final id = side.createForHost(SshTarget.parse('me@devbox:2222')!);
    side.rename(id, 'Prod box');
    final w = container.read(sidebarWorkspacesProvider).workspace(id)!;
    expect(w.name, 'Prod box');
    expect(w.ssh, 'me@devbox:2222');
    expect(side.workspaceForHost('me@devbox:2222'), id);
  });

  test('createForHost with makeCurrent false keeps the current workspace', () {
    final container = ProviderContainer.test(
      overrides: [
        localSessionsProvider.overrideWithValue(FakeLocalSessions()),
        settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
      ],
    );
    final side = container.read(sidebarWorkspacesProvider.notifier);
    side.createForHost(SshTarget.parse('devbox')!, makeCurrent: false);
    expect(
      container.read(sidebarWorkspacesProvider).currentId,
      kDefaultWorkspaceId,
    );
  });
}
