import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:xterm/xterm.dart';

import 'link_layer.dart' show linkModifierDown;

/// A logical line wrapped over more rows than this selects only that many.
const int kMaxLogicalRowsSelect = 256;

/// Counts clicks that are close in time and place (A11 D12): the third is a
/// triple-click. A fourth starts over.
class ClickCounter {
  ClickCounter({this.window = kDoubleTapTimeout, this.slop = kDoubleTapSlop});

  final Duration window;
  final double slop;
  Offset? _at;
  Duration? _time;
  int _count = 0;

  int register(Offset p, Duration time) {
    final near =
        _at != null &&
        _time != null &&
        time - _time! <= window &&
        (p - _at!).distance <= slop;
    _count = near && _count < 3 ? _count + 1 : 1;
    _at = p;
    _time = time;
    return _count;
  }

  void reset() {
    _count = 0;
    _at = null;
    _time = null;
  }
}

/// The rows of the logical line that contains [row]: the soft-wrapped rows
/// around it merged, at most [kMaxLogicalRowsSelect] on either side.
({int first, int last}) logicalLineRange(Buffer b, int row) {
  final lines = b.lines;
  final at = row.clamp(0, lines.length - 1);
  var first = at;
  while (first > 0 &&
      lines[first].isWrapped &&
      at - first < kMaxLogicalRowsSelect) {
    first--;
  }
  var last = at;
  while (last + 1 < lines.length &&
      lines[last + 1].isWrapped &&
      last - at < kMaxLogicalRowsSelect) {
    last++;
  }
  return (first: first, last: last);
}

/// Windows: the left Alt only (A3 D20); macOS: either Option.
bool get _rectangleKeyDown {
  final keys = HardwareKeyboard.instance.logicalKeysPressed;
  return keys.contains(LogicalKeyboardKey.altLeft) ||
      (defaultTargetPlatform == TargetPlatform.macOS &&
          keys.contains(LogicalKeyboardKey.altRight));
}

/// A11 D12. xterm 4.0.0 gives double-click and drag; this adds the third
/// click (a logical line) and ⌥/Alt-drag (a rectangle) from a [Listener]
/// outside the gesture arena, like the link layer: the arena never reports
/// a third tap. Nothing here reads or logs terminal text.
class ClickSelectLayer extends StatefulWidget {
  const ClickSelectLayer({
    super.key,
    required this.terminal,
    required this.controller,
    required this.viewKey,
    required this.child,
  });

  final Terminal terminal;
  final TerminalController controller;
  final GlobalKey<TerminalViewState> viewKey;
  final Widget child;

  @override
  State<ClickSelectLayer> createState() => _ClickSelectLayerState();
}

class _ClickSelectLayerState extends State<ClickSelectLayer> {
  final _counter = ClickCounter();

  void _down(PointerDownEvent e) {
    if (e.kind != PointerDeviceKind.mouse || e.buttons != kPrimaryButton) {
      return;
    }
    // ⌘/Ctrl-click opens a link (A10 D8): not part of a click series.
    if (linkModifierDown) {
      _counter.reset();
      return;
    }
    // A program that owns the mouse keeps it unless ⌥ is held (iTerm2).
    final rectangle = _rectangleKeyDown;
    if (widget.terminal.mouseMode != MouseMode.none && !rectangle) {
      _counter.reset();
      return;
    }
    widget.controller.setSelectionMode(
      rectangle ? SelectionMode.block : SelectionMode.line,
    );
    if (_counter.register(e.localPosition, e.timeStamp) != 3) return;
    final render = widget.viewKey.currentState?.renderTerminal;
    if (render == null) return;
    final row = render.getCellOffset(e.localPosition).y;
    // After xterm's own tap handling of this pointer-down has run.
    WidgetsBinding.instance
      ..addPostFrameCallback((_) => _selectLine(row))
      ..ensureVisualUpdate();
  }

  void _selectLine(int row) {
    if (!mounted) return;
    final b = widget.terminal.buffer;
    if (row >= b.lines.length) return;
    final range = logicalLineRange(b, row);
    widget.controller.setSelection(
      b.createAnchorFromOffset(CellOffset(0, range.first)),
      b.createAnchorFromOffset(CellOffset(b.viewWidth, range.last)),
      mode: SelectionMode.line,
    );
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: _down,
    child: widget.child,
  );
}
