part of 'terminal_tabs.dart';

// A3: a tab's panes — split, focus, zoom, dividers, close one pane. Kept
// apart from the tab list's own bookkeeping; uses the same internals
// ([_guardedOpen], [_attach], [_sync], [_set]).

/// Uses [TerminalTabs._ref] and [TerminalTabs._state]: an extension may
/// not touch the notifier's protected `ref` and `state` itself.
extension TerminalTabsPanes on TerminalTabs {
  /// ⌘W on a split tab, the pane ×, "Đóng pane" (D6): the last pane closes
  /// the tab.
  void closePane(int sessionId) {
    final pane = _state.tabOfSession(sessionId)?.panes[sessionId];
    if (pane == null) return;
    if (!pane.exited) _local.close(sessionId);
    _removePane(sessionId);
  }

  /// A7 D21: how session [id] ended, while it is one of the last 64 that
  /// ended here; null otherwise.
  int? lastExitCode(int id) => _lastExitCodes[id];

  void _recordExit(int id, int code) {
    _lastExitCodes
      ..remove(id)
      ..[id] = code;
    if (_lastExitCodes.length > 64) {
      _lastExitCodes.remove(_lastExitCodes.keys.first);
    }
  }

  /// Stores the size for later decisions only: safe during layout.
  void reportPaneMetrics(PaneMetrics metrics) => _metrics = metrics;

  /// ⌘D / ⌘⇧D (D3): the selected tab's focused pane, in its directory
  /// (D17), at half its grid; the new pane is focused. Failures are toasts.
  Future<void> split(SplitAxis axis) async {
    final tab = _state.selected;
    if (tab == null || _state.opening) return;
    try {
      await splitPaneFor(tab.focusedPaneId, axis, focus: true);
    } on PaneNoRoomException {
      if (_ref.mounted) _set(notice: const PaneNoRoomNotice());
    } on SessionLimitException catch (error) {
      if (_ref.mounted) _set(notice: SessionLimitNotice(error.max));
    } on SpawnFailedException catch (error) {
      if (_ref.mounted) {
        _set(notice: SpawnFailedNotice(spawnFailureOf(error.message)));
      }
    } on PaneGoneException {
      // The new shell ended before it could be placed: nothing to show.
    }
  }

  /// D3 for pane [target] of any tab, selected or not (A7 D15): in [cwd],
  /// else the target's directory (D17), at half its grid. The new session
  /// knows its tab (A7 D29). With [focus] the new pane becomes its tab's
  /// focused pane; without it the tab's focus and zoom stay. Never changes
  /// the selection. Returns the new pane's id. Throws
  /// [PaneGoneException] (no such pane, or the shell ended before it could
  /// be placed), [OpenBusyException], [PaneNoRoomException] (D4),
  /// [SessionLimitException], [SpawnFailedException].
  Future<int> splitPaneFor(
    int target,
    SplitAxis axis, {
    String? cwd,
    bool focus = false,
  }) async {
    final tab = _state.tabOfSession(target);
    final pane = tab?.panes[target];
    if (tab == null || pane == null) throw const PaneGoneException();
    if (_state.opening) throw const OpenBusyException();
    if (!_roomToSplit(tab, target, axis)) throw const PaneNoRoomException();
    final grid = _halfGrid(pane, axis);
    return _guardedOpen(
      () => _local.open(
        cols: grid.cols,
        rows: grid.rows,
        cwd: cwd ?? pane.cwd,
        tabId: tab.id,
      ),
      (id) {
        _adoptPane(
          id,
          tabId: tab.id,
          target: target,
          axis: axis,
          size: grid,
          focus: focus,
        );
        if (_state.tabOfSession(id) == null) throw const PaneGoneException();
        return id;
      },
    );
  }

  /// A click in a pane, a jump to a notification: [sessionId]'s tab is
  /// selected and the pane focused; a zoom that hides it ends (D10).
  void focusPane(int sessionId) {
    final tab = _state.tabOfSession(sessionId);
    if (tab == null) return;
    final unzoom = tab.zoomedPaneId != null && tab.zoomedPaneId != sessionId;
    if (tab.focusedPaneId != sessionId || unzoom) {
      _replaceTab(
        tab.copyWith(
          focusedPaneId: sessionId,
          paneHistory: [
            sessionId,
            ...tab.paneHistory.where((id) => id != sessionId),
          ],
          zoomedPaneId: unzoom ? null : tab.zoomedPaneId,
        ),
      );
    }
    if (_state.selectedId != tab.id) {
      _restoreMaySelect = false; // the user chose (A5a D10)
      _set(selectedId: tab.id);
    } else if (unzoom) {
      _visibleChanged();
    }
  }

  /// ⌘⌥arrows (D9). False when there is no pane that way.
  bool focusDirection(PaneDirection direction) {
    final tab = _state.selected;
    if (tab == null || !tab.isSplit) return false;
    final next = neighbourPane(
      tab.layout,
      tab.focusedPaneId,
      direction,
      mru: tab.paneHistory,
    );
    if (next == null) return false;
    if (tab.zoomedPaneId != null) {
      _replaceTab(tab.copyWith(zoomedPaneId: null));
      _visibleChanged();
    }
    focusPane(next);
    return true;
  }

  /// ⌘⇧↩ (D10): the new state; a one-pane tab is never zoomed.
  bool toggleZoom() {
    final tab = _state.selected;
    if (tab == null || !tab.isSplit) return false;
    final zoom = tab.zoomedPaneId == null;
    _replaceTab(tab.copyWith(zoomedPaneId: zoom ? tab.focusedPaneId : null));
    if (!zoom) _visibleChanged();
    return zoom;
  }

  /// ⌘⌃= (D11). Unzooms first (D10, final ruling m-4): a layout change
  /// the user cannot see would only surprise them later.
  void equalize() {
    final tab = _state.selected;
    if (tab == null || !tab.isSplit) return;
    _replaceTab(
      tab.copyWith(layout: equalized(tab.layout), zoomedPaneId: null),
    );
    if (tab.zoomedPaneId != null) _visibleChanged();
  }

  /// Double-click on a divider (D11).
  void equalizeAt(int tabId, PanePath path) {
    final tab = _tab(tabId);
    if (tab == null || nodeAt(tab.layout, path) is! PaneSplit) return;
    _replaceTab(tab.copyWith(layout: equalizedAt(tab.layout, path)));
  }

  /// A divider drag (D14): ignored when [path] is no longer a split (a
  /// pane closed mid-drag), or is a split of another [axis] than the one
  /// the drag began on (final ruling m-3: a close can hand the path to a
  /// split across); clamped to the pixel minimums (D4).
  void setRatio(int tabId, PanePath path, double ratio, {SplitAxis? axis}) {
    final tab = _tab(tabId);
    final node = tab == null ? null : nodeAt(tab.layout, path);
    if (tab == null || node is! PaneSplit) return;
    if (axis != null && node.axis != axis) return;
    _replaceTab(
      tab.copyWith(
        layout: withRatio(tab.layout, path, _clampForPixels(tab, path, ratio)),
      ),
    );
  }

  /// ⌘⌃arrows (D12): the nearest split of the arrow's axis above the
  /// focused pane moves [ShellxSizes.paneResizeStep] the arrow's way.
  void resizeFocused(PaneDirection direction) {
    final tab = _state.selected;
    if (tab == null || !tab.isSplit) return;
    final sideways =
        direction == PaneDirection.left || direction == PaneDirection.right;
    final path = ancestorSplit(
      tab.layout,
      tab.focusedPaneId,
      sideways ? SplitAxis.row : SplitAxis.column,
    );
    if (path == null) return;
    final split = nodeAt(tab.layout, path)! as PaneSplit;
    final forward =
        direction == PaneDirection.right || direction == PaneDirection.down;
    const step = ShellxSizes.paneResizeStep;
    // D10, final ruling m-4: as a directional focus does, a resize shows
    // the panes it changes.
    if (tab.zoomedPaneId != null) {
      _replaceTab(tab.copyWith(zoomedPaneId: null));
      _visibleChanged();
    }
    setRatio(tab.id, path, split.ratio + (forward ? step : -step));
  }

  /// D3: session [id] (opened by [splitPaneFor]) joins tab [tabId] next
  /// to [target]. When it ended already, or its tab went while it opened,
  /// the normal rules apply: a tab of its own, selected only with [focus]
  /// (A7 D15: a command-line split never takes the selection). Without
  /// [focus] the tab keeps its focused pane and zoom; the new pane comes
  /// second in the focus history.
  void _adoptPane(
    int id, {
    required int tabId,
    required int target,
    required SplitAxis axis,
    required TerminalGrid size,
    required bool focus,
  }) {
    final summary = _local.sessions.where((s) => s.id == id).firstOrNull;
    final tab = _tab(tabId);
    if (summary == null || tab == null) {
      _sync(own: id);
      if (focus) {
        if (_state.tabOfSession(id) case final own?) {
          _restoreMaySelect = false;
          _set(selectedId: own.id);
        }
      }
      return;
    }
    final pane = _attach(summary, size: size);
    if (pane == null) {
      _sync(); // Ended between the listing and now; others may wait (D5).
      return;
    }
    final at = tab.panes.containsKey(target) ? target : tab.paneOrder.first;
    final unzoom = focus && tab.zoomedPaneId != null;
    final layout = splitPane(tab.layout, at, id, axis);
    final panes = {...tab.panes, id: pane};
    _replaceTab(
      focus
          ? tab.copyWith(
              layout: layout,
              panes: panes,
              focusedPaneId: id,
              zoomedPaneId: null,
              paneHistory: [id, ...tab.paneHistory],
            )
          : tab.copyWith(
              layout: layout,
              panes: panes,
              paneHistory: [
                ...tab.paneHistory.take(1),
                id,
                ...tab.paneHistory.skip(1),
              ],
            ),
    );
    _sync();
    // Final ruling m-1: a split that finishes after the user moved to
    // another tab stays in its own tab; it never pulls the user back.
    if (_state.selectedId == tabId && unzoom) _visibleChanged();
  }

  /// D13 estimate; the real grid follows at the next layout.
  TerminalGrid _halfGrid(PaneSession pane, SplitAxis axis) {
    final cols = pane.terminal.viewWidth;
    final rows = pane.terminal.viewHeight;
    return axis == SplitAxis.row
        ? (cols: max(1, (cols - 1) ~/ 2), rows: max(1, rows - 1))
        : (cols: cols, rows: max(1, (rows - 1) ~/ 2 - 1));
  }

  /// D4: room for two minimum panes, in the pixels the pane really has
  /// ([panePixelSizes]) and the halves the new split will really get
  /// ([splitExtents] at 0.5: the first half is snapped, so a sum check can
  /// leave the second one a pixel short — final ruling m-2).
  bool _roomToSplit(TerminalTab tab, int target, SplitAxis axis) {
    final m = _metrics;
    if (m == null) return true;
    final size = panePixelSizes(
      tab.layout,
      m.area,
      m.divider,
      m.devicePixelRatio,
    )[target];
    if (size == null) return false;
    final row = axis == SplitAxis.row;
    final (along, across) = row
        ? (size.width, size.height)
        : (size.height, size.width);
    final (minAlong, minAcross) = row
        ? (m.minPane.width, m.minPane.height)
        : (m.minPane.height, m.minPane.width);
    final (a, b) = splitExtents(along, 0.5, m.divider, m.devicePixelRatio);
    return a >= minAlong && b >= minAlong && across >= minAcross;
  }

  /// D4: no pane of either side may end up below [PaneMetrics.minPane].
  ///
  /// Pixel contract ([splitExtents], the same function the pane view lays
  /// out with): a split of extent E at ratio r gives its first child
  /// `r·E` snapped to a device pixel, then the divider, then the rest. The
  /// limits are whole device pixels, so the snapped layout at a limit
  /// still holds every minimum.
  ///
  /// When the split cannot hold both sides at all (lo > hi), the ratio may
  /// only move toward the point where both sides fall short by the same
  /// number of pixels — a drag that relieves the more squeezed side works,
  /// one that squeezes it further does not.
  double _clampForPixels(TerminalTab tab, PanePath path, double ratio) {
    final m = _metrics;
    final node = nodeAt(tab.layout, path);
    final size = m == null
        ? null
        : splitPixelSize(
            tab.layout,
            path,
            m.area,
            m.divider,
            m.devicePixelRatio,
          );
    if (m == null || node is! PaneSplit || size == null) {
      return clampRatio(ratio);
    }
    final row = node.axis == SplitAxis.row;
    final extent = row ? size.width : size.height;
    if (extent <= 0) return node.ratio;
    final dpr = m.devicePixelRatio > 0 ? m.devicePixelRatio : 1.0;
    // Tolerates float noise in a minimum that already is a device pixel.
    const noise = 1e-9;
    final firstMin =
        (_minExtent(node.first, node.axis) * dpr - noise).ceilToDouble() / dpr;
    final firstMax =
        ((extent - m.divider - _minExtent(node.second, node.axis)) * dpr +
                noise)
            .floorToDouble() /
        dpr;
    final lo = firstMin / extent;
    final hi = firstMax / extent;
    if (lo <= hi) return clampRatio(ratio.clamp(lo, hi).toDouble());
    final fair = (lo + hi) / 2;
    final towards = node.ratio < fair
        ? ratio.clamp(node.ratio, fair)
        : ratio.clamp(fair, node.ratio);
    return clampRatio(towards.toDouble());
  }

  /// The smallest extent along [axis] that keeps every pane of [node] at
  /// its minimum, with [node]'s own ratios kept as they are. A nested
  /// split's first side is snapped ([splitExtents]): it may lose up to half
  /// a device pixel to rounding, and its second side may lose the same.
  double _minExtent(PaneNode node, SplitAxis axis) {
    final m = _metrics!;
    final half = 0.5 / (m.devicePixelRatio > 0 ? m.devicePixelRatio : 1.0);
    switch (node) {
      case PaneLeaf():
        return axis == SplitAxis.row ? m.minPane.width : m.minPane.height;
      case PaneSplit(axis: final a, :final ratio, :final first, :final second)
          when a == axis:
        // snap(r·X) ≥ min(first); X − divider − snap(r·X) ≥ min(second).
        return max(
          (_minExtent(first, axis) + half) / ratio,
          (_minExtent(second, axis) + m.divider + half) / (1 - ratio),
        );
      case PaneSplit(:final first, :final second):
        return max(_minExtent(first, axis), _minExtent(second, axis));
    }
  }
}
