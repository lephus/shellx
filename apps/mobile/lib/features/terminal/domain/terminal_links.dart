import 'package:shellx_core/shellx_core.dart';
import 'package:xterm/core.dart';

/// The web address drawn in cell [cell] of [terminal] (A10 D12), or null. Rows the terminal wrapped
/// are one line, so an address that wraps is one address. At most 8 rows around the cell are read.
/// Mirrors the desktop's `logicalLineAt` (the two apps share no package that has xterm).
String? urlAt(Terminal terminal, CellOffset cell, {int maxRows = 8}) {
  final buffer = terminal.buffer;
  if (cell.y < 0 || cell.y >= buffer.height) return null;
  var first = cell.y;
  while (first > 0 && buffer.lines[first].isWrapped && cell.y - first < maxRows - 1) {
    first--;
  }
  var last = cell.y;
  while (last + 1 < buffer.height && buffer.lines[last + 1].isWrapped && last - first + 1 < maxRows) {
    last++;
  }
  final text = StringBuffer();
  var index = -1;
  for (var row = first; row <= last; row++) {
    final line = buffer.lines[row];
    final cells = row < last ? line.length : line.getTrimmedLength();
    for (var col = 0; col < cells; col++) {
      final width = line.getWidth(col);
      if (width == 0) continue;
      final code = line.getCodePoint(col);
      final unit = code == 0 ? ' ' : String.fromCharCode(code);
      if (row == cell.y && col <= cell.x && cell.x < col + width) index = text.length;
      text.write(unit);
    }
  }
  if (index < 0) return null;
  return linkAt(text.toString(), index)?.target;
}
