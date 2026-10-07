import 'dart:math' as math;

import 'package:flutter/services.dart' show LogicalKeyboardKey;

/// A11 D13: copy mode's keyboard model — a pure state machine over a text
/// grid, so it is tested without a terminal. Keys are matched by their
/// [LogicalKeyboardKey] (the physical key's meaning), never by the
/// character they produced, so a Telex, Hangul or Kana layout does not
/// break the vim motions.

/// The rows copy mode reads: a snapshot-free view of the terminal buffer
/// (scrollback included). Row indices are buffer rows.
abstract interface class CopyModeBuffer {
  int get rowCount;
  int get columns;
  String rowText(int row);

  /// Row [row] continues the line above it (the terminal wrapped it).
  bool isWrapped(int row);
}

/// Optional: a buffer whose text units are not one per cell (wide
/// characters, emoji, combining marks) says where its units sit, so a block
/// selection follows what is painted.
abstract interface class CopyModeCells {
  /// The first cell of [unit] in [row].
  int cellOfUnit(int row, int unit);

  /// The cell after the character that starts at [unit].
  int cellEndOfUnit(int row, int unit);

  /// The unit that covers [cell].
  int unitOfCell(int row, int cell);
}

enum SelectKind { none, char, line, block }

/// Where the cursor is and what is selected. Rows/columns index
/// [CopyModeBuffer.rowText] (text units).
final class CopyModeState {
  const CopyModeState({
    required this.row,
    required this.col,
    this.anchorRow,
    this.anchorCol,
    this.kind = SelectKind.none,
    this.pending = '',
  });

  final int row;
  final int col;
  final int? anchorRow;
  final int? anchorCol;
  final SelectKind kind;

  /// A first key waiting for its second (`g` of `gg`).
  final String pending;

  CopyModeState moved(int row, int col) => CopyModeState(
    row: row,
    col: col,
    anchorRow: anchorRow,
    anchorCol: anchorCol,
    kind: kind,
  );

  CopyModeState copyWith({
    int? row,
    int? col,
    SelectKind? kind,
    String? pending,
    bool anchorHere = false,
    bool dropAnchor = false,
  }) => CopyModeState(
    row: row ?? this.row,
    col: col ?? this.col,
    anchorRow: dropAnchor
        ? null
        : anchorHere
        ? this.row
        : anchorRow,
    anchorCol: dropAnchor
        ? null
        : anchorHere
        ? this.col
        : anchorCol,
    kind: kind ?? this.kind,
    pending: pending ?? this.pending,
  );

  @override
  bool operator ==(Object other) =>
      other is CopyModeState &&
      other.row == row &&
      other.col == col &&
      other.anchorRow == anchorRow &&
      other.anchorCol == anchorCol &&
      other.kind == kind &&
      other.pending == pending;

  @override
  int get hashCode =>
      Object.hash(row, col, anchorRow, anchorCol, kind, pending);

  /// Never anything the terminal showed (A11 §5).
  @override
  String toString() => 'CopyModeState(…)';
}

/// One key as copy mode sees it.
final class CopyKey {
  const CopyKey(this.key, {this.ctrl = false, this.shift = false});
  final LogicalKeyboardKey key;
  final bool ctrl;
  final bool shift;

  @override
  String toString() => 'CopyKey(…)';
}

sealed class CopyResult {
  const CopyResult();
}

/// The mode goes on with [state].
final class Stay extends CopyResult {
  const Stay(this.state);
  final CopyModeState state;
}

/// Copy [selectedText] of [state], then leave.
final class Yank extends CopyResult {
  const Yank(this.state);
  final CopyModeState state;
}

final class Exit extends CopyResult {
  const Exit();
}

/// `/`: leave the mode and open the pane's find bar.
final class OpenFind extends CopyResult {
  const OpenFind();
}

final class FindNext extends CopyResult {
  const FindNext();
}

final class FindPrev extends CopyResult {
  const FindPrev();
}

bool isWordChar(String c) => _word.hasMatch(c);
final RegExp _word = RegExp(r'[\p{L}\p{N}_]', unicode: true);

// 0 blank, 1 word, 2 other.
int _class(String c) => c == ' ' || c == '\t' || c.isEmpty
    ? 0
    : isWordChar(c)
    ? 1
    : 2;

/// The text of [row] without its trailing blanks.
final RegExp _trailingBlanks = RegExp(r'[ \u0000\t]+$');

String _text(CopyModeBuffer b, int row) =>
    b.rowText(row).replaceFirst(_trailingBlanks, '');

bool _isHigh(int unit) => unit >= 0xD800 && unit <= 0xDBFF;
bool _isLow(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;

/// [col] moved off the second half of an emoji onto its first.
int _snap(CopyModeBuffer b, int row, int col) {
  if (col <= 0) return col;
  final t = b.rowText(row);
  return col < t.length &&
          _isLow(t.codeUnitAt(col)) &&
          _isHigh(t.codeUnitAt(col - 1))
      ? col - 1
      : col;
}

/// How many units the character at [col] takes (2 for an emoji).
int _width(CopyModeBuffer b, int row, int col) {
  final t = b.rowText(row);
  return col >= 0 && col + 1 < t.length && _isHigh(t.codeUnitAt(col)) ? 2 : 1;
}

int _len(CopyModeBuffer b, int row) => _text(b, row).length;

int _lastCol(CopyModeBuffer b, int row) => math.max(_len(b, row) - 1, 0);

String _charAt(CopyModeBuffer b, int row, int col) {
  final t = _text(b, row);
  return col >= 0 && col < t.length ? t[col] : ' ';
}

typedef _Pos = (int, int);

// The next position in reading order; the end of a row counts as one blank.
_Pos? _next(CopyModeBuffer b, _Pos p) {
  final (r, c) = p;
  if (c < _len(b, r)) return (r, c + 1);
  return r + 1 < b.rowCount ? (r + 1, 0) : null;
}

_Pos? _prev(CopyModeBuffer b, _Pos p) {
  final (r, c) = p;
  if (c > 0) return (r, math.max(math.min(c, _len(b, r)) - 1, 0));
  return r > 0 ? (r - 1, _len(b, r - 1)) : null;
}

int _classAt(CopyModeBuffer b, _Pos p) => _class(_charAt(b, p.$1, p.$2));

_Pos _wordForward(CopyModeBuffer b, _Pos from) {
  var p = from;
  final start = _classAt(b, p);
  // The rest of the word we are on.
  if (start != 0) {
    while (true) {
      final n = _next(b, p);
      if (n == null) return (p.$1, _lastCol(b, p.$1));
      p = n;
      if (_classAt(b, p) != start) break;
    }
  }
  // Blanks (the end of a row is one); an empty row is a stop of its own.
  while (_classAt(b, p) == 0) {
    if (p.$2 == 0 && _len(b, p.$1) == 0 && p.$1 != from.$1) return p;
    final n = _next(b, p);
    if (n == null) return (p.$1, _lastCol(b, p.$1));
    p = n;
  }
  return p;
}

_Pos _wordEnd(CopyModeBuffer b, _Pos from) {
  final first = _next(b, from);
  if (first == null) return from;
  var p = first;
  while (_classAt(b, p) == 0) {
    final n = _next(b, p);
    if (n == null) return (p.$1, _lastCol(b, p.$1));
    p = n;
  }
  final cls = _classAt(b, p);
  while (true) {
    final n = _next(b, p);
    if (n == null || n.$1 != p.$1 || _classAt(b, n) != cls) return p;
    p = n;
  }
}

_Pos _wordBack(CopyModeBuffer b, _Pos from) {
  final first = _prev(b, from);
  if (first == null) return from;
  var p = first;
  while (_classAt(b, p) == 0) {
    if (p.$2 == 0 && _len(b, p.$1) == 0) return p; // an empty row stops
    final n = _prev(b, p);
    if (n == null) return (0, 0);
    p = n;
  }
  final cls = _classAt(b, p);
  while (p.$2 > 0) {
    final n = (p.$1, p.$2 - 1);
    if (_classAt(b, n) != cls) break;
    p = n;
  }
  return p;
}

int _clampCol(CopyModeBuffer b, int row, int col) =>
    math.min(math.max(col, 0), _lastCol(b, row));

CopyModeState _toRow(CopyModeBuffer b, CopyModeState s, int row) {
  final r = math.min(math.max(row, 0), math.max(b.rowCount - 1, 0));
  return s.moved(r, _snap(b, r, _clampCol(b, r, s.col)));
}

CopyModeState _toPos(CopyModeBuffer b, CopyModeState s, _Pos p) =>
    s.moved(p.$1, _snap(b, p.$1, math.max(p.$2, 0)));

CopyModeState _select(CopyModeState s, SelectKind kind) {
  if (s.kind == kind) {
    return s.copyWith(kind: SelectKind.none, dropAnchor: true);
  }
  return s.kind == SelectKind.none
      ? s.copyWith(kind: kind, anchorHere: true)
      : s.copyWith(kind: kind);
}

/// Applies [k] in copy mode. A key copy mode does not know is swallowed
/// (`Stay` with the same state): nothing reaches the program.
CopyResult applyCopyKey(
  CopyModeBuffer b,
  CopyModeState s,
  CopyKey k, {
  required int pageRows,
}) {
  final key = k.key;
  final waiting = s.pending;
  var st = s.pending.isEmpty ? s : s.copyWith(pending: '');
  if (waiting == 'g' && key == LogicalKeyboardKey.keyG && !k.shift && !k.ctrl) {
    return Stay(_toRow(b, st, 0));
  }
  CopyResult stay(CopyModeState n) => Stay(n);

  if (k.ctrl) {
    final half = math.max(pageRows ~/ 2, 1);
    final page = math.max(pageRows, 1);
    final target = switch (key) {
      LogicalKeyboardKey.keyD => st.row + half,
      LogicalKeyboardKey.keyU => st.row - half,
      LogicalKeyboardKey.keyF => st.row + page,
      LogicalKeyboardKey.keyB => st.row - page,
      _ => null,
    };
    if (target != null) {
      return stay(_toRow(b, st, target));
    }
    if (key == LogicalKeyboardKey.keyV) {
      return stay(_select(st, SelectKind.block));
    }
    return stay(st);
  }

  final p = (st.row, st.col);
  if (key == LogicalKeyboardKey.keyH || key == LogicalKeyboardKey.arrowLeft) {
    return stay(st.moved(st.row, _snap(b, st.row, math.max(st.col - 1, 0))));
  }
  if (key == LogicalKeyboardKey.keyL || key == LogicalKeyboardKey.arrowRight) {
    return stay(
      st.moved(
        st.row,
        math.min(
          st.col + _width(b, st.row, st.col),
          math.max(_lastCol(b, st.row), st.col),
        ),
      ),
    );
  }
  if (key == LogicalKeyboardKey.keyJ || key == LogicalKeyboardKey.arrowDown) {
    return stay(_toRow(b, st, st.row + 1));
  }
  if (key == LogicalKeyboardKey.keyK || key == LogicalKeyboardKey.arrowUp) {
    return stay(_toRow(b, st, st.row - 1));
  }
  if (key == LogicalKeyboardKey.keyW && !k.shift) {
    return stay(_toPos(b, st, _wordForward(b, p)));
  }
  if (key == LogicalKeyboardKey.keyB && !k.shift) {
    return stay(_toPos(b, st, _wordBack(b, p)));
  }
  if (key == LogicalKeyboardKey.keyE && !k.shift) {
    return stay(_toPos(b, st, _wordEnd(b, p)));
  }
  if (key == LogicalKeyboardKey.digit0 && !k.shift) {
    return stay(st.moved(st.row, 0));
  }
  if (key == LogicalKeyboardKey.digit6 && k.shift) {
    final t = _text(b, st.row);
    final first = t.length - t.trimLeft().length;
    return stay(st.moved(st.row, math.min(first, _lastCol(b, st.row))));
  }
  if (key == LogicalKeyboardKey.digit4 && k.shift) {
    return stay(st.moved(st.row, _lastCol(b, st.row)));
  }
  if (key == LogicalKeyboardKey.keyG) {
    return k.shift
        ? stay(_toRow(b, st, b.rowCount - 1))
        : stay(st.copyWith(pending: 'g'));
  }
  if (key == LogicalKeyboardKey.keyV) {
    return stay(_select(st, k.shift ? SelectKind.line : SelectKind.char));
  }
  if (key == LogicalKeyboardKey.keyY ||
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter) {
    return Yank(st);
  }
  if (key == LogicalKeyboardKey.escape) {
    return st.kind != SelectKind.none
        ? stay(st.copyWith(kind: SelectKind.none, dropAnchor: true))
        : const Exit();
  }
  if (key == LogicalKeyboardKey.keyQ && !k.shift) return const Exit();
  if (key == LogicalKeyboardKey.slash && !k.shift) return const OpenFind();
  if (key == LogicalKeyboardKey.keyN) {
    return k.shift ? const FindPrev() : const FindNext();
  }
  return stay(st);
}

/// The text [s] selects (the cursor's own character when nothing is
/// selected). Trailing blanks of each row are dropped; rows the terminal
/// wrapped are joined without a break.
String selectedText(CopyModeBuffer b, CopyModeState s) {
  // [keepBlanks]: the row is followed by its own continuation, so its
  // trailing spaces are real text.
  String slice(int row, int from, int to, {bool keepBlanks = false}) {
    final t = keepBlanks ? b.rowText(row) : _text(b, row);
    if (from >= t.length) return '';
    return t.substring(from, math.min(to, t.length));
  }

  final ar = s.anchorRow ?? s.row;
  final ac = s.anchorCol ?? s.col;
  switch (s.kind) {
    case SelectKind.none:
      return slice(s.row, s.col, s.col + _width(b, s.row, s.col));
    case SelectKind.block:
      final r0 = math.min(ar, s.row), r1 = math.max(ar, s.row);
      final cells = b is CopyModeCells ? b as CopyModeCells : null;
      if (cells == null) {
        final c0 = math.min(ac, s.col), c1 = math.max(ac, s.col);
        return [
          for (var r = r0; r <= r1; r++) slice(r, c0, c1 + _width(b, r, c1)),
        ].join('\n');
      }
      // The rectangle the user sees: whole cells, whatever the units.
      final lo = math.min(
        cells.cellOfUnit(ar, ac),
        cells.cellOfUnit(s.row, s.col),
      );
      final hi = math.max(
        cells.cellEndOfUnit(ar, ac),
        cells.cellEndOfUnit(s.row, s.col),
      );
      return [
        for (var r = r0; r <= r1; r++)
          () {
            final from = cells.unitOfCell(r, lo);
            final last = cells.unitOfCell(r, math.max(hi - 1, lo));
            return slice(r, from, last + _width(b, r, last));
          }(),
      ].join('\n');
    case SelectKind.line:
    case SelectKind.char:
      final before = ar < s.row || (ar == s.row && ac <= s.col);
      final (r0, c0) = before ? (ar, ac) : (s.row, s.col);
      final (r1, c1) = before ? (s.row, s.col) : (ar, ac);
      final out = StringBuffer();
      for (var r = r0; r <= r1; r++) {
        final keep = r < r1 && b.isWrapped(r + 1);
        final line = s.kind == SelectKind.line
            ? slice(r, 0, 1 << 30, keepBlanks: keep)
            : slice(
                r,
                r == r0 ? c0 : 0,
                r == r1 ? c1 + _width(b, r, c1) : 1 << 30,
                keepBlanks: keep,
              );
        if (r > r0 && !b.isWrapped(r)) out.write('\n');
        out.write(line);
      }
      return out.toString();
  }
}
