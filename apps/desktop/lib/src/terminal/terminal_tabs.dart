import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:xterm/xterm.dart';

import '../restore/restore_snapshot.dart';
import '../ui/theme/shellx_desktop_theme.dart' show ShellxSizes;
import 'desktop_terminal.dart';
import 'local_sessions_provider.dart';
import 'pane_layout.dart';
import 'terminal_feed.dart';
import 'terminal_style.dart';

part 'terminal_tabs_restore.dart';

enum SpawnFailure { notFound, denied, other }

/// Picks the toast wording of UI §5 `terminalSpawnFailed` from the error
/// text (never shown to the user as is).
SpawnFailure spawnFailureOf(String message) {
  final m = message.toLowerCase();
  if (m.contains('no such file') ||
      m.contains('not found') ||
      m.contains('errno = 2)') ||
      m.contains('cannot find')) {
    return SpawnFailure.notFound;
  }
  if (m.contains('permission denied') ||
      m.contains('errno = 13') ||
      m.contains('access is denied')) {
    return SpawnFailure.denied;
  }
  return SpawnFailure.other;
}

/// The floating notice of UI §2.8.
sealed class TabNotice {
  const TabNotice();
}

final class SessionLimitNotice extends TabNotice {
  const SessionLimitNotice(this.max);
  final int max;
}

final class SpawnFailedNotice extends TabNotice {
  const SpawnFailedNotice(this.kind);
  final SpawnFailure kind;
}

/// A workspace was deleted; its tabs moved to [movedTo] (spec D16).
/// Neutral toast.
final class WorkspaceDeletedNotice extends TabNotice {
  const WorkspaceDeletedNotice({required this.name, required this.movedTo});
  final String name;
  final String movedTo;
}

/// The browser could not be started for a port link (UI-A2 §2.4).
final class PortOpenFailedNotice extends TabNotice {
  const PortOpenFailedNotice();
}

/// ⌘⇧U found nothing (A4 D13). Neutral toast.
final class NoUnreadNotice extends TabNotice {
  const NoUnreadNotice();
}

/// D4: the focused pane is too small to hold two (neutral toast).
final class PaneNoRoomNotice extends TabNotice {
  const PaneNoRoomNotice();
}

/// What the pane area looks like (D4), reported by the terminal pane on
/// every layout: the tab list needs pixels to refuse a split or clamp a
/// divider.
@immutable
final class PaneMetrics {
  const PaneMetrics({
    required this.area,
    required this.minPane,
    required this.divider,
    this.devicePixelRatio = 1,
  });

  /// The whole terminal area of a tab.
  final Size area;

  /// 20 columns × 5 rows of the current font, plus padding and the pane
  /// header (UI-A3 §1.2).
  final Size minPane;
  final double divider;

  /// Split extents snap to device pixels at this ratio ([splitExtents]).
  final double devicePixelRatio;
}

/// D19: the longest tab name, in characters.
const int kTabNameMaxLength = 64;

/// [text] trimmed, cut to [max] user-perceived characters (grapheme
/// clusters: an accent never loses its letter, an emoji is never split),
/// and trimmed again so a cut never leaves a trailing space (M2).
String clipName(String text, int max) =>
    text.trim().characters.take(max).toString().trim();

const Object _unset = Object();

/// One pane of a tab: one session's view (A3 D2). These are the fields the
/// A1/A2 tab record had; the tab now holds one per pane.
@immutable
final class PaneSession {
  const PaneSession({
    required this.id,
    required this.index,
    required this.shell,
    required this.title,
    required this.origin,
    required this.phoneAttached,
    required this.runningCommand,
    required this.driver,
    required this.terminal,
    required this.selection,
    this.cwd,
    this.gitBranch,
    this.ports = const [],
    this.exitCode,
  });

  final int id;
  final int index;
  final String shell;
  final String title;
  final SessionOrigin origin;
  final bool phoneAttached;
  final bool runningCommand;
  final DriverSide driver;
  final DesktopTerminal terminal;

  /// xterm selection (⌘C copies it).
  final TerminalController selection;

  /// A2 C1–C3, from the session; the last values stay after an exit.
  final String? cwd;
  final String? gitBranch;
  final List<int> ports;

  /// Non-null once the shell exited with a non-zero code (D14).
  final int? exitCode;

  bool get exited => exitCode != null;

  /// OSC 0/2 title, else `<shell> <index>` (D13, UI §5 terminalDefaultTitle).
  String get automaticLabel => title.isNotEmpty ? title : '$shell $index';

  /// The row has a context line (UI-A2 §2.1).
  bool get hasContext => cwd != null || gitBranch != null || ports.isNotEmpty;

  PaneSession copyWith({
    String? title,
    bool? phoneAttached,
    bool? runningCommand,
    DriverSide? driver,
    int? exitCode,
    Object? cwd = _unset,
    Object? gitBranch = _unset,
    List<int>? ports,
  }) => PaneSession(
    id: id,
    index: index,
    shell: shell,
    title: title ?? this.title,
    origin: origin,
    phoneAttached: phoneAttached ?? this.phoneAttached,
    runningCommand: runningCommand ?? this.runningCommand,
    driver: driver ?? this.driver,
    terminal: terminal,
    selection: selection,
    cwd: identical(cwd, _unset) ? this.cwd : cwd as String?,
    gitBranch: identical(gitBranch, _unset)
        ? this.gitBranch
        : gitBranch as String?,
    ports: ports ?? this.ports,
    exitCode: exitCode ?? this.exitCode,
  );
}

/// A sidebar tab (A3 P1): a tree of panes, one session each. Its id is the
/// id of the session that created it and never changes (D1). The A1/A2
/// getters read the focused pane, so the sidebar, the workspaces and A4
/// read a tab exactly as before.
@immutable
final class TerminalTab {
  const TerminalTab({
    required this.id,
    required this.origin,
    required this.layout,
    required this.panes,
    required this.focusedPaneId,
    this.zoomedPaneId,
    this.paneHistory = const [],
    this.customTitle,
  });

  factory TerminalTab.single(PaneSession pane) => TerminalTab(
    id: pane.id,
    origin: pane.origin,
    layout: PaneLeaf(pane.id),
    panes: {pane.id: pane},
    focusedPaneId: pane.id,
    paneHistory: [pane.id],
  );

  final int id;

  /// Where the session that created the tab came from (the 📱 mark, D19).
  final SessionOrigin origin;
  final PaneNode layout;
  final Map<int, PaneSession> panes;
  final int focusedPaneId;

  /// D10: the pane drawn over the whole area; null when not zoomed.
  final int? zoomedPaneId;

  /// D8: most recently focused first.
  final List<int> paneHistory;

  /// C6: the user's name for this tab (desktop only); wins over [title].
  final String? customTitle;

  PaneSession get focused => panes[focusedPaneId]!;

  /// D23: reading order.
  List<int> get paneOrder => paneIds(layout);
  int get paneCount => panes.length;
  bool get isSplit => panes.length > 1;

  /// 1-based position of [sessionId] in [paneOrder] ("Pane 2 of 3").
  int paneNumber(int sessionId) => paneOrder.indexOf(sessionId) + 1;

  int get index => focused.index;
  String get shell => focused.shell;
  String get title => focused.title;
  bool get runningCommand => focused.runningCommand;
  DesktopTerminal get terminal => focused.terminal;
  TerminalController get selection => focused.selection;
  String? get cwd => focused.cwd;
  String? get gitBranch => focused.gitBranch;
  List<int> get ports => focused.ports;
  int? get exitCode => focused.exitCode;
  bool get exited => focused.exited;
  String get automaticLabel => focused.automaticLabel;

  /// What the sidebar, the window title and dialogs show.
  String get label => customTitle ?? automaticLabel;

  /// What a notice from pane [sessionId] is labelled with (final ruling
  /// m-6): in a split tab the pane that sent it (its automatic label), not
  /// the focused one; a one-pane tab, or a pane no longer here, uses
  /// [label].
  String noticeLabel(int sessionId) {
    if (!isSplit) return label;
    return panes[sessionId]?.automaticLabel ?? label;
  }

  bool get hasContext => focused.hasContext;

  /// D19: 👁 when any pane has a phone attached.
  bool get phoneAttached => panes.values.any((p) => p.phoneAttached);

  /// D19: the 👁 turns `warn` when any attached pane is phone-driven.
  bool get phoneDriving =>
      panes.values.any((p) => p.phoneAttached && p.driver == DriverSide.phone);
  DriverSide get driver => phoneDriving ? DriverSide.phone : focused.driver;

  TerminalTab withPane(int id, PaneSession Function(PaneSession pane) change) {
    final pane = panes[id];
    return pane == null ? this : copyWith(panes: {...panes, id: change(pane)});
  }

  TerminalTab copyWith({
    PaneNode? layout,
    Map<int, PaneSession>? panes,
    int? focusedPaneId,
    Object? zoomedPaneId = _unset,
    List<int>? paneHistory,
    Object? customTitle = _unset,
  }) => TerminalTab(
    id: id,
    origin: origin,
    layout: layout ?? this.layout,
    panes: panes ?? this.panes,
    focusedPaneId: focusedPaneId ?? this.focusedPaneId,
    zoomedPaneId: identical(zoomedPaneId, _unset)
        ? this.zoomedPaneId
        : zoomedPaneId as int?,
    paneHistory: paneHistory ?? this.paneHistory,
    customTitle: identical(customTitle, _unset)
        ? this.customTitle
        : customTitle as String?,
  );
}

@immutable
final class TerminalTabsState {
  const TerminalTabsState({
    this.tabs = const [],
    this.selectedId,
    this.notice,
    this.opening = false,
  });

  final List<TerminalTab> tabs;
  final int? selectedId;
  final TabNotice? notice;

  /// An open is in flight (UI §3.2 busy `+`).
  final bool opening;

  TerminalTab? get selected {
    for (final tab in tabs) {
      if (tab.id == selectedId) return tab;
    }
    return null;
  }

  /// The tab holding session [sessionId] (A3 D1: not always `tab.id`).
  TerminalTab? tabOfSession(int sessionId) {
    for (final tab in tabs) {
      if (tab.panes.containsKey(sessionId)) return tab;
    }
    return null;
  }
}

/// What a tab holds that is not state: its view, feed, selection and
/// subscriptions, all released when the tab goes.
final class _Link {
  _Link(this.view, this.terminal, this.feed);
  final LocalSessionView view;
  final DesktopTerminal terminal;
  final TerminalFeed feed;
  final selection = TerminalController();
  final subscriptions = <StreamSubscription<Object?>>[];

  void dispose() {
    for (final s in subscriptions) {
      unawaited(s.cancel());
    }
    feed.dispose();
    view.dispose();
    selection.dispose();
  }
}

/// I2: who picks the tab selected after the selected one closes. The
/// sidebar sets [choose] while it exists (it knows the visible order; the
/// tab list cannot read the sidebar, which listens to it).
final class CloseSuccessor {
  /// The tab to select once [closed] is gone; null: the tab list decides.
  int? Function(int closed)? choose;
}

final closeSuccessorProvider = Provider<CloseSuccessor>(
  (ref) => CloseSuccessor(),
);

final terminalTabsProvider = NotifierProvider<TerminalTabs, TerminalTabsState>(
  TerminalTabs.new,
);

/// The window's tabs (spec §3.2): one per session, in creation order. Tabs
/// opened here are selected; tabs a phone opened are appended and not
/// selected (unless nothing is selected at all).
class TerminalTabs extends Notifier<TerminalTabsState> {
  late LocalSessions _local;
  final _links = <int, _Link>{};
  StreamSubscription<void>? _changes;

  /// The pane's grid, so a new shell starts at the size it will be shown.
  TerminalGrid _grid = (cols: 80, rows: 24);

  /// D5: how many of this window's own opens are in flight (⌘T, a split,
  /// each pane a restore reopens); a desktop session that appears meanwhile
  /// waits for its opener to place it.
  int _awaitingOpens = 0;

  /// A5a: sessions restore opened and has not placed in a tab yet; [_merge]
  /// never makes them tabs of their own (Review Focus 1).
  final _restoreHeld = <int>{};

  /// A5a D8: saved text (+ divider) written into a pane's terminal before
  /// its backlog. Consumed by [_attach].
  final _restoreText = <int, String>{};

  /// A5a D16: completes when the running restore ends; null when none runs.
  Completer<void>? _restoring;

  /// A5a D10: restore still picks the selection; false once it did, or
  /// once the user chose a tab meanwhile (⌘T, a click).
  bool _restoreMaySelect = false;

  /// A5a m1: set by [cancelRestore]; the running restore stops.
  bool _restoreCancelled = false;

  /// Never closed on a rebuild (the notifier outlives it, Riverpod 3):
  /// only when the provider really goes ([_dispose]).
  final _paneOutputs = StreamController<int>.broadcast(sync: true);

  /// A5a D4: the session whose pane just received output.
  Stream<int> get paneOutputs => _paneOutputs.stream;

  /// A5a D16: a restore is reopening saved panes.
  bool get restoring => _restoring != null;

  /// A5a m1: Quit or a power-off during a restore. The restore opens no
  /// further pane and ends without a toast or taking the selection; what
  /// it already opened still becomes tabs. Nothing when none runs.
  void cancelRestore() {
    if (_restoring != null) _restoreCancelled = true;
  }

  /// For the restore extension (`terminal_tabs_restore.dart`).
  Ref get _ref => ref;
  TerminalTabsState get _state => state;

  /// D4: the last pane area the view reported; null until the first layout
  /// (then nothing is refused or clamped beyond [clampRatio]).
  PaneMetrics? _metrics;

  @override
  TerminalTabsState build() {
    _local = ref.watch(localSessionsProvider);
    _changes = _local.changes.listen((_) => _sync());
    ref.onDispose(_dispose);
    final tabs = _merge(const []);
    return TerminalTabsState(tabs: tabs, selectedId: tabs.firstOrNull?.id);
  }

  void reportGrid(TerminalGrid grid) => _grid = grid;

  Future<void> openTab() async {
    if (state.opening) return;
    _set(opening: true);
    _awaitingOpens++;
    var held = true;
    void release() {
      if (!held) return;
      held = false;
      _awaitingOpens--;
    }

    var synced = false;
    try {
      final id = await _local.open(cols: _grid.cols, rows: _grid.rows);
      if (!ref.mounted) return;
      release();
      // A5a D16: placed now, even while a restore's opens are pending.
      _sync(own: id);
      synced = true;
      // The new shell may already be gone (exit 0, or ended before it could
      // be viewed): then keep a selection that exists.
      final opened = state.tabOfSession(id);
      if (opened != null) _restoreMaySelect = false;
      _set(
        selectedId:
            opened?.id ?? state.selected?.id ?? state.tabs.firstOrNull?.id,
      );
    } on SessionLimitException catch (error) {
      if (ref.mounted) _set(notice: SessionLimitNotice(error.max));
    } on SpawnFailedException catch (error) {
      if (ref.mounted) {
        _set(notice: SpawnFailedNotice(spawnFailureOf(error.message)));
      }
    } finally {
      release();
      if (ref.mounted) {
        // D5: desktop sessions held back while the open was pending get
        // their tabs now, even when the open failed.
        if (!synced) _sync();
        // Whatever happened (an unexpected error too), `+` is usable again.
        _set(opening: false);
      }
    }
  }

  /// D11: activation and startup open a tab when there is none. During a
  /// restore it waits for the restore (A5a D16): restored tabs count.
  Future<void> ensureTab() async {
    final restoring = _restoring;
    if (restoring != null) {
      await restoring.future;
      if (!ref.mounted) return;
    }
    if (state.tabs.isEmpty && !state.opening) await openTab();
  }

  void select(int id) {
    if (state.tabs.any((t) => t.id == id)) {
      _restoreMaySelect = false;
      _set(selectedId: id);
    }
  }

  /// A5a D7–D10: reopens every saved pane in its directory, the selected
  /// tab first, then in sidebar order; rebuilds each tree without the
  /// panes that failed; selects the saved tab as soon as it is there.
  /// Never throws.
  ///
  /// The restore counts as running from this call on, while [plan] is
  /// still being read (null: nothing to restore): an activation meanwhile
  /// waits instead of opening a blank tab (D16). Pane grids are estimated
  /// once the plan is there, from the last area grid the view reported —
  /// 80×24 before the first layout; the real grid then follows at that
  /// layout, as for any pane (D17).
  Future<RestoreOutcome> restore(FutureOr<RestorePlan?> plan) =>
      _runRestore(plan);

  /// ⌘1…⌘9: the n-th tab (1-based); nothing when there is none.
  void selectIndex(int position) {
    if (position >= 1 && position <= state.tabs.length) {
      _restoreMaySelect = false;
      _set(selectedId: state.tabs[position - 1].id);
    }
  }

  void next() => _step(1);
  void previous() => _step(-1);

  /// D15 for a tab: how many of its panes run a command.
  int runningPaneCount(int tabId) =>
      _tab(
        tabId,
      )?.panes.values.where((p) => !p.exited && p.runningCommand).length ??
      0;

  /// D15: a close asks first while a command runs (any pane of the tab).
  bool needsCloseConfirm(int id) => runningPaneCount(id) > 0;

  /// D6: one pane's D15.
  bool needsPaneCloseConfirm(int sessionId) {
    final pane = state.tabOfSession(sessionId)?.panes[sessionId];
    return pane != null && !pane.exited && pane.runningCommand;
  }

  /// "Đóng tab", the row ×, middle click: every pane (D6). The desktop may
  /// close every session (A1 D4).
  void close(int id) {
    final tab = _tab(id);
    if (tab == null) return;
    for (final pane in tab.panes.values) {
      if (!pane.exited) _local.close(pane.id);
    }
    _removeTab(id);
  }

  /// ⌘W on a split tab, the pane ×, "Đóng pane" (D6): the last pane closes
  /// the tab.
  void closePane(int sessionId) {
    final pane = state.tabOfSession(sessionId)?.panes[sessionId];
    if (pane == null) return;
    if (!pane.exited) _local.close(sessionId);
    _removePane(sessionId);
  }

  void dismissNotice() => _set(notice: null);

  /// C6/D19: the user's name for tab [id]; trimmed, at most
  /// [kTabNameMaxLength] characters; blank restores the automatic title.
  void rename(int id, String? name) {
    final clipped = clipName(name ?? '', kTabNameMaxLength);
    final value = clipped.isEmpty ? null : clipped;
    _update(id, (t) => t.copyWith(customTitle: value));
  }

  /// A notice from outside the tab list (workspaces, port links).
  void showNotice(TabNotice notice) => _set(notice: notice);

  // ---- panes (A3) -------------------------------------------------------

  /// Stores the size for later decisions only: safe during layout.
  void reportPaneMetrics(PaneMetrics metrics) => _metrics = metrics;

  /// ⌘D / ⌘⇧D (D3): the selected tab's focused pane, in its directory
  /// (D17), at half its grid; the new pane is focused.
  Future<void> split(SplitAxis axis) async {
    final tab = state.selected;
    if (tab == null || state.opening) return;
    final target = tab.focusedPaneId;
    if (!_roomToSplit(tab, target, axis)) {
      _set(notice: const PaneNoRoomNotice());
      return;
    }
    final pane = tab.panes[target]!;
    final grid = _halfGrid(pane, axis);
    _set(opening: true);
    _awaitingOpens++;
    var held = true;
    void release() {
      if (!held) return;
      held = false;
      _awaitingOpens--;
    }

    var synced = false;
    try {
      final id = await _local.open(
        cols: grid.cols,
        rows: grid.rows,
        cwd: pane.cwd,
      );
      if (!ref.mounted) return;
      release();
      _adoptPane(id, tabId: tab.id, target: target, axis: axis, size: grid);
      synced = true; // [_adoptPane] synced.
    } on SessionLimitException catch (error) {
      if (ref.mounted) _set(notice: SessionLimitNotice(error.max));
    } on SpawnFailedException catch (error) {
      if (ref.mounted) {
        _set(notice: SpawnFailedNotice(spawnFailureOf(error.message)));
      }
    } finally {
      release();
      if (ref.mounted) {
        // D5: as in [openTab], desktop sessions held back while the open
        // was pending get their tabs now, even when the open failed.
        if (!synced) _sync();
        _set(opening: false);
      }
    }
  }

  /// A click in a pane, a jump to a notification: [sessionId]'s tab is
  /// selected and the pane focused; a zoom that hides it ends (D10).
  void focusPane(int sessionId) {
    final tab = state.tabOfSession(sessionId);
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
    if (state.selectedId != tab.id) {
      _restoreMaySelect = false; // the user chose (A5a D10)
      _set(selectedId: tab.id);
    } else if (unzoom) {
      _visibleChanged();
    }
  }

  /// ⌘⌥arrows (D9). False when there is no pane that way.
  bool focusDirection(PaneDirection direction) {
    final tab = state.selected;
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
    final tab = state.selected;
    if (tab == null || !tab.isSplit) return false;
    final zoom = tab.zoomedPaneId == null;
    _replaceTab(tab.copyWith(zoomedPaneId: zoom ? tab.focusedPaneId : null));
    if (!zoom) _visibleChanged();
    return zoom;
  }

  /// ⌘⌃= (D11). Unzooms first (D10, final ruling m-4): a layout change
  /// the user cannot see would only surprise them later.
  void equalize() {
    final tab = state.selected;
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
    final tab = state.selected;
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

  // ---- internals --------------------------------------------------------

  void _step(int delta) {
    final tabs = state.tabs;
    if (tabs.isEmpty) return;
    final i = tabs.indexWhere((t) => t.id == state.selectedId);
    final next = i < 0 ? 0 : (i + delta) % tabs.length;
    _restoreMaySelect = false; // the user chose (A5a D10)
    _set(selectedId: tabs[next < 0 ? next + tabs.length : next].id);
  }

  TerminalTab? _tab(int id) {
    for (final tab in state.tabs) {
      if (tab.id == id) return tab;
    }
    return null;
  }

  /// [own]: a session this window just opened, placed even while other
  /// opens are pending (A5a D16).
  void _sync({int? own}) {
    if (!ref.mounted) return;
    final tabs = _merge(state.tabs, own: own);
    _set(tabs: tabs, selectedId: state.selectedId ?? tabs.firstOrNull?.id);
  }

  /// Existing tabs keep their place (and their panes stay while a session
  /// is gone but its exit is not handled yet); new sessions are appended as
  /// one-pane tabs — except a desktop session while this window's own open
  /// is pending (D5): the opener decides whether it is a tab or a pane —
  /// and a session a restore holds for its tree (A5a).
  List<TerminalTab> _merge(List<TerminalTab> current, {int? own}) {
    final summaries = {for (final s in _local.sessions) s.id: s};
    final next = <TerminalTab>[];
    for (final tab in current) {
      var updated = tab;
      for (final id in tab.panes.keys) {
        final s = summaries.remove(id);
        if (s == null) continue;
        updated = updated.withPane(
          id,
          (p) => p.copyWith(
            title: s.title,
            phoneAttached: s.phoneAttached,
            runningCommand: s.runningCommand,
            driver: s.driver,
            cwd: s.cwd,
            gitBranch: s.gitBranch,
            ports: s.ports,
          ),
        );
      }
      next.add(updated);
    }
    for (final s in summaries.values) {
      if (_restoreHeld.contains(s.id)) continue;
      if (_awaitingOpens > 0 &&
          s.origin == SessionOrigin.desktop &&
          s.id != own) {
        continue;
      }
      final pane = _attach(s);
      if (pane != null) next.add(TerminalTab.single(pane));
    }
    return next;
  }

  PaneSession? _attach(SessionSummary s, {TerminalGrid? size}) {
    final LocalSessionView view;
    try {
      view = _local.view(s.id);
    } on StateError {
      return null; // Ended between the listing and now.
    }
    final terminal = DesktopTerminal(platform: _platform());
    final feed = TerminalFeed(terminal.write);
    final link = _Link(view, terminal, feed);
    _links[s.id] = link;
    // Size first, without telling the session: the backlog is laid out at
    // the pane's width, and a phone keeps driving until the user acts.
    final grid = size ?? _grid;
    terminal.resize(grid.cols, grid.rows);
    // A5a D8: the saved text sits above everything the new shell prints,
    // in this terminal only — never the PTY, never a phone.
    final restored = _restoreText.remove(s.id);
    if (restored != null) feed.add(utf8.encode(restored));
    feed.add(view.backlog);
    feed.drain();
    // A5a D8: [onReply] is set only after the drain above — load-bearing.
    // Saved text holding a query (`ESC[6n`, `ESC[c`) is answered into
    // nothing; a reply must never reach the new shell.
    // Plain assignments: a cascade after an arrow closure would be parsed
    // as part of that closure's body.
    terminal.onUserInput = (data) => _onUserInput(s.id, data);
    terminal.onReply = (data) => view.reply(utf8.encode(data));
    terminal.onResize = (cols, rows, _, _) {
      // A3 D13 (A1's rule, per pane): every pane is laid out (IndexedStack,
      // Offstage under zoom); only visible ones tell their session, so a
      // hidden pane the phone drives keeps the phone driver and its size.
      if (!_reportsSize(s.id)) return;
      if (state.tabOfSession(s.id)?.isSplit == false) {
        _grid = (cols: cols, rows: rows);
      }
      view.resize(cols, rows);
    };
    link.subscriptions
      ..add(
        view.output.listen((bytes) {
          feed.add(bytes);
          if (!_paneOutputs.isClosed) _paneOutputs.add(s.id);
        }),
      )
      ..add(
        view.driver.listen(
          (side) => _updatePane(s.id, (p) => p.copyWith(driver: side)),
        ),
      );
    unawaited(view.exitCode.then((code) => _exited(s.id, code)));
    return PaneSession(
      id: s.id,
      index: s.index,
      shell: s.shell,
      title: s.title,
      origin: s.origin,
      phoneAttached: s.phoneAttached,
      runningCommand: s.runningCommand,
      driver: s.driver,
      terminal: terminal,
      selection: link.selection,
      cwd: s.cwd,
      gitBranch: s.gitBranch,
      ports: s.ports,
    );
  }

  void _onUserInput(int id, String data) {
    final pane = state.tabOfSession(id)?.panes[id];
    if (pane == null) return;
    if (pane.exited) {
      // UI §2.6: Enter closes an exited pane (D7); other keys are ignored.
      if (data.contains('\r')) _removePane(id);
      return;
    }
    _links[id]?.view.write(utf8.encode(data));
  }

  void _exited(int id, int code) {
    if (!ref.mounted) return;
    final link = _links[id];
    if (link == null) return; // Already closed here.
    if (code == 0 || link.view.closedOnRequest) {
      _removePane(id);
      return;
    }
    link.feed.drain();
    final terminal = link.terminal;
    final line = ref.read(appL10nProvider).terminalExitedLine(code);
    final at = line.indexOf('$code');
    final newline = terminal.buffer.cursorX == 0 ? '' : '\r\n';
    if (at < 0) {
      // A translation without the number: the whole line dim.
      terminal.write('$newline\x1b[2m$line\x1b[0m\x1b[?25l');
    } else {
      final before = line.substring(0, at);
      final after = line.substring(at + '$code'.length);
      // UI §2.6: dim text, the code in red, cursor hidden.
      terminal.write(
        '$newline\x1b[2m$before\x1b[22;31m$code\x1b[39;2m$after'
        '\x1b[0m\x1b[?25l',
      );
    }
    _updatePane(id, (p) => p.copyWith(exitCode: code));
  }

  void _update(int id, TerminalTab Function(TerminalTab tab) change) {
    if (!ref.mounted) return;
    _set(tabs: [for (final t in state.tabs) t.id == id ? change(t) : t]);
  }

  void _updatePane(int sessionId, PaneSession Function(PaneSession) change) {
    if (!ref.mounted) return;
    _set(
      tabs: [
        for (final t in state.tabs)
          t.panes.containsKey(sessionId) ? t.withPane(sessionId, change) : t,
      ],
    );
  }

  void _replaceTab(TerminalTab tab) =>
      _set(tabs: [for (final t in state.tabs) t.id == tab.id ? tab : t]);

  void _removeTab(int tabId) {
    final tabs = List.of(state.tabs);
    final i = tabs.indexWhere((t) => t.id == tabId);
    if (i < 0) return;
    for (final id in tabs[i].panes.keys) {
      _links.remove(id)?.dispose();
    }
    tabs.removeAt(i);
    var selected = state.selectedId;
    if (selected == tabId) selected = _successorOf(tabId, tabs);
    final before = state.selectedId;
    state = TerminalTabsState(
      tabs: tabs,
      selectedId: selected,
      notice: state.notice,
      opening: state.opening,
    );
    if (state.selectedId != before) _visibleChanged();
  }

  /// D7/D8: the sibling takes the place; focus goes to the most recently
  /// used remaining pane. The last pane takes the tab with it.
  void _removePane(int sessionId) {
    final tab = state.tabOfSession(sessionId);
    if (tab == null) {
      _links.remove(sessionId)?.dispose();
      return;
    }
    if (!tab.isSplit) {
      _removeTab(tab.id);
      return;
    }
    _links.remove(sessionId)?.dispose();
    final layout = removePane(tab.layout, sessionId)!;
    final remaining = paneIds(layout);
    final history = [
      for (final id in tab.paneHistory)
        if (id != sessionId && remaining.contains(id)) id,
    ];
    var focused = tab.focusedPaneId;
    if (focused == sessionId) {
      focused =
          history.firstOrNull ??
          siblingLeaf(tab.layout, sessionId) ??
          remaining.first;
    }
    final unzoom = tab.zoomedPaneId == sessionId;
    // Criterion 13: a tab left with one pane looks exactly like A4 — never
    // zoomed (the remaining pane was the zoomed one: already visible).
    final zoomed = unzoom || remaining.length == 1 ? null : tab.zoomedPaneId;
    _replaceTab(
      tab.copyWith(
        layout: layout,
        panes: Map.of(tab.panes)..remove(sessionId),
        focusedPaneId: focused,
        paneHistory: [focused, ...history.where((id) => id != focused)],
        zoomedPaneId: zoomed,
      ),
    );
    if (unzoom && state.selectedId == tab.id) _visibleChanged();
  }

  /// D3: session [id] (opened by [split]) joins tab [tabId] next to
  /// [target]. When it ended already, or its tab went while it opened, the
  /// normal rules apply: a tab of its own, selected.
  void _adoptPane(
    int id, {
    required int tabId,
    required int target,
    required SplitAxis axis,
    required TerminalGrid size,
  }) {
    final summary = _local.sessions.where((s) => s.id == id).firstOrNull;
    final tab = _tab(tabId);
    if (summary == null || tab == null) {
      _sync(own: id);
      if (state.tabOfSession(id) case final own?) {
        _restoreMaySelect = false;
        _set(selectedId: own.id);
      }
      return;
    }
    final pane = _attach(summary, size: size);
    if (pane == null) {
      _sync(); // Ended between the listing and now; others may wait (D5).
      return;
    }
    final at = tab.panes.containsKey(target) ? target : tab.paneOrder.first;
    final wasZoomed = tab.zoomedPaneId != null;
    _replaceTab(
      tab.copyWith(
        layout: splitPane(tab.layout, at, id, axis),
        panes: {...tab.panes, id: pane},
        focusedPaneId: id,
        zoomedPaneId: null,
        paneHistory: [id, ...tab.paneHistory],
      ),
    );
    _sync();
    // Final ruling m-1: a split that finishes after the user moved to
    // another tab stays in its own tab; it never pulls the user back.
    if (state.selectedId == tabId && wasZoomed) _visibleChanged();
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

  /// D13: the selected tab's live panes, minus those a zoom hides.
  bool _reportsSize(int sessionId) {
    final tab = state.tabOfSession(sessionId);
    if (tab == null || tab.id != state.selectedId) return false;
    // An exited pane's session is gone: nothing to tell it.
    if (tab.panes[sessionId]?.exited ?? true) return false;
    final zoomed = tab.zoomedPaneId;
    return zoomed == null || zoomed == sessionId;
  }

  /// I2: the sidebar decides (its visible order, the same one ⌘1–9,
  /// Ctrl+Tab and ↑/↓ follow) when it is there; without one, the creation
  /// order neighbour. [remaining] no longer holds [closed].
  int? _successorOf(int closed, List<TerminalTab> remaining) {
    if (remaining.isEmpty) return null;
    final next = ref.read(closeSuccessorProvider).choose?.call(closed);
    if (next != null && remaining.any((t) => t.id == next)) return next;
    final i = state.tabs.indexWhere((t) => t.id == closed);
    return remaining[min(max(i, 0), remaining.length - 1)].id;
  }

  /// Panes that just became visible (a new selection, an unzoom) tell
  /// their sessions the size they were laid out at while hidden; a size
  /// that did not change is ignored by the agent.
  void _visibleChanged() {
    final tab = state.selected;
    if (tab == null) return;
    for (final id in tab.paneOrder) {
      final pane = tab.panes[id];
      final link = _links[id];
      if (pane == null || link == null || pane.exited) continue;
      if (!_reportsSize(id)) continue;
      final terminal = link.terminal;
      if (!tab.isSplit) {
        _grid = (cols: terminal.viewWidth, rows: terminal.viewHeight);
      }
      link.view.resize(terminal.viewWidth, terminal.viewHeight);
    }
  }

  static const Object _keep = Object();

  void _set({
    List<TerminalTab>? tabs,
    Object? selectedId = _keep,
    Object? notice = _keep,
    bool? opening,
  }) {
    final before = state.selectedId;
    state = TerminalTabsState(
      tabs: tabs ?? state.tabs,
      selectedId: identical(selectedId, _keep)
          ? state.selectedId
          : selectedId as int?,
      notice: identical(notice, _keep) ? state.notice : notice as TabNotice?,
      opening: opening ?? state.opening,
    );
    if (state.selectedId != before) _visibleChanged();
  }

  TerminalTargetPlatform _platform() => switch (defaultTargetPlatform) {
    TargetPlatform.macOS => TerminalTargetPlatform.macos,
    TargetPlatform.windows => TerminalTargetPlatform.windows,
    _ => TerminalTargetPlatform.unknown,
  };

  void _dispose() {
    unawaited(_changes?.cancel());
    for (final link in _links.values) {
      link.dispose();
    }
    _links.clear();
    // Sessions of the old [LocalSessions]: nothing to hold or write now.
    _restoreHeld.clear();
    _restoreText.clear();
    // A rebuild reuses this notifier and keeps the stream; only a real
    // dispose leaves the ref unmounted once this turn is over.
    scheduleMicrotask(() {
      bool alive;
      try {
        alive = ref.mounted;
      } on Object {
        alive = false;
      }
      if (!alive) unawaited(_paneOutputs.close());
    });
  }
}
