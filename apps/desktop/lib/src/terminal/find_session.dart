import 'dart:async';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show FocusNode;
import 'package:xterm/xterm.dart';

import 'terminal_search.dart';

/// The longest search text (A10 D3).
const int kMaxFindQuery = 200;

/// One pane's find (A10 D3–D5): the query, its matches in the pane's whole
/// buffer, the current one, and the highlights drawn for them.
final class FindSession extends ChangeNotifier {
  FindSession({
    required this.terminal,
    required this.controller,
    required this.matchColor,
    required this.currentColor,
    this.refreshAfter = const Duration(milliseconds: 150),
  }) {
    terminal.addListener(_onTerminal);
  }

  final Terminal terminal;
  final TerminalController controller;
  final Color matchColor;
  final Color currentColor;
  final Duration refreshAfter;

  /// The bar's input: focused when the bar opens or ⌘F is pressed again.
  final FocusNode focusNode = FocusNode(debugLabel: 'find');

  /// Scrolls match [m] into view; set by the pane that shows the bar.
  void Function(SearchMatch m)? reveal;

  String _query = '';
  bool _matchCase = false;
  SearchResult _result = const SearchResult([]);
  int _current = -1;
  final _highlights = <TerminalHighlight>[];
  Timer? _timer;
  bool _closed = false;

  String get query => _query;
  bool get matchCase => _matchCase;
  List<SearchMatch> get matches => _result.matches;
  bool get capped => _result.capped;

  /// Index of the current match; -1 when there is none.
  int get current => _current;
  bool get hasQuery => _query.isNotEmpty;

  /// Never shows the query (A10 §5).
  @override
  String toString() => 'FindSession(…)';

  void setQuery(String text) {
    var q = text.replaceAll(RegExp(r'[\r\n]'), '');
    if (q.length > kMaxFindQuery) q = q.substring(0, kMaxFindQuery);
    if (q == _query) return;
    _query = q;
    _search(pickLast: true, scroll: true);
  }

  void toggleMatchCase() {
    _matchCase = !_matchCase;
    _search(pickLast: true, scroll: true);
  }

  void next() => _step(1);
  void previous() => _step(-1);

  void _step(int delta) {
    final n = matches.length;
    if (n == 0) return;
    _setCurrent((_current + delta + n) % n, scroll: true);
  }

  void _onTerminal() {
    if (_closed || !hasQuery || _timer != null) return;
    _timer = Timer(refreshAfter, () {
      _timer = null;
      if (!_closed) _search(pickLast: false, scroll: false);
    });
  }

  void _search({required bool pickLast, required bool scroll}) {
    final before = _current >= 0 && _current < matches.length
        ? matches[_current]
        : null;
    _result = hasQuery
        ? searchBuffer(terminal.buffer, _query, matchCase: _matchCase)
        : const SearchResult([]);
    _clearHighlights();
    if (matches.isEmpty) {
      _current = -1;
      notifyListeners();
      return;
    }
    if (pickLast || before == null) {
      _current = matches.length - 1;
    } else {
      // Keep the match the user is on, if it is still there; else the one
      // that follows it.
      final same = matches.indexOf(before);
      _current = same >= 0 ? same : firstMatchFrom(matches, before.startRow);
    }
    _paint();
    if (scroll) reveal?.call(matches[_current]);
    notifyListeners();
  }

  void _setCurrent(int i, {required bool scroll}) {
    final old = _current;
    _current = i;
    if (old >= 0 && old < _highlights.length) _recolor(old, matchColor);
    if (i < _highlights.length) _recolor(i, currentColor);
    if (scroll) reveal?.call(matches[i]);
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

  void _recolor(int i, Color color) {
    _dispose(_highlights[i]);
    _highlights[i] = _highlightFor(matches[i], color);
  }

  void _dispose(TerminalHighlight h) {
    h.p1.dispose();
    h.p2.dispose();
    try {
      h.dispose();
    } on Object {
      // A pane that closes disposes its controller before this session
      // hears of it: the highlight is gone with it.
    }
  }

  void _clearHighlights() {
    for (final h in _highlights) {
      _dispose(h);
    }
    _highlights.clear();
  }

  /// The bar closed or its pane went: no highlight and no anchor is left.
  void close() => dispose();

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    terminal.removeListener(_onTerminal);
    _clearHighlights();
    focusNode.dispose();
    super.dispose();
  }
}
