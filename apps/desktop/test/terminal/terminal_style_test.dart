import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/terminal_style.dart';

void main() {
  test('JetBrains Mono 13, line height 1.2 (UI §1.3)', () {
    final style = desktopTerminalStyle(kTerminalFontSizeDefault);
    expect(style.fontFamily, 'JetBrainsMono');
    expect(style.fontSize, 13);
    expect(style.height, 1.2);
    expect((kTerminalFontSizeMin, kTerminalFontSizeMax), (9.0, 28.0));
  });

  test('grid measurement: null below one cell, columns grow with width', () {
    final style = desktopTerminalStyle(13);
    expect(
      measureTerminalGrid(const Size(1, 1), style, TextScaler.noScaling),
      isNull,
    );
    final narrow = measureTerminalGrid(
      const Size(400, 300),
      style,
      TextScaler.noScaling,
    )!;
    final wide = measureTerminalGrid(
      const Size(800, 300),
      style,
      TextScaler.noScaling,
    )!;
    expect(narrow.cols, greaterThan(0));
    expect(wide.cols, greaterThan(narrow.cols));
    expect(wide.rows, narrow.rows);
  });
}
