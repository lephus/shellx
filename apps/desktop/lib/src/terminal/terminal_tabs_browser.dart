part of 'terminal_tabs.dart';

// A6: browser panes in the tab model. A browser pane is a leaf of the pane
// tree with a negative id ([isBrowserPaneId]); its state lives in
// [TerminalTab.browsers], never in `panes`, `_links` or the daemon.

extension TerminalTabsBrowser on TerminalTabs {
  /// A6 D7: splits [target] (default: the focused pane) of [tabId] (default:
  /// the selected tab) with a browser pane at [url] (default: the active
  /// terminal's smallest port, else about:blank). [notify] false (agent,
  /// A7) raises errors without a toast. Throws [BrowserError] `not_found`,
  /// `browser_limit` or `no_room`.
  int openBrowser({
    int? tabId,
    int? target,
    Uri? url,
    SplitAxis axis = SplitAxis.row,
    bool focus = true,
    bool notify = true,
  }) {
    final tab = tabId == null ? _state.selected : _tab(tabId);
    if (tab == null) throw const BrowserError('not_found');
    final at = target ?? tab.focusedPaneId;
    if (!tab.paneOrder.contains(at)) throw const BrowserError('not_found');
    if (_state.browserCount >= kMaxBrowserPanes) {
      if (notify) _set(notice: const BrowserLimitNotice(kMaxBrowserPanes));
      throw const BrowserError('browser_limit');
    }
    if (!_roomToSplit(tab, at, axis, newIsBrowser: true)) {
      if (notify) _set(notice: const PaneNoRoomNotice());
      throw const BrowserError('no_room');
    }
    final id = _nextBrowserId--;
    final ports = tab.activeTerminalPane.ports;
    final start =
        url ??
        (ports.isEmpty
            ? aboutBlank
            : Uri.parse('http://localhost:${ports.reduce(min)}/'));
    final wasZoomed = tab.zoomedPaneId != null;
    _replaceTab(
      tab.copyWith(
        layout: splitPane(tab.layout, at, id, axis),
        browsers: {
          ...tab.browsers,
          id: BrowserPaneState(url: start),
        },
        focusedPaneId: focus ? id : tab.focusedPaneId,
        paneHistory: focus
            ? [id, ...tab.paneHistory]
            : [...tab.paneHistory, id],
        zoomedPaneId: null, // A3 D3: a split ends the zoom
      ),
    );
    if (focus && _state.selectedId != tab.id) {
      _restoreMaySelect = false; // the user chose (A5a D10)
      _set(selectedId: tab.id);
    }
    if (wasZoomed && _state.selectedId == tab.id) _visibleChanged();
    return id;
  }

  /// The registry copies each controller's state here (pane header, A7
  /// `list`). Ignored for a pane that is gone.
  void updateBrowser(int id, BrowserPaneState browser) {
    final tab = _state.tabOfPane(id);
    if (tab == null ||
        !tab.browsers.containsKey(id) ||
        identical(tab.browsers[id], browser)) {
      return;
    }
    _replaceTab(tab.copyWith(browsers: {...tab.browsers, id: browser}));
  }
}
