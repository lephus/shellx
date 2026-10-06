import 'package:flutter/painting.dart';
import 'package:xterm/xterm.dart';

/// Bundled in pubspec.yaml (A1 D16).
const String kTerminalFontFamily = 'JetBrainsMono';

/// UI §1.3: 13 by default, steps of 1, clamped to 9–28.
const double kTerminalFontSizeDefault = 13;
const double kTerminalFontSizeMin = 9;
const double kTerminalFontSizeMax = 28;

TerminalStyle desktopTerminalStyle(double fontSize) => TerminalStyle(
  fontSize: fontSize,
  height: 1.2,
  fontFamily: kTerminalFontFamily,
);

typedef TerminalGrid = ({int cols, int rows});

/// Columns × rows of [style] cells that fit in [size], measured the way
/// xterm's RenderTerminal measures a cell (width of "mmmmmmmmmm" / 10, line
/// height). Null when not even one column or row fits. Copied from mobile's
/// terminal_metrics.dart.
TerminalGrid? measureTerminalGrid(
  Size size,
  TerminalStyle style,
  TextScaler textScaler,
) {
  final painter = TextPainter(
    text: TextSpan(text: 'mmmmmmmmmm', style: style.toTextStyle()),
    textDirection: TextDirection.ltr,
    textScaler: textScaler,
  )..layout();
  final cellWidth = painter.width / 10;
  final cellHeight = painter.height;
  painter.dispose();
  if (cellWidth <= 0 || cellHeight <= 0) return null;
  final cols = (size.width / cellWidth).floor();
  final rows = (size.height / cellHeight).floor();
  if (cols < 1 || rows < 1) return null;
  return (cols: cols, rows: rows);
}
