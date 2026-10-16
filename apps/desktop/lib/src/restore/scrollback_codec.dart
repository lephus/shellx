import 'dart:convert';

import 'package:xterm/xterm.dart';

/// A5a D5, D26: what one pane keeps.
const int kRestoreMaxLines = 2000;
const int kRestoreMaxBytes = 262144;

/// D6: a larger file is not a file we wrote.
const int kRestoreMaxFileBytes = 524288;

const int _keptAttrs =
    CellAttr.bold |
    CellAttr.faint |
    CellAttr.italic |
    CellAttr.underline |
    CellAttr.inverse |
    CellAttr.strikethrough;

/// The main buffer's last [maxLines] logical lines (wrapped rows joined),
/// re-encoded from the cells as printable text + SGR only (D5): never the
/// PTY's bytes, so no title, clipboard, mouse-mode or alt-screen sequence
/// can ever be saved. Lines are joined by CRLF with a trailing CRLF; blank
/// rows at the end are dropped; oldest whole lines go first when the UTF-8
/// size would pass [maxBytes]. Empty string: nothing worth saving.
String encodeScrollback(
  Terminal terminal, {
  int maxLines = kRestoreMaxLines,
  int maxBytes = kRestoreMaxBytes,
}) {
  final buffer = terminal.mainBuffer;
  final lines = buffer.lines;
  var end = lines.length - 1;
  // Trailing blank rows (the empty screen under the prompt).
  while (end >= 0 &&
      lines[end].getTrimmedLength() == 0 &&
      (end + 1 >= lines.length || !lines[end + 1].isWrapped)) {
    end--;
  }
  final newestFirst = <String>[];
  var bytes = 0;
  while (end >= 0 && newestFirst.length < maxLines) {
    var start = end;
    // `isWrapped` marks a row that continues the row above it.
    while (start > 0 && lines[start].isWrapped) {
      start--;
    }
    final text = encodeLogicalLines(buffer, start, end);
    final size = utf8.encode(text).length + 2;
    if (bytes + size > maxBytes) break;
    bytes += size;
    newestFirst.add(text);
    end = start - 1;
  }
  if (newestFirst.isEmpty) return '';
  return '${newestFirst.reversed.join('\r\n')}\r\n';
}

/// Rows [start]..[end] of [buffer] — one logical line (soft-wrapped rows
/// joined) — as printable text + SGR (D5). A7 `read --ansi` uses it too.
String encodeLogicalLines(Buffer buffer, int start, int end) {
  final lines = buffer.lines;
  final out = StringBuffer();
  var fg = 0, bg = 0, attrs = 0; // the terminal default
  // The previous cell written was a wide character, so an empty cell right
  // after it (on this row or at the start of the next) is its right half.
  var afterWide = false;
  for (var row = start; row <= end; row++) {
    final line = lines[row];
    final continued = row < end;
    // The last row of a logical line stops at its text; earlier rows of a
    // wrapped line are full width.
    final width = continued ? line.length : line.getTrimmedLength();
    for (var i = 0; i < width; i++) {
      var code = line.getCodePoint(i);
      final cellWidth = line.getWidth(i);
      if (code == 0 && afterWide) {
        afterWide = false;
        continue; // the right half of a wide character
      }
      afterWide = false;
      // A resize moves a wide character that no longer fits to the next
      // row and leaves this row's last cell empty: not a space.
      if (code == 0 &&
          continued &&
          i == width - 1 &&
          lines[row + 1].getWidth(0) == 2) {
        continue;
      }
      var a = line.getAttributes(i);
      if (a & CellAttr.invisible != 0) code = 0x20;
      a &= _keptAttrs;
      final f = line.getForeground(i);
      final b = line.getBackground(i);
      if (f != fg || b != bg || a != attrs) {
        out.write(_sgr(f, b, a));
        fg = f;
        bg = b;
        attrs = a;
      }
      out.writeCharCode(code == 0 ? 0x20 : code);
      afterWide = cellWidth == 2;
    }
  }
  if (fg != 0 || bg != 0 || attrs != 0) out.write('\x1b[0m');
  return out.toString();
}

String _sgr(int fg, int bg, int attrs) {
  final p = <Object>[0];
  if (attrs & CellAttr.bold != 0) p.add(1);
  if (attrs & CellAttr.faint != 0) p.add(2);
  if (attrs & CellAttr.italic != 0) p.add(3);
  if (attrs & CellAttr.underline != 0) p.add(4);
  if (attrs & CellAttr.inverse != 0) p.add(7);
  if (attrs & CellAttr.strikethrough != 0) p.add(9);
  p
    ..addAll(_colour(fg, foreground: true))
    ..addAll(_colour(bg, foreground: false));
  return '\x1b[${p.join(';')}m';
}

List<Object> _colour(int c, {required bool foreground}) {
  final value = c & CellColor.valueMask;
  switch (c & CellColor.typeMask) {
    case CellColor.named:
      return value < 8
          ? [(foreground ? 30 : 40) + value]
          : [(foreground ? 90 : 100) + value - 8];
    case CellColor.palette:
      return [foreground ? 38 : 48, 5, value];
    case CellColor.rgb:
      return [
        foreground ? 38 : 48,
        2,
        (value >> 16) & 0xFF,
        (value >> 8) & 0xFF,
        value & 0xFF,
      ];
    default:
      return const [];
  }
}

final RegExp _sgrPattern = RegExp(r'\x1b\[[0-9;:]{0,64}m');

/// D6: the file is untrusted on load. Keeps printable characters (Unicode
/// included), CR, LF, TAB and well-formed SGR; every other escape sequence
/// is removed with its parameters: CSI, OSC up to BEL/ST, DCS/SOS/PM/APC up
/// to ST and two-byte ESC sequences, in their 7-bit (ESC-introduced) and
/// 8-bit (C1) forms alike. Other C0, DEL and C1 characters are dropped.
String sanitizeRestored(String text) {
  final out = StringBuffer();
  var i = 0;
  while (i < text.length) {
    final c = text.codeUnitAt(i);
    if (c == 0x1b) {
      final sgr = _sgrPattern.matchAsPrefix(text, i);
      if (sgr != null) {
        out.write(sgr[0]);
        i = sgr.end;
        continue;
      }
      i = _skipEscape(text, i);
      continue;
    }
    if (c == _c1Csi) {
      i = _skipCsi(text, i + 1);
      continue;
    }
    if (_c1Strings.contains(c)) {
      i = _skipString(text, i + 1);
      continue;
    }
    final printable =
        c == 0x09 ||
        c == 0x0a ||
        c == 0x0d ||
        (c >= 0x20 && c != 0x7f && (c < 0x80 || c > 0x9f));
    if (printable) out.writeCharCode(c);
    i++;
  }
  return out.toString();
}

/// 8-bit CSI.
const int _c1Csi = 0x9b;

/// 8-bit DCS, SOS, OSC, PM and APC: each runs to a string terminator.
const Set<int> _c1Strings = {0x90, 0x98, 0x9d, 0x9e, 0x9f};

/// Index just past the escape sequence starting at [i] (an ESC).
int _skipEscape(String text, int i) {
  if (i + 1 >= text.length) return i + 1;
  final kind = text[i + 1];
  if (kind == '[') return _skipCsi(text, i + 2);
  if (kind == ']' || kind == 'P' || kind == 'X' || kind == '^' || kind == '_') {
    return _skipString(text, i + 2);
  }
  return i + 2; // ESC + one byte
}

/// Index just past a CSI whose parameters start at [j]: its final byte.
int _skipCsi(String text, int j) {
  while (j < text.length) {
    final c = text.codeUnitAt(j);
    j++;
    if (c >= 0x40 && c <= 0x7e) break; // final byte
  }
  return j;
}

/// Index just past a control string whose body starts at [j]: BEL, ESC \
/// or the 8-bit ST; the end of [text] when it is never terminated.
int _skipString(String text, int j) {
  while (j < text.length) {
    final c = text.codeUnitAt(j);
    if (c == 0x07 || c == 0x9c) return j + 1;
    if (c == 0x1b && j + 1 < text.length && text[j + 1] == r'\') {
      return j + 2;
    }
    j++;
  }
  return j;
}

/// D8: one dim line under the restored text, never sent to the shell.
String restoreDivider(String label) => '\x1b[0m\x1b[2m$label\x1b[0m\r\n';

const List<String> _enMonths = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Whole calendar days from [from]'s date to [to]'s date, read from their
/// year/month/day fields (negative when [from] is later). Counted on UTC
/// midnights so a DST switch (a 23 h or 25 h local day) never turns
/// "yesterday" into "today".
int calendarDaysBetween(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

/// D23: local time of the pane's last save, 24 h: today → "14:32";
/// yesterday → [yesterday]("14:32"); older → "6/10 14:32" (vi) or
/// "Oct 6 14:32" (en).
String formatRestoreTime(
  DateTime saved,
  DateTime now, {
  required String localeName,
  required String Function(String time) yesterday,
}) {
  final local = saved.toLocal();
  final hm =
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
  final days = calendarDaysBetween(local, now.toLocal());
  // A save stamped later than now (clock skew) reads as today.
  if (days <= 0) return hm;
  if (days == 1) return yesterday(hm);
  return localeName.startsWith('vi')
      ? '${local.day}/${local.month} $hm'
      : '${_enMonths[local.month - 1]} ${local.day} $hm';
}
