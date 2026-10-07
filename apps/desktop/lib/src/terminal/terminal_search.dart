import 'package:xterm/core.dart';

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

/// Finds [needle] in the whole [buffer] (scrollback and screen), one
/// logical line at a time: rows the terminal wrapped (`isWrapped`) are
/// joined, so a match can cross a wrap. Non-overlapping, in order. An empty
/// needle matches nothing.
SearchResult searchBuffer(
  Buffer buffer,
  String needle, {
  bool matchCase = false,
  int maxMatches = kMaxSearchMatches,
}) {
  if (needle.isEmpty) return const SearchResult([]);
  final wanted = matchCase ? needle : foldCase(needle);
  final matches = <SearchMatch>[];
  final height = buffer.height;
  var row = 0;
  while (row < height) {
    // One logical line: [row] and the rows after it that wrap into it.
    var last = row;
    while (last + 1 < height && buffer.lines[last + 1].isWrapped) {
      last++;
    }
    final text = StringBuffer();
    final rows = <int>[];
    final cols = <int>[];
    final widths = <int>[];
    for (var r = row; r <= last; r++) {
      final line = buffer.lines[r];
      final cells = r < last ? line.length : line.getTrimmedLength();
      for (var c = 0; c < cells; c++) {
        final width = line.getWidth(c);
        if (width == 0) continue; // the second half of a wide character
        final code = line.getCodePoint(c);
        final unit = code == 0 ? ' ' : String.fromCharCode(code);
        for (var u = 0; u < unit.length; u++) {
          rows.add(r);
          cols.add(c);
          widths.add(width);
        }
        text.write(unit);
      }
    }
    final haystack = matchCase ? text.toString() : foldCase(text.toString());
    var from = 0;
    while (true) {
      final at = haystack.indexOf(wanted, from);
      if (at < 0) break;
      final lastUnit = at + wanted.length - 1;
      if (matches.length >= maxMatches) {
        return SearchResult(matches, capped: true);
      }
      matches.add(
        SearchMatch(
          rows[at],
          cols[at],
          rows[lastUnit],
          cols[lastUnit] + widths[lastUnit],
        ),
      );
      from = at + wanted.length;
    }
    row = last + 1;
  }
  return SearchResult(matches);
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
