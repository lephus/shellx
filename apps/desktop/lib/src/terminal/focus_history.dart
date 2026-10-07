import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'terminal_tabs.dart';

// A11 D15: back and forward through the panes the user looked at, as a
// browser does through pages. Memory only; what it holds is where the user
// has been, so nothing prints it.

/// One place: a pane and the tab it is in.
final class FocusEntry {
  const FocusEntry(this.tabId, this.paneId);
  final int tabId;
  final int paneId;

  @override
  bool operator ==(Object other) =>
      other is FocusEntry && other.tabId == tabId && other.paneId == paneId;

  @override
  int get hashCode => Object.hash(tabId, paneId);

  @override
  String toString() => '…';
}

/// The places visited, at most [max], and where the user is among them.
class FocusHistory {
  FocusHistory({this.max = 50});
  final int max;
  final List<FocusEntry> _s = [];
  int _i = -1;

  int get length => _s.length;
  FocusEntry? get current => _i >= 0 ? _s[_i] : null;

  /// The user went to [e]: a new place at the end (the "forward" part is
  /// cut, as a browser does); the place they are already at adds nothing.
  void visit(FocusEntry e) {
    if (_i >= 0 && _s[_i] == e) return;
    if (_i + 1 < _s.length) _s.removeRange(_i + 1, _s.length);
    _s.add(e);
    if (_s.length > max) _s.removeAt(0);
    _i = _s.length - 1;
  }

  /// The nearest earlier place that is still [alive]; null when none (the
  /// position then stays).
  /// A reconnect gave a pane a new session id: the places it was keep
  /// pointing at it.
  void remap(int from, int to) {
    for (var k = 0; k < _s.length; k++) {
      final e = _s[k];
      if (e.paneId == from) _s[k] = FocusEntry(e.tabId, to);
    }
  }

  FocusEntry? back(bool Function(FocusEntry) alive) => _go(-1, alive);

  FocusEntry? forward(bool Function(FocusEntry) alive) => _go(1, alive);

  FocusEntry? _go(int d, bool Function(FocusEntry) alive) {
    for (var j = _i + d; j >= 0 && j < _s.length; j += d) {
      if (alive(_s[j])) {
        _i = j;
        return _s[j];
      }
    }
    return null;
  }

  @override
  String toString() => '…';
}

final focusHistoryProvider =
    NotifierProvider<FocusHistoryNotifier, FocusHistory>(
      FocusHistoryNotifier.new,
    );

/// Records where the *user* goes and walks the history. The state is the
/// history itself (it changes in place; nothing watches it).
class FocusHistoryNotifier extends Notifier<FocusHistory> {
  /// True while [go] moves the focus: that move is not a new visit.
  bool navigating = false;

  @override
  FocusHistory build() {
    final history = FocusHistory();
    final first = _place(ref.read(terminalTabsProvider));
    if (first != null) history.visit(first);
    ref.listen<TerminalTabsState>(terminalTabsProvider, _onTabs);
    // The event comes before the state change (A8 D22).
    final replaced = ref
        .read(terminalTabsProvider.notifier)
        .paneReplacements
        .listen((r) => history.remap(r.from, r.to));
    ref.onDispose(replaced.cancel);
    return history;
  }

  static FocusEntry? _place(TerminalTabsState s) {
    final tab = s.selected;
    return tab == null ? null : FocusEntry(tab.id, tab.focusedPaneId);
  }

  void _onTabs(TerminalTabsState? prev, TerminalTabsState next) {
    if (prev == null || navigating) return;
    if (ref.read(terminalTabsProvider.notifier).restoring) return;
    final from = _place(prev);
    final to = _place(next);
    if (to == null || from == to) return;
    // A tab or pane that closed hands the focus to its successor: that is
    // not somewhere the user went.
    if (from != null && next.tabOfSession(from.paneId)?.id != from.tabId) {
      return;
    }
    state.visit(to);
  }

  bool _alive(FocusEntry e) =>
      ref.read(terminalTabsProvider).tabOfSession(e.paneId)?.id == e.tabId;

  /// One step back or forward; false when there is nowhere to go (nothing
  /// happens then, and nothing is said).
  bool go({required bool back}) {
    // Never "back" to where the user already is (a close that handed the
    // focus to the tab the history had just before).
    final here = _place(ref.read(terminalTabsProvider));
    bool alive(FocusEntry e) => e != here && _alive(e);
    final entry = back ? state.back(alive) : state.forward(alive);
    if (entry == null) return false;
    navigating = true;
    try {
      ref.read(terminalTabsProvider.notifier).focusPane(entry.paneId);
    } finally {
      navigating = false;
    }
    return true;
  }
}
