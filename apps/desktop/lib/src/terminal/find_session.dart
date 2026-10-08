import 'dart:async';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show FocusNode;
import 'package:xterm/xterm.dart';

import 'terminal_search.dart';

/// The longest search text (A10 D3).
const int kMaxFindQuery = 200;

/// The longest the search holds the UI thread at a time (A10 D3).
const Duration kFindSlice = Duration(milliseconds: 4);

/// One pane's find (A10 D3-D5): the query, its matches in the pane's whole
/// buffer, the current one, and the highlights drawn for them.
///
/// A search runs in slices of [kFindSlice] so a huge scrollback never
/// freezes the window: the first slice runs at once (a small buffer is
/// finished before [setQuery] returns), the rest after [queryDebounce] and
/// then one slice per event-loop turn; a new query cancels the old search.
/// Output refreshes the matches after [refreshAfter], backing off to
/// [busyRefreshAfter] while it keeps streaming, and leaves the highlights
/// alone when nothing changed. The current match is followed through its
/// highlight's anchors, so it survives scrollback being trimmed.
final class FindSession extends ChangeNotifier {
  FindSession({
    required this.terminal,
    required this.controller,
    required this.matchColor,
    required this.currentColor,
    this.refreshAfter = const Duration(milliseconds: 150),
    this.busyRefreshAfter = const Duration(milliseconds: 500),
    this.queryDebounce = const Duration(milliseconds: 150),
    this.slice = kFindSlice,
  }) {
    terminal.addListener(_onTerminal);
  }

  Terminal terminal;
  TerminalController controller;
  final Color matchColor;
  final Color currentColor;
  final Duration refreshAfter;
  final Duration busyRefreshAfter;
  final Duration queryDebounce;

  /// How long one slice of a search may run.
  final Duration slice;

  /// The bar's input: focused when the bar opens or ⌘F is pressed again.
  final FocusNode focusNode = FocusNode(debugLabel: 'find');

  /// Scrolls match [m] into view; set by the pane that shows the bar.
  void Function(SearchMatch m)? reveal;

  String _query = '';
  bool _matchCase = false;
  SearchResult _result = const SearchResult([]);
  int _current = -1;
  final _highlights = <TerminalHighlight>[];
  BufferSearch? _search;
  Timer? _work;
  Timer? _refreshTimer;
  Timer? _idle;
  var _pickLast = true;
  int? _goToRow;
  var _scroll = false;
  var _dirty = false;
  var _restarts = 0;
  var _streak = 0;
  bool _closed = false;

  String get query => _query;
  bool get matchCase => _matchCase;
  List<SearchMatch> get matches => _result.matches;
  bool get capped => _result.capped;

  /// Index of the current match; -1 when there is none.
  int get current => _current;
  bool get hasQuery => _query.isNotEmpty;

  /// A search is still running (a huge buffer).
  bool get searching => _search != null;

  /// Never shows the query (A10 §5).
  @override
  String toString() => 'FindSession(…)';

  void setQuery(String text) {
    var q = text.replaceAll(RegExp(r'[\r\n]'), '');
    if (q.length > kMaxFindQuery) q = q.substring(0, kMaxFindQuery);
    if (q == _query) return;
    _query = q;
    _restarts = 0;
    _begin(pickLast: true, scroll: true, debounce: true);
  }

  void toggleMatchCase() {
    _matchCase = !_matchCase;
    _restarts = 0;
    _begin(pickLast: true, scroll: true, debounce: true);
  }

  /// The pane's terminal and highlight controller were replaced (a
  /// reconnect); the bar and the query stay.
  void rebind(Terminal newTerminal, TerminalController newController) {
    if (_closed ||
        (identical(newTerminal, terminal) &&
            identical(newController, controller))) {
      return;
    }
    _cancelWork();
    terminal.removeListener(_onTerminal);
    _clearHighlights();
    terminal = newTerminal;
    controller = newController;
    terminal.addListener(_onTerminal);
    _current = -1;
    _restarts = 0;
    _begin(pickLast: true, scroll: false, debounce: false);
  }

  /// A11 D21: stands on the first match whose row is at or after [row]
  /// (wrapping to the first) and shows it. While a search is still running
  /// it is done once the search has its matches.
  void goToMatchAtOrAfter(int row) {
    if (_closed) return;
    if (_search != null || _refreshTimer != null) {
      _goToRow = row;
      return;
    }
    _goTo(row);
  }

  bool _goTo(int row) {
    final i = firstMatchFrom(matches, row);
    if (i < 0 || _highlights.length != matches.length) return false;
    final live = _liveOf(i);
    if (live == null) return false;
    _setCurrent(i, live);
    return true;
  }

  void next() => _step(1);
  void previous() => _step(-1);

  /// The match highlight [i] stands on now, wherever the buffer has moved
  /// it; null when its line has been trimmed away.
  SearchMatch? _liveOf(int i) {
    final h = _highlights[i];
    if (!h.p1.attached || !h.p2.attached) return null;
    return SearchMatch(h.p1.y, h.p1.x, h.p2.y, h.p2.x);
  }

  void _step(int delta) {
    final n = matches.length;
    if (n == 0 || _highlights.length != n) return;
    // Skip matches whose line has scrolled out of the history.
    for (var k = 1; k <= n; k++) {
      final i = ((_current + delta * k) % n + n) % n;
      final live = _liveOf(i);
      if (live == null) continue;
      _setCurrent(i, live);
      return;
    }
  }

  void _onTerminal() {
    if (_closed || !hasQuery) return;
    if (_search != null) _dirty = true;
    if (_refreshTimer != null) return;
    _refreshTimer = Timer(_streak > 0 ? busyRefreshAfter : refreshAfter, () {
      _refreshTimer = null;
      if (_closed) return;
      _streak++;
      _idle?.cancel();
      _idle = Timer(const Duration(seconds: 1), () => _streak = 0);
      _begin(pickLast: false, scroll: false, debounce: false);
    });
  }

  void _cancelWork() {
    _work?.cancel();
    _work = null;
    _search = null;
  }

  void _begin({
    required bool pickLast,
    required bool scroll,
    required bool debounce,
  }) {
    _cancelWork();
    _pickLast = pickLast;
    _scroll = scroll;
    _dirty = false;
    if (!hasQuery) {
      _goToRow = null;
      _publish(const SearchResult([]));
      return;
    }
    final search = BufferSearch(terminal.buffer, _query, matchCase: _matchCase);
    _search = search;
    if (search.step(slice)) {
      _finish();
      return;
    }
    _work = Timer(debounce ? queryDebounce : Duration.zero, _slice);
  }

  void _slice() {
    _work = null;
    final search = _search;
    if (_closed || search == null) return;
    if (search.step(slice)) {
      _finish();
    } else {
      _work = Timer(Duration.zero, _slice);
    }
  }

  void _finish() {
    final search = _search!;
    _search = null;
    if (_dirty && _restarts < 2) {
      // Output arrived while the buffer was being read: read it again.
      _restarts++;
      _begin(pickLast: _pickLast, scroll: _scroll, debounce: false);
      return;
    }
    _restarts = 0;
    _publish(search.result);
  }

  bool _sameAsHighlights(List<SearchMatch> found) {
    if (found.length != _highlights.length) return false;
    for (var i = 0; i < found.length; i++) {
      if (_liveOf(i) != found[i]) return false;
    }
    return true;
  }

  void _publish(SearchResult found) {
    _publishFound(found);
    final goTo = _goToRow;
    if (goTo != null) {
      _goToRow = null;
      _goTo(goTo);
    }
  }

  void _publishFound(SearchResult found) {
    final hadCurrent = _current >= 0 && _current < _highlights.length;
    if (!_pickLast && hadCurrent && _sameAsHighlights(found.matches)) {
      // Nothing moved: no highlight is rebuilt.
      final cappedChanged = found.capped != _result.capped;
      _result = found;
      if (cappedChanged) notifyListeners();
      return;
    }
    final before = hadCurrent ? _liveOf(_current) : null;
    _result = found;
    _clearHighlights();
    if (matches.isEmpty) {
      _current = -1;
      notifyListeners();
      return;
    }
    if (_pickLast || !hadCurrent) {
      _current = matches.length - 1;
    } else if (before == null) {
      _current = 0; // the match the user was on has left the history
    } else {
      // Keep the match the user is on, if it is still there; else the one
      // that follows it.
      final same = matches.indexOf(before);
      _current = same >= 0 ? same : firstMatchFrom(matches, before.startRow);
    }
    _paint();
    if (_scroll) reveal?.call(matches[_current]);
    notifyListeners();
  }

  void _setCurrent(int i, SearchMatch live) {
    final old = _current;
    _current = i;
    if (old >= 0 && old < _highlights.length) _recolor(old, matchColor);
    _recolor(i, currentColor);
    reveal?.call(live);
    notifyListeners();
  }

  TerminalHighlight _highlightFor(SearchMatch m, Color color) {
    final buffer = terminal.buffer;
    return controller.highlight(
      p1: buffer.createAnchor(m.startCol, m.startRow),
      p2: buffer.createAnchor(m.endCol, m.endRow),
      color: color,
    );
  }

  void _paint() {
    for (var i = 0; i < matches.length; i++) {
      _highlights.add(
        _highlightFor(matches[i], i == _current ? currentColor : matchColor),
      );
    }
  }

  /// Changes a highlight's colour; its anchors stay (they hold its place).
  void _recolor(int i, Color color) {
    final old = _highlights[i];
    _disposeHighlight(old);
    _highlights[i] = controller.highlight(p1: old.p1, p2: old.p2, color: color);
  }

  void _disposeHighlight(TerminalHighlight h) {
    try {
      h.dispose();
    } on Object {
      // A pane that closes disposes its controller before this session
      // hears of it: the highlight is gone with it.
    }
  }

  void _clearHighlights() {
    for (final h in _highlights) {
      h.p1.dispose();
      h.p2.dispose();
      _disposeHighlight(h);
    }
    _highlights.clear();
  }

  /// The bar closed or its pane went: no highlight and no anchor is left.
  void close() => dispose();

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    _work?.cancel();
    _refreshTimer?.cancel();
    _idle?.cancel();
    _search = null;
    terminal.removeListener(_onTerminal);
    _clearHighlights();
    focusNode.dispose();
    super.dispose();
  }
}
