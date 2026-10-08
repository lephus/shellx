import 'package:flutter/painting.dart';
import 'package:shellx_mobile/shared/shared.dart';
import 'package:xterm/xterm.dart';

typedef TerminalGrid = ({int cols, int rows});

/// Used when the viewport cannot fit one cell yet (a size below 1×1 is never sent): the real
/// size follows as a `resize` as soon as the terminal is laid out.
const TerminalGrid fallbackGrid = (cols: 80, rows: 24);

/// JetBrains Mono, bundled (spec §9.1); the rest of the UI uses the base's Raleway.
TerminalStyle shellxTerminalStyle(double fontSize) =>
    TerminalStyle(fontSize: fontSize, fontFamily: FontFamily.jetBrainsMono);

/// Columns × rows of [style] cells that fit in [size], measured the way
/// xterm's RenderTerminal measures a cell (width of "mmmmmmmmmm" / 10, line
/// height). Null when not even one column or row fits.
TerminalGrid? measureTerminalGrid(Size size, TerminalStyle style, TextScaler textScaler) {
  final cell = terminalCellSize(style, textScaler);
  if (cell.width <= 0 || cell.height <= 0) return null;
  final cols = (size.width / cell.width).floor();
  final rows = (size.height / cell.height).floor();
  if (cols < 1 || rows < 1) return null;
  return (cols: cols, rows: rows);
}

/// One cell of [style], measured the way xterm's RenderTerminal does (width of "mmmmmmmmmm" / 10, line
/// height).
Size terminalCellSize(TerminalStyle style, TextScaler textScaler) {
  final painter = TextPainter(
    text: TextSpan(text: 'mmmmmmmmmm', style: style.toTextStyle()),
    textDirection: TextDirection.ltr,
    textScaler: textScaler,
  )..layout();
  final size = Size(painter.width / 10, painter.height);
  painter.dispose();
  return size;
}
