import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_design/shellx_design.dart';

/// V2-5a §5.3–§5.8: every token's exact value.
void main() {
  test('dark palette (§5.3)', () {
    final values = <Color, int>{
      ShellxPalette.navy900: 0xFF1C222E,
      ShellxPalette.navy850: 0xFF222834,
      ShellxPalette.navy825: 0xFF242C3B,
      ShellxPalette.navy800: 0xFF28303F,
      ShellxPalette.navy750: 0xFF2C3547,
      ShellxPalette.navy700: 0xFF323B4F,
      ShellxPalette.navy650: 0xFF38445A,
      ShellxPalette.navy600: 0xFF3F4B62,
    };
    values.forEach((c, v) => expect(c, Color(v)));
    expect(ShellxPalette.white100, const Color(0xFFFFFFFF));
    expect(ShellxPalette.white87, const Color(0xFFE2E3E5));
    expect(ShellxPalette.white75, const Color(0xFFCACCD1));
    expect(ShellxPalette.white60, const Color(0xFFA7A9AE));
    expect(ShellxPalette.white50, const Color(0xFF8E9096));
    expect(ShellxPalette.white38, const Color(0xFF767A81));
    expect(ShellxPalette.hairline, const Color(0x14FFFFFF));
    expect(ShellxPalette.hairlineStrong, const Color(0x1AFFFFFF));
    expect(ShellxPalette.handle, const Color(0x33FFFFFF));
    expect(ShellxPalette.fieldOutline, const Color(0xFF76829C));
    expect(ShellxPalette.cyan, const Color(0xFF34C8E8));
    expect(ShellxPalette.onCyan, const Color(0xFF0E1A26));
    expect(ShellxPalette.cyanSoft, const Color(0xFF253E4D));
    expect(ShellxPalette.azure, const Color(0xFF3D9CEA));
    expect(ShellxPalette.link, const Color(0xFF5EADEE));
    expect(ShellxPalette.onAccent, const Color(0xFFFFFFFF));
    expect(ShellxPalette.accentLight, const Color(0xFF1A9BD8));
    expect(ShellxPalette.accentStrongLight, const Color(0xFF157CAD));
    expect(ShellxPalette.indigo, const Color(0xFF4E4AF2));
    expect(ShellxPalette.wedgeBottom, const Color(0xFF3C65CF));
    expect(ShellxPalette.scrim, const Color(0x99000000));
    expect(ShellxPalette.scrollThumb, const Color(0xFF3D424C));
    expect(ShellxPalette.scrollThumbHover, const Color(0xFF4E535D));
    expect(ShellxPalette.keyboardBackground, const Color(0xFF1E1F21));
    expect(ShellxPalette.keyboardKey, const Color(0xFF47484B));
    expect(ShellxPalette.keyboardInk, const Color(0xFFFFFFFF));
    expect(ShellxPalette.glassFill, const Color(0xCC323B4F));
  });

  test('status colours (§5.6)', () {
    expect(ShellxPalette.ok, const Color(0xFF5ED39C));
    expect(ShellxPalette.okSoft, const Color(0xFF293D40));
    expect(ShellxPalette.warn, const Color(0xFFF5B94E));
    expect(ShellxPalette.warnSoft, const Color(0xFF3B3937));
    expect(ShellxPalette.warnLine, const Color(0xFF554B3A));
    expect(ShellxPalette.error, const Color(0xFFFF8A94));
    expect(ShellxPalette.errorSoft, const Color(0xFF3D3440));
    expect(ShellxPalette.onError, const Color(0xFF2A0A0C));
    expect(ShellxPalette.errorHover, const Color(0xFFFF98A1));
    expect(ShellxPalette.noticeBg, const Color(0xFF453F50));
    expect(ShellxPalette.noticeText, const Color(0xFFFFD9DB));
    expect(ShellxPalette.noticeLine, const Color(0xFF5F4959));
    expect(ShellxPalette.inProgress, const Color(0xFF6EA8FE));
  });

  test('light palette (§5.4)', () {
    expect(ShellxLightPalette.page, const Color(0xFFEAEFF5));
    expect(ShellxLightPalette.surface, const Color(0xFFF5F7FA));
    expect(ShellxLightPalette.raised, const Color(0xFFFFFFFF));
    expect(ShellxLightPalette.inset, const Color(0xFFE0E6EE));
    expect(ShellxLightPalette.text, const Color(0xFF141A26));
    expect(ShellxLightPalette.textSecondary, const Color(0xFF4E586B));
    expect(ShellxLightPalette.placeholder, const Color(0xFF596376));
    expect(ShellxLightPalette.hairline, const Color(0x1A141A26));
    expect(ShellxLightPalette.handle, const Color(0x33141A26));
    expect(ShellxLightPalette.fieldOutline, const Color(0xFF717C92));
    expect(ShellxLightPalette.primary, const Color(0xFF1767AD));
    expect(ShellxLightPalette.primarySoft, const Color(0xFFDCE8F3));
    expect(ShellxLightPalette.ok, const Color(0xFF256B45));
    expect(ShellxLightPalette.okDot, const Color(0xFF2E8A57));
    expect(ShellxLightPalette.okSoft, const Color(0xFFE9F0EC));
    expect(ShellxLightPalette.warn, const Color(0xFF7F4C00));
    expect(ShellxLightPalette.warnSoft, const Color(0xFFF2EDE6));
    expect(ShellxLightPalette.error, const Color(0xFFB0202B));
    expect(ShellxLightPalette.errorSoft, const Color(0xFFF7E9EA));
    expect(ShellxLightPalette.scrim, const Color(0x73141A26));
    expect(ShellxLightPalette.keyboardBackground, const Color(0xFFD1D4DA));
    expect(ShellxLightPalette.keyboardKey, const Color(0xFFFFFFFF));
    expect(ShellxLightPalette.keyboardInk, const Color(0xFF000000));
    expect(ShellxLightPalette.keyboardLink, const Color(0xFF14598F));
    expect(ShellxLightPalette.keyboardError, const Color(0xFFA3161D));
    expect(ShellxLightPalette.glassFill, const Color(0xCCFFFFFF));
    expect(ShellxLightPalette.glassBorder, const Color(0x14141A26));
  });

  test('gradients (§5.5): stops and directions', () {
    void check(
      LinearGradient g,
      List<int> colors,
      Alignment begin,
      Alignment end,
    ) {
      expect(g.colors, [for (final c in colors) Color(c)]);
      expect(g.stops, isNull);
      expect(g.begin, begin);
      expect(g.end, end);
    }

    check(
      ShellxGradients.accent,
      [0xFF1A9BD8, 0xFF4E4AF2],
      Alignment.topLeft,
      Alignment.bottomRight,
    );
    check(
      ShellxGradients.accentStrong,
      [0xFF157CAD, 0xFF4E4AF2],
      Alignment.topLeft,
      Alignment.bottomRight,
    );
    check(
      ShellxGradients.wedge,
      [0xFF1A9BD8, 0xFF3C65CF],
      Alignment.topCenter,
      Alignment.bottomCenter,
    );
    check(
      ShellxGradients.glassBorderDark,
      [0x33FFFFFF, 0x0AFFFFFF],
      Alignment.topLeft,
      Alignment.bottomRight,
    );
    check(
      ShellxGradients.glassBorderLight,
      [0x14141A26, 0x05141A26],
      Alignment.topLeft,
      Alignment.bottomRight,
    );
    expect(ShellxGradients.hoverShade, const Color(0x14000000));
    expect(ShellxGradients.pressedShade, const Color(0x29000000));
  });

  test('terminal palette (§5.7)', () {
    expect(ShellxTerminalPalette.background, const Color(0xFF1C222E));
    expect(ShellxTerminalPalette.foreground, const Color(0xFFDDE3EC));
    expect(ShellxTerminalPalette.cursor, const Color(0xFFDDE3EC));
    expect(ShellxTerminalPalette.white, const Color(0xFFDDE3EC));
    expect(ShellxTerminalPalette.selection, const Color(0x4D34C8E8));
    expect(ShellxTerminalPalette.black, const Color(0xFF2C3547));
    expect(ShellxTerminalPalette.brightBlack, const Color(0xFF8590A6));
    expect(
      [
        ShellxTerminalPalette.red,
        ShellxTerminalPalette.green,
        ShellxTerminalPalette.yellow,
        ShellxTerminalPalette.blue,
        ShellxTerminalPalette.magenta,
        ShellxTerminalPalette.cyan,
      ],
      const [
        Color(0xFFF07178),
        Color(0xFF7ED492),
        Color(0xFFE9C46A),
        Color(0xFF82AAFF),
        Color(0xFFC792EA),
        Color(0xFF5FD4E2),
      ],
    );
    expect(
      [
        ShellxTerminalPalette.brightRed,
        ShellxTerminalPalette.brightGreen,
        ShellxTerminalPalette.brightYellow,
        ShellxTerminalPalette.brightBlue,
        ShellxTerminalPalette.brightMagenta,
        ShellxTerminalPalette.brightCyan,
        ShellxTerminalPalette.brightWhite,
      ],
      const [
        Color(0xFFFF8F95),
        Color(0xFF9BE3AB),
        Color(0xFFF2D68C),
        Color(0xFFA5C2FF),
        Color(0xFFDAB3F1),
        Color(0xFF8FE3EC),
        Color(0xFFFFFFFF),
      ],
    );
    expect(
      ShellxTerminalPalette.searchHitBackground,
      ShellxTerminalPalette.yellow,
    );
    expect(
      ShellxTerminalPalette.searchHitBackgroundCurrent,
      ShellxTerminalPalette.cyan,
    );
    expect(
      ShellxTerminalPalette.searchHitForeground,
      ShellxTerminalPalette.background,
    );
    expect(ShellxTerminalPalette.chrome, const Color(0xFF242C3B));
    expect(ShellxTerminalPalette.chrome2, const Color(0xFF2C3547));
    expect(ShellxTerminalPalette.line, const Color(0xFF343944));
    expect(ShellxTerminalPalette.dim, const Color(0xFF767A81));
    expect(ShellxTerminalPalette.muted, const Color(0xFFA7A9AE));
    expect(ShellxTerminalPalette.title, const Color(0xFFFFFFFF));
    expect(ShellxTerminalPalette.secondaryAction, const Color(0xFF323B4F));
    expect(ShellxTerminalPalette.onCyan, const Color(0xFF0E1A26));
    expect(ShellxTerminalPalette.noticeBackground, const Color(0xFF453F50));
    expect(ShellxTerminalPalette.noticeText, const Color(0xFFFFD9DB));
    expect(ShellxTerminalPalette.noticeBorder, const Color(0xFF5F4959));
    expect(
      ShellxTerminalPalette.driverBannerBackground,
      const Color(0xFF3B3937),
    );
    expect(ShellxTerminalPalette.driverBannerBorder, const Color(0xFF554B3A));
  });

  test('radii and spacing (§5.8)', () {
    expect(
      [
        ShellxRadii.tiny,
        ShellxRadii.control,
        ShellxRadii.card,
        ShellxRadii.sheet,
        ShellxRadii.pill,
      ],
      [6, 10, 16, 28, 999],
    );
    expect(
      [
        ShellxSpacing.s2,
        ShellxSpacing.s4,
        ShellxSpacing.s6,
        ShellxSpacing.s8,
        ShellxSpacing.s12,
        ShellxSpacing.s16,
        ShellxSpacing.s20,
        ShellxSpacing.s24,
        ShellxSpacing.s32,
        ShellxSpacing.s40,
        ShellxSpacing.s48,
      ],
      [2, 4, 6, 8, 12, 16, 20, 24, 32, 40, 48],
    );
  });

  test('shadows (§5.8), dark and light', () {
    List<(double, double, double, int)> shape(List<BoxShadow> s) => [
      for (final b in s)
        (b.offset.dx, b.offset.dy, b.blurRadius, b.color.toARGB32()),
    ];
    final dark = ShellxElevation.dark;
    expect(shape(dark.raised), [
      (4.0, 4.0, 12.0, 0x59000000),
      (-3.0, -3.0, 10.0, 0x0FFFFFFF),
    ]);
    expect(shape(dark.raisedSmall), [
      (2.0, 2.0, 6.0, 0x59000000),
      (-1.0, -1.0, 4.0, 0x0DFFFFFF),
    ]);
    expect(shape(dark.inset.shadows), [
      (2.0, 2.0, 6.0, 0x73000000),
      (-1.0, -1.0, 3.0, 0x0DFFFFFF),
    ]);
    expect(shape(dark.float1), [(0.0, 4.0, 16.0, 0x73000000)]);
    expect(shape(dark.float2), [(0.0, 16.0, 48.0, 0x8C000000)]);
    expect(shape(dark.cta), [(0.0, 8.0, 20.0, 0x664E4AF2)]);
    final light = ShellxElevation.light;
    expect(shape(light.raised), [
      (4.0, 4.0, 12.0, 0x40566A8C),
      (-4.0, -4.0, 12.0, 0xFFFFFFFF),
    ]);
    expect(shape(light.raisedSmall), [
      (2.0, 2.0, 6.0, 0x33566A8C),
      (-2.0, -2.0, 6.0, 0xFFFFFFFF),
    ]);
    expect(shape(light.inset.shadows), [
      (2.0, 2.0, 6.0, 0x33566A8C),
      (-1.0, -1.0, 3.0, 0xCCFFFFFF),
    ]);
    expect(shape(light.float1), [(0.0, 4.0, 16.0, 0x1F141A26)]);
    expect(shape(light.float2), [(0.0, 12.0, 32.0, 0x29141A26)]);
    expect(shape(light.cta), [(0.0, 6.0, 16.0, 0x404E4AF2)]);
    // The const lists are the same objects the instances hold.
    expect(
      identical(ShellxElevation.dark.float1, ShellxElevation.darkFloat1),
      isTrue,
    );
    expect(ShellxElevation.float1Elevation, 8);
    expect(ShellxElevation.float1ShadowColor, const Color(0x73000000));
  });

  test('motion (§5.8)', () {
    expect(ShellxDurations.fast, const Duration(milliseconds: 80));
    expect(ShellxDurations.press, const Duration(milliseconds: 100));
    expect(ShellxDurations.exit, const Duration(milliseconds: 120));
    expect(ShellxDurations.base, const Duration(milliseconds: 150));
    expect(ShellxDurations.toastIn, const Duration(milliseconds: 160));
    expect(ShellxDurations.slide, const Duration(milliseconds: 200));
    expect(ShellxDurations.sheet, const Duration(milliseconds: 250));
    expect(ShellxDurations.toastVisible, const Duration(seconds: 4));
    expect(ShellxDurations.toastVisibleError, const Duration(seconds: 6));
    expect(ShellxDurations.toastVisiblePhone, const Duration(seconds: 3));
    expect(ShellxDurations.tooltipWait, const Duration(milliseconds: 500));
    expect(ShellxDurations.scrollbarFade, const Duration(milliseconds: 800));
    expect(ShellxDurations.dragExpandDelay, const Duration(milliseconds: 600));
    expect(ShellxCurves.fast, Curves.easeOut);
    expect(ShellxCurves.press, Curves.easeOut);
    expect(ShellxCurves.exit, Curves.easeIn);
    expect(ShellxCurves.base, Curves.easeOutCubic);
    expect(ShellxCurves.slide, Curves.easeOutCubic);
  });

  testWidgets('reduced motion turns every duration to zero', (tester) async {
    late Duration normal, reduced;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          normal = ShellxDurations.of(context, ShellxDurations.slide);
          return MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Builder(
              builder: (context) {
                reduced = ShellxDurations.of(context, ShellxDurations.slide);
                return const SizedBox();
              },
            ),
          );
        },
      ),
    );
    expect(normal, const Duration(milliseconds: 200));
    expect(reduced, Duration.zero);
  });
}
