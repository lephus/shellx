part of 'terminal_tabs.dart';

// A5a D7–D10, D16, D17: reopening the saved tabs. Kept apart from the
// tab list's everyday operations; it uses the same internals ([_attach],
// [_merge] holds, [_set]).

/// A5a D7: some saved panes could not be reopened. Neutral toast.
final class RestorePanesFailedNotice extends TabNotice {
  const RestorePanesFailedNotice(this.count);
  final int count;
}

/// What restore needs: the checked snapshot and, per pane key, the saved
/// text already followed by its divider (A5a D8).
final class RestorePlan {
  const RestorePlan({required this.snapshot, required this.textByKey});
  final RestoreSnapshot snapshot;
  final Map<String, String> textByKey;
}

final class RestoreOutcome {
  const RestoreOutcome({
    required this.keyBySession,
    required this.tabIdByKey,
    required this.panesFailed,
  });

  /// The saved pane key of every reopened session.
  final Map<int, String> keyBySession;

  /// The new tab id of every restored tab, by saved tab key.
  final Map<String, int> tabIdByKey;
  final int panesFailed;
  int get tabsRestored => tabIdByKey.length;
}

/// A5a criterion 1: where a restored tab goes in the sidebar. The tab
/// list writes [pending] just before the tab appears; the sidebar takes
/// the entry when it places the tab — in its saved workspace (null or
/// gone: Default), without expanding anything. The sidebar sets [isShown]
/// while it exists, so restore's D10 fallback picks a tab the user sees.
final class RestorePlacement {
  final pending = <int, String?>{};

  /// Whether workspace [id] (null: Default) shows its tabs.
  bool Function(String? id)? isShown;
}

final restorePlacementProvider = Provider<RestorePlacement>(
  (ref) => RestorePlacement(),
);

/// Uses [TerminalTabs._ref] and [TerminalTabs._state]: an extension may
/// not touch the notifier's protected `ref` and `state` itself.
extension _Restore on TerminalTabs {
  Future<RestoreOutcome> _runRestore(RestorePlan plan) async {
    final keyBySession = <int, String>{};
    final tabIdByKey = <String, int>{};
    var failed = 0;
    if (_restoring != null) {
      return RestoreOutcome(
        keyBySession: keyBySession,
        tabIdByKey: tabIdByKey,
        panesFailed: 0,
      );
    }
    final done = _restoring = Completer<void>();
    _restoreMaySelect = true;
    final local = _local;
    bool alive() => _ref.mounted && identical(_local, local);
    final snapshot = plan.snapshot;
    final workspaceOf = {
      for (final w in snapshot.workspaces)
        for (final key in w.tabs) key: w.id,
    };
    final order = _restoreOrder(snapshot);
    try {
      for (final saved in order) {
        if (!alive()) break;
        final grids = _restoreGrids(saved.layout, _grid);
        final sessionByKey = <String, int>{};
        for (final pane in savedLeaves(saved.layout)) {
          if (!alive()) break;
          final id = await _openForRestore(
            local,
            pane.cwd,
            grids[pane.key]!,
            plan.textByKey[pane.key],
          );
          if (id == null) {
            failed++;
            continue;
          }
          sessionByKey[pane.key] = id;
          keyBySession[id] = pane.key;
        }
        if (!alive()) break;
        final layout = buildLayout(saved.layout, sessionByKey);
        final ended = <int>[];
        final tab = layout == null
            ? null
            : _assemble(
                saved,
                layout,
                sessionByKey,
                grids,
                workspaceOf[saved.key],
                ended,
              );
        // A pane whose shell ended before its tab was assembled did not
        // come back either (D7).
        failed += ended.length;
        ended.forEach(keyBySession.remove);
        if (tab == null) continue;
        tabIdByKey[saved.key] = tab.id;
        // D7/D10: the saved tab is usable as soon as it is there; when it
        // could not be reopened, the first restored tab the user can see.
        if (_restoreMaySelect &&
            (saved.key == snapshot.selectedTab ||
                _workspaceShown(workspaceOf[saved.key]))) {
          _restoreMaySelect = false;
          _set(selectedId: tab.id);
        }
      }
    } on Object catch (error) {
      // Never throws: what was restored so far stays.
      debugPrint('restore stopped: ${error.runtimeType}');
    } finally {
      if (alive()) {
        _restoreHeld.clear();
        _sync(); // anything opened elsewhere meanwhile becomes its own tab
        if (_restoreMaySelect) {
          // Every restored tab is hidden: the first one in sidebar order.
          final first = order
              .map((t) => tabIdByKey[t.key])
              .whereType<int>()
              .firstOrNull;
          if (first != null) _set(selectedId: first);
        }
        if (failed > 0) _set(notice: RestorePanesFailedNotice(failed));
      }
      _restoreMaySelect = false;
      _restoring = null;
      done.complete();
    }
    return RestoreOutcome(
      keyBySession: keyBySession,
      tabIdByKey: tabIdByKey,
      panesFailed: failed,
    );
  }

  /// D7: the selected tab first, then sidebar order, then any tab no
  /// workspace lists.
  List<SavedTab> _restoreOrder(RestoreSnapshot snapshot) {
    final byKey = {for (final t in snapshot.tabs) t.key: t};
    final keys = <String>[
      ?snapshot.selectedTab,
      for (final w in snapshot.workspaces) ...w.tabs,
      for (final t in snapshot.tabs) t.key,
    ];
    final seen = <String>{};
    return [
      for (final key in keys)
        if (byKey.containsKey(key) && seen.add(key)) byKey[key]!,
    ];
  }

  bool _workspaceShown(String? id) =>
      _ref.read(restorePlacementProvider).isShown?.call(id) ?? true;

  /// D17: each leaf's grid estimated from the area grid and the saved
  /// ratios: its share of the area, less a column (row) for a divider on
  /// its right (bottom), and a row for the pane header in a split tab.
  /// The real grid follows at the next layout.
  Map<String, TerminalGrid> _restoreGrids(
    SavedPaneNode layout,
    TerminalGrid area,
  ) {
    final leaves = savedLeaves(layout);
    final index = {for (var i = 0; i < leaves.length; i++) leaves[i].key: i};
    final rects = paneRects(buildLayout(layout, index)!);
    const eps = 1e-6;
    final split = leaves.length > 1;
    return {
      for (final MapEntry(key: key, value: i) in index.entries)
        key: () {
          final r = rects[i]!;
          final cols =
              (r.width * area.cols + eps).floor() - (r.right < 1 - eps ? 1 : 0);
          final rows =
              (r.height * area.rows + eps).floor() -
              (r.bottom < 1 - eps ? 1 : 0) -
              (split ? 1 : 0);
          return (cols: max(1, cols), rows: max(1, rows));
        }(),
    };
  }

  /// Null when the pane cannot be reopened (spawn error, session limit,
  /// anything unexpected: restore never throws).
  Future<int?> _openForRestore(
    LocalSessions local,
    String? cwd,
    TerminalGrid grid,
    String? text,
  ) async {
    _awaitingOpens++;
    try {
      final id = await local.open(cols: grid.cols, rows: grid.rows, cwd: cwd);
      // Held before the count drops: a change event of this open must
      // never make the session a tab of its own.
      if (identical(_local, local)) {
        _restoreHeld.add(id);
        if (text != null) _restoreText[id] = text;
      }
      return id;
    } on SessionLimitException {
      return null;
    } on SpawnFailedException {
      return null;
    } on Object catch (error) {
      debugPrint('restore: a pane did not open: ${error.runtimeType}');
      return null;
    } finally {
      _awaitingOpens--;
    }
  }

  /// Attaches the reopened sessions and adds the tab; null when none of
  /// them is alive any more. Sessions that ended in the meantime are added
  /// to [ended].
  TerminalTab? _assemble(
    SavedTab saved,
    PaneNode layout,
    Map<String, int> sessionByKey,
    Map<String, TerminalGrid> grids,
    String? workspaceId,
    List<int> ended,
  ) {
    final summaries = {for (final s in _local.sessions) s.id: s};
    final keyOf = {for (final e in sessionByKey.entries) e.value: e.key};
    final panes = <int, PaneSession>{};
    var tree = layout;
    for (final id in paneIds(layout)) {
      _restoreHeld.remove(id);
      final summary = summaries[id];
      final pane = summary == null
          ? null
          : _attach(summary, size: grids[keyOf[id]]);
      if (pane == null) {
        ended.add(id);
        _restoreText.remove(id);
        tree = removePane(tree, id) ?? tree;
        continue;
      }
      panes[id] = pane;
    }
    if (panes.isEmpty) return null;
    final order = paneIds(tree);
    final creator = sessionByKey[saved.key];
    final focused = sessionByKey[saved.focused];
    final zoomed = sessionByKey[saved.zoomed];
    final focus = panes.containsKey(focused) ? focused! : order.first;
    final tab = TerminalTab(
      // A3 D1: the creating pane's session; when that pane is gone, the
      // first remaining one — still a session id, never reused.
      id: panes.containsKey(creator) ? creator! : order.first,
      origin: SessionOrigin.desktop,
      layout: tree,
      panes: panes,
      focusedPaneId: focus,
      zoomedPaneId: order.length > 1 && panes.containsKey(zoomed)
          ? zoomed
          : null,
      paneHistory: [focus, ...order.where((id) => id != focus)],
      customTitle: saved.name,
    );
    _ref.read(restorePlacementProvider).pending[tab.id] = workspaceId;
    _set(tabs: [..._state.tabs, tab]);
    return tab;
  }
}
