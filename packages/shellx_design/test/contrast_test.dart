import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_design/shellx_design.dart';

/// V2-5a §10.1: every contrast the spec measures (§5.3–§5.7), with its
/// floor (text 4.5:1, bold text from 15 px and everything that is not text
/// 3:1) and the value the spec gives (± 0.05: the spec rounds composites).
void main() {
  const inset = ShellxPalette.navy900;
  const page = ShellxPalette.navy850;
  const surface = ShellxPalette.navy750;
  const raised = ShellxPalette.navy700;

  /// [fg] on [bg]; an [fg] with alpha is composited over [bg] first.
  double ratio(Color fg, Color bg) =>
      contrastRatio(fg.a < 1 ? compositeOver(fg, bg) : fg, bg);

  void pair(String name, Color fg, Color bg, double measured, double floor) {
    final r = ratio(fg, bg);
    expect(r, closeTo(measured, 0.05), reason: '$name: $r');
    expect(r, greaterThanOrEqualTo(floor), reason: '$name: $r');
  }

  void onFour(String name, Color fg, List<double> measured, double floor) {
    final bgs = [inset, page, surface, raised];
    for (var i = 0; i < measured.length; i++) {
      pair('$name on layer $i', fg, bgs[i], measured[i], floor);
    }
  }

  group('dark (§5.3)', () {
    test('text on every layer: inset · page · surface · raised', () {
      onFour('white100', ShellxPalette.white100, [
        15.94,
        14.78,
        12.30,
        11.21,
      ], 4.5);
      onFour('white87', ShellxPalette.white87, [12.41, 11.51, 9.58, 8.73], 4.5);
      onFour('white75', ShellxPalette.white75, [9.92, 9.20, 7.65, 6.97], 4.5);
      onFour('white60', ShellxPalette.white60, [6.78, 6.28, 5.23, 4.76], 4.5);
      pair('white50 on inset', ShellxPalette.white50, inset, 4.99, 4.5);
      pair(
        'white60 on a bar',
        ShellxPalette.white60,
        ShellxPalette.navy825,
        5.96,
        4.5,
      );
      onFour('link', ShellxPalette.link, [6.59, 6.11, 5.09, 4.64], 4.5);
      onFour('cyan', ShellxPalette.cyan, [8.02, 7.44, 6.19, 5.64], 4.5);
    });

    test('layers read apart: hover < selected; pressed on a surface', () {
      pair('navy800 vs page', ShellxPalette.navy800, page, 1.12, 1);
      pair('navy700 vs page', ShellxPalette.navy700, page, 1.32, 1.25);
      pair('navy650 vs surface', ShellxPalette.navy650, surface, 1.25, 1);
    });

    test('field outline and focus ring ≥ 3:1 (not text)', () {
      for (final (bg, v) in [(inset, 4.13), (page, 3.83), (surface, 3.19)]) {
        pair('fieldOutline', ShellxPalette.fieldOutline, bg, v, 3);
      }
    });

    test('ink on accents and soft fills', () {
      pair(
        'onCyan on cyan',
        ShellxPalette.onCyan,
        ShellxPalette.cyan,
        8.85,
        4.5,
      );
      pair(
        'white87 on cyanSoft',
        ShellxPalette.white87,
        ShellxPalette.cyanSoft,
        8.72,
        4.5,
      );
      pair(
        'link on cyanSoft',
        ShellxPalette.link,
        ShellxPalette.cyanSoft,
        4.63,
        4.5,
      );
      pair('azure on page', ShellxPalette.azure, page, 5.03, 4.5);
      // Azure on a surface is for text from 18 px only.
      pair('azure on surface', ShellxPalette.azure, surface, 4.18, 3);
      expect(ratio(ShellxPalette.azure, surface), lessThan(4.5));
      expect(ratio(ShellxPalette.azure, raised), lessThan(4.5));
    });

    test('white on the gradient stops', () {
      pair(
        'accentLight',
        ShellxPalette.white100,
        ShellxPalette.accentLight,
        3.12,
        3,
      );
      pair(
        'accentStrongLight',
        ShellxPalette.white100,
        ShellxPalette.accentStrongLight,
        4.65,
        4.5,
      );
      pair('indigo', ShellxPalette.white100, ShellxPalette.indigo, 5.86, 4.5);
      pair(
        'wedgeBottom',
        ShellxPalette.white100,
        ShellxPalette.wedgeBottom,
        5.31,
        4.5,
      );
      // Why the stop moved (A20): the reference's cyan holds 1.99:1.
      expect(
        contrastRatio(ShellxPalette.white100, const Color(0xFF34C8E8)),
        closeTo(1.99, 0.05),
      );
    });

    test(
      'glass over the wedge\'s light end: textPrimary and up only (A29)',
      () {
        final glass = compositeOver(
          ShellxPalette.glassFill,
          ShellxPalette.accentLight,
        );
        for (final text in [
          ShellxPalette.white100,
          ShellxPalette.white87,
          ShellxPalette.white75,
        ]) {
          expect(contrastRatio(text, glass), greaterThanOrEqualTo(4.5));
        }
        expect(
          contrastRatio(ShellxPalette.white87, glass),
          closeTo(6.79, 0.05),
        );
        expect(
          contrastRatio(ShellxPalette.white75, glass),
          closeTo(5.42, 0.05),
        );
        expect(
          contrastRatio(ShellxPalette.white60, glass),
          closeTo(3.71, 0.05),
        );
        expect(contrastRatio(ShellxPalette.white60, glass), lessThan(4.5));
      },
    );
  });

  group('gradients (§5.5), 101 samples', () {
    test('accent: white ≥ 3:1 everywhere, also hovered and pressed', () {
      const g = ShellxGradients.accent;
      final white = ShellxPalette.onAccent;
      expect(minContrastOnGradient(g, white), closeTo(3.12, 0.05));
      expect(minContrastOnGradient(g, white), greaterThanOrEqualTo(3));
      expect(
        minContrastOnGradient(g, white, overlay: ShellxGradients.hoverShade),
        closeTo(3.63, 0.05),
      );
      expect(
        minContrastOnGradient(g, white, overlay: ShellxGradients.pressedShade),
        closeTo(4.29, 0.05),
      );
    });

    test(
      'accentStrong: white ≥ 4.5:1 everywhere, also hovered and pressed',
      () {
        const g = ShellxGradients.accentStrong;
        final white = ShellxPalette.onAccent;
        expect(minContrastOnGradient(g, white), closeTo(4.65, 0.05));
        expect(minContrastOnGradient(g, white), greaterThanOrEqualTo(4.5));
        expect(
          minContrastOnGradient(g, white, overlay: ShellxGradients.hoverShade),
          closeTo(5.34, 0.05),
        );
        expect(
          minContrastOnGradient(
            g,
            white,
            overlay: ShellxGradients.pressedShade,
          ),
          closeTo(6.15, 0.05),
        );
        // A white overlay would drop it under 4.5 (why hover shades black).
        expect(
          minContrastOnGradient(g, white, overlay: const Color(0x14FFFFFF)),
          lessThan(4.5),
        );
      },
    );

    test('wedge: white ≥ 3:1', () {
      expect(
        minContrastOnGradient(ShellxGradients.wedge, ShellxPalette.white100),
        closeTo(3.12, 0.05),
      );
      expect(
        minContrastOnGradient(ShellxGradients.wedge, ShellxPalette.white100),
        greaterThanOrEqualTo(3),
      );
    });

    test('samples include both ends', () {
      const g = LinearGradient(colors: [Color(0xFF000000), Color(0xFFFFFFFF)]);
      expect(minContrastOnGradient(g, const Color(0xFF000000)), 1);
      expect(minContrastOnGradient(g, const Color(0xFFFFFFFF)), 1);
    });
  });

  group('status, dark (§5.6)', () {
    test('on every layer and on their soft fills', () {
      onFour('ok', ShellxPalette.ok, [8.56, 7.93, 6.60, 6.02], 4.5);
      onFour('warn', ShellxPalette.warn, [9.06, 8.40, 6.99, 6.37], 4.5);
      onFour('error', ShellxPalette.error, [7.07, 6.55, 5.46, 4.97], 4.5);
      onFour('inProgress', ShellxPalette.inProgress, [
        6.60,
        6.12,
        5.09,
        4.64,
      ], 4.5);
      pair('ok on okSoft', ShellxPalette.ok, ShellxPalette.okSoft, 6.14, 4.5);
      pair(
        'warn on warnSoft',
        ShellxPalette.warn,
        ShellxPalette.warnSoft,
        6.53,
        4.5,
      );
      pair(
        'error on errorSoft',
        ShellxPalette.error,
        ShellxPalette.errorSoft,
        5.28,
        4.5,
      );
      pair(
        'onError on error',
        ShellxPalette.onError,
        ShellxPalette.error,
        8.12,
        4.5,
      );
      pair(
        'onError on errorHover',
        ShellxPalette.onError,
        ShellxPalette.errorHover,
        8.94,
        4.5,
      );
      pair(
        'noticeText on noticeBg',
        ShellxPalette.noticeText,
        ShellxPalette.noticeBg,
        7.79,
        4.5,
      );
      // A23: the old red failed on a surface.
      expect(
        contrastRatio(const Color(0xFFF07178), surface),
        closeTo(4.30, 0.05),
      );
    });
  });

  group('light (§5.4)', () {
    const l = (
      inset: ShellxLightPalette.inset,
      page: ShellxLightPalette.page,
      surface: ShellxLightPalette.surface,
      raised: ShellxLightPalette.raised,
    );
    void onLight(String name, Color fg, List<double> measured, double floor) {
      final bgs = [l.inset, l.page, l.surface, l.raised];
      for (var i = 0; i < measured.length; i++) {
        pair('$name on light layer $i', fg, bgs[i], measured[i], floor);
      }
    }

    test('text, status and the primary on every layer', () {
      onLight('text', ShellxLightPalette.text, [
        13.87,
        15.07,
        16.23,
        17.42,
      ], 4.5);
      onLight('textSecondary', ShellxLightPalette.textSecondary, [
        5.70,
        6.19,
        6.67,
        7.16,
      ], 4.5);
      onLight('primary', ShellxLightPalette.primary, [
        4.67,
        5.07,
        5.47,
        5.87,
      ], 4.5);
      onLight('ok', ShellxLightPalette.ok, [5.12, 5.56, 5.99, 6.43], 4.5);
      onLight('warn', ShellxLightPalette.warn, [5.70, 6.19, 6.66, 7.15], 4.5);
      onLight('error', ShellxLightPalette.error, [5.42, 5.88, 6.34, 6.80], 4.5);
      onLight('fieldOutline', ShellxLightPalette.fieldOutline, [
        3.34,
        3.63,
        3.91,
      ], 3);
      pair(
        'placeholder on inset',
        ShellxLightPalette.placeholder,
        l.inset,
        4.82,
        4.5,
      );
    });

    test('ink on fills and on the keyboard', () {
      pair(
        'white on primary',
        ShellxPalette.white100,
        ShellxLightPalette.primary,
        5.87,
        4.5,
      );
      pair(
        'primary on primarySoft',
        ShellxLightPalette.primary,
        ShellxLightPalette.primarySoft,
        4.72,
        4.5,
      );
      pair(
        'ok on okSoft',
        ShellxLightPalette.ok,
        ShellxLightPalette.okSoft,
        5.55,
        4.5,
      );
      pair('okDot on page', ShellxLightPalette.okDot, l.page, 3.72, 3);
      pair(
        'warn on warnSoft',
        ShellxLightPalette.warn,
        ShellxLightPalette.warnSoft,
        6.14,
        4.5,
      );
      pair(
        'error on errorSoft',
        ShellxLightPalette.error,
        ShellxLightPalette.errorSoft,
        5.76,
        4.5,
      );
      pair(
        'white on error',
        ShellxPalette.white100,
        ShellxLightPalette.error,
        6.80,
        4.5,
      );
      pair(
        'keyboard link',
        ShellxLightPalette.keyboardLink,
        ShellxLightPalette.keyboardBackground,
        4.95,
        4.5,
      );
      pair(
        'keyboard error',
        ShellxLightPalette.keyboardError,
        ShellxLightPalette.keyboardBackground,
        5.26,
        4.5,
      );
      pair(
        'keyboard secondary',
        ShellxLightPalette.textSecondary,
        ShellxLightPalette.keyboardBackground,
        4.82,
        4.5,
      );
    });

    test('light glass over the wedge\'s light end', () {
      final glass = compositeOver(
        ShellxLightPalette.glassFill,
        ShellxPalette.accentLight,
      );
      expect(
        contrastRatio(ShellxLightPalette.text, glass),
        closeTo(14.05, 0.05),
      );
      expect(
        contrastRatio(ShellxLightPalette.textSecondary, glass),
        closeTo(5.78, 0.05),
      );
    });
  });

  group('terminal (§5.7)', () {
    const bg = ShellxTerminalPalette.background;
    test('foreground, ANSI and their bright forms ≥ 4.5:1', () {
      pair('foreground', ShellxTerminalPalette.foreground, bg, 12.35, 4.5);
      pair('brightBlack', ShellxTerminalPalette.brightBlack, bg, 4.96, 4.5);
      for (final c in [
        ShellxTerminalPalette.red,
        ShellxTerminalPalette.green,
        ShellxTerminalPalette.yellow,
        ShellxTerminalPalette.blue,
        ShellxTerminalPalette.magenta,
        ShellxTerminalPalette.cyan,
        ShellxTerminalPalette.brightRed,
        ShellxTerminalPalette.brightGreen,
        ShellxTerminalPalette.brightYellow,
        ShellxTerminalPalette.brightBlue,
        ShellxTerminalPalette.brightMagenta,
        ShellxTerminalPalette.brightCyan,
        ShellxTerminalPalette.brightWhite,
      ]) {
        expect(contrastRatio(c, bg), greaterThanOrEqualTo(5.5), reason: '$c');
      }
      expect(contrastRatio(ShellxTerminalPalette.red, bg), closeTo(5.57, 0.05));
      expect(
        contrastRatio(ShellxTerminalPalette.brightWhite, bg),
        closeTo(15.94, 0.05),
      );
      // The old bright black fails on the new background.
      expect(contrastRatio(const Color(0xFF6C8288), bg), closeTo(3.94, 0.05));
    });

    test('text on the selection; a black block is visible', () {
      final selected = compositeOver(ShellxTerminalPalette.selection, bg);
      expect(
        contrastRatio(ShellxTerminalPalette.foreground, selected),
        closeTo(6.43, 0.05),
      );
      expect(
        contrastRatio(ShellxTerminalPalette.foreground, selected),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrastRatio(ShellxTerminalPalette.black, bg),
        closeTo(1.30, 0.05),
      );
    });

    test('the phone\'s chrome', () {
      pair(
        'muted on chrome',
        ShellxTerminalPalette.muted,
        ShellxTerminalPalette.chrome,
        5.96,
        4.5,
      );
      pair(
        'muted on chrome2',
        ShellxTerminalPalette.muted,
        ShellxTerminalPalette.chrome2,
        5.23,
        4.5,
      );
      pair(
        'onCyan on cyan',
        ShellxTerminalPalette.onCyan,
        ShellxTerminalPalette.cyan,
        10.05,
        4.5,
      );
    });
  });
}
