import 'package:xterm/core.dart';

import 'latin_compose.dart';

/// One match, as buffer cells: rows are indices into `Buffer.lines`
/// (scrollback included), the end column is exclusive.
final class SearchMatch {
  const SearchMatch(this.startRow, this.startCol, this.endRow, this.endCol);
  final int startRow;
  final int startCol;
  final int endRow;
  final int endCol;

  CellOffset get begin => CellOffset(startCol, startRow);
  CellOffset get end => CellOffset(endCol, endRow);

  @override
  bool operator ==(Object other) =>
      other is SearchMatch &&
      other.startRow == startRow &&
      other.startCol == startCol &&
      other.endRow == endRow &&
      other.endCol == endCol;

  @override
  int get hashCode => Object.hash(startRow, startCol, endRow, endCol);

  /// Positions only; never the text (A10 §5).
  @override
  String toString() => 'SearchMatch($startRow:$startCol-$endRow:$endCol)';
}

final class SearchResult {
  const SearchResult(this.matches, {this.capped = false});
  final List<SearchMatch> matches;

  /// More than the cap matched; [matches] holds the first ones.
  final bool capped;
}

/// The most matches kept and highlighted (A10 D3, D5).
const int kMaxSearchMatches = 1000;

/// Lower-cases without changing the length of [s] (a character whose
/// lower case is longer or shorter stays as it is), so an index into the
/// result is an index into [s].
String foldCase(String s) {
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c >= 0x41 && c <= 0x5A) {
      out.writeCharCode(c + 32);
    } else if (c < 0x80 || (c >= 0xD800 && c <= 0xDFFF)) {
      out.writeCharCode(c);
    } else {
      final lower = String.fromCharCode(c).toLowerCase();
      out.write(lower.length == 1 ? lower : s[i]);
    }
  }
  return out.toString();
}

/// The most rows joined into one logical line; a longer wrapped line is
/// searched in pieces of this size (a match never spans two pieces).
const int kMaxLogicalRows = 256;

/// One row's text and where each UTF-16 unit of it sits. Blank cells read
/// as spaces, so a needle with a space matches the gap between two words.
/// [starts] / [ends] are null when unit i is simply cell i (the usual case).
final class _RowText {
  _RowText(this.row, this.text, this.starts, this.ends);
  final int row;
  final String text;
  final List<int>? starts;
  final List<int>? ends;
}

_RowText _rowText(BufferLine line, int row, int cells) {
  final units = <int>[];
  List<int>? starts;
  List<int>? ends;
  void table() {
    if (starts != null) return;
    starts = [for (var i = 0; i < units.length; i++) i];
    ends = [for (var i = 0; i < units.length; i++) i + 1];
  }

  for (var c = 0; c < cells; c++) {
    final width = line.getWidth(c);
    var code = line.getCodePoint(c);
    if (width == 0 && code == 0) continue; // the second half of a wide char
    if (code == 0) code = 0x20;
    final plain = width == 1 && code < 0x10000 && !isCombiningMark(code);
    if (plain && starts == null) {
      units.add(code);
      continue;
    }
    table();
    final end = c + (width == 0 ? 1 : width);
    if (width == 0 && isCombiningMark(code) && units.isNotEmpty) {
      // Decomposed text: fold the mark into the letter before it.
      final merged = composePair(units.last, code);
      if (merged != null) {
        units[units.length - 1] = merged;
        ends![ends!.length - 1] = end;
        continue;
      }
    }
    if (code >= 0x10000) {
      final v = code - 0x10000;
      units
        ..add(0xD800 + (v >> 10))
        ..add(0xDC00 + (v & 0x3FF));
      starts!
        ..add(c)
        ..add(c);
      ends!
        ..add(end)
        ..add(end);
    } else {
      units.add(code);
      starts!.add(c);
      ends!.add(end);
    }
  }
  return _RowText(row, String.fromCharCodes(units), starts, ends);
}

/// A11 D13: row [row] of [b] as text (blank cells read as spaces, a wide
/// character is one unit); the same reading the search uses.
String bufferRowText(Buffer b, int row) => bufferRowCells(b, row).text;

/// A row's text together with the cell each of its UTF-16 units sits on, so
/// copy mode can move between text positions and screen cells.
final class RowCells {
  RowCells._(this.text, this._starts, this._ends);
  final String text;
  final List<int>? _starts;
  final List<int>? _ends;

  int get _lastEnd =>
      text.isEmpty ? 0 : (_ends?[text.length - 1] ?? text.length);

  /// The first cell of unit [unit]; past the text, one cell per unit.
  int cellOfUnit(int unit) {
    if (unit < text.length) return _starts?[unit] ?? unit;
    return _lastEnd + (unit - text.length);
  }

  /// The cell after the character that starts at [unit].
  int cellEndOfUnit(int unit) {
    if (unit < text.length) return _ends?[unit] ?? unit + 1;
    return cellOfUnit(unit) + 1;
  }

  /// The unit that covers [cell]; past the text, one unit per cell.
  int unitOfCell(int cell) {
    final ends = _ends;
    if (ends == null) return cell;
    for (var i = 0; i < ends.length; i++) {
      if (ends[i] > cell) return i;
    }
    return text.length + (cell - _lastEnd);
  }
}

RowCells bufferRowCells(Buffer b, int row) {
  final line = b.lines[row];
  final r = _rowText(line, row, line.length);
  return RowCells._(r.text, r.starts, r.ends);
}

/// A search over a [Buffer] that can be run in slices: [step] works for at
/// most a time budget and says whether it finished, so a huge scrollback
/// never holds the UI thread (A10 D3). Rows the terminal wrapped are
/// joined, so a match can cross a wrap; matches do not overlap; an empty
/// needle matches nothing. The buffer must not change between steps (the
/// caller restarts the search when it does); rows past a shrunken buffer
/// are simply not searched.
final class BufferSearch {
  BufferSearch(
    this.buffer,
    String needle, {
    this.matchCase = false,
    this.maxMatches = kMaxSearchMatches,
  }) : _wanted = matchCase
           ? composeLatin(needle)
           : foldCase(composeLatin(needle)) {
    _done = _wanted.isEmpty;
  }

  final Buffer buffer;
  final bool matchCase;
  final int maxMatches;
  final String _wanted;
  final _matches = <SearchMatch>[];
  var _row = 0;
  var _capped = false;
  late bool _done;

  bool get done => _done;
  SearchResult get result => SearchResult(_matches, capped: _capped);

  /// Searches for at most [budget] (checked between logical lines); true
  /// when the whole buffer has been searched.
  bool step(Duration budget) {
    if (_done) return true;
    final watch = Stopwatch()..start();
    while (!_done) {
      if (_row >= buffer.height) {
        _done = true;
        break;
      }
      _searchLine();
      if (!_done && watch.elapsed >= budget) return false;
    }
    return true;
  }

  void _searchLine() {
    final height = buffer.height;
    var last = _row;
    while (last + 1 < height &&
        last - _row + 1 < kMaxLogicalRows &&
        buffer.lines[last + 1].isWrapped) {
      last++;
    }
    final rows = <_RowText>[];
    for (var r = _row; r <= last; r++) {
      final line = buffer.lines[r];
      final cells = r < last ? line.length : line.getTrimmedLength();
      rows.add(_rowText(line, r, cells));
    }
    _row = last + 1;
    final text = rows.length == 1
        ? rows.first.text
        : rows.map((r) => r.text).join();
    final haystack = matchCase ? text : foldCase(text);
    var from = 0;
    while (true) {
      final at = haystack.indexOf(_wanted, from);
      if (at < 0) return;
      if (_matches.length >= maxMatches) {
        _capped = true;
        _done = true;
        return;
      }
      final lastUnit = at + _wanted.length - 1;
      _matches.add(_match(rows, at, lastUnit));
      from = at + _wanted.length;
    }
  }

  SearchMatch _match(List<_RowText> rows, int first, int last) {
    (_RowText, int) locate(int unit) {
      var base = 0;
      for (final r in rows) {
        if (unit < base + r.text.length) return (r, unit - base);
        base += r.text.length;
      }
      throw StateError('unit out of range');
    }

    final (a, ai) = locate(first);
    final (b, bi) = locate(last);
    return SearchMatch(
      a.row,
      a.starts?[ai] ?? ai,
      b.row,
      b.ends?[bi] ?? bi + 1,
    );
  }
}

/// Finds [needle] in the whole [buffer] (scrollback and screen) in one go;
/// see [BufferSearch] for the rules and for the sliced form the UI uses.
SearchResult searchBuffer(
  Buffer buffer,
  String needle, {
  bool matchCase = false,
  int maxMatches = kMaxSearchMatches,
}) {
  final search = BufferSearch(
    buffer,
    needle,
    matchCase: matchCase,
    maxMatches: maxMatches,
  );
  search.step(const Duration(days: 1));
  return search.result;
}

/// The index of the first match at or after [from] (a buffer row), wrapping
/// to the first one; -1 when there are none.
int firstMatchFrom(List<SearchMatch> matches, int from) {
  if (matches.isEmpty) return -1;
  for (var i = 0; i < matches.length; i++) {
    if (matches[i].startRow >= from) return i;
  }
  return 0;
}
