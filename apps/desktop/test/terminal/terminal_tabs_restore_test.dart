import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/restore/restore_snapshot.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/fake_local_sessions.dart';

final k1 = '1' * 32, k2 = '2' * 32, k3 = '3' * 32, k4 = '4' * 32;

late FakeLocalSessions local;
late ProviderContainer container;
late InMemorySettingsStore settings;
TerminalTabs tabs() => container.read(terminalTabsProvider.notifier);
TerminalTabsState state() => container.read(terminalTabsProvider);
SidebarState sidebar() => container.read(sidebarWorkspacesProvider);

void boot({List<String> workspaces = const []}) {
  settings = InMemorySettingsStore()
    ..strings[SettingKeys.terminalWorkspaces] = workspaces;
  container = ProviderContainer.test(
    overrides: [
      localSessionsProvider.overrideWithValue(local),
      settingsStoreProvider.overrideWithValue(settings),
      appL10nProvider.overrideWithValue(
        lookupAppLocalizations(const Locale('en')),
      ),
    ],
  );
  container.read(sidebarWorkspacesProvider);
}

Future<RestoreOutcome> restore([RestoreSnapshot? s]) =>
    tabs().restore(RestorePlan(snapshot: s ?? snapshot(), textByKey: const {}));

/// Tab A (k1 | k2, ratio 0.3, k2 focused+zoomed) in workspace w2;
/// tab B (k3) in default, selected.
RestoreSnapshot snapshot() => RestoreSnapshot(
  savedAt: DateTime.utc(2026, 10, 7, 14, 32),
  cleanExit: true,
  selectedTab: k3,
  workspaces: [
    SavedWorkspace(id: 'default', tabs: [k3]),
    SavedWorkspace(id: 'w2', tabs: [k1]),
  ],
  tabs: [
    SavedTab(
      key: k1,
      name: 'server',
      focused: k2,
      zoomed: k2,
      layout: SavedSplit(
        axis: SplitAxis.row,
        ratio: 0.3,
        first: SavedPane(key: k1, cwd: '/w/api'),
        second: SavedPane(key: k2, cwd: '/w/web'),
      ),
    ),
    SavedTab(
      key: k3,
      focused: k3,
      layout: SavedPane(key: k3, cwd: '/w/x'),
    ),
  ],
);

int sessionOf(RestoreOutcome out, String key) =>
    out.keyBySession.entries.firstWhere((e) => e.value == key).key;

void main() {
  setUp(() => local = FakeLocalSessions());

  test(
    'opens the selected tab first, then sidebar order, with cwd (D7)',
    () async {
      boot(
        workspaces: [
          '{"id":"default","collapsed":false}',
          '{"id":"w2","name":"API","collapsed":false}',
        ],
      );
      final out = await restore();
      expect(local.openCwds, ['/w/x', '/w/api', '/w/web']);
      expect(out.tabsRestored, 2);
      expect(out.panesFailed, 0);
      expect(out.keyBySession.values.toSet(), {k1, k2, k3});
      expect(tabs().restoring, isFalse);
    },
  );

  test(
    'rebuilds tree, ratio, focus, zoom, name; selects the saved tab (D10)',
    () async {
      boot();
      final out = await restore();
      final a = state().tabs.firstWhere((t) => t.id == out.tabIdByKey[k1]);
      final split = a.layout as PaneSplit;
      expect(split.ratio, 0.3);
      expect(split.axis, SplitAxis.row);
      expect(a.paneOrder, [sessionOf(out, k1), sessionOf(out, k2)]);
      final s2 = sessionOf(out, k2);
      expect(a.focusedPaneId, s2);
      expect(a.zoomedPaneId, s2);
      expect(a.customTitle, 'server');
      expect(a.origin, SessionOrigin.desktop);
      expect(out.tabIdByKey[k1], sessionOf(out, k1));
      expect(state().selectedId, out.tabIdByKey[k3]);
    },
  );

  test('saved text + divider come before the backlog; nothing is written to '
      'the session (D8)', () async {
    boot();
    local.nextBacklog = 'PROMPT% ';
    await tabs().restore(
      RestorePlan(
        snapshot: snapshot(),
        textByKey: {
          k3:
              'old line\r\n\x1b[0m\x1b[2m— Session restored · 14:32 —'
              '\x1b[0m\r\n',
        },
      ),
    );
    final tab = state().selected!;
    final lines = [
      for (var i = 0; i < tab.terminal.mainBuffer.lines.length; i++)
        tab.terminal.mainBuffer.lines[i].getText().trimRight(),
    ].where((l) => l.isNotEmpty).toList();
    expect(lines.take(3), [
      'old line',
      '— Session restored · 14:32 —',
      'PROMPT%',
    ]);
    // Only the pane that had saved text shows it.
    final other = state().tabs.firstWhere((t) => t.id != tab.id);
    for (final pane in other.panes.values) {
      final text = [
        for (var i = 0; i < pane.terminal.mainBuffer.lines.length; i++)
          pane.terminal.mainBuffer.lines[i].getText(),
      ].join();
      expect(text, isNot(contains('restored')));
    }
    for (final view in local.views.values) {
      expect(view.writes, isEmpty);
      expect(view.replies, isEmpty);
    }
  });

  test('failed panes are dropped, an empty tab is skipped, one neutral '
      'toast (D7)', () async {
    boot();
    local.failOpens = {'/w/api', '/w/x'};
    final out = await restore();
    expect(out.panesFailed, 2);
    expect(out.tabsRestored, 1);
    expect(state().tabs.single.layout, isA<PaneLeaf>());
    expect(state().tabs.single.zoomedPaneId, isNull);
    expect(state().notice, isA<RestorePanesFailedNotice>());
    expect((state().notice! as RestorePanesFailedNotice).count, 2);
  });

  test('restore never throws: an unexpected open error counts as a failed '
      'pane', () async {
    boot();
    local.openError = StateError('boom');
    final logged = <String?>[];
    final print = debugPrint;
    debugPrint = (message, {wrapWidth}) => logged.add(message);
    addTearDown(() => debugPrint = print);
    final out = await restore();
    // The error type only: never a directory (privacy).
    expect(logged, everyElement(isNot(contains('/w/'))));
    expect(logged, isNotEmpty);
    expect(out.panesFailed, 3);
    expect(out.tabsRestored, 0);
    expect(state().tabs, isEmpty);
  });

  test('a session opened elsewhere during restore becomes its own tab and is '
      'never grafted into a restored tree (Review Focus 1)', () async {
    boot();
    local.notifyOnOpen = true;
    local.openGate = Completer<void>();
    final restoring = restore();
    local.add(local.summary(77)); // a phone opens a session meanwhile
    local.openGate!.complete();
    local.openGate = null;
    final out = await restoring;
    expect(state().tabs.map((t) => t.id), contains(77));
    expect(state().tabs.where((t) => t.paneOrder.contains(77)).single.id, 77);
    expect(out.keyBySession.keys, isNot(contains(77)));
    expect(state().tabs.length, 3);
    // Every restored session sits in exactly one restored tab.
    for (final id in out.keyBySession.keys) {
      expect(state().tabs.where((t) => t.panes.containsKey(id)), hasLength(1));
    }
  });

  test('⌘T during restore is placed and selected at once; restore does not '
      'take the selection back (D16)', () async {
    boot();
    local.notifyOnOpen = true;
    final gate = Completer<void>();
    local.openGate = gate;
    final restoring = restore();
    expect(tabs().restoring, isTrue);
    local.openGate = null; // ⌘T's own open goes through
    await tabs().openTab();
    final own = state().selectedId;
    expect(own, isNotNull);
    expect(state().tabs.map((t) => t.id), [own]);
    expect(state().opening, isFalse);
    gate.complete();
    final out = await restoring;
    expect(out.tabsRestored, 2);
    expect(state().selectedId, own);
    expect(state().tabs.length, 3);
  });

  test('a split during restore joins its tab at once (D16)', () async {
    local.add(local.summary(5));
    boot();
    local.notifyOnOpen = true;
    final gate = Completer<void>();
    local.openGate = gate;
    final restoring = restore();
    local.openGate = null;
    tabs().select(5);
    await tabs().split(SplitAxis.row);
    expect(state().tabs.firstWhere((t) => t.id == 5).paneCount, 2);
    gate.complete();
    await restoring;
    expect(state().tabs.firstWhere((t) => t.id == 5).paneCount, 2);
  });

  test('an activation during restore adds no tab; with nothing restored it '
      'opens one afterwards (D16)', () async {
    boot();
    final gate = Completer<void>();
    local.openGate = gate;
    final restoring = restore();
    final activation = tabs().ensureTab();
    gate.complete();
    local.openGate = null;
    await restoring;
    await activation;
    expect(state().tabs.length, 2);

    local = FakeLocalSessions()..failOpens = {'/w/x', '/w/api', '/w/web'};
    boot();
    final gate2 = Completer<void>();
    local.openGate = gate2;
    final again = restore();
    final activation2 = tabs().ensureTab();
    gate2.complete();
    await again;
    local.openGate = null;
    await activation2;
    expect(state().tabs.length, 1);
  });

  test('the saved selected tab is selected as soon as it is assembled; the '
      'others open after it (D7, criterion 10)', () async {
    boot();
    final later = Completer<void>();
    local.afterOpen = (id) {
      if (id == 100) local.openGate = later;
    };
    final restoring = restore();
    await pumpEventQueue();
    expect(state().tabs.length, 1);
    expect(state().selectedId, 100);
    later.complete();
    local.openGate = null;
    await restoring;
    expect(state().selectedId, 100);
    expect(state().tabs.length, 2);
  });

  test('D10: the saved selected tab fails → the first restored tab in '
      'sidebar order, not a phone tab', () async {
    local.add(local.summary(5));
    boot();
    local.failOpens = {'/w/x'};
    final out = await restore();
    expect(state().selectedId, out.tabIdByKey[k1]);
  });

  test(
    'D10: the fallback skips tabs hidden in a collapsed workspace',
    () async {
      boot(
        workspaces: [
          '{"id":"w2","name":"API","collapsed":true}',
          '{"id":"default","collapsed":false}',
        ],
      );
      final s = RestoreSnapshot(
        savedAt: DateTime.utc(2026, 10, 7),
        cleanExit: true,
        selectedTab: k3,
        workspaces: [
          SavedWorkspace(id: 'w2', tabs: [k1]),
          SavedWorkspace(id: 'default', tabs: [k3, k4]),
        ],
        tabs: [
          SavedTab(
            key: k1,
            focused: k1,
            layout: SavedPane(key: k1, cwd: '/w/api'),
          ),
          SavedTab(
            key: k3,
            focused: k3,
            layout: SavedPane(key: k3, cwd: '/w/x'),
          ),
          SavedTab(
            key: k4,
            focused: k4,
            layout: SavedPane(key: k4, cwd: '/w/y'),
          ),
        ],
      );
      local.failOpens = {'/w/x'};
      final out = await restore(s);
      expect(state().selectedId, out.tabIdByKey[k4]);
    },
  );

  test('restored tabs go to their saved workspaces; collapsed workspaces '
      'stay collapsed (criterion 1)', () async {
    final stored = [
      '{"id":"default","collapsed":true}',
      '{"id":"w2","name":"API","collapsed":true}',
    ];
    boot(workspaces: stored);
    final out = await restore();
    await pumpEventQueue();
    expect(sidebar().tabsOf('w2'), [out.tabIdByKey[k1]]);
    expect(sidebar().tabsOf('default'), [out.tabIdByKey[k3]]);
    expect(sidebar().workspace('w2')!.collapsed, isTrue);
    expect(sidebar().workspace('default')!.collapsed, isTrue);
    expect(settings.strings[SettingKeys.terminalWorkspaces], stored);
  });

  test('D17: each pane opens at a grid estimated from the area and the saved '
      'ratios', () async {
    boot();
    tabs().reportGrid((cols: 101, rows: 41));
    final out = await restore();
    // B (one pane): the whole grid. A (row split 0.3): 30.3 → 30 columns
    // less the divider, 70.7 → 70; one row less for the pane header.
    expect(local.opens, [(101, 41), (29, 40), (70, 40)]);
    final a = state().tabs.firstWhere((t) => t.id == out.tabIdByKey[k1]);
    expect(a.panes[sessionOf(out, k1)]!.terminal.viewWidth, 29);
    expect(a.panes[sessionOf(out, k2)]!.terminal.viewWidth, 70);
    expect(a.panes[sessionOf(out, k2)]!.terminal.viewHeight, 40);
  });

  test(
    'adopt places tabs in their workspaces; unknown workspace → Default',
    () async {
      boot(
        workspaces: [
          '{"id":"default","collapsed":false}',
          '{"id":"w2","name":"API","collapsed":true}',
        ],
      );
      final out = await restore();
      container
          .read(sidebarWorkspacesProvider.notifier)
          .adopt(
            snapshot().workspaces,
            out.tabIdByKey,
            selectedTabId: out.tabIdByKey[k3],
          );
      expect(sidebar().tabsOf('w2'), [out.tabIdByKey[k1]]);
      expect(sidebar().tabsOf('default'), [out.tabIdByKey[k3]]);
      expect(sidebar().currentId, 'default');
      expect(sidebar().workspace('w2')!.collapsed, isTrue);

      local = FakeLocalSessions();
      boot(); // fresh sessions; only Default exists now
      final again = await restore();
      container
          .read(sidebarWorkspacesProvider.notifier)
          .adopt(snapshot().workspaces, again.tabIdByKey);
      expect(
        sidebar().tabsOf('default').toSet(),
        again.tabIdByKey.values.toSet(),
      );
    },
  );

  test('adopt restores the saved order inside a workspace', () async {
    boot();
    final s = RestoreSnapshot(
      savedAt: DateTime.utc(2026, 10, 7),
      cleanExit: true,
      selectedTab: k4,
      workspaces: [
        SavedWorkspace(id: 'default', tabs: [k3, k4]),
      ],
      tabs: [
        SavedTab(
          key: k3,
          focused: k3,
          layout: SavedPane(key: k3, cwd: '/w/x'),
        ),
        SavedTab(
          key: k4,
          focused: k4,
          layout: SavedPane(key: k4, cwd: '/w/y'),
        ),
      ],
    );
    final out = await restore(s);
    container
        .read(sidebarWorkspacesProvider.notifier)
        .adopt(s.workspaces, out.tabIdByKey, selectedTabId: out.tabIdByKey[k4]);
    expect(sidebar().tabsOf('default'), [
      out.tabIdByKey[k3],
      out.tabIdByKey[k4],
    ]);
  });

  test('paneOutputs reports the session that printed', () async {
    local.add(local.summary(5));
    boot();
    final seen = <int>[];
    final sub = tabs().paneOutputs.listen(seen.add);
    local.views[5]!.emit('hi');
    await pumpEventQueue();
    expect(seen, [5]);
    await sub.cancel();
  });

  test('paneOutputs keeps working after the tab list rebuilds', () async {
    local.add(local.summary(5));
    var current = local;
    final source = Provider<LocalSessions>((ref) => current);
    container = ProviderContainer.test(
      overrides: [
        localSessionsProvider.overrideWith((ref) => ref.watch(source)),
        appL10nProvider.overrideWithValue(
          lookupAppLocalizations(const Locale('en')),
        ),
      ],
    );
    state();
    final notifier = tabs();
    final seen = <int>[];
    final sub = notifier.paneOutputs.listen(seen.add);
    current = FakeLocalSessions()..add(local.summary(6));
    container.invalidate(source);
    expect(state().tabs.single.id, 6);
    await pumpEventQueue();
    expect(identical(tabs(), notifier), isTrue);
    current.views[6]!.emit('hi');
    await pumpEventQueue();
    expect(seen, [6]);
    await sub.cancel();
  });
}
