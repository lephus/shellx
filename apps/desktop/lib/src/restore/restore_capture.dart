import '../terminal/pane_layout.dart';
import '../terminal/sidebar_workspaces.dart';
import '../terminal/terminal_tabs.dart';
import 'restore_snapshot.dart';

/// What is restorable right now (D9: exited panes and tabs left with no
/// live pane are skipped). [keyOf] gives each session its pane key (D14);
/// a tab's key is that of the session that created it (A3 D1), kept even
/// after that pane has closed.
RestoreSnapshot captureSnapshot({
  required TerminalTabsState tabs,
  required SidebarState sidebar,
  required String Function(int sessionId) keyOf,
  required DateTime now,
  required bool cleanExit,
  String? daemon,
}) {
  final saved = <int, SavedTab>{};
  for (final tab in tabs.tabs) {
    final layout = _save(tab.layout, tab, keyOf);
    if (layout == null) continue;
    final leaves = savedLeaves(layout);
    final keys = {for (final p in leaves) p.key};
    String? live(int? id) {
      if (id == null) return null;
      final key = keyOf(id);
      return keys.contains(key) ? key : null;
    }

    saved[tab.id] = SavedTab(
      key: keyOf(tab.id),
      name: tab.customTitle,
      focused: live(tab.focusedPaneId) ?? leaves.first.key,
      zoomed: live(tab.zoomedPaneId),
      layout: layout,
    );
  }
  final ordered = sidebar.orderedTabIds;
  final placed = ordered.toSet();
  return RestoreSnapshot(
    savedAt: now,
    cleanExit: cleanExit,
    daemon: daemon,
    selectedTab: saved[tabs.selectedId]?.key,
    workspaces: [
      for (final w in sidebar.workspaces)
        SavedWorkspace(
          id: w.id,
          tabs: [for (final id in sidebar.tabsOf(w.id)) ?saved[id]?.key],
        ),
    ],
    tabs: [
      for (final id in ordered) ?saved[id],
      // Tabs the sidebar has not placed yet keep creation order.
      for (final t in tabs.tabs)
        if (!placed.contains(t.id)) ?saved[t.id],
    ],
  );
}

SavedPaneNode? _save(
  PaneNode node,
  TerminalTab tab,
  String Function(int) keyOf,
) => switch (node) {
  PaneLeaf(:final sessionId) => switch (tab.panes[sessionId]) {
    final pane? when !pane.exited => SavedPane(
      key: keyOf(sessionId),
      cwd: switch (pane.cwd) {
        final cwd? when isRestorableCwd(cwd) => cwd,
        _ => null,
      },
      session: sessionId,
    ),
    _ => null,
  },
  PaneSplit(:final axis, :final ratio, :final first, :final second) => switch ((
    _save(first, tab, keyOf),
    _save(second, tab, keyOf),
  )) {
    (null, final b) => b,
    (final a, null) => a,
    (final a?, final b?) => SavedSplit(
      axis: axis,
      ratio: ratio,
      first: a,
      second: b,
    ),
  },
};
