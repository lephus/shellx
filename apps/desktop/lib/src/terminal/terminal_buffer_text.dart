import 'package:xterm/core.dart';

/// A logical line of the terminal: the rows the terminal wrapped
/// (`isWrapped`) joined into one string, with the cell of every UTF-16
/// unit (A10 D9). Link detection runs on [text]; the cells map the result
/// back to the screen.
final class LogicalLine {
  LogicalLine._(
    this.firstRow,
    this.text,
    this._rows,
    this._cols,
    this._widths, {
    this.clippedBefore = false,
    this.clippedAfter = false,
  });

  /// The row cap cut the logical line off before its first / after its last
  /// character read: a link touching that end may be longer than it looks.
  final bool clippedBefore;
  final bool clippedAfter;

  /// Buffer row of the first row.
  final int firstRow;
  final String text;
  final List<int> _rows;
  final List<int> _cols;
  final List<int> _widths;

  bool get isEmpty => text.isEmpty;

  /// The index into [text] of the character drawn in cell ([row], [col]);
  /// null when the cell is past the text.
  int? indexOfCell(int row, int col) {
    for (var i = 0; i < _rows.length; i++) {
      if (_rows[i] == row && col >= _cols[i] && col < _cols[i] + _widths[i]) {
        return i;
      }
    }
    return null;
  }

  /// The first cell of the character at [index].
  CellOffset beginOf(int index) => CellOffset(_cols[index], _rows[index]);

  /// The cell after the character at [lastIndex] (end exclusive).
  CellOffset endAfter(int lastIndex) =>
      CellOffset(_cols[lastIndex] + _widths[lastIndex], _rows[lastIndex]);
}

/// The logical line that contains buffer row [row]: back to its first row
/// and on to its last, at most [maxRows] rows (A10 D9: 4 096 characters at
/// 512 columns is more than any link needs). Trailing blanks of the last
/// row are not part of the text; a row that wraps on is full.
LogicalLine logicalLineAt(Buffer buffer, int row, {int maxRows = 8}) {
  final height = buffer.height;
  if (row < 0 || row >= height) {
    return LogicalLine._(row, '', const [], const [], const []);
  }
  var first = row;
  while (first > 0 &&
      buffer.lines[first].isWrapped &&
      row - first < maxRows - 1) {
    first--;
  }
  var last = row;
  while (last + 1 < height &&
      buffer.lines[last + 1].isWrapped &&
      last - first + 1 < maxRows) {
    last++;
  }
  final clippedBefore = first > 0 && buffer.lines[first].isWrapped;
  final clippedAfter = last + 1 < height && buffer.lines[last + 1].isWrapped;
  final text = StringBuffer();
  final rows = <int>[];
  final cols = <int>[];
  final widths = <int>[];
  for (var r = first; r <= last; r++) {
    final line = buffer.lines[r];
    final wrapsOn = r < last;
    final cells = wrapsOn ? line.length : line.getTrimmedLength();
    for (var c = 0; c < cells; c++) {
      final width = line.getWidth(c);
      if (width == 0) continue;
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
  return LogicalLine._(
    first,
    text.toString(),
    rows,
    cols,
    widths,
    clippedBefore: clippedBefore,
    clippedAfter: clippedAfter,
  );
}
