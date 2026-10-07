import 'dart:ui';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart'
    show clockProvider;
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/restore/restore_persistence.dart';
import 'package:shellx_desktop/src/restore/restore_snapshot.dart';
import 'package:shellx_desktop/src/restore/restore_store.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/fake_local_sessions.dart';
import '../support/restore_fakes.dart';

/// A5b D14 (UI side): the daemon kept the shells; a snapshot saved against
/// the same daemon instance is laid back over the live sessions, with
/// nothing opened and no saved text.
void main() {
  late FakeLocalSessions local;
  late RecordingFiles files;
  late ProviderContainer c;

  final k5 = '5' * 32, k6 = '6' * 32;

  RestoreSnapshot snapshot({String? daemon = 'i1'}) => RestoreSnapshot(
    savedAt: DateTime(2026, 10, 7, 14, 31),
    cleanExit: true,
    daemon: daemon,
    selectedTab: k5,
    workspaces: [
      SavedWorkspace(id: 'default', tabs: [k5]),
    ],
    tabs: [
      SavedTab(
        key: k5,
        name: 'build',
        focused: k6,
        layout: SavedSplit(
          axis: SplitAxis.row,
          ratio: 0.5,
          first: SavedPane(key: k5, cwd: '/w', session: 5),
          second: SavedPane(key: k6, cwd: '/w', session: 6),
        ),
      ),
    ],
  );

  void boot() {
    c = ProviderContainer.test(
      overrides: [
        localSessionsProvider.overrideWithValue(local),
        settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
        restoreStoreProvider.overrideWithValue(files),
        clockProvider.overrideWithValue(() => DateTime(2026, 10, 7, 15)),
        appL10nProvider.overrideWithValue(
          lookupAppLocalizations(const Locale('vi')),
        ),
      ],
    );
    c.read(sidebarWorkspacesProvider);
    c.read(restorePersistenceProvider.notifier).start();
  }

  setUp(() {
    final print = debugPrint;
    debugPrint = (message, {wrapWidth}) {};
    addTearDown(() => debugPrint = print);
    local = FakeLocalSessions();
    files = RecordingFiles();
    for (final id in [5, 6]) {
      local.add(
        local.summary(id, origin: SessionOrigin.desktop),
        notify: false,
      );
    }
  });

  TerminalTabsState tabsState() => c.read(terminalTabsProvider);

  test('the same daemon instance: no open, the saved tree over sessions 5 and '
      '6, no divider', () async {
    boot();
    await c
        .read(restorePersistenceProvider.notifier)
        .restoreAtStartup(
          RestoreLoad(snapshot: snapshot()),
          daemonInstance: 'i1',
        );
    expect(local.openCwds, isEmpty);
    final tab = tabsState().tabs.single;
    expect(tab.customTitle, 'build');
    expect(paneIds(tab.layout), [5, 6]);
    expect(tab.focusedPaneId, 6);
    expect(tab.panes.keys, [5, 6]);
    // Nothing of the A5a reopen: no saved text, no divider line.
    for (final pane in tab.panes.values) {
      expect(
        pane.terminal.buffer.lines.toString().contains('Phiên được khôi phục'),
        isFalse,
      );
    }
  });

  test(
    'a live session the snapshot never had gets its own tab in Default',
    () async {
      local.add(local.summary(9, origin: SessionOrigin.desktop), notify: false);
      boot();
      await c
          .read(restorePersistenceProvider.notifier)
          .restoreAtStartup(
            RestoreLoad(snapshot: snapshot()),
            daemonInstance: 'i1',
          );
      expect(tabsState().tabs.map((t) => t.id), [5, 9]);
      expect(paneIds(tabsState().tabs.first.layout), [5, 6]);
      final sidebar = c.read(sidebarWorkspacesProvider);
      expect(sidebar.tabsOf(kDefaultWorkspaceId), [5, 9]);
    },
  );

  test(
    'panes whose session is gone are dropped, the rest keep their place',
    () async {
      local.summaries.removeWhere((s) => s.id == 6);
      boot();
      await c
          .read(restorePersistenceProvider.notifier)
          .restoreAtStartup(
            RestoreLoad(snapshot: snapshot()),
            daemonInstance: 'i1',
          );
      final tab = tabsState().tabs.single;
      expect(paneIds(tab.layout), [5]);
      expect(tab.focusedPaneId, 5);
    },
  );

  test('a remote pane that is not connected is not lost: it stays', () async {
    local.summaries
      ..removeWhere((s) => s.id == 6)
      ..add(
        local.summary(
          6,
          origin: SessionOrigin.desktop,
          remote: SessionRemote(
            launch: SshLaunch(SshTarget.parse('devbox')!),
            connected: false,
          ),
        ),
      );
    boot();
    await c
        .read(restorePersistenceProvider.notifier)
        .restoreAtStartup(
          RestoreLoad(snapshot: snapshot()),
          daemonInstance: 'i1',
        );
    expect(paneIds(tabsState().tabs.single.layout), [5, 6]);
  });

  test(
    'another instance (the daemon restarted): the A5a reopen path',
    () async {
      boot();
      await c
          .read(restorePersistenceProvider.notifier)
          .restoreAtStartup(
            RestoreLoad(snapshot: snapshot()),
            daemonInstance: 'i2',
          );
      expect(local.openCwds, isNotEmpty);
    },
  );

  test('no daemon instance (in-process): the A5a reopen path', () async {
    boot();
    await c
        .read(restorePersistenceProvider.notifier)
        .restoreAtStartup(RestoreLoad(snapshot: snapshot(daemon: null)));
    expect(local.openCwds, isNotEmpty);
  });

  test('later saves carry the instance (D21)', () async {
    boot();
    final persistence = c.read(restorePersistenceProvider.notifier)
      ..currentDaemon = 'i1';
    await c
        .read(restorePersistenceProvider.notifier)
        .restoreAtStartup(
          RestoreLoad(snapshot: snapshot()),
          daemonInstance: 'i1',
        );
    await persistence.flushAll(clean: true);
    expect(files.layouts.last.daemon, 'i1');
  });

  test('a live tab partly claimed by a saved tab: its unclaimed panes stay, '
      'one single-pane tab each', () async {
    // Live tab {5, 6} (a split opened elsewhere); the snapshot only has 5.
    local.summaries.clear();
    local.views.clear();
    for (final id in [5, 6]) {
      local.add(
        local.summary(id, origin: SessionOrigin.desktop),
        notify: false,
      );
    }
    boot();
    final tabs0 = c.read(terminalTabsProvider);
    expect(tabs0.tabs, hasLength(2));
    final one = RestoreSnapshot(
      savedAt: DateTime(2026, 10, 7, 14, 31),
      cleanExit: true,
      daemon: 'i1',
      selectedTab: k5,
      workspaces: [
        SavedWorkspace(id: 'default', tabs: [k5]),
      ],
      tabs: [
        SavedTab(
          key: k5,
          focused: k5,
          layout: SavedPane(key: k5, cwd: '/w', session: 5),
        ),
      ],
    );
    await c
        .read(restorePersistenceProvider.notifier)
        .restoreAtStartup(RestoreLoad(snapshot: one), daemonInstance: 'i1');
    expect(tabsState().tabs.map((t) => t.id), [5, 6]);
    expect(tabsState().tabs.every((t) => t.panes.length == 1), isTrue);
  });
}
