import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/terminal_style.dart';

void main() {
  test('adjust-cell-height scales the line height', () {
    expect(
      desktopTerminalStyle(13, cellHeightPercent: 15).height,
      closeTo(1.2 * 1.15, 1e-9),
    );
    expect(desktopTerminalStyle(13).height, 1.2);
  });

  test('JetBrains Mono 13, line height 1.2 (UI §1.3)', () {
    final style = desktopTerminalStyle(kTerminalFontSizeDefault);
    // font-weight defaults to light: the light face (see
    // terminal_font_weight_test.dart for why).
    expect(style.fontFamily, kTerminalFontFamilyLight);
    expect(style.fontFamily, 'JetBrainsMonoLight');
    expect(style.fontSize, 13);
    expect(style.height, 1.2);
    expect((kTerminalFontSizeMin, kTerminalFontSizeMax), (9.0, 28.0));
  });

  test(
    'font-weight regular draws with the Regular face; a named family is first',
    () {
      expect(
        desktopTerminalStyle(13, regular: true).fontFamily,
        kTerminalFontFamily,
      );
      final named = desktopTerminalStyle(13, families: ['Menlo']);
      expect(named.fontFamily, 'Menlo');
      expect(named.fontFamilyFallback, contains(kTerminalFontFamilyLight));
      expect(
        desktopTerminalStyle(
          13,
          families: ['Menlo'],
          regular: true,
        ).fontFamilyFallback,
        contains(kTerminalFontFamily),
      );
    },
  );

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
