import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../../terminal/copy_mode.dart';
import '../../terminal/find_sessions.dart';
import '../../terminal/terminal_search.dart';
import '../../terminal/terminal_tabs.dart';
import '../theme/shellx_desktop_theme.dart';

/// The xterm [Buffer] as copy mode reads it (rows are buffer rows,
/// scrollback included; the alternate screen is just its own buffer).
final class XtermCopyBuffer implements CopyModeBuffer {
  XtermCopyBuffer(this.buffer);
  final Buffer buffer;

  @override
  int get rowCount => buffer.height;
  @override
  int get columns => buffer.viewWidth;
  @override
  String rowText(int row) => bufferRowText(buffer, row);
  @override
  bool isWrapped(int row) => buffer.lines[row].isWrapped;
}

// The keys copy mode knows, by the physical key's meaning (A11 D13): a
// layout that reports another character for the key (Telex, Hangul, Kana)
// still moves.
final Map<PhysicalKeyboardKey, LogicalKeyboardKey> _byPhysical = {
  PhysicalKeyboardKey.keyB: LogicalKeyboardKey.keyB,
  PhysicalKeyboardKey.keyD: LogicalKeyboardKey.keyD,
  PhysicalKeyboardKey.keyE: LogicalKeyboardKey.keyE,
  PhysicalKeyboardKey.keyF: LogicalKeyboardKey.keyF,
  PhysicalKeyboardKey.keyG: LogicalKeyboardKey.keyG,
  PhysicalKeyboardKey.keyH: LogicalKeyboardKey.keyH,
  PhysicalKeyboardKey.keyJ: LogicalKeyboardKey.keyJ,
  PhysicalKeyboardKey.keyK: LogicalKeyboardKey.keyK,
  PhysicalKeyboardKey.keyL: LogicalKeyboardKey.keyL,
  PhysicalKeyboardKey.keyN: LogicalKeyboardKey.keyN,
  PhysicalKeyboardKey.keyQ: LogicalKeyboardKey.keyQ,
  PhysicalKeyboardKey.keyU: LogicalKeyboardKey.keyU,
  PhysicalKeyboardKey.keyV: LogicalKeyboardKey.keyV,
  PhysicalKeyboardKey.keyW: LogicalKeyboardKey.keyW,
  PhysicalKeyboardKey.keyY: LogicalKeyboardKey.keyY,
  PhysicalKeyboardKey.digit0: LogicalKeyboardKey.digit0,
  PhysicalKeyboardKey.digit4: LogicalKeyboardKey.digit4,
  PhysicalKeyboardKey.digit6: LogicalKeyboardKey.digit6,
  PhysicalKeyboardKey.slash: LogicalKeyboardKey.slash,
};

final Set<LogicalKeyboardKey> _known = {
  ..._byPhysical.values,
  LogicalKeyboardKey.arrowLeft,
  LogicalKeyboardKey.arrowRight,
  LogicalKeyboardKey.arrowUp,
  LogicalKeyboardKey.arrowDown,
  LogicalKeyboardKey.enter,
  LogicalKeyboardKey.numpadEnter,
  LogicalKeyboardKey.escape,
};

final Set<LogicalKeyboardKey> _modifiers = {
  LogicalKeyboardKey.shiftLeft,
  LogicalKeyboardKey.shiftRight,
  LogicalKeyboardKey.controlLeft,
  LogicalKeyboardKey.controlRight,
  LogicalKeyboardKey.altLeft,
  LogicalKeyboardKey.altRight,
  LogicalKeyboardKey.metaLeft,
  LogicalKeyboardKey.metaRight,
  LogicalKeyboardKey.capsLock,
  LogicalKeyboardKey.fn,
};

/// The key of [e] as copy mode names it: the logical key when copy mode
/// knows it, else the one the physical key stands for; null when it is
/// neither (a key copy mode swallows).
LogicalKeyboardKey? copyLogicalKey(KeyEvent e) {
  if (_known.contains(e.logicalKey)) return e.logicalKey;
  return _byPhysical[e.physicalKey];
}

/// One pane's copy mode (A11 D13): the cursor and the selection live on
/// xterm anchors, so they follow the text as the buffer scrolls; the mode
/// only ever draws a highlight and the pane's selection, and gives both
/// back on [exit]. Never logs or keeps what it reads beyond the yank.
final class CopyModeController extends ChangeNotifier {
  CopyModeController({
    required this.paneId,
    required this.terminal,
    required this.selection,
    required this.onYank,
    required this.onOpenFind,
    required this.onFind,
    required this.onClosed,
  }) {
    _begin();
  }

  final int paneId;
  final Terminal terminal;
  final TerminalController selection;

  /// The text a yank copied (never empty), and the pane's find bar.
  final void Function(String text) onYank;
  final void Function() onOpenFind;
  final void Function(bool next) onFind;
  final void Function() onClosed;

  /// Scrolls buffer row [row] into view; set by the pane that shows the mode.
  void Function(int row)? reveal;

  late CopyModeState _state;
  TerminalHighlight? _cursor;
  CellAnchor? _anchor;
  bool _closed = false;
  late bool _alt;

  bool get active => !_closed;
  CopyModeState get state => _state;

  @override
  String toString() => 'CopyModeController(…)';

  void _begin() {
    _alt = terminal.isUsingAltBuffer;
    selection.clearSelection();
    final b = terminal.buffer;
    final row = _clampRow(b.absoluteCursorY);
    _state = CopyModeState(
      row: row,
      col: bufferRowCells(b, row).unitOfCell(b.cursorX),
    );
    terminal.addListener(_onTerminal);
    _paint();
  }

  int _clampRow(int row) {
    final last = terminal.buffer.height - 1;
    return row < 0 ? 0 : (row > last ? last : row);
  }

  // The program switched screens: the rows under the cursor are gone.
  void _onTerminal() {
    if (!_closed && terminal.isUsingAltBuffer != _alt) exit();
  }

  /// The state as the anchors have it now (output may have scrolled the
  /// buffer since the last key); null when the cursor's line was trimmed.
  CopyModeState? _live() {
    final c = _cursor;
    if (c == null || !c.p1.attached) return null;
    final b = terminal.buffer;
    final row = c.p1.y;
    final col = bufferRowCells(b, row).unitOfCell(c.p1.x);
    final a = _anchor;
    if (a != null && a.attached) {
      return CopyModeState(
        row: row,
        col: col,
        anchorRow: a.y,
        anchorCol: bufferRowCells(b, a.y).unitOfCell(a.x),
        kind: _state.kind,
        pending: _state.pending,
      );
    }
    return CopyModeState(row: row, col: col, pending: _state.pending);
  }

  void _releaseCursor() {
    final c = _cursor;
    _cursor = null;
    if (c == null) return;
    c.p1.dispose();
    c.p2.dispose();
    try {
      c.dispose();
    } on Object {
      // The pane closed first and took its controller's highlights along.
    }
  }

  void _paint() {
    final b = terminal.buffer;
    final s = _state;
    _releaseCursor();
    _anchor?.dispose();
    _anchor = null;
    final here = bufferRowCells(b, s.row);
    final x = here.cellOfUnit(s.col);
    _cursor = selection.highlight(
      p1: b.createAnchor(x, s.row),
      p2: b.createAnchor(here.cellOfUnit(s.col + 1), s.row),
      color: ShellxDesktopColors.accent.withValues(alpha: 0.55),
    );
    final ar = s.anchorRow;
    final ac = s.anchorCol;
    if (s.kind == SelectKind.none || ar == null || ac == null) {
      selection.clearSelection();
    } else {
      _anchor = b.createAnchor(bufferRowCells(b, ar).cellOfUnit(ac), ar);
      final ax = bufferRowCells(b, ar).cellOfUnit(ac);
      final r0 = ar < s.row ? ar : s.row;
      final r1 = ar < s.row ? s.row : ar;
      final forward = ar < s.row || (ar == s.row && ac <= s.col);
      switch (s.kind) {
        case SelectKind.line:
          selection.setSelection(
            b.createAnchor(0, r0),
            b.createAnchor(b.viewWidth, r1),
            mode: SelectionMode.line,
          );
        case SelectKind.char:
          final (c0, c1) = forward ? (ax, x) : (x, ax);
          final (rr0, rr1) = forward ? (ar, s.row) : (s.row, ar);
          selection.setSelection(
            b.createAnchor(c0, rr0),
            b.createAnchor(c1 + 1, rr1),
            mode: SelectionMode.line,
          );
        case SelectKind.block:
          final lo = ax < x ? ax : x;
          final hi = ax < x ? x : ax;
          selection.setSelection(
            b.createAnchor(lo, r0),
            b.createAnchor(hi + 1, r1),
            mode: SelectionMode.block,
          );
        case SelectKind.none:
          break;
      }
    }
    reveal?.call(s.row);
    notifyListeners();
  }

  /// Moves the cursor onto buffer cell ([cellCol], [row]) — the find bar's
  /// current match — keeping any selection.
  void jumpTo(int row, int cellCol) {
    if (_closed) return;
    final live = _live();
    if (live == null) return exit();
    final r = _clampRow(row);
    _state = CopyModeState(
      row: r,
      col: bufferRowCells(terminal.buffer, r).unitOfCell(cellCol),
      anchorRow: live.anchorRow,
      anchorCol: live.anchorCol,
      kind: live.kind,
    );
    _paint();
  }

  /// Handles a key while the mode is active. Every key is swallowed (it
  /// never reaches the program) except a window chord, which [windowChord]
  /// recognises and which keeps working (⌘W, the toggle itself).
  KeyEventResult handleKey(
    KeyEvent e, {
    bool Function(KeyEvent e)? windowChord,
  }) {
    if (_closed) return KeyEventResult.ignored;
    if (e is KeyUpEvent) return KeyEventResult.handled;
    if (windowChord != null && windowChord(e)) return KeyEventResult.ignored;
    if (_modifiers.contains(e.logicalKey)) return KeyEventResult.handled;
    final hw = HardwareKeyboard.instance;
    final key = copyLogicalKey(e);
    if (key == null || hw.isMetaPressed || hw.isAltPressed) {
      return KeyEventResult.handled;
    }
    final live = _live();
    if (live == null) {
      exit();
      return KeyEventResult.handled;
    }
    final result = applyCopyKey(
      XtermCopyBuffer(terminal.buffer),
      live,
      CopyKey(key, ctrl: hw.isControlPressed, shift: hw.isShiftPressed),
      pageRows: terminal.viewHeight,
    );
    switch (result) {
      case Stay(:final state):
        _state = state;
        _paint();
      case Yank(:final state):
        final text = selectedText(XtermCopyBuffer(terminal.buffer), state);
        exit();
        if (text.isNotEmpty) onYank(text);
      case Exit():
        exit();
      case OpenFind():
        exit();
        onOpenFind();
      case FindNext():
        onFind(true);
      case FindPrev():
        onFind(false);
    }
    return KeyEventResult.handled;
  }

  /// Gives the pane back: no highlight, no anchor, no selection left.
  void exit() {
    if (_closed) return;
    _closed = true;
    terminal.removeListener(_onTerminal);
    _releaseCursor();
    _anchor?.dispose();
    _anchor = null;
    try {
      selection.clearSelection();
    } on Object {
      // The pane's controller is already gone.
    }
    onClosed();
    notifyListeners();
  }
}

/// A11 D13: the panes in copy mode, by session id. At most one per pane; a
/// pane that exits, loses the focus or is left by its tab ends its mode.
final copyModeProvider =
    NotifierProvider<CopyModes, Map<int, CopyModeController>>(CopyModes.new);

class CopyModes extends Notifier<Map<int, CopyModeController>> {
  final _all = <int, CopyModeController>{};

  @override
  Map<int, CopyModeController> build() {
    ref.onDispose(() {
      for (final c in List.of(_all.values)) {
        c.exit();
      }
      _all.clear();
    });
    ref.listen<TerminalTabsState>(terminalTabsProvider, (_, next) {
      for (final e in List.of(_all.entries)) {
        final tab = next.tabOfSession(e.key);
        final pane = tab?.panes[e.key];
        final stays =
            tab != null &&
            pane != null &&
            !pane.exited &&
            identical(pane.terminal, e.value.terminal) &&
            tab.id == next.selectedId &&
            tab.focusedPaneId == e.key;
        if (!stays) e.value.exit();
      }
    });
    return const {};
  }

  /// Starts copy mode in pane [id] (a live pane of the selected tab).
  bool enter(int id) {
    if (_all.containsKey(id)) return true;
    final tabs = ref.read(terminalTabsProvider);
    final tab = tabs.tabOfSession(id);
    final pane = tab?.panes[id];
    if (tab == null || pane == null || pane.exited) return false;
    exitAll();
    late final CopyModeController c;
    c = CopyModeController(
      paneId: id,
      terminal: pane.terminal,
      selection: pane.selection,
      onYank: _yank,
      onOpenFind: () => _openFind(id),
      onFind: (next) => _find(id, next),
      onClosed: () {
        if (_all[id] == c) _all.remove(id);
        if (ref.mounted) state = Map.of(_all);
      },
    );
    if (!c.active) return false;
    _all[id] = c;
    state = Map.of(_all);
    return true;
  }

  void toggle(int id) => _all.containsKey(id) ? exit(id) : enter(id);

  void exit(int id) => _all[id]?.exit();

  void exitAll() {
    for (final c in List.of(_all.values)) {
      c.exit();
    }
  }

  void _yank(String text) {
    unawaited(Clipboard.setData(ClipboardData(text: text)));
    ref
        .read(terminalTabsProvider.notifier)
        .showNotice(const CopyModeCopiedNotice());
  }

  void _openFind(int id) {
    ref.read(findSessionsProvider.notifier).open(id);
    WidgetsBinding.instance
      ..addPostFrameCallback(
        (_) => ref.read(findSessionsProvider)[id]?.focusNode.requestFocus(),
      )
      ..ensureVisualUpdate();
  }

  void _find(int id, bool next) {
    final session = ref.read(findSessionsProvider)[id];
    if (session == null) return;
    next ? session.next() : session.previous();
    final i = session.current;
    if (i < 0 || i >= session.matches.length) return;
    final m = session.matches[i];
    _all[id]?.jumpTo(m.startRow, m.startCol);
  }
}
