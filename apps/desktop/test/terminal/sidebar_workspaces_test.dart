import 'dart:ui';

import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/fake_local_sessions.dart';

void main() {
  late FakeLocalSessions local;
  late InMemorySettingsStore settings;
  late ProviderContainer container;

  SidebarWorkspaces sidebar() =>
      container.read(sidebarWorkspacesProvider.notifier);
  SidebarState state() => container.read(sidebarWorkspacesProvider);
  TerminalTabs tabs() => container.read(terminalTabsProvider.notifier);
  int? selected() => container.read(terminalTabsProvider).selectedId;
  List<String>? saved() => settings.strings[SettingKeys.terminalWorkspaces];

  void boot() {
    container = ProviderContainer.test(
      overrides: [
        localSessionsProvider.overrideWithValue(local),
        appL10nProvider.overrideWithValue(
          lookupAppLocalizations(const Locale('en')),
        ),
        settingsStoreProvider.overrideWithValue(settings),
      ],
    );
    state(); // build
  }

  void addDesktop(int id) =>
      local.add(local.summary(id, origin: SessionOrigin.desktop));

  setUp(() {
    local = FakeLocalSessions();
    settings = InMemorySettingsStore();
  });

  group('loadWorkspaces (Review Focus 5)', () {
    test('drops broken, duplicate and nameless entries; Default first when '
        'missing', () {
      final list = loadWorkspaces([
        'not json',
        '{"id": 5}',
        '[1, 2]',
        '{"id":"w1","name":"  Backend  ","collapsed":true}',
        '{"id":"w1","name":"dupe"}',
        '{"id":"w2"}',
        '{"id":"w3","name":"   "}',
        '{"id":"w4","name":"Ops","collapsed":"yes"}',
      ]);
      expect(list.map((w) => w.id), [kDefaultWorkspaceId, 'w1']);
      expect((list[1].name, list[1].collapsed), ('Backend', true));
      expect(loadWorkspaces(const []).single.isDefault, isTrue);
    });

    test('a stored Default keeps its place, name and collapsed state', () {
      final list = loadWorkspaces([
        '{"id":"w1","name":"A"}',
        '{"id":"default","name":"Home","collapsed":true}',
      ]);
      expect(list.map((w) => w.id), ['w1', kDefaultWorkspaceId]);
      expect((list[1].name, list[1].collapsed), ('Home', true));
    });

    test('encode/decode round trip; names are clipped to 64', () {
      final w = Workspace(id: 'w9', name: 'x' * 80, collapsed: true);
      final back = Workspace.decode(w.encode())!;
      expect((back.id, back.name!.length, back.collapsed), ('w9', 64, true));
    });
  });

  test(
    'desktop tabs join the current workspace, phone tabs Default; a '
    'closed tab leaves and its open rename is dropped (Review Focus 4)',
    () async {
      boot();
      await sidebar().create(); // "Workspace 2" with tab 100
      final ws = state().workspaces.last.id;
      expect(state().workspace(ws)!.name, 'Workspace 2');
      expect(state().renaming, RenameWorkspace(ws));
      expect(state().tabsOf(ws), [100]);
      await tabs().openTab(); // current = ws (tab 100 selected)
      expect(state().tabsOf(ws), [100, 101]);
      local.add(local.summary(7, origin: SessionOrigin.phone));
      expect(state().tabsOf(kDefaultWorkspaceId), [7]);
      expect(selected(), 101); // a phone tab is not selected
      sidebar().startRename(const RenameTab(101));
      local.close(101);
      await pumpEventQueue();
      expect(state().tabsOf(ws), [100]);
      expect(state().renaming, isNull);
    },
  );

  test('openTabIn puts the next tab there and expands it, whatever is '
      'selected', () async {
    addDesktop(1);
    boot();
    await sidebar().create(); // ws with tab 100, selected
    final ws = state().workspaces.last.id;
    sidebar().setCollapsed(kDefaultWorkspaceId, true);
    await sidebar().openTabIn(kDefaultWorkspaceId);
    expect(state().tabsOf(kDefaultWorkspaceId), [1, 101]);
    expect(state().workspace(kDefaultWorkspaceId)!.collapsed, isFalse);
    expect(state().tabsOf(ws), [100]);
  });

  test('the visible order skips collapsed workspaces; ⌘N and Ctrl+Tab use '
      'it, also from a hidden selected tab (C5)', () async {
    addDesktop(1);
    addDesktop(2);
    boot();
    await sidebar().create(); // tab 100
    sidebar().endRename();
    expect(state().visibleTabIds, [1, 2, 100]);
    sidebar().selectVisible(1);
    expect(selected(), 1);
    sidebar().step(-1);
    expect(selected(), 100); // wraps
    sidebar().toggleCollapsed(kDefaultWorkspaceId);
    expect(state().visibleTabIds, [100]);
    sidebar().selectVisible(2);
    expect(selected(), 100); // no second visible tab: unchanged
    tabs().select(1); // hidden (a click before collapsing)
    sidebar().step(1);
    expect(selected(), 100);
  });

  test('closing the selected tab selects its neighbour in the sidebar '
      'order: the next visible, else the previous; collapsed workspaces '
      'are skipped (I2)', () async {
    addDesktop(1);
    addDesktop(2);
    addDesktop(3);
    boot();
    sidebar().moveTab(3, kDefaultWorkspaceId, 0); // sidebar: 3, 1, 2
    tabs().select(3);
    tabs().close(3);
    expect(selected(), 1); // creation order would pick 2
    await sidebar().create(); // ws: 100
    final ws = state().workspaces.last.id;
    await sidebar().create(); // ws2: 101
    sidebar().endRename();
    sidebar().setCollapsed(ws, true); // visible: 1, 2, 101
    tabs().select(2);
    tabs().close(2);
    expect(selected(), 101); // 100 is hidden
    tabs().close(101); // the last visible: the previous one
    expect(selected(), 1);
  });

  test(
    'closing a selected tab hidden in a collapsed workspace picks the '
    'nearest visible tab; with none visible, the sidebar order (I2)',
    () async {
      addDesktop(1);
      addDesktop(2);
      boot();
      await sidebar().create(); // ws: 100
      final ws = state().workspaces.last.id;
      await sidebar().create(); // ws2: 101
      sidebar().endRename();
      final ws2 = state().workspaces.last.id;
      sidebar().moveTab(2, ws, 0); // Default [1], ws [2, 100], ws2 [101]
      sidebar().setCollapsed(ws, true);
      tabs().select(2); // hidden
      tabs().close(2);
      expect(selected(), 101); // the nearest visible tab below
      sidebar().setCollapsed(kDefaultWorkspaceId, true);
      sidebar().setCollapsed(ws2, true); // nothing visible
      tabs().select(100);
      tabs().close(100);
      expect(selected(), 101); // next in the sidebar order
    },
  );

  test('tab and workspace names are cut on whole characters, then trimmed '
      '(M2)', () async {
    addDesktop(1);
    boot();
    final accented = 'e\u0301' * 70; // 70 user-perceived characters
    tabs().rename(1, accented);
    final label = container.read(terminalTabsProvider).tabs.single.label;
    expect(label.characters.length, 64);
    expect(label, 'e\u0301' * 64);
    tabs().rename(1, '${'x' * 63} y');
    expect(container.read(terminalTabsProvider).tabs.single.label, 'x' * 63);
    await sidebar().create();
    final ws = state().workspaces.last.id;
    sidebar().rename(ws, accented);
    expect(state().workspace(ws)!.name, 'e\u0301' * 64);
    sidebar().rename(ws, '${'z' * 63} w');
    expect(state().workspace(ws)!.name, 'z' * 63);
    final decoded = Workspace.decode(
      Workspace(id: 'w1', name: '${'q' * 63} r').encode(),
    )!;
    expect(decoded.name, 'q' * 63);
  });

  test('with one workspace, collapsed is ignored (no headers, D10)', () {
    addDesktop(1);
    boot();
    sidebar().setCollapsed(kDefaultWorkspaceId, true);
    expect(state().showHeaders, isFalse);
    expect(state().visibleTabIds, [1]);
  });

  test('moveTab reorders and crosses workspaces; move up/down cross '
      'boundaries; a target expands (D18)', () async {
    addDesktop(1);
    addDesktop(2);
    addDesktop(3);
    boot();
    sidebar().moveTab(1, kDefaultWorkspaceId, 3);
    expect(state().tabsOf(kDefaultWorkspaceId), [2, 3, 1]);
    sidebar().moveUp(1);
    expect(state().tabsOf(kDefaultWorkspaceId), [2, 1, 3]);
    expect(sidebar().canMoveUp(2), isFalse);
    expect(sidebar().canMoveDown(3), isFalse); // one workspace: the end
    await sidebar().create(); // tab 100
    final ws = state().workspaces.last.id;
    expect(sidebar().canMoveDown(3), isTrue);
    sidebar().moveDown(3); // last of Default → first of ws
    expect(state().tabsOf(ws), [3, 100]);
    sidebar().moveUp(3);
    expect(state().tabsOf(kDefaultWorkspaceId), [2, 1, 3]);
    sidebar().setCollapsed(ws, true);
    sidebar().moveTab(2, ws);
    expect(state().tabsOf(ws), [100, 2]);
    expect(state().workspace(ws)!.collapsed, isFalse);
  });

  test('delete: tabs to the end of Default (expanded), a neutral notice; '
      'Default cannot be deleted; the list persists (D11, D16, D17)', () async {
    addDesktop(1);
    boot();
    await sidebar().create(); // tab 100
    final ws = state().workspaces.last.id;
    sidebar().rename(ws, '  Backend  ');
    sidebar().rename(ws, '   '); // blank keeps the name
    sidebar().setCollapsed(kDefaultWorkspaceId, true);
    final stored = loadWorkspaces(saved()!);
    expect(stored.map((w) => (w.name, w.collapsed)), [
      (null, true),
      ('Backend', false),
    ]);
    sidebar().delete(kDefaultWorkspaceId);
    expect(state().workspaces, hasLength(2));
    sidebar().delete(ws);
    expect(state().workspaces.single.isDefault, isTrue);
    expect(state().tabsOf(kDefaultWorkspaceId), [1, 100]);
    expect(state().workspaces.single.collapsed, isFalse);
    final notice =
        container.read(terminalTabsProvider).notice! as WorkspaceDeletedNotice;
    expect((notice.name, notice.movedTo), ('Backend', 'Default'));
    expect(saved(), hasLength(1));
  });

  test('numbered names take the smallest free number', () async {
    boot();
    await sidebar().create();
    await sidebar().create();
    final names = [for (final w in state().workspaces) w.name];
    expect(names, [null, 'Workspace 2', 'Workspace 3']);
    sidebar().rename(state().workspaces[1].id, 'API');
    await sidebar().create();
    expect(state().workspaces.last.name, 'Workspace 2');
  });

  test(
    'a new container over the same settings gets the same workspaces',
    () async {
      boot();
      await sidebar().create();
      sidebar().rename(state().workspaces.last.id, 'Ops');
      container.dispose();
      local = FakeLocalSessions(); // sessions end with the app
      boot();
      expect(state().workspaces.map((w) => w.name), [null, 'Ops']);
      expect(state().tabsOf(state().workspaces.last.id), isEmpty);
    },
  );
}
