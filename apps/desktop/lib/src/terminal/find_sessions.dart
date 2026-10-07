import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ui/theme/shellx_desktop_theme.dart' show ShellxDesktopColors;
import '../ui/window_focus.dart' show terminalFocusRequestProvider;
import 'find_session.dart';
import 'terminal_tabs.dart';

/// A10 D3: the panes that have a find bar open, by session id. At most one
/// bar per pane; a pane that goes away takes its bar (highlights and
/// anchors included) with it.
final findSessionsProvider =
    NotifierProvider<FindSessions, Map<int, FindSession>>(FindSessions.new);

class FindSessions extends Notifier<Map<int, FindSession>> {
  final _all = <int, FindSession>{};

  @override
  Map<int, FindSession> build() {
    // A8 D22: a reconnect gives the pane a new session id (and may give it
    // a new highlight controller); its bar follows, query and all. The
    // event comes before the tab state changes, so the terminal is
    // rebound by the tabs listener below.
    final replaced = ref
        .read(terminalTabsProvider.notifier)
        .paneReplacements
        .listen((r) {
          final session = _all.remove(r.from);
          if (session == null) return;
          _all[r.to] = session;
          state = Map.of(_all);
        });
    ref.onDispose(() {
      unawaited(replaced.cancel());
      for (final s in _all.values) {
        s.close();
      }
      _all.clear();
    });
    ref.listen<TerminalTabsState>(terminalTabsProvider, (_, next) {
      final live = {for (final t in next.tabs) ...t.panes};
      for (final e in _all.entries) {
        final pane = live[e.key];
        if (pane != null) e.value.rebind(pane.terminal, pane.selection);
      }
      final gone = [
        for (final id in _all.keys)
          if (!live.containsKey(id)) id,
      ];
      for (final id in gone) {
        close(id);
      }
    });
    return const {};
  }

  /// Opens pane [id]'s bar, or returns the open one. A one-line selection
  /// (at most [kMaxFindQuery] characters) is the starting query.
  FindSession? open(int id) {
    final existing = _all[id];
    if (existing != null) return existing;
    final pane = ref.read(terminalTabsProvider).tabOfSession(id)?.panes[id];
    if (pane == null) return null;
    final session = FindSession(
      terminal: pane.terminal,
      controller: pane.selection,
      matchColor: ShellxDesktopColors.accent.withValues(alpha: 0.25),
      currentColor: ShellxDesktopColors.accent.withValues(alpha: 0.55),
    );
    final range = pane.selection.selection;
    if (range != null) {
      final text = pane.terminal.buffer.getText(range);
      if (text.isNotEmpty &&
          !text.contains('\n') &&
          text.length <= kMaxFindQuery) {
        session.setQuery(text);
      }
    }
    _all[id] = session;
    state = Map.of(_all);
    return session;
  }

  void close(int id) {
    final session = _all.remove(id);
    if (session == null) return;
    // A bar that had the keyboard must not leave it on a widget that goes.
    final hadFocus = session.focusNode.hasFocus;
    session.close();
    if (hadFocus && ref.mounted) {
      ref.read(terminalFocusRequestProvider.notifier).request();
    }
    if (ref.mounted) state = Map.of(_all);
  }
}
