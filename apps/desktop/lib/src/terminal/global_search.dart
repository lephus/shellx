import 'package:xterm/core.dart';

import 'terminal_search.dart';

/// A11 D21: the most rows the overlay lists, and per pane.
const int kGlobalSearchTotal = 200;
const int kGlobalSearchPerPane = 20;

/// The shortest query searched.
const int kGlobalSearchMinQuery = 2;

/// The longest snippet (characters, ellipses included).
const int kGlobalSnippetMax = 120;

/// How long one [GlobalSearch.step] may hold the UI thread (A11 D21).
const Duration kGlobalSearchSlice = Duration(milliseconds: 8);

/// One live pane to search: where it is and its terminal.
final class PaneSource {
  const PaneSource({
    required this.tabId,
    required this.paneId,
    required this.tabLabel,
    required this.paneNumber,
    required this.terminal,
  });

  final int tabId;
  final int paneId;
  final String tabLabel;
  final int paneNumber;
  final Terminal terminal;

  /// Never the label (a tab's name is the user's text).
  @override
  String toString() => '…';
}

/// One match in one pane. The snippet is the line around the match, kept in
/// memory by the overlay only; [snippetStart]..[snippetEnd] marks the match
/// inside it. [row] is the buffer row when the search saw it; [liveRow]
/// follows the line while the buffer moves.
final class GlobalHit {
  GlobalHit({
    required this.tabId,
    required this.paneId,
    required this.row,
    required this.col,
    required this.snippet,
    required this.snippetStart,
    required this.snippetEnd,
    required this.tabLabel,
    required this.paneNumber,
    CellAnchor? anchor,
  }) : _anchor = anchor;

  final int tabId;
  final int paneId;
  final int row;
  final int col;
  final String snippet;
  final int snippetStart;
  final int snippetEnd;
  final String tabLabel;
  final int paneNumber;
  CellAnchor? _anchor;

  /// The line this match was on now (output and trimmed scrollback move
  /// it); null when that line has left the history.
  int? get liveRow {
    final a = _anchor;
    if (a == null) return row;
    return a.attached ? a.y : null;
  }

  void _release() {
    _anchor?.dispose();
    _anchor = null;
  }

  /// Never the snippet (A11 §5).
  @override
  String toString() => '…';
}

final RegExp _control = RegExp(r'[\x00-\x1f\x7f]');

/// A search of every pane's buffer, run in slices so the UI never waits for
/// it: call [step] until it returns true. Each pane is read with the A10
/// [BufferSearch] (its sliced search, its wrapped-line joining and
/// case-folding); at most [perPane] hits per pane and [total] overall.
final class GlobalSearch {
  GlobalSearch(
    List<PaneSource> sources,
    this.needle, {
    this.perPane = kGlobalSearchPerPane,
    this.total = kGlobalSearchTotal,
    this.slice = kGlobalSearchSlice,
  }) : sources = List.unmodifiable(sources) {
    _finished = needle.length < kGlobalSearchMinQuery;
  }

  final List<PaneSource> sources;
  final String needle;
  final int perPane;
  final int total;
  final Duration slice;

  final _hits = <GlobalHit>[];
  var _index = 0;
  BufferSearch? _search;
  var _capped = false;
  late bool _finished;

  List<GlobalHit> get hits => _hits;

  /// More matched than are listed.
  bool get capped => _capped;
  bool get done => _finished;

  /// Works for at most [slice]; true when every pane has been searched (or
  /// the total was reached).
  bool step() {
    if (_finished) return true;
    final watch = Stopwatch()..start();
    while (!_finished) {
      if (_index >= sources.length) {
        _finished = true;
        break;
      }
      final source = sources[_index];
      final search = _search ??= BufferSearch(
        source.terminal.buffer,
        needle,
        maxMatches: perPane,
      );
      final left = slice - watch.elapsed;
      final paneDone = search.step(left.isNegative ? Duration.zero : left);
      if (paneDone) {
        _collect(source, search.result);
        _search = null;
        _index++;
        if (_hits.length >= total && _index < sources.length) {
          // Full: the panes after this one are not looked at.
          _capped = true;
          _finished = true;
        }
      }
      if (!_finished && watch.elapsed >= slice) return false;
    }
    return true;
  }

  void _collect(PaneSource source, SearchResult result) {
    if (result.capped) _capped = true;
    final buffer = source.terminal.buffer;
    for (final m in result.matches) {
      if (_hits.length >= total) {
        _capped = true;
        return;
      }
      if (m.startRow >= buffer.height) continue;
      _hits.add(_hit(source, buffer, m));
    }
  }

  GlobalHit _hit(PaneSource source, Buffer buffer, SearchMatch m) {
    final cells = bufferRowCells(buffer, m.startRow);
    final clean = cells.text.replaceAll(_control, ' ');
    final lastText = clean.trimRight().length;
    var s = cells.unitOfCell(m.startCol).clamp(0, clean.length);
    var e = m.endRow == m.startRow
        ? cells.unitOfCell(m.endCol).clamp(s, clean.length)
        : clean.length;
    if (e <= s) e = (s + 1).clamp(s, clean.length);
    // A match that goes on over the wrap: the part on this row.
    if (e - s > kGlobalSnippetMax - 20) e = s + kGlobalSnippetMax - 20;
    final len = lastText > e ? lastText : e;
    var from = s > 30 ? s - 30 : 0;
    var to = from + (kGlobalSnippetMax - 2);
    if (to > len) to = len;
    if (to < e) {
      to = e;
      from = to - (kGlobalSnippetMax - 2);
      if (from < 0) from = 0;
    }
    while (from < s && clean.codeUnitAt(from) == 0x20) {
      from++;
    }
    while (to > e && clean.codeUnitAt(to - 1) == 0x20) {
      to--;
    }
    final before = from > 0 ? '…' : '';
    final after = to < len ? '…' : '';
    final snippet = '$before${clean.substring(from, to)}$after';
    final start = before.length + (s - from);
    return GlobalHit(
      tabId: source.tabId,
      paneId: source.paneId,
      row: m.startRow,
      col: m.startCol,
      snippet: snippet,
      snippetStart: start,
      snippetEnd: start + (e - s),
      tabLabel: source.tabLabel,
      paneNumber: source.paneNumber,
      anchor: buffer.createAnchor(m.startCol, m.startRow),
    );
  }

  /// Releases the anchors the hits hold in the panes' buffers.
  void dispose() {
    for (final h in _hits) {
      h._release();
    }
    _hits.clear();
    _search = null;
    _finished = true;
  }

  /// Never the query or a hit.
  @override
  String toString() => 'GlobalSearch(…)';
}
