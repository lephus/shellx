part of 'terminal_tabs.dart';

// A8: SSH and tmux panes — the lost-connection line, reconnect in place
// (D20–D22), the id forwarding table, the named toasts. Kept apart from
// the tab list's own bookkeeping.

/// A8 D3: no ssh binary.
final class SshUnavailableNotice extends TabNotice {
  const SshUnavailableNotice();
}

/// A8 D25: no tmux on this computer.
final class TmuxUnavailableNotice extends TabNotice {
  const TmuxUnavailableNotice();
}

/// A8 D19: the port could not be forwarded.
final class RemotePortForwardFailedNotice extends TabNotice {
  const RemotePortForwardFailedNotice(this.port);
  final int port;
}

/// The toast for a failed open: the named A8 ones, else A1's wording.
TabNotice spawnNoticeFor(SpawnFailedException error) => switch (error.message) {
  'ssh_unavailable' => const SshUnavailableNotice(),
  'tmux_unavailable' => const TmuxUnavailableNotice(),
  _ => SpawnFailedNotice(spawnFailureOf(error.message)),
};

/// A8 D22: pane [from] of tab [tabId] is now session [to].
@immutable
final class PaneReplacement {
  const PaneReplacement({
    required this.tabId,
    required this.from,
    required this.to,
  });
  final int tabId;
  final int from;
  final int to;

  @override
  bool operator ==(Object other) =>
      other is PaneReplacement &&
      other.tabId == tabId &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(tabId, from, to);
}

/// A8 D22: how many replaced ids [TerminalTabs.resolveReplaced] remembers.
const int kReplacedMemory = 64;

/// What [TerminalTabs] keeps for reconnects. Never closed on a rebuild (the
/// notifier outlives it, Riverpod 3): only when the provider really goes.
final class _RemoteBook {
  final replacements = StreamController<PaneReplacement>.broadcast(sync: true);
  final replaced = <int, int>{};
  final reconnecting = <int>{};

  Future<void> close() => replacements.close();
}

extension TerminalTabsRemote on TerminalTabs {
  /// A8 D22: emitted before the tab changes, so listeners can move what
  /// they keep for [PaneReplacement.from] first.
  Stream<PaneReplacement> get paneReplacements => _remote.replacements.stream;

  /// A8 D22: the pane a reconnect made of [id] (followed along a chain);
  /// [id] itself when it was never replaced.
  int resolveReplaced(int id) {
    var current = id;
    for (var i = 0; i < kReplacedMemory; i++) {
      final next = _remote.replaced[current];
      if (next == null) break;
      current = next;
    }
    return current;
  }

  /// UI-A8 §3.2: a dim line, nothing red, cursor hidden (as A1's exit
  /// line), for a pane whose connection ended. False for anything else.
  bool _writeLostLine(int id, int code, DesktopTerminal terminal) {
    final pane = _state.tabOfSession(id)?.panes[id];
    final remote = pane?.remote;
    if (pane == null || remote == null) return false;
    final lost = remoteStateOf(
      remote: remote,
      exitCode: code,
      everConnected: pane.everConnected,
    );
    if (lost != RemoteState.disconnected && lost != RemoteState.failed) {
      return false;
    }
    final l10n = _ref.read(appL10nProvider);
    final host = remote.hostKey!;
    final line = lost == RemoteState.disconnected
        ? l10n.sshDisconnectedLine(host)
        : l10n.sshFailedLine(host);
    final newline = terminal.buffer.cursorX == 0 ? '' : '\r\n';
    terminal.write('$newline\x1b[2m$line\x1b[0m\x1b[?25l');
    _updatePane(id, (p) => p.copyWith(exitCode: code));
    return true;
  }

  /// A8 D20–D22: a new session for the lost pane [sessionId], in the same
  /// place of the same tab, writing into the same terminal. Null when the
  /// pane cannot reconnect, ShellX stayed busy opening for 10 s, the pane
  /// went meanwhile, or the open failed (with its toast).
  Future<int?> reconnect(int sessionId, {bool withoutHook = false}) async {
    if (!_remote.reconnecting.add(sessionId)) return null;
    try {
      for (var i = 0; _state.opening; i++) {
        if (i >= 200 || !_ref.mounted) return null;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      if (!_ref.mounted) return null;
      final before = _state.tabOfSession(sessionId);
      final pane = before?.panes[sessionId];
      if (before == null || pane == null || !pane.canReconnect) return null;
      var launch = pane.remote!.launch.forReconnect(pane.cwd);
      if (withoutHook) launch = launchWithoutHook(launch);
      final grid = (
        cols: max(1, pane.terminal.viewWidth),
        rows: max(1, pane.terminal.viewHeight),
      );
      return await _guardedOpen(
        () => _local.open(
          cols: grid.cols,
          rows: grid.rows,
          tabId: before.id,
          launch: launch,
        ),
        (id) => _placeReconnected(sessionId, id, grid),
      );
    } on OpenBusyException {
      return null;
    } on PaneGoneException {
      return null; // closed meanwhile, or ended before it could be placed
    } on SessionLimitException catch (error) {
      if (_ref.mounted) _set(notice: SessionLimitNotice(error.max));
      return null;
    } on SpawnFailedException catch (error) {
      if (_ref.mounted) _set(notice: spawnNoticeFor(error));
      return null;
    } finally {
      _remote.reconnecting.remove(sessionId);
    }
  }

  /// The [_guardedOpen] placement of a reconnect: the new session [id]
  /// takes pane [from]'s slot. It must be in the tab before [_sync] runs,
  /// or [_merge] would make it a tab of its own.
  int _placeReconnected(int from, int id, TerminalGrid grid) {
    final tab = _state.tabOfSession(from);
    final old = tab?.panes[from];
    if (tab == null || old == null) {
      _local.close(id); // the pane was closed while we connected
      throw const PaneGoneException();
    }
    final summary = _local.sessions.where((s) => s.id == id).firstOrNull;
    if (summary == null) throw const PaneGoneException();
    final next = _attach(
      summary,
      size: grid,
      reuse: old.terminal,
      preface: _reconnectedDivider(),
    );
    if (next == null) throw const PaneGoneException();
    _swapPane(
      tab,
      from,
      next.copyWith(everConnected: old.everConnected || next.everConnected),
    );
    _sync(own: id);
    return id;
  }

  /// UI-A8 §3.4: cursor back, a dim divider with the time (A5a D23 style).
  String _reconnectedDivider() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final line = _ref
        .read(appL10nProvider)
        .sshReconnectedDivider('${two(now.hour)}:${two(now.minute)}');
    return '\x1b[?25h\r\n\x1b[0m\x1b[2m$line\x1b[0m\r\n';
  }

  void _swapPane(TerminalTab tab, int from, PaneSession pane) {
    final to = pane.id;
    final book = _remote;
    book.replaced[from] = to;
    while (book.replaced.length > kReplacedMemory) {
      book.replaced.remove(book.replaced.keys.first);
    }
    book.replacements.add(PaneReplacement(tabId: tab.id, from: from, to: to));
    // The old link's view goes; the terminal stays: it moved to [pane].
    _links.remove(from)?.dispose();
    int map(int id) => id == from ? to : id;
    final zoomed = tab.zoomedPaneId;
    _replaceTab(
      tab.copyWith(
        layout: replaceLeaf(tab.layout, from, to),
        panes: {
          for (final e in tab.panes.entries)
            if (e.key == from) to: pane else e.key: e.value,
        },
        focusedPaneId: map(tab.focusedPaneId),
        zoomedPaneId: zoomed == null ? null : map(zoomed),
        paneHistory: [for (final id in tab.paneHistory) map(id)],
      ),
    );
    if (_state.selectedId == tab.id) _visibleChanged();
  }
}
