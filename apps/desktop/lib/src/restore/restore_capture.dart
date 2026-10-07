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
    final layout = savePaneTree(tab.layout, tab, keyOf);
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

/// [tab]'s pane tree as saved panes (A5a D9, public for A11 D14's closed
/// tabs). With [includeExited] a pane whose shell ended is kept too: a
/// closed tab's text is worth reopening even when its shell is gone.
SavedPaneNode? savePaneTree(
  PaneNode node,
  TerminalTab tab,
  String Function(int) keyOf, {
  bool includeExited = false,
}) => switch (node) {
  PaneLeaf(:final sessionId) => switch (tab.panes[sessionId]) {
    // A8 D29: a remote pane that lost its connection can reconnect, so it
    // is saved; an exited local one (or a remote one that ended for good)
    // is not.
    final pane? when includeExited || !pane.exited || pane.canReconnect =>
      SavedPane(
        key: keyOf(sessionId),
        // A remote pane's folder is the server's: it travels in the launch.
        cwd: switch (pane.cwd) {
          final cwd? when pane.remote == null && isRestorableCwd(cwd) => cwd,
          _ => null,
        },
        session: sessionId,
        launch: pane.remote?.launch.forReconnect(pane.cwd),
      ),
    _ => null,
  },
  PaneSplit(:final axis, :final ratio, :final first, :final second) => switch ((
    savePaneTree(first, tab, keyOf, includeExited: includeExited),
    savePaneTree(second, tab, keyOf, includeExited: includeExited),
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
