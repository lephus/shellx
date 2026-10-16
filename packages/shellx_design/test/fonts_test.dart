import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_design/shellx_design.dart';

void main() {
  test('families by platform (§6.1): SF Mono only on iOS and macOS', () {
    for (final p in [TargetPlatform.iOS, TargetPlatform.macOS]) {
      expect(ShellxFonts.isApple(p), isTrue);
      expect(ShellxFonts.uiFamily(p), 'SF Mono');
      expect(ShellxFonts.uiFallback(p), ['JetBrainsMono']);
    }
    for (final p in [
      TargetPlatform.android,
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.fuchsia,
    ]) {
      expect(ShellxFonts.isApple(p), isFalse);
      expect(ShellxFonts.uiFamily(p), 'JetBrainsMono');
      expect(ShellxFonts.uiFallback(p), isEmpty);
    }
    expect(ShellxFonts.systemMono, 'SF Mono');
    expect(ShellxFonts.bundledMono, 'JetBrainsMono');
    expect(ShellxFonts.bundledMonoLight, 'JetBrainsMonoLight');
  });

  test('shellxWeight sets the weight and the wght axis together (A35)', () {
    const base = TextStyle(
      fontSize: 12,
      fontVariations: [FontVariation('wght', 400)],
    );
    for (final w in [
      FontWeight.w300,
      FontWeight.w500,
      FontWeight.w600,
      FontWeight.w700,
    ]) {
      final s = shellxWeight(base, w);
      expect(s.fontWeight, w);
      expect(s.fontVariations, [FontVariation('wght', w.value.toDouble())]);
      expect(s.fontSize, 12);
    }
  });

  test('a theme\'s text styles carry wght = their weight', () {
    final theme = shellxWeightedTextTheme(
      ThemeData(useMaterial3: true).textTheme,
    );
    for (final style in [
      theme.displayLarge,
      theme.headlineSmall,
      theme.titleLarge,
      theme.titleMedium,
      theme.bodyLarge,
      theme.bodyMedium,
      theme.bodySmall,
      theme.labelLarge,
      theme.labelSmall,
    ]) {
      final weight = style!.fontWeight ?? FontWeight.w400;
      expect(style.fontVariations, [
        FontVariation('wght', weight.value.toDouble()),
      ]);
    }
    expect(
      shellxWeightedTextTheme(
        const TextTheme(bodyMedium: TextStyle()),
      ).bodyMedium!.fontVariations,
      [const FontVariation('wght', 400)],
    );
  });

  group('type scale (§6.5): new sizes, line heights in px as before', () {
    void scale(TextStyle s, double size, double linePx, FontWeight weight) {
      expect(s.fontSize, size);
      expect(s.fontSize! * s.height!, closeTo(linePx, 0.01));
      expect(s.fontWeight, weight);
      expect(s.fontVariations, [
        FontVariation('wght', weight.value.toDouble()),
      ]);
      expect(s.fontFamily, isNull, reason: 'the theme gives the family');
      expect(s.color, isNull);
    }

    test('desktop', () {
      scale(ShellxTypeScale.desktopCaption, 11, 14, FontWeight.w500);
      scale(ShellxTypeScale.desktopSmall, 11.5, 16, FontWeight.w400);
      scale(ShellxTypeScale.desktopBody, 12, 18, FontWeight.w400);
      scale(ShellxTypeScale.desktopBodyStrong, 12, 18, FontWeight.w600);
      scale(ShellxTypeScale.desktopLabel, 11.5, 16, FontWeight.w600);
      scale(ShellxTypeScale.desktopDialogBody, 13, 20, FontWeight.w400);
      scale(ShellxTypeScale.desktopEmptyTitle, 14, 20, FontWeight.w600);
      scale(ShellxTypeScale.desktopDialogTitle, 16, 22, FontWeight.w600);
      scale(ShellxTypeScale.desktopDisplay, 22, 28, FontWeight.w600);
      scale(ShellxTypeScale.desktopCode, 12, 17, FontWeight.w400);
    });

    test('phone', () {
      const w = FontWeight.w400;
      scale(ShellxTypeScale.mobileDisplay56, 54, 78.4, w);
      scale(ShellxTypeScale.mobileDisplay42, 40, 63, w);
      scale(ShellxTypeScale.mobileDisplay36, 34, 54, w);
      scale(ShellxTypeScale.mobileDisplay32, 30, 48, w);
      scale(ShellxTypeScale.mobileHeading28, 26, 42, w);
      scale(ShellxTypeScale.mobileHeading26, 24, 39, w);
      scale(ShellxTypeScale.mobileHeading24, 22, 36, w);
      scale(ShellxTypeScale.mobileHeading20, 19, 32, w);
      scale(ShellxTypeScale.mobileTitle, 17, 28.98, w);
      scale(ShellxTypeScale.mobileSubHeader, 15, 26, w);
      scale(ShellxTypeScale.mobileSubHeader15, 14, 24.375, w);
      scale(ShellxTypeScale.mobileParagraph, 13, 21.98, w);
      scale(ShellxTypeScale.mobileParagraph13, 13, 20.41, w);
      scale(ShellxTypeScale.mobileMetadata12, 12, 19, w);
      scale(ShellxTypeScale.mobileMetadata11, 11, 11 * 19 / 12, w);
      scale(ShellxTypeScale.mobileMetadata10, 10, 16, w);
      scale(ShellxTypeScale.mobileMetadata8, 8, 12.8, w);
      expect(ShellxTypeScale.mobileAppBarTitle.fontSize, 16);
      expect(ShellxTypeScale.mobileAppBarTitle.fontWeight, FontWeight.w700);
    });

    test('the Windows boost (A36): off by default; +n px, same line px', () {
      expect(ShellxTypeScale.desktopWindowsBoost, 0);
      const body = ShellxTypeScale.desktopBody;
      for (final p in TargetPlatform.values) {
        expect(identical(ShellxTypeScale.desktopFor(body, p), body), isTrue);
      }
      final boosted = ShellxTypeScale.desktopFor(
        body,
        TargetPlatform.windows,
        boost: 1,
      );
      expect(boosted.fontSize, 13);
      expect(boosted.fontSize! * boosted.height!, closeTo(18, 1e-9));
      expect(
        identical(
          ShellxTypeScale.desktopFor(body, TargetPlatform.macOS, boost: 1),
          body,
        ),
        isTrue,
      );
    });
  });
}
