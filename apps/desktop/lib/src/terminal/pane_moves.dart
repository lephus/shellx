import 'dart:math' show min;

import 'package:shellx_agent/shellx_agent.dart' show SessionOrigin;

import 'pane_layout.dart';
import 'terminal_tabs.dart';

// A11 D20: swap, break and move panes. Pure: each function takes tabs and
// gives tabs, never touching a session — a moved pane is the same
// [PaneSession] (same terminal, same scrollback, same shell), only its tab
// changes, so nothing is closed, restarted or re-opened.

/// [node] with the sessions of leaves [a] and [b] exchanged; the tree's
/// shape, axes and ratios stay. Unchanged when either is absent or they are
/// the same pane.
PaneNode swapLeaves(PaneNode node, int a, int b) {
  if (a == b) return node;
  final ids = paneIds(node);
  if (!ids.contains(a) || !ids.contains(b)) return node;
  // A6: browser panes have negative ids, so the temporary leaf takes an id
  // below every leaf of the tree instead of a fixed one.
  final tmp = ids.reduce(min) - 1;
  return replaceLeaf(replaceLeaf(replaceLeaf(node, a, tmp), b, a), tmp, b);
}

/// [from] swapped with the pane next to it in [d] (the geometry decides,
/// A3 D9); null when there is none.
PaneNode? swapInDirection(
  PaneNode node,
  int from,
  PaneDirection d, {
  List<int> mru = const [],
}) {
  final other = neighbourPane(node, from, d, mru: mru);
  return other == null ? null : swapLeaves(node, from, other);
}

/// [tab] without pane [paneId] (which is not the only one): the sibling
/// takes its place; the focus goes to the most recently used pane left; a
/// zoom on that pane, or on a tab left with one pane, ends.
TerminalTab _without(TerminalTab tab, int paneId) {
  final layout = removePane(tab.layout, paneId)!;
  final remaining = paneIds(layout);
  final history = [
    for (final id in tab.paneHistory)
      if (id != paneId && remaining.contains(id)) id,
  ];
  var focused = tab.focusedPaneId;
  if (focused == paneId) {
    focused =
        history.firstOrNull ??
        siblingLeaf(tab.layout, paneId) ??
        remaining.first;
  }
  final zoomed = tab.zoomedPaneId == paneId || remaining.length == 1
      ? null
      : tab.zoomedPaneId;
  return tab.copyWith(
    layout: layout,
    panes: Map.of(tab.panes)..remove(paneId),
    focusedPaneId: focused,
    paneHistory: [focused, ...history.where((id) => id != focused)],
    zoomedPaneId: zoomed,
  );
}

/// A pane taken out of a tab to stand alone.
typedef BrokenPane = ({TerminalTab from, TerminalTab detached});

/// Pane [paneId] of [tab] becomes a tab of its own. Null when the tab has
/// only that pane (nothing to break) or does not hold it. The new tab's id
/// is [detachedId], by default the pane's own id (a tab id is a session id,
/// A3 D1); the caller names another when that id is already a tab's (the
/// pane's creating tab is still around). The old tab keeps its id, title and
/// place.
BrokenPane? breakPane(TerminalTab tab, int paneId, {int? detachedId}) {
  final pane = tab.panes[paneId];
  if (pane == null || !tab.isSplit) return null;
  // A6 D5: the last terminal pane stays with its tab's browser panes.
  if (tab.panes.length == 1 && tab.browsers.isNotEmpty) return null;
  return (
    from: _without(tab, paneId),
    detached: TerminalTab(
      id: detachedId ?? paneId,
      origin: pane.origin,
      layout: PaneLeaf(paneId),
      panes: {paneId: pane},
      focusedPaneId: paneId,
      paneHistory: [paneId],
    ),
  );
}

/// A pane moved into another tab; [from] is null when it was its tab's only
/// pane (the tab goes, the session stays).
typedef MovedPane = ({TerminalTab? from, TerminalTab to});

/// Pane [paneId] of [from] splits the focused pane of [to] (to its right,
/// or below with [SplitAxis.column]) and takes the focus; a zoom in [to]
/// ends so the pane is seen. Null when [from] and [to] are the same tab or
/// [from] does not hold the pane.
MovedPane? joinPane(
  TerminalTab from,
  TerminalTab to,
  int paneId, {
  SplitAxis axis = SplitAxis.row,
}) {
  final pane = from.panes[paneId];
  if (pane == null || from.id == to.id || to.panes.containsKey(paneId)) {
    return null;
  }
  if (from.panes.length == 1 && from.browsers.isNotEmpty) return null; // D5
  final joined = to.copyWith(
    // A desktop pane in a tab a phone opened: the user made it theirs.
    origin: pane.origin == SessionOrigin.desktop ? SessionOrigin.desktop : null,
    layout: splitPane(to.layout, to.focusedPaneId, paneId, axis),
    panes: {...to.panes, paneId: pane},
    focusedPaneId: paneId,
    zoomedPaneId: null,
    paneHistory: [paneId, ...to.paneHistory],
  );
  return (from: from.isSplit ? _without(from, paneId) : null, to: joined);
}
