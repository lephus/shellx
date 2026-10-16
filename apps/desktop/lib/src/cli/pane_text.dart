import 'package:xterm/xterm.dart';

import '../restore/scrollback_codec.dart';

/// A7 D20: one `read` page holds at most this much UTF-8.
const kReadPageBytes = 49152;

/// A7 D20: `read --lines` is 1–this.
const kReadMaxLines = 10000;

final _sgr = RegExp(r'\x1b\[[0-9;]*m');

/// C1 controls (U+0080–U+009F): a cell may hold one; never read out.
final _c1 = RegExp('[\u0080-\u009f]');

/// One logical line per entry (soft-wrapped rows joined), oldest first.
/// [fromRow]: start at this absolute row (moved back to the start of its
/// logical line). [last]: keep only the newest N. Trailing blank rows are
/// dropped, and C1 controls with them. Always re-encoded from the cells,
/// never the PTY's bytes:
/// [ansi] keeps SGR (A5a D5), else plain text with trailing spaces cut.
List<String> logicalLines(
  Buffer buffer, {
  int? last,
  int? fromRow,
  bool ansi = false,
}) {
  final rows = buffer.lines;
  var end = rows.length - 1;
  while (end >= 0 &&
      rows[end].getTrimmedLength() == 0 &&
      (end + 1 >= rows.length || !rows[end + 1].isWrapped)) {
    end--;
  }
  var first = fromRow ?? 0;
  while (first > 0 && first < rows.length && rows[first].isWrapped) {
    first--;
  }
  final out = <String>[];
  var i = end;
  while (i >= first && (last == null || out.length < last)) {
    var start = i;
    while (start > first && rows[start].isWrapped) {
      start--;
    }
    final encoded = encodeLogicalLines(buffer, start, i).replaceAll(_c1, '');
    out.add(ansi ? encoded : encoded.replaceAll(_sgr, '').trimRight());
    i = start - 1;
  }
  return out.reversed.toList();
}

/// A7 D21 (Task 7 review M7): [logicalLines] for `wait --match`, cheaper:
/// the rows' text as xterm gives it (no SGR codec; a skipped cell is not a
/// space), trailing spaces cut.
List<String> matchLines(Buffer buffer, {int? last, int? fromRow}) {
  final rows = buffer.lines;
  var end = rows.length - 1;
  while (end >= 0 &&
      rows[end].getTrimmedLength() == 0 &&
      (end + 1 >= rows.length || !rows[end + 1].isWrapped)) {
    end--;
  }
  var first = fromRow ?? 0;
  while (first > 0 && first < rows.length && rows[first].isWrapped) {
    first--;
  }
  final out = <String>[];
  var i = end;
  while (i >= first && (last == null || out.length < last)) {
    var start = i;
    while (start > first && rows[start].isWrapped) {
      start--;
    }
    final line = StringBuffer();
    for (var r = start; r <= i; r++) {
      line.write(rows[r].getText());
    }
    out.add(line.toString().trimRight());
    i = start - 1;
  }
  return out.reversed.toList();
}

/// D20: the screen of the buffer in use (the alt screen while vim runs).
String screenText(Terminal t) => _join(_screenLines(t, ansi: false));

/// Absolute row of the cursor in the buffer in use.
int cursorRow(Terminal t) => t.buffer.absoluteCursorY;

List<String> _screenLines(Terminal t, {required bool ansi}) =>
    logicalLines(t.buffer, fromRow: t.buffer.scrollBack, ansi: ansi);

String _join(List<String> lines) =>
    lines.isEmpty ? '' : '${lines.join('\n')}\n';

/// D20: a page of the screen (no [lines]) or of the last [lines] logical
/// lines, at most [kReadPageBytes] of UTF-8. Pages hold whole lines; a
/// line longer than a page is cut over several, never inside a character
/// or an SGR sequence, so the pages joined are the whole text. [offset]
/// and `next` count the pieces already sent.
({String text, int? next}) readPage(
  Terminal t, {
  int? lines,
  bool ansi = false,
  int offset = 0,
}) {
  final all = lines == null
      ? _screenLines(t, ansi: ansi)
      : logicalLines(t.buffer, last: lines, ansi: ansi);
  final pieces = [for (final line in all) ..._pieces('$line\n')];
  final out = StringBuffer();
  var bytes = 0;
  var i = offset;
  while (i < pieces.length) {
    final (text, size) = pieces[i];
    if (bytes + size > kReadPageBytes) break;
    out.write(text);
    bytes += size;
    i++;
  }
  return (text: out.toString(), next: i < pieces.length ? i : null);
}

/// [line] as one piece, or cut into pieces of at most [kReadPageBytes];
/// each with its UTF-8 size.
List<(String, int)> _pieces(String line) {
  final out = <(String, int)>[];
  var start = 0;
  var bytes = 0;
  var i = 0;
  while (i < line.length) {
    final c = line.codeUnitAt(i);
    int units;
    int size;
    final sgr = c == 0x1b ? _sgr.matchAsPrefix(line, i) : null;
    if (sgr != null) {
      units = sgr.end - i;
      size = units; // ASCII
    } else if (c < 0x80) {
      (units, size) = (1, 1);
    } else if (c < 0x800) {
      (units, size) = (1, 2);
    } else if (c >= 0xD800 &&
        c <= 0xDBFF &&
        i + 1 < line.length &&
        line.codeUnitAt(i + 1) >= 0xDC00 &&
        line.codeUnitAt(i + 1) <= 0xDFFF) {
      (units, size) = (2, 4);
    } else {
      (units, size) = (1, 3);
    }
    if (bytes + size > kReadPageBytes) {
      out.add((line.substring(start, i), bytes));
      start = i;
      bytes = 0;
    }
    bytes += size;
    i += units;
  }
  out.add((line.substring(start), bytes));
  return out;
}
