import 'dart:async' show scheduleMicrotask;

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../terminal/sidebar_workspaces.dart';
import '../terminal/terminal_tabs.dart';
import '../ui/window_focus.dart' show ProviderReader;
import 'tool_dock_state.dart';
import 'tool_embed.dart';
import 'tool_entry.dart';
import 'tool_registry.dart';

/// Every workspace's dock, and the workspace shown without a tab of its
/// own (D4 [loose]).
final class ToolDocks {
  const ToolDocks({this.byWorkspace = const {}, this.loose});

  final Map<String, ToolDockState> byWorkspace;

  /// D4: a tool of a workspace with no tab opened: that workspace's dock
  /// shows beside an empty content area until a tab is selected.
  final String? loose;

  ToolDockState of(String ws) => byWorkspace[ws] ?? const ToolDockState();

  ToolDocks copyWith({
    Map<String, ToolDockState>? byWorkspace,
    Object? loose = _keep,
  }) => ToolDocks(
    byWorkspace: byWorkspace ?? this.byWorkspace,
    loose: identical(loose, _keep) ? this.loose : loose as String?,
  );

  @override
  bool operator ==(Object other) =>
      other is ToolDocks &&
      other.loose == loose &&
      mapEquals(other.byWorkspace, byWorkspace);

  @override
  int get hashCode => Object.hash(
    loose,
    Object.hashAllUnordered([
      for (final e in byWorkspace.entries) Object.hash(e.key, e.value),
    ]),
  );

  @override
  String toString() => 'ToolDocks(${byWorkspace.length})';
}

const Object _keep = Object();

final toolDockProvider = NotifierProvider<ToolDockController, ToolDocks>(
  ToolDockController.new,
);

/// D3, D4: the workspace whose dock the window shows — the one shown
/// without a tab ([ToolDocks.loose]), else the selected tab's ([selectedId]),
/// else the current one.
String dockWorkspaceOf(
  ToolDocks docks,
  int? selectedId,
  SidebarState sidebar,
) =>
    docks.loose ??
    (selectedId == null ? null : sidebar.workspaceOf(selectedId)) ??
    sidebar.currentId;

/// D3, D4: the selected tab's panes are covered — by the panel of a
/// workspace shown without a tab, or by the shown workspace's dock ([shown])
/// zoomed over them. Exactly what `ToolArea` draws over the panes. A covered
/// pane is not in view (A4's "seen", A12's "watched") and takes no drop.
bool toolPanesCovered(
  ToolDocks docks, {
  required ToolDockState shown,
  required bool embedded,
}) => docks.loose != null || toolDockCoversPanes(shown, embedded: embedded);

/// [toolPanesCovered] for the window as it is, read from its sources with
/// [read] (`ref.read`, `ref.watch` or `container.read`). Inside a listener
/// of one of those sources read it this way, not through
/// [toolPanesCoveredProvider]: a derived provider can still give the old
/// value there (see `windowActiveProvider`).
bool readToolPanesCovered(ProviderReader read) {
  final docks = read(toolDockProvider);
  final ws = dockWorkspaceOf(
    docks,
    read(terminalTabsProvider.select((s) => s.selectedId)),
    read(sidebarWorkspacesProvider),
  );
  return toolPanesCovered(
    docks,
    shown: docks.of(ws),
    embedded: read(toolsEmbeddedProvider),
  );
}

/// [toolPanesCovered] as a provider: listen to it to hear the panes being
/// covered or shown again.
final toolPanesCoveredProvider = Provider<bool>(
  (ref) => readToolPanesCovered(ref.watch),
);

/// V2-3 D3–D5, D14: the docks. A deleted tool leaves every dock; a deleted
/// workspace takes its dock and its tools (D2, §8). Each workspace's last
/// selected tab is remembered for D4 ("the nearest tab").
class ToolDockController extends Notifier<ToolDocks> {
  final _lastTab = <String, int>{};

  /// D10: the tool each workspace showed last — the chip last on show,
  /// however it got there — kept after its chip closed.
  final _lastViewed = <String, String>{};

  @override
  ToolDocks build() {
    ref.listen<List<ToolEntry>>(toolRegistryProvider, (before, after) {
      final ids = {for (final t in after) t.id};
      final gone = {
        for (final t in before ?? const <ToolEntry>[])
          if (!ids.contains(t.id)) t.id,
      };
      for (final id in gone) {
        _dropTool(id);
      }
    });
    ref.listen<SidebarState>(sidebarWorkspacesProvider, (before, after) {
      final now = {for (final w in after.workspaces) w.id};
      for (final w in before?.workspaces ?? const <Workspace>[]) {
        if (now.contains(w.id)) continue;
        _dropWorkspace(w.id);
        ref.read(toolRegistryProvider.notifier).removeWorkspace(w.id);
      }
      if (state.loose != null && after.tabsOf(state.loose!).isNotEmpty) {
        state = state.copyWith(loose: null);
      }
    });
    ref.listen<int?>(terminalTabsProvider.select((s) => s.selectedId), (_, id) {
      if (id == null) return;
      final ws = ref.read(sidebarWorkspacesProvider).workspaceOf(id);
      if (ws != null) _lastTab[ws] = id;
      if (state.loose != null) state = state.copyWith(loose: null);
    });
    scheduleMicrotask(_pruneOrphans);
    return const ToolDocks();
  }

  /// D4: the tab of [ws] the user was last in, if it is still there.
  int? lastTabOf(String ws) {
    final id = _lastTab[ws];
    final sidebar = ref.read(sidebarWorkspacesProvider);
    return id != null && sidebar.tabsOf(ws).contains(id) ? id : null;
  }

  /// D4: [ws]'s dock opens with [toolId] on show.
  void open(String ws, String toolId) => _set(ws, state.of(ws).opened(toolId));

  /// D5: a chip of [ws] on show.
  void activate(String ws, String toolId) =>
      _set(ws, state.of(ws).activated(toolId));

  /// D10: the tool [ws] showed last (it may have been deleted since): the
  /// chip last on show, however it got there — opened or chosen, the one a
  /// closed chip handed over to, or the restored one.
  String? lastViewedOf(String ws) => _lastViewed[ws];

  /// D10, D17 ×: [toolId]'s chip closes (the last one closes the dock).
  void closeTool(String ws, String toolId) {
    final next = state.of(ws).without(toolId);
    _set(ws, next);
    if (!next.open && state.loose == ws) state = state.copyWith(loose: null);
  }

  /// D17 ⋯ "Close tools", ⌘⇧B: hidden; the chips and their pages stay
  /// (D5: closing the dock unloads nothing).
  void close(String ws) {
    final dock = state.of(ws);
    if (!dock.open) return;
    _set(ws, dock.copyWith(open: false, zoom: false));
    if (state.loose == ws) state = state.copyWith(loose: null);
  }

  /// ⌘⇧B with chips: the dock shows again with the tool last on show.
  bool reopen(String ws) {
    final dock = state.of(ws);
    if (dock.open || dock.tools.isEmpty) return false;
    _set(ws, dock.copyWith(open: true));
    return true;
  }

  /// D3 "Expand" / "Restore".
  void setZoom(String ws, bool zoom) {
    final dock = state.of(ws);
    if (dock.open && dock.zoom != zoom) _set(ws, dock.copyWith(zoom: zoom));
  }

  void setWidth(String ws, double fraction) {
    final dock = state.of(ws);
    if (dock.width != fraction) _set(ws, dock.copyWith(width: fraction));
  }

  /// D4: show [ws] (which has no tab) with its dock.
  void showLoose(String ws) => state = state.copyWith(loose: ws);

  void clearLoose() {
    if (state.loose != null) state = state.copyWith(loose: null);
  }

  /// D14: what `layout.json` keeps — every dock that is not the default.
  Map<String, ToolDockState> get saved => {
    for (final e in state.byWorkspace.entries)
      if (!e.value.isDefault) e.key: e.value,
  };

  /// D14 at startup: the saved docks of workspaces that still exist, with
  /// the chips of tools that still exist in them. Pages load later, when a
  /// dock first shows (lazy).
  void restore(Map<String, ToolDockState> saved) {
    final sidebar = ref.read(sidebarWorkspacesProvider);
    final registry = ref.read(toolRegistryProvider.notifier);
    final next = <String, ToolDockState>{...state.byWorkspace};
    for (final MapEntry(key: ws, value: dock) in saved.entries) {
      if (sidebar.workspace(ws) == null) continue;
      final known = {for (final t in registry.inWorkspace(ws)) t.id};
      var kept = dock;
      for (final id in dock.tools) {
        if (!known.contains(id)) kept = kept.without(id);
      }
      if (kept.isDefault) continue;
      next[ws] = kept;
      // D10: the restored chip on show is the one viewed last.
      if (kept.active case final active?) _lastViewed[ws] = active;
    }
    state = state.copyWith(byWorkspace: Map.unmodifiable(next));
  }

  /// D2, §8: a workspace's tools die with it, whichever build deleted it.
  /// V1 and V2.0 delete a workspace without touching `workspace_tools`, so
  /// its tools would stay for good, unseen. Once after start, every tool
  /// whose workspace the sidebar did not load goes (ids are never reused).
  /// Run after `build`: a provider may not change another while it
  /// initializes.
  void _pruneOrphans() {
    if (!ref.mounted) return;
    final known = {
      for (final w in ref.read(sidebarWorkspacesProvider).workspaces) w.id,
    };
    final orphaned = {
      for (final t in ref.read(toolRegistryProvider))
        if (!known.contains(t.ws)) t.ws,
    };
    final registry = ref.read(toolRegistryProvider.notifier);
    for (final ws in orphaned) {
      registry.removeWorkspace(ws);
    }
  }

  void _dropTool(String id) {
    for (final MapEntry(key: ws, value: dock) in state.byWorkspace.entries) {
      if (dock.tools.contains(id)) closeTool(ws, id);
    }
  }

  void _dropWorkspace(String ws) {
    if (!state.byWorkspace.containsKey(ws) && state.loose != ws) return;
    state = state.copyWith(
      byWorkspace: Map.unmodifiable({
        for (final e in state.byWorkspace.entries)
          if (e.key != ws) e.key: e.value,
      }),
      loose: state.loose == ws ? null : state.loose,
    );
    _lastTab.remove(ws);
    _lastViewed.remove(ws);
  }

  void _set(String ws, ToolDockState dock) {
    // D10: whatever put a chip on show made it the one viewed last; the last
    // chip closing (none on show then) keeps the one before.
    if (dock.active case final active?) _lastViewed[ws] = active;
    if (state.of(ws) == dock) return;
    state = state.copyWith(
      byWorkspace: Map.unmodifiable({...state.byWorkspace, ws: dock}),
    );
  }
}
