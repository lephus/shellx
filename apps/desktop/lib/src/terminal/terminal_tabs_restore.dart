part of 'terminal_tabs.dart';

// A5a D7–D10, D16, D17: reopening the saved tabs. Kept apart from the
// tab list's everyday operations; it uses the same internals ([_attach],
// [_merge] holds, [_set]).

/// A5a D7: some saved panes could not be reopened. Neutral toast.
final class RestorePanesFailedNotice extends TabNotice {
  const RestorePanesFailedNotice(this.count);
  final int count;
}

/// A5b: "Thoát hoàn toàn" could not stop the background service; the
/// window stays open (UI-A5 §7.2 follow-up).
final class DaemonQuitFailedNotice extends TabNotice {
  const DaemonQuitFailedNotice();
}

/// What restore needs: the checked snapshot and, per pane key, the saved
/// text already followed by its divider (A5a D8).
final class RestorePlan {
  const RestorePlan({
    required this.snapshot,
    required this.textByKey,
    this.reattach = false,
  });
  final RestoreSnapshot snapshot;
  final Map<String, String> textByKey;

  /// A5b D14: the shells are alive in the background service the snapshot
  /// was saved against: lay the tree over them, open nothing, no text.
  final bool reattach;
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

  /// Nothing was restored (no plan, or a restore already running).
  static const none = RestoreOutcome(
    keyBySession: {},
    tabIdByKey: {},
    panesFailed: 0,
  );
  int get tabsRestored => tabIdByKey.length;
}

/// A5a criterion 1: where a restored tab goes in the sidebar — and A7 D14,
/// where a command-line tab with a target workspace goes. The tab list
/// writes [pending] just before the tab appears; the sidebar takes the
/// entry when it places the tab — in that workspace (null or gone:
/// Default), without expanding anything. The sidebar sets [isShown]
/// while it exists, so restore's D10 fallback picks a tab the user sees.
final class RestorePlacement {
  final pending = <int, String?>{};

  /// Whether workspace [id] (null: Default) shows its tabs.
  bool Function(String? id)? isShown;

  /// A11 D14: whether workspace [id] still exists, and which one ⌘T would
  /// open a tab in now; set by the sidebar like [isShown].
  bool Function(String id)? hasWorkspace;
  String Function()? currentWorkspace;
}

final restorePlacementProvider = Provider<RestorePlacement>(
  (ref) => RestorePlacement(),
);

/// A11 D14: bringing back what the user closed, over the same restore
/// path (A5a's divider, grid estimate, placement and selection).
extension TerminalTabsReopen on TerminalTabs {
  /// Reopens a closed tab: its panes in their folders (SSH panes on their
  /// servers), the saved text above each new shell, in its workspace when
  /// that still exists, else the current one; selected. Never replays
  /// anything: the shells are new. [RestoreOutcome.none] while a restore
  /// is running.
  Future<RestoreOutcome> reopenClosed(
    ClosedTab c, {
    required String Function(String key) dividerFor,
  }) {
    final placement = _ref.read(restorePlacementProvider);
    final saved = c.workspaceId;
    final workspace =
        saved != null && (placement.hasWorkspace?.call(saved) ?? true)
        ? saved
        : placement.currentWorkspace?.call() ?? saved ?? 'default';
    final snapshot = RestoreSnapshot(
      savedAt: _ref.read(clockProvider)(),
      cleanExit: false,
      selectedTab: c.tab.key,
      workspaces: [
        SavedWorkspace(id: workspace, tabs: [c.tab.key]),
      ],
      tabs: [c.tab],
    );
    final text = {
      for (final e in c.textByKey.entries) e.key: e.value + dividerFor(e.key),
    };
    return _runRestore(RestorePlan(snapshot: snapshot, textByKey: text));
  }

  /// Reopens a closed pane: next to the focused pane of its old tab when
  /// that tab is still there (and has room), else as a tab of its own.
  /// Returns the new pane's id, or null when nothing opened (the notice
  /// says why, when there is one to say).
  Future<int?> reopenClosedPane(ClosedPane p, {String divider = ''}) async {
    final text = p.text.isEmpty ? null : p.text + divider;
    try {
      final tab = _state.tabs.where((t) => t.id == p.tabId).firstOrNull;
      if (tab != null) {
        try {
          final id = await splitPaneFor(
            tab.focusedPaneId,
            SplitAxis.row,
            cwd: p.cwd,
            focus: true,
            local: p.launch == null,
            launchOverride: p.launch,
            ownFolder: true,
            restoreText: text,
          );
          focusPane(id);
          return id;
        } on PaneNoRoomException {
          // No room beside it: the pane gets a tab of its own.
        }
      }
      return await openTabFor(
        cwd: p.cwd,
        launch: p.launch,
        select: true,
        restoreText: text,
      );
    } on SessionLimitException catch (error) {
      if (_ref.mounted) _set(notice: SessionLimitNotice(error.max));
    } on SpawnFailedException catch (error) {
      if (_ref.mounted) _set(notice: spawnNoticeFor(error));
    } on OpenBusyException {
      // Another open is in flight: the item stays for the next try.
    } on PaneGoneException {
      // The new shell ended before it could be placed.
    }
    return null;
  }
}

/// Uses [TerminalTabs._ref] and [TerminalTabs._state]: an extension may
/// not touch the notifier's protected `ref` and `state` itself.
extension _Restore on TerminalTabs {
  Future<RestoreOutcome> _runRestore(FutureOr<RestorePlan?> pending) async {
    final keyBySession = <int, String>{};
    final tabIdByKey = <String, int>{};
    var failed = 0;
    if (_restoring != null) return RestoreOutcome.none;
    final done = _restoring = Completer<void>();
    _restoreMaySelect = true;
    _restoreCancelled = false;
    final local = _local;
    bool live() => _ref.mounted && identical(_local, local);
    // A5a m1: a Quit or power-off meanwhile stops the restore.
    bool alive() => live() && !_restoreCancelled;
    var order = const <SavedTab>[];
    try {
      final plan = await pending;
      if (plan == null) return RestoreOutcome.none;
      if (plan.reattach) return _layOver(plan.snapshot, local);
      final snapshot = plan.snapshot;
      final workspaceOf = {
        for (final w in snapshot.workspaces)
          for (final key in w.tabs) key: w.id,
      };
      order = _restoreOrder(snapshot);
      for (final saved in order) {
        if (!alive()) break;
        final grids = _restoreGrids(saved.layout, _grid);
        final sessionByKey = <String, int>{};
        // A7 D29: the creating pane first — its session id becomes the tab
        // id — and the others are told that id. When it fails, they open
        // without one (their SHELLX_TAB_ID then names no tab: residual).
        final leaves = savedLeaves(saved.layout);
        final creator = leaves.where((p) => p.key == saved.key).firstOrNull;
        int? tabId;
        for (final pane in [?creator, ...leaves.where((p) => p != creator)]) {
          if (!alive()) break;
          final id = await _openForRestore(
            local,
            pane.cwd,
            grids[pane.key]!,
            plan.textByKey[pane.key],
            launch: pane.launch,
            tabId: tabId,
          );
          if (id == null) {
            failed++;
            continue;
          }
          if (pane == creator) tabId = id;
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
      if (live()) {
        _restoreHeld.clear();
        _restoreRemote.clear();
        _sync(); // anything opened elsewhere meanwhile becomes its own tab
      }
      // Cancelled (A5a m1): no selection taken, no toast.
      if (alive()) {
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
      _restoreCancelled = false;
      _restoring = null;
      done.complete();
    }
    return RestoreOutcome(
      keyBySession: keyBySession,
      tabIdByKey: tabIdByKey,
      panesFailed: failed,
    );
  }

  /// A5b D14: the saved tabs over the sessions that are alive (their panes
  /// are the ones [TerminalTabs.build] attached already, with their
  /// terminals and backlog). Panes whose session is gone are dropped; a
  /// remote pane that is not connected is still a live session, so it
  /// stays (A8). Sessions the snapshot never had keep the tab they got.
  RestoreOutcome _layOver(RestoreSnapshot snapshot, LocalSessions local) {
    final alive = <int, PaneSession>{
      for (final tab in _state.tabs) ...tab.panes,
    };
    final keyBySession = <int, String>{};
    final tabIdByKey = <String, int>{};
    final claimed = <int>{};
    final tabs = <TerminalTab>[];
    var failed = 0;
    for (final saved in _restoreOrder(snapshot)) {
      final sessionByKey = <String, int>{};
      for (final pane in savedLeaves(saved.layout)) {
        final id = pane.session;
        if (id == null || !alive.containsKey(id) || !claimed.add(id)) {
          failed++;
          continue;
        }
        sessionByKey[pane.key] = id;
        keyBySession[id] = pane.key;
      }
      final layout = buildLayout(saved.layout, sessionByKey);
      if (layout == null) continue;
      final order = paneIds(layout);
      final creator = sessionByKey[saved.key];
      final focused = sessionByKey[saved.focused];
      final zoomed = sessionByKey[saved.zoomed];
      final focus = order.contains(focused) ? focused! : order.first;
      final tab = TerminalTab(
        id: order.contains(creator) ? creator! : order.first,
        origin: SessionOrigin.desktop,
        layout: layout,
        panes: {for (final id in order) id: alive[id]!},
        focusedPaneId: focus,
        zoomedPaneId: order.length > 1 && order.contains(zoomed)
            ? zoomed
            : null,
        paneHistory: [focus, ...order.where((id) => id != focus)],
        customTitle: saved.name,
      );
      tabIdByKey[saved.key] = tab.id;
      tabs.add(tab);
    }
    // Tabs nobody claimed (sessions opened while the window was away, by a
    // phone or the command line) stay as the one-pane tabs they are.
    // A live tab a saved tab only partly claimed keeps its other panes, one
    // single-pane tab each (as [_merge] makes them): none is hidden.
    final rest = <TerminalTab>[
      for (final tab in _state.tabs)
        if (!tab.panes.keys.any(claimed.contains))
          tab
        else
          for (final pane in tab.panes.values)
            if (!claimed.contains(pane.id)) TerminalTab.single(pane),
    ];
    final selected = snapshot.selectedTab == null
        ? null
        : tabIdByKey[snapshot.selectedTab];
    _set(
      tabs: [...tabs, ...rest],
      selectedId: selected ?? tabs.firstOrNull?.id ?? _state.selectedId,
    );
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
    String? text, {
    SessionLaunch? launch,
    int? tabId,
  }) async {
    _awaitingOpens++;
    try {
      final id = await local.open(
        cols: grid.cols,
        rows: grid.rows,
        // A remote pane's folder is in its launch, never a local cwd.
        cwd: launch == null ? cwd : null,
        tabId: tabId,
        launch: launch,
      );
      // Held before the count drops: a change event of this open must
      // never make the session a tab of its own.
      if (identical(_local, local)) {
        _restoreHeld.add(id);
        if (text != null) _restoreText[id] = text;
        if (launch != null && launch.host != null) {
          _restoreRemote[id] =
              local.sessions.where((s) => s.id == id).firstOrNull ??
              SessionSummary(
                id: id,
                index: 1,
                shell: 'ssh',
                createdAt: DateTime.now(),
                attachedMobileId: null,
                origin: SessionOrigin.desktop,
                remote: SessionRemote(launch: launch),
              );
        }
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
      var pane = summary == null
          ? null
          : _attach(summary, size: grids[keyOf[id]]);
      // A8 D29: a server session that is gone already (no network) stays
      // as a lost pane the user can reconnect, never dropped.
      final remote = _restoreRemote.remove(id);
      if (pane == null && remote != null) {
        pane = _lostRemotePane(remote, grids[keyOf[id]]);
      }
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

  /// A pane for a server session that ended before it could be attached:
  /// the saved text, then the "couldn't connect" line; Enter reconnects
  /// (UI-A8 §3.2). Nothing to write to: there is no session behind it.
  PaneSession? _lostRemotePane(SessionSummary s, TerminalGrid? size) {
    // A local tmux client has no server to name: dropped as any local pane.
    final host = s.remote?.hostKey;
    if (host == null) return null;
    final terminal = DesktopTerminal(
      platform: _platform(),
      maxLines: _ref.read(shellxConfigProvider).config.scrollbackLimit,
      inputHandler: _inputHandler,
    );
    final grid = size ?? _grid;
    terminal.resize(grid.cols, grid.rows);
    final restored = _restoreText.remove(s.id);
    if (restored != null) terminal.write(restored);
    final newline = terminal.buffer.cursorX == 0 ? '' : '\r\n';
    final line = _ref.read(appL10nProvider).sshFailedLine(host);
    terminal.write('$newline\x1b[2m$line\x1b[0m\x1b[?25l');
    terminal.onUserInput = (data) => _onUserInput(s.id, data);
    return PaneSession(
      id: s.id,
      index: s.index,
      shell: s.shell,
      title: s.title,
      origin: s.origin,
      phoneAttached: false,
      runningCommand: false,
      driver: s.driver,
      terminal: terminal,
      selection: DesktopTerminalController(),
      cwd: s.cwd,
      remote: s.remote,
      exitCode: 255,
    );
  }
}
