import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:xterm/xterm.dart';

import 'desktop_terminal.dart';
import 'local_sessions_provider.dart';
import 'terminal_feed.dart';
import 'terminal_style.dart';

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

/// D19: the longest tab name, in characters.
const int kTabNameMaxLength = 64;

const Object _unset = Object();

@immutable
final class TerminalTab {
  const TerminalTab({
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
    this.customTitle,
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

  /// C6: the user's name for this tab (desktop only); wins over [title].
  final String? customTitle;

  /// Non-null once the shell exited with a non-zero code (D14).
  final int? exitCode;

  bool get exited => exitCode != null;

  /// OSC 0/2 title, else `<shell> <index>` (D13, UI §5 terminalDefaultTitle).
  String get automaticLabel => title.isNotEmpty ? title : '$shell $index';

  /// What the sidebar, the window title and dialogs show.
  String get label => customTitle ?? automaticLabel;

  /// The row has a context line (UI-A2 §2.1).
  bool get hasContext => cwd != null || gitBranch != null || ports.isNotEmpty;

  TerminalTab copyWith({
    String? title,
    bool? phoneAttached,
    bool? runningCommand,
    DriverSide? driver,
    int? exitCode,
    Object? cwd = _unset,
    Object? gitBranch = _unset,
    List<int>? ports,
    Object? customTitle = _unset,
  }) => TerminalTab(
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
    customTitle: identical(customTitle, _unset)
        ? this.customTitle
        : customTitle as String?,
    exitCode: exitCode ?? this.exitCode,
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
    try {
      final id = await _local.open(cols: _grid.cols, rows: _grid.rows);
      if (!ref.mounted) return;
      _sync();
      // The new shell may already be gone (exit 0, or ended before it could
      // be viewed): then keep a selection that exists.
      final opened = _tab(id) != null;
      _set(
        selectedId: opened
            ? id
            : (state.selected?.id ?? state.tabs.firstOrNull?.id),
      );
    } on SessionLimitException catch (error) {
      if (ref.mounted) _set(notice: SessionLimitNotice(error.max));
    } on SpawnFailedException catch (error) {
      if (ref.mounted) {
        _set(notice: SpawnFailedNotice(spawnFailureOf(error.message)));
      }
    } finally {
      // Whatever happened (an unexpected error too), `+` is usable again.
      if (ref.mounted) _set(opening: false);
    }
  }

  /// D11: activation and startup open a tab when there is none.
  Future<void> ensureTab() async {
    if (state.tabs.isEmpty && !state.opening) await openTab();
  }

  void select(int id) {
    if (state.tabs.any((t) => t.id == id)) _set(selectedId: id);
  }

  /// ⌘1…⌘9: the n-th tab (1-based); nothing when there is none.
  void selectIndex(int position) {
    if (position >= 1 && position <= state.tabs.length) {
      _set(selectedId: state.tabs[position - 1].id);
    }
  }

  void next() => _step(1);
  void previous() => _step(-1);

  /// D15: a close asks first while a command runs.
  bool needsCloseConfirm(int id) {
    final tab = _tab(id);
    return tab != null && !tab.exited && tab.runningCommand;
  }

  /// ⌘W, "Đóng tab", middle click: the desktop may close every session (D4).
  void close(int id) {
    final tab = _tab(id);
    if (tab == null) return;
    if (!tab.exited) _local.close(id);
    _remove(id);
  }

  void dismissNotice() => _set(notice: null);

  /// C6/D19: the user's name for tab [id]; trimmed, at most
  /// [kTabNameMaxLength] characters; blank restores the automatic title.
  void rename(int id, String? name) {
    final trimmed = name?.trim() ?? '';
    final value = trimmed.isEmpty
        ? null
        : String.fromCharCodes(trimmed.runes.take(kTabNameMaxLength));
    _update(id, (t) => t.copyWith(customTitle: value));
  }

  /// A notice from outside the tab list (workspaces, port links).
  void showNotice(TabNotice notice) => _set(notice: notice);

  // ---- internals --------------------------------------------------------

  void _step(int delta) {
    final tabs = state.tabs;
    if (tabs.isEmpty) return;
    final i = tabs.indexWhere((t) => t.id == state.selectedId);
    final next = i < 0 ? 0 : (i + delta) % tabs.length;
    _set(selectedId: tabs[next < 0 ? next + tabs.length : next].id);
  }

  TerminalTab? _tab(int id) {
    for (final tab in state.tabs) {
      if (tab.id == id) return tab;
    }
    return null;
  }

  void _sync() {
    if (!ref.mounted) return;
    final tabs = _merge(state.tabs);
    _set(tabs: tabs, selectedId: state.selectedId ?? tabs.firstOrNull?.id);
  }

  /// Existing tabs keep their place (and stay while their session is gone
  /// but the exit is not handled yet); new sessions are appended.
  List<TerminalTab> _merge(List<TerminalTab> current) {
    final summaries = {for (final s in _local.sessions) s.id: s};
    final next = <TerminalTab>[];
    for (final tab in current) {
      final s = summaries.remove(tab.id);
      next.add(
        s == null
            ? tab
            : tab.copyWith(
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
    for (final s in summaries.values) {
      final tab = _attach(s);
      if (tab != null) next.add(tab);
    }
    return next;
  }

  TerminalTab? _attach(SessionSummary s) {
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
    terminal.resize(_grid.cols, _grid.rows);
    feed.add(view.backlog);
    feed.drain();
    // Plain assignments: a cascade after an arrow closure would be parsed
    // as part of that closure's body.
    terminal.onUserInput = (data) => _onUserInput(s.id, data);
    terminal.onReply = (data) => view.reply(utf8.encode(data));
    terminal.onResize = (cols, rows, _, _) {
      // Every tab's view is mounted (IndexedStack), so a window resize lays
      // them all out; only the selected one tells its session, so a hidden
      // tab the phone drives keeps the phone driver (and its size). A tab
      // sends its size when it becomes selected ([_selectionChanged]).
      if (state.selectedId != s.id) return;
      _grid = (cols: cols, rows: rows);
      view.resize(cols, rows);
    };
    link.subscriptions
      ..add(view.output.listen(feed.add))
      ..add(
        view.driver.listen(
          (side) => _update(s.id, (t) => t.copyWith(driver: side)),
        ),
      );
    unawaited(view.exitCode.then((code) => _exited(s.id, code)));
    return TerminalTab(
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
    final tab = _tab(id);
    if (tab == null) return;
    if (tab.exited) {
      // UI §2.6: Enter closes an exited tab; other keys are ignored.
      if (data.contains('\r')) _remove(id);
      return;
    }
    _links[id]?.view.write(utf8.encode(data));
  }

  void _exited(int id, int code) {
    if (!ref.mounted) return;
    final link = _links[id];
    if (link == null) return; // Already closed here.
    if (code == 0 || link.view.closedOnRequest) {
      _remove(id);
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
    _update(id, (t) => t.copyWith(exitCode: code));
  }

  void _update(int id, TerminalTab Function(TerminalTab tab) change) {
    if (!ref.mounted) return;
    _set(tabs: [for (final t in state.tabs) t.id == id ? change(t) : t]);
  }

  void _remove(int id) {
    _links.remove(id)?.dispose();
    final tabs = List.of(state.tabs);
    final i = tabs.indexWhere((t) => t.id == id);
    if (i < 0) return;
    tabs.removeAt(i);
    var selected = state.selectedId;
    if (selected == id) {
      selected = tabs.isEmpty ? null : tabs[min(i, tabs.length - 1)].id;
    }
    final before = state.selectedId;
    state = TerminalTabsState(
      tabs: tabs,
      selectedId: selected,
      notice: state.notice,
      opening: state.opening,
    );
    if (state.selectedId != before) _selectionChanged();
  }

  /// The newly selected tab's view tells its session the size it was laid
  /// out at while hidden (a resize while it was not selected went nowhere).
  void _selectionChanged() {
    final id = state.selectedId;
    final link = id == null ? null : _links[id];
    final tab = id == null ? null : _tab(id);
    if (link == null || tab == null || tab.exited) return;
    final terminal = link.terminal;
    _grid = (cols: terminal.viewWidth, rows: terminal.viewHeight);
    link.view.resize(terminal.viewWidth, terminal.viewHeight);
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
    if (state.selectedId != before) _selectionChanged();
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
  }
}
