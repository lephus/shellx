import 'package:flutter/painting.dart';
import 'package:xterm/xterm.dart';

/// Bundled in pubspec.yaml (A1 D16).
const String kTerminalFontFamily = 'JetBrainsMono';

/// UI §1.3: 13 by default, steps of 1, clamped to 9–28.
const double kTerminalFontSizeDefault = 13;
const double kTerminalFontSizeMin = 9;
const double kTerminalFontSizeMax = 28;

/// D11: [families] first (primary, then fallbacks), then the bundled
/// JetBrains Mono, then xterm's own fallbacks. No families = A1 exactly.
TerminalStyle desktopTerminalStyle(
  double fontSize, {
  List<String> families = const [],
}) => TerminalStyle(
  fontSize: fontSize,
  height: 1.2,
  fontFamily: families.isEmpty ? kTerminalFontFamily : families.first,
  fontFamilyFallback: families.isEmpty
      ? const TerminalStyle().fontFamilyFallback
      : [
          ...families.skip(1),
          kTerminalFontFamily,
          ...const TerminalStyle().fontFamilyFallback,
        ],
);

typedef TerminalGrid = ({int cols, int rows});

/// One [style] cell, measured the way xterm's RenderTerminal measures it
/// (width of "mmmmmmmmmm" / 10, line height). Copied from mobile's
/// terminal_metrics.dart.
Size measureTerminalCell(TerminalStyle style, TextScaler textScaler) {
  final painter = TextPainter(
    text: TextSpan(text: 'mmmmmmmmmm', style: style.toTextStyle()),
    textDirection: TextDirection.ltr,
    textScaler: textScaler,
  )..layout();
  final cell = Size(painter.width / 10, painter.height);
  painter.dispose();
  return cell;
}

/// Columns × rows of [style] cells that fit in [size]. Null when not even
/// one column or row fits.
TerminalGrid? measureTerminalGrid(
  Size size,
  TerminalStyle style,
  TextScaler textScaler,
) {
  final cell = measureTerminalCell(style, textScaler);
  if (cell.width <= 0 || cell.height <= 0) return null;
  final cols = (size.width / cell.width).floor();
  final rows = (size.height / cell.height).floor();
  if (cols < 1 || rows < 1) return null;
  return (cols: cols, rows: rows);
}
