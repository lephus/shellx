import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/remote/remote_state.dart';
import 'package:shellx_desktop/src/restore/restore_capture.dart';
import 'package:shellx_desktop/src/restore/restore_persistence.dart';
import 'package:shellx_desktop/src/restore/restore_snapshot.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/fake_local_sessions.dart';
import '../support/restore_fakes.dart';

final devbox = SshTarget.parse('devbox')!;
final k1 = 'a' * 32;
final k2 = 'b' * 32;

RestoreSnapshot snap(SavedPaneNode layout) => RestoreSnapshot(
  savedAt: DateTime.utc(2026, 10, 7, 9),
  cleanExit: true,
  selectedTab: k1,
  workspaces: [
    SavedWorkspace(id: 'default', tabs: [k1]),
  ],
  tabs: [SavedTab(key: k1, focused: k1, layout: layout)],
);

SavedPaneNode twoPanes({SessionLaunch? launch}) => SavedSplit(
  axis: SplitAxis.row,
  ratio: 0.5,
  first: SavedPane(
    key: k1,
    launch: launch ?? SshLaunch(devbox, remoteCwd: '/srv/app'),
  ),
  second: SavedPane(key: k2, cwd: '/Users/me'),
);

late FakeLocalSessions local;
late ProviderContainer container;

TerminalTabs tabs() => container.read(terminalTabsProvider.notifier);
TerminalTabsState state() => container.read(terminalTabsProvider);

void boot({List<Override> extra = const []}) {
  container = ProviderContainer.test(
    overrides: [
      localSessionsProvider.overrideWithValue(local),
      settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
      appL10nProvider.overrideWithValue(
        lookupAppLocalizations(const Locale('en')),
      ),
      ...extra,
    ],
  );
  container.read(sidebarWorkspacesProvider);
}

Future<void> lose(int id, int code) async {
  local.summaries.removeWhere((s) => s.id == id);
  local.views[id]!.end(code);
  await pumpEventQueue();
}

RestoreSnapshot capture(Map<int, String> keys) => captureSnapshot(
  tabs: state(),
  sidebar: container.read(sidebarWorkspacesProvider),
  keyOf: (id) => keys[id]!,
  now: DateTime.utc(2026),
  cleanExit: true,
);

String text(TerminalTab tab) => tab.terminal.mainBuffer.lines
    .toList()
    .map((l) => l.getText().trimRight())
    .join('\n');

void main() {
  setUp(() => local = FakeLocalSessions());

  test('a leaf keeps its launch through the file; old leaves are local '
      '(D29)', () {
    final back = RestoreSnapshot.tryParse(snap(twoPanes()).encode())!;
    final leaves = savedLeaves(back.tabs.single.layout);
    expect(leaves.first.launch, SshLaunch(devbox, remoteCwd: '/srv/app'));
    expect(leaves.last.launch, isNull);
    final json = snap(twoPanes()).encode();
    expect(
      json,
      contains(
        '"launch":{"kind":"ssh","target":"devbox","cwd":"/srv/app",'
        '"hook":true}',
      ),
    );
    // A local leaf writes no launch key at all.
    expect('"launch"'.allMatches(json), hasLength(1));
  });

  test('a launch that does not validate makes the file broken (A5a D11)', () {
    final text = snap(
      twoPanes(),
    ).encode().replaceAll('"target":"devbox"', '"target":"-oProxyCommand=x"');
    expect(RestoreSnapshot.tryParse(text), isNull);
    final tmux = snap(
      twoPanes(launch: TmuxLaunch('main', host: devbox)),
    ).encode().replaceAll('"session":"main"', '"session":"a:b"');
    expect(RestoreSnapshot.tryParse(tmux), isNull);
    final extra = snap(
      twoPanes(),
    ).encode().replaceAll('"hook":true', '"hook":true,"shell":"x"');
    expect(RestoreSnapshot.tryParse(extra), isNull); // strict keys
  });

  test('restore opens SSH leaves with their launch, local ones with their '
      'cwd; an unreachable server stays in the tree as failed (D29)', () async {
    boot();
    await tabs().restore(
      RestorePlan(snapshot: snap(twoPanes()), textByKey: const {}),
    );
    // The creating pane (k1) opens first.
    expect(local.openLaunches, [
      SshLaunch(devbox, remoteCwd: '/srv/app'),
      null,
    ]);
    expect(local.openCwds, [null, '/Users/me']);
    final sshId = local.nextId - 2;
    await lose(sshId, 255);
    final tab = state().tabs.single;
    expect(tab.paneCount, 2);
    expect(tab.panes[sshId]!.remoteState, RemoteState.failed);
  });

  test('restored remote panes show the saved text, a lost one reconnects '
      'into the same terminal (Task 7 carry)', () async {
    boot();
    await tabs().restore(
      RestorePlan(
        snapshot: snap(twoPanes()),
        textByKey: {k1: 'old line\r\n— Session restored —\r\n'},
      ),
    );
    final sshId = local.nextId - 2;
    expect(text(state().tabs.single), contains('old line'));
    await lose(sshId, 255);
    expect(state().tabs.single.panes[sshId]!.canReconnect, isTrue);
    final fresh = await tabs().reconnect(sshId);
    expect(fresh, isNotNull);
    expect(local.openLaunches.last, SshLaunch(devbox, remoteCwd: '/srv/app'));
    final pane = state().tabs.single.panes[fresh]!;
    expect(pane.remote, isNotNull);
    expect(
      pane.terminal.mainBuffer.lines.toList().map((l) => l.getText()).join(),
      contains('old line'),
    );
  });

  test('a remote leaf that cannot spawn (no ssh) is dropped like any pane '
      '(D7)', () async {
    boot();
    local.openError = const SpawnFailedException('ssh_unavailable');
    final out = await tabs().restore(
      RestorePlan(snapshot: snap(twoPanes()), textByKey: const {}),
    );
    expect(out.panesFailed, 2);
    expect(state().tabs, isEmpty);
  });

  test('capture keeps a pane that can reconnect, with its launch and no '
      'cwd; an ended local pane is skipped', () async {
    local
      ..add(
        local.summary(
          1,
          origin: SessionOrigin.desktop,
          cwd: '/srv/deep',
          remote: SessionRemote(
            launch: SshLaunch(devbox, remoteCwd: '/srv/app'),
            connected: true,
          ),
        ),
      )
      ..add(local.summary(2, origin: SessionOrigin.desktop, cwd: '/w'))
      ..add(
        local.summary(
          3,
          origin: SessionOrigin.desktop,
          remote: SessionRemote(launch: TmuxLaunch('main', host: devbox)),
        ),
      );
    boot();
    await tabs().split(SplitAxis.row);
    await pumpEventQueue();
    // Session 1 lost its connection: it stays and can reconnect.
    await lose(1, 255);
    await lose(2, 1); // a local shell that exited: skipped
    final leaves = savedLeaves(
      capture({1: k1, 3: k2, 100: 'c' * 32}).tabs.first.layout,
    );
    final ssh = leaves.firstWhere((p) => p.key == k1);
    expect(ssh.cwd, isNull);
    expect(ssh.launch, SshLaunch(devbox, remoteCwd: '/srv/deep'));
    expect(leaves.any((p) => p.session == 2), isFalse);
  });

  test('capture drops a remote pane that exited for good', () async {
    local.add(
      local.summary(
        1,
        origin: SessionOrigin.desktop,
        remote: SessionRemote(launch: SshLaunch(devbox), connected: true),
      ),
    );
    boot();
    await lose(1, 1); // connected, then exited: not a lost connection
    expect(state().tabs.single.panes[1]!.canReconnect, isFalse);
    expect(capture({1: k1}).tabs, isEmpty);
  });

  test('a reconnected pane keeps its restore key (D22)', () async {
    local.add(
      local.summary(
        1,
        origin: SessionOrigin.desktop,
        remote: SessionRemote(launch: SshLaunch(devbox), connected: true),
      ),
    );
    final files = RecordingFiles();
    boot(extra: [restoreStoreProvider.overrideWithValue(files)]);
    final persistence = container.read(restorePersistenceProvider.notifier)
      ..start();
    final key = persistence.keyOf(1);
    await lose(1, 255);
    final fresh = (await tabs().reconnect(1))!;
    expect(persistence.keyOf(fresh), key);
  });

  test('a replacement of a pane never keyed does not throw (B17)', () async {
    local.add(
      local.summary(
        1,
        origin: SessionOrigin.desktop,
        remote: SessionRemote(launch: SshLaunch(devbox), connected: true),
      ),
    );
    boot(extra: [restoreStoreProvider.overrideWithValue(RecordingFiles())]);
    container.read(restorePersistenceProvider.notifier).start();
    await lose(1, 255);
    expect(await tabs().reconnect(1), isNotNull);
  });
}
