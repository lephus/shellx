import 'dart:async';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/remote/remote_state.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/tab_attention.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/fake_local_sessions.dart';

late FakeLocalSessions local;
late ProviderContainer container;

TerminalTabs tabs() => container.read(terminalTabsProvider.notifier);
TerminalTabsState state() => container.read(terminalTabsProvider);

final devbox = SshTarget.parse('devbox')!;

SessionRemote ssh({bool connected = true}) => SessionRemote(
  launch: SshLaunch(devbox),
  connected: connected,
  home: '/home/me',
);

void boot() {
  container = ProviderContainer.test(
    overrides: [
      localSessionsProvider.overrideWithValue(local),
      appL10nProvider.overrideWithValue(
        lookupAppLocalizations(const Locale('en')),
      ),
    ],
  );
  state();
}

PaneSession pane(int id) => state().tabOfSession(id)!.panes[id]!;

/// The shell [id] died: gone from the listing, then its exit (as the agent
/// does).
Future<void> lose(int id, int code) async {
  local.summaries.removeWhere((s) => s.id == id);
  local.views[id]!.end(code);
  await pumpEventQueue();
}

void main() {
  setUp(() => local = FakeLocalSessions());

  test('remote state follows the summary; everConnected sticks (D17)', () {
    local.add(
      local.summary(
        1,
        origin: SessionOrigin.desktop,
        remote: ssh(connected: false),
      ),
    );
    boot();
    expect(pane(1).remote!.hostKey, 'devbox');
    expect(pane(1).remoteState, RemoteState.connecting);
    expect(pane(1).everConnected, isFalse);
    local.replace(
      local.summary(
        1,
        origin: SessionOrigin.desktop,
        remote: ssh(),
        cwd: '/srv/app',
      ),
    );
    expect(pane(1).remoteState, RemoteState.connected);
    expect(pane(1).everConnected, isTrue);
    expect(pane(1).cwd, '/srv/app');
  });

  test('local shells and local tmux have no remote state', () {
    local.add(local.summary(1, origin: SessionOrigin.desktop));
    local.add(
      local.summary(
        2,
        origin: SessionOrigin.desktop,
        remote: const SessionRemote(
          launch: TmuxLaunch('main'),
          connected: true,
        ),
      ),
    );
    boot();
    expect(pane(1).remoteState, isNull);
    expect(pane(2).remoteState, isNull);
  });

  test('launchWithoutHook switches the hook off, keeps the rest', () {
    expect(
      launchWithoutHook(SshLaunch(devbox, remoteCwd: '/srv')),
      SshLaunch(devbox, remoteCwd: '/srv', hook: false),
    );
    expect(
      launchWithoutHook(TmuxLaunch('main', host: devbox, create: true)),
      TmuxLaunch('main', host: devbox, create: true, hook: false),
    );
  });

  test('tabs open with a launch; splits inherit the server and its folder, '
      'or not when local (D24)', () async {
    local.add(
      local.summary(
        1,
        origin: SessionOrigin.desktop,
        remote: ssh(),
        cwd: '/srv/app',
      ),
    );
    boot();
    await tabs().split(SplitAxis.row);
    expect(local.openLaunches.last, SshLaunch(devbox, remoteCwd: '/srv/app'));
    expect(local.openCwds.last, isNull);
    await tabs().split(SplitAxis.column, local: true);
    expect(local.openLaunches.last, isNull);
    // I2: the server's folder never reaches a local shell.
    expect(local.openCwds.last, isNull);
    await tabs().openTab(launch: const TmuxLaunch('main'));
    expect(local.openLaunches.last, const TmuxLaunch('main'));
    await tabs().openTabFor(launch: SshLaunch(devbox));
    expect(local.openLaunches.last, SshLaunch(devbox));
    await tabs().splitPaneFor(1, SplitAxis.column, local: true);
    expect(local.openLaunches.last, isNull);
    expect(local.openCwds.last, isNull);
    await tabs().splitPaneFor(1, SplitAxis.column, local: true, cwd: '/srv');
    expect(local.openCwds.last, isNull);
  });

  test('a lost connection keeps the pane with a dim line; Enter reconnects '
      'in place — same terminal, tab id, focus, zoom (D20–D22)', () async {
    local.notifyOnOpen = true; // as the real manager (B2)
    local.add(
      local.summary(
        1,
        origin: SessionOrigin.desktop,
        remote: ssh(),
        cwd: '/srv/app',
      ),
    );
    boot();
    await tabs().split(SplitAxis.row, local: true); // pane 100, focused
    tabs().focusPane(1);
    tabs().toggleZoom();
    final replaced = <PaneReplacement>[];
    tabs().paneReplacements.listen(replaced.add);
    final outputs = <int>[];
    tabs().paneOutputs.listen(outputs.add);
    local.views[1]!.emit('hello\r\n');
    await pumpEventQueue();
    await lose(1, 255);
    final lost = pane(1);
    expect(lost.remoteState, RemoteState.disconnected);
    expect(lost.canReconnect, isTrue);
    final terminal = lost.terminal;
    expect(
      terminal.buffer.getText(),
      contains('[Lost connection to devbox] — press Enter to reconnect'),
    );
    terminal.textInput('\r');
    await pumpEventQueue();
    expect(local.openLaunches.last, SshLaunch(devbox, remoteCwd: '/srv/app'));
    final fresh = local.nextId - 1;
    expect(state().tabs, hasLength(1)); // not a tab of its own
    final tab = state().tabs.single;
    expect(tab.id, 1);
    expect(tab.paneOrder, [fresh, 100]);
    expect(tab.focusedPaneId, fresh);
    expect(tab.zoomedPaneId, fresh);
    expect(identical(tab.panes[fresh]!.terminal, terminal), isTrue);
    expect(tab.panes[fresh]!.everConnected, isTrue);
    expect(terminal.buffer.getText(), contains('hello'));
    expect(terminal.buffer.getText(), contains('— Reconnected · '));
    expect(replaced.single, PaneReplacement(tabId: 1, from: 1, to: fresh));
    expect(tabs().resolveReplaced(1), fresh);
    expect(tabs().resolveReplaced(fresh), fresh);
    outputs.clear();
    local.views[fresh]!.emit('world');
    await pumpEventQueue();
    expect(terminal.buffer.getText(), contains('world'));
    expect(outputs, [fresh]); // A5a: output events follow the new id
    expect(local.views[1]!.disposed, isTrue);
    expect(state().opening, isFalse);
  });

  test('the replacement is announced before the state changes (D22)', () async {
    local.add(local.summary(1, origin: SessionOrigin.desktop, remote: ssh()));
    boot();
    await lose(1, 255);
    int? idAtEmit;
    tabs().paneReplacements.listen(
      (r) => idAtEmit = state().tabs.single.focusedPaneId,
    );
    await tabs().reconnect(1);
    expect(idAtEmit, 1);
  });

  test('never connected → failed line; any other exit after connecting → A1 '
      'exit line', () async {
    local.add(
      local.summary(
        1,
        origin: SessionOrigin.desktop,
        remote: ssh(connected: false),
      ),
    );
    local.add(local.summary(2, origin: SessionOrigin.desktop, remote: ssh()));
    boot();
    await lose(1, 255);
    expect(pane(1).remoteState, RemoteState.failed);
    expect(
      pane(1).terminal.buffer.getText(),
      contains('[Couldn’t connect to devbox] — press Enter to try again'),
    );
    await lose(2, 1);
    expect(pane(2).remoteState, RemoteState.exited);
    expect(pane(2).canReconnect, isFalse);
    expect(
      pane(2).terminal.buffer.getText(),
      contains('[Process exited with code 1]'),
    );
    pane(2).terminal.textInput('\r');
    await pumpEventQueue();
    expect(state().tabOfSession(2), isNull); // Enter closes it (A3 D7)
  });

  test('a retry that fails stays "disconnected", and can try without the '
      'hook', () async {
    local.add(local.summary(1, origin: SessionOrigin.desktop, remote: ssh()));
    boot();
    await lose(1, 255);
    final fresh = await tabs().reconnect(1, withoutHook: true);
    expect(local.openLaunches.last, SshLaunch(devbox, hook: false));
    await lose(fresh!, 255);
    expect(pane(fresh).remoteState, RemoteState.disconnected);
  });

  test('reconnect of a pane that cannot reconnect does nothing', () async {
    local.add(local.summary(1, origin: SessionOrigin.desktop, remote: ssh()));
    boot();
    expect(await tabs().reconnect(1), isNull);
    expect(local.openLaunches, isEmpty);
  });

  test(
    'reconnect: the pane closed meanwhile → the new shell is closed',
    () async {
      local.notifyOnOpen = true;
      local.add(local.summary(1, origin: SessionOrigin.desktop, remote: ssh()));
      boot();
      await lose(1, 255);
      local.openGate = Completer<void>();
      final pending = tabs().reconnect(1);
      await pumpEventQueue();
      tabs().close(1);
      local.openGate!.complete();
      expect(await pending, isNull);
      expect(local.closed, contains(local.nextId - 1));
      expect(state().tabs, isEmpty);
    },
  );

  test('ssh / tmux missing → named toasts', () async {
    local.add(local.summary(1, origin: SessionOrigin.desktop));
    boot();
    local.openError = const SpawnFailedException('ssh_unavailable');
    await tabs().openTab(launch: SshLaunch(devbox));
    expect(state().notice, isA<SshUnavailableNotice>());
    local.openError = const SpawnFailedException('tmux_unavailable');
    await tabs().openTab(launch: const TmuxLaunch('main'));
    expect(state().notice, isA<TmuxUnavailableNotice>());
  });

  test('forwarding is remembered for the last 64 replacements only', () async {
    local.add(local.summary(1, origin: SessionOrigin.desktop, remote: ssh()));
    boot();
    var current = 1;
    for (var i = 0; i < 66; i++) {
      await lose(current, 255);
      current = (await tabs().reconnect(current))!;
    }
    expect(tabs().resolveReplaced(current), current);
    // The oldest links fell out: 1 no longer leads all the way.
    expect(tabs().resolveReplaced(1), isNot(current));
  });

  test('a reconnect that ends before it is placed writes the line again '
      '(M1)', () async {
    local.add(local.summary(1, origin: SessionOrigin.desktop, remote: ssh()));
    boot();
    await lose(1, 255);
    final terminal = pane(1).terminal;
    local.afterOpen = (id) => local.summaries.removeWhere((s) => s.id == id);
    expect(await tabs().reconnect(1), isNull);
    final lines = 'press Enter to reconnect'.allMatches(
      terminal.buffer.getText(),
    );
    expect(lines, hasLength(2));
    expect(pane(1).canReconnect, isTrue);
    expect(state().opening, isFalse);
  });

  test('the new pane keeps the old index; its folder follows the new '
      'session (M2, M5)', () async {
    local.add(local.summary(2, origin: SessionOrigin.desktop));
    local.add(
      local.summary(
        1,
        origin: SessionOrigin.desktop,
        remote: ssh(),
        cwd: '/srv/app',
      ),
    );
    boot();
    final index = pane(1).index;
    await lose(1, 255);
    local.add(local.summary(3, origin: SessionOrigin.desktop));
    final fresh = (await tabs().reconnect(1))!;
    expect(pane(fresh).index, index);
    expect(pane(fresh).automaticLabel, 'zsh $index');
    expect(
      pane(fresh).remote!.launch,
      SshLaunch(devbox, remoteCwd: '/srv/app'),
    );
    local.setCwd(fresh, '/srv/other');
    expect(pane(fresh).cwd, '/srv/other');
  });

  test('unread kept for the old pane id is dropped (M5, A4)', () async {
    final c = ProviderContainer.test(
      overrides: [
        localSessionsProvider.overrideWithValue(local),
        appL10nProvider.overrideWithValue(
          lookupAppLocalizations(const Locale('en')),
        ),
        settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
      ],
    );
    container = c;
    local.add(local.summary(1, origin: SessionOrigin.desktop, remote: ssh()));
    c.read(terminalTabsProvider);
    c.read(sidebarWorkspacesProvider);
    c.read(tabAttentionProvider);
    await tabs().split(SplitAxis.row); // pane 100 focused; pane 1 unfocused
    local.notice(1, SessionNoticeKind.message, body: 'done');
    await pumpEventQueue();
    expect(c.read(tabAttentionProvider).unreadPanes(1), {1});
    await lose(1, 255);
    final fresh = (await tabs().reconnect(1))!;
    expect(c.read(tabAttentionProvider).unreadPanes(1), isNot(contains(1)));
    expect(state().tabOfSession(fresh), isNotNull);
  });
}
