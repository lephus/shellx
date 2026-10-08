import 'dart:ui' show Locale;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/restore/restore_capture.dart';
import 'package:shellx_desktop/src/restore/restore_snapshot.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/tab_meta.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/fake_local_sessions.dart';

final k1 = 'a' * 32, k2 = 'b' * 32, k3 = 'c' * 32;

void main() {
  late FakeLocalSessions local;
  late ProviderContainer container;

  void boot() {
    container = ProviderContainer.test(
      overrides: [
        localSessionsProvider.overrideWithValue(local),
        settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
        appL10nProvider.overrideWithValue(
          lookupAppLocalizations(const Locale('en')),
        ),
      ],
    );
    container.read(sidebarWorkspacesProvider);
  }

  RestoreSnapshot capture(Map<int, String> keys) => captureSnapshot(
    tabs: container.read(terminalTabsProvider),
    sidebar: container.read(sidebarWorkspacesProvider),
    keyOf: (id) => keys[id]!,
    now: DateTime.utc(2026),
    cleanExit: true,
  );

  setUp(() => local = FakeLocalSessions());

  test(
    'captureSnapshot: tabs, membership, names, tree; exited panes skipped',
    () async {
      local
        ..add(local.summary(1, cwd: '/w/one'))
        ..add(local.summary(2));
      boot();
      container.read(terminalTabsProvider.notifier).rename(2, 'logs');
      local.views[1]!.end(3); // exit ≠ 0: kept on screen, not restored
      await pumpEventQueue();
      final s = capture({1: k1, 2: k2});
      expect(s.tabs.map((t) => t.key), [k2]);
      expect(s.tabs.single.name, 'logs');
      expect(s.workspaces.single.tabs, [k2]);
      expect(s.selectedTab, isNull); // the selected tab (1) is not restorable
      expect(s.cleanExit, isTrue);
      expect(s.daemon, isNull);
    },
  );

  test('captureSnapshot: split tree with ratios, cwd, session, focus and '
      'zoom; an exited pane collapses into its sibling', () async {
    local.add(
      local.summary(1, origin: SessionOrigin.desktop, cwd: '/Users/test/w'),
    );
    boot();
    final tabs = container.read(terminalTabsProvider.notifier);
    await tabs.split(SplitAxis.row); // 1 | 100, focus 100
    await tabs.split(SplitAxis.column); // 1 | (100 / 101), focus 101
    tabs.focusPane(100);
    expect(tabs.toggleZoom(), isTrue);
    final keys = {1: k1, 100: k2, 101: k3};

    final whole = capture(keys);
    final tab = whole.tabs.single;
    expect(tab.key, k1);
    expect(tab.name, isNull);
    expect(tab.focused, k2);
    expect(tab.zoomed, k2);
    expect(whole.selectedTab, k1);
    expect(whole.workspaces.single.id, kDefaultWorkspaceId);
    final leaves = savedLeaves(tab.layout);
    expect(leaves.map((p) => p.key), [k1, k2, k3]);
    expect(leaves.map((p) => p.session), [1, 100, 101]);
    expect(leaves.first.cwd, '/Users/test/w');
    expect(
      buildLayout(tab.layout, {k1: 1, k2: 100, k3: 101}),
      container.read(terminalTabsProvider).tabs.single.layout,
    );

    // The creating pane exits ≠ 0: it is skipped, its sibling takes its
    // place, and the tab keeps the creating pane's key (accepted: stable,
    // though no longer a leaf).
    local.views[1]!.end(3);
    await pumpEventQueue();
    final after = capture(keys).tabs.single;
    expect(after.key, k1);
    expect(savedLeaves(after.layout).map((p) => p.key), [k2, k3]);
    expect(after.layout, isA<SavedSplit>());
    expect((after.layout as SavedSplit).axis, SplitAxis.column);
    expect(after.focused, k2);
    // Capture's output always loads back, including a tab key that is no
    // longer a leaf (preflight T2 row).
    expect(RestoreSnapshot.tryParse(whole.encode()), isNotNull);
    expect(RestoreSnapshot.tryParse(capture(keys).encode()), isNotNull);
  });

  test('captureSnapshot: a cwd that would not load is saved as null', () async {
    local
      ..add(local.summary(1, cwd: 'relative/dir'))
      ..add(local.summary(2, cwd: '/tmp/a\u0007b'))
      ..add(local.summary(3, cwd: '/ok'));
    boot();
    final s = capture({1: k1, 2: k2, 3: k3});
    expect(s.tabs.map((t) => savedLeaves(t.layout).single.cwd), [
      null,
      null,
      '/ok',
    ]);
    expect(RestoreSnapshot.tryParse(s.encode()), isNotNull);
  });

  test('captureSnapshot: focus on an exited pane falls back to the first '
      'live pane, a zoom on it is dropped', () async {
    local.add(local.summary(1, origin: SessionOrigin.desktop));
    boot();
    final tabs = container.read(terminalTabsProvider.notifier);
    await tabs.split(SplitAxis.row); // 1 | 100, focus 100
    expect(tabs.toggleZoom(), isTrue);
    local.views[100]!.end(3);
    await pumpEventQueue();
    final tab = capture({1: k1, 100: k2}).tabs.single;
    expect(tab.layout, isA<SavedPane>());
    expect(tab.focused, k1);
    expect(tab.zoomed, isNull);
  });

  test('captureSnapshot: a tab whose creating pane moved to another tab '
      'still saves a layout that loads (A11 review C1)', () async {
    local
      ..add(local.summary(1, origin: SessionOrigin.desktop))
      ..add(local.summary(2, origin: SessionOrigin.desktop));
    boot();
    final tabs = container.read(terminalTabsProvider.notifier);
    tabs.select(1);
    await tabs.split(SplitAxis.row); // tab 1: 1 | 100
    expect(tabs.joinPane(1, 2), isTrue); // pane 1 (tab 1's creator) -> tab 2
    final kt = 'd' * 32;
    final keys = {1: k1, 2: k2, 100: k3, -1: kt};
    final s = capture(keys);
    final loaded = RestoreSnapshot.tryParse(s.encode());
    expect(loaded, isNotNull, reason: 'the whole file must still load');
    expect(loaded!.tabs.map((t) => t.key).toSet(), hasLength(2));
    final first = loaded.tabs.firstWhere(
      (t) => savedLeaves(t.layout).map((p) => p.key).contains(k3),
    );
    expect(first.key, kt, reason: 'not the key of a pane of another tab');
    expect(
      savedLeaves(
        loaded.tabs.firstWhere((t) => t.key == k2).layout,
      ).map((p) => p.key),
      [k2, k1],
    );
  });

  test('captureSnapshot: a pane broken out of the tab it created gets a '
      'tab of its own with a synthetic id and a loadable layout', () async {
    local.add(local.summary(1, origin: SessionOrigin.desktop));
    boot();
    final tabs = container.read(terminalTabsProvider.notifier);
    await tabs.split(SplitAxis.row); // 1 | 100
    expect(tabs.breakPane(1), isTrue);
    final state = container.read(terminalTabsProvider);
    expect(state.tabs.map((t) => t.id), [1, kSyntheticTabIdBase]);
    final kt = 'e' * 32;
    final s = capture({1: k1, 100: k2, kSyntheticTabIdBase: k3, -1: kt});
    expect(RestoreSnapshot.tryParse(s.encode()), isNotNull);
    expect(s.tabs.map((t) => t.key).toSet(), hasLength(2));
  });

  test('captureSnapshot: pin, description and status are saved and survive '
      'a pane move that renames the tab key (A11 D18)', () async {
    local
      ..add(local.summary(1, origin: SessionOrigin.desktop))
      ..add(local.summary(2, origin: SessionOrigin.desktop));
    boot();
    final tabs = container.read(terminalTabsProvider.notifier);
    tabs.select(1);
    await tabs.split(SplitAxis.row); // tab 1: 1 | 100
    tabs.setMeta(
      1,
      (m) => m.copyWith(
        pinned: true,
        description: 'deploy\nstaging',
        status: TabStatus.blocked,
      ),
    );
    expect(tabs.joinPane(1, 2), isTrue); // tab 1's creator moves to tab 2
    final kt = 'd' * 32;
    final s = capture({1: k1, 2: k2, 100: k3, -1: kt});
    final loaded = RestoreSnapshot.tryParse(s.encode())!;
    final first = loaded.tabs.firstWhere((t) => t.key == kt);
    expect(first.pinned, isTrue);
    expect(first.description, 'deploy staging');
    expect(first.status, TabStatus.blocked);
    final second = loaded.tabs.firstWhere((t) => t.key == k2);
    expect(second.pinned, isFalse);
    expect(second.status, TabStatus.none);
  });
}
