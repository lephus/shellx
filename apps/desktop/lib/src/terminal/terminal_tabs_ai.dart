part of 'terminal_tabs.dart';

// V2-1 D2, D3: AI tabs — a tab whose main pane is an AI pane (a negative
// leaf, its record in [TerminalTab.aiPanes]). The agent and the
// conversation live in the AI runtimes; the tab list holds only what the
// sidebar, the window, the command line and restore need.

/// D3: the AI pane's share of its tab once a terminal pane joins it.
const double kAiPaneRatio = 0.72;

/// Uses [TerminalTabs._ref] and [TerminalTabs._state], as the other parts.
extension TerminalTabsAi on TerminalTabs {
  /// D5: a new AI tab holding one AI pane, placed like any desktop tab (in
  /// the current workspace) or straight into [workspace]; selected unless
  /// [select] is false. [cwd] null: the pane asks for a folder first.
  /// [sessionId]: the session it reopens (`session/load`, D14/D15). Starts
  /// nothing: the pane starts its agent when it is shown. Returns the id.
  int openAiTab({
    required String agentId,
    required String agentName,
    required String title,
    String? cwd,
    String? sessionId,
    String? workspace,
    bool select = true,
    String? customTitle,
    TabMeta meta = TabMeta.empty,
  }) {
    final tab = TerminalTab.ai(
      id: kSyntheticTabIdBase + _syntheticTabIds++,
      pane: AiPaneState(
        id: _nextAiPaneId--,
        agentId: agentId,
        agentName: agentName,
        title: title,
        cwd: cwd,
        sessionId: sessionId,
      ),
      customTitle: customTitle,
      meta: meta,
    );
    // Before the tab appears: the sidebar takes it as it places the tab.
    if (workspace != null) {
      _ref.read(restorePlacementProvider).pending[tab.id] = workspace;
    }
    if (select) _restoreMaySelect = false;
    _set(
      tabs: [..._state.tabs, tab],
      selectedId: select ? tab.id : _state.selectedId ?? tab.id,
    );
    return tab.id;
  }

  /// Changes AI pane [paneId] (title, folder, session). Nothing when the
  /// pane is gone or nothing changed (no rebuild, no layout save).
  void updateAiPane(int paneId, AiPaneState Function(AiPaneState pane) change) {
    final tab = _state.tabOfPane(paneId);
    final pane = tab?.aiPanes[paneId];
    if (tab == null || pane == null) return;
    final next = change(pane);
    if (next == pane) return;
    _replaceTab(tab.copyWith(aiPanes: {...tab.aiPanes, paneId: next}));
  }

  /// D3 "Terminal": a terminal pane under tab [tabId]'s AI pane, in the
  /// session's folder, focused; the AI pane keeps [kAiPaneRatio]. With one
  /// there already, that one is focused. Returns the terminal pane's id.
  /// Throws as [splitPaneFor] does.
  Future<int> addAiTerminal(int tabId) async {
    final tab = _tab(tabId);
    final ai = tab?.ai;
    if (tab == null || ai == null) throw const PaneGoneException();
    final existing = tab.paneOrder.where(tab.panes.containsKey).firstOrNull;
    if (existing != null) {
      focusPane(existing);
      return existing;
    }
    if (_state.opening) throw const OpenBusyException();
    final TerminalGrid grid = (
      cols: _grid.cols,
      rows: max(1, (_grid.rows * (1 - kAiPaneRatio)).floor() - 1),
    );
    return _guardedOpen(
      () => _local.open(
        cols: grid.cols,
        rows: grid.rows,
        cwd: ai.cwd,
        tabId: tab.id,
      ),
      (id) {
        _adoptPane(
          id,
          tabId: tab.id,
          target: ai.id,
          axis: SplitAxis.column,
          size: grid,
          focus: true,
        );
        if (_state.tabOfSession(id) == null) throw const PaneGoneException();
        setRatio(tab.id, '', kAiPaneRatio);
        return id;
      },
    );
  }
}
