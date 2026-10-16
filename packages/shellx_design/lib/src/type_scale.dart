import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TextTheme;
import 'package:flutter/painting.dart';

/// V2-5a A31, §6.1: the font families by platform. SF Mono is the system's
/// own on iOS and macOS, loaded at run time ([ShellxSystemFont]) and never
/// bundled; JetBrains Mono ships in both apps and is used everywhere else,
/// and on iOS and macOS when SF Mono did not load.
abstract final class ShellxFonts {
  /// The family [ShellxSystemFont] registers the system's SF Mono under.
  static const String systemMono = 'SF Mono';

  /// Bundled by both apps (`assets/fonts/JetBrainsMono-*.ttf`).
  static const String bundledMono = 'JetBrainsMono';

  /// The desktop's Light cut as its own family (the terminal default).
  static const String bundledMonoLight = 'JetBrainsMonoLight';

  /// iOS and macOS: the platforms whose system font ShellX may display.
  static bool isApple(TargetPlatform platform) =>
      platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;

  /// The UI family of [platform]. A32: never "SF Mono" off Apple platforms,
  /// not even when the user installed it there.
  static String uiFamily(TargetPlatform platform) =>
      isApple(platform) ? systemMono : bundledMono;

  /// What the engine falls back to when [uiFamily] is not registered.
  static List<String> uiFallback(TargetPlatform platform) =>
      isApple(platform) ? const [bundledMono] : const [];
}

/// [style] at [weight]: sets `fontWeight` and the variable font's `wght`
/// axis together (A35). The system's SF Mono is one variable font whose
/// default is 295 (Light): a weight alone would not change it. JetBrains
/// Mono is static and ignores the axis (500 draws Regular, 600 Bold).
TextStyle shellxWeight(TextStyle style, FontWeight weight) => style.copyWith(
  fontWeight: weight,
  fontVariations: [FontVariation('wght', weight.value.toDouble())],
);

/// [theme] with each style's `wght` axis set to its weight, so text that
/// only takes a theme style (a plain `Text`, a Material label) is never
/// drawn at SF Mono's default Light.
TextTheme shellxWeightedTextTheme(TextTheme theme) {
  TextStyle? weighted(TextStyle? style) => style == null
      ? null
      : shellxWeight(style, style.fontWeight ?? FontWeight.w400);
  return TextTheme(
    displayLarge: weighted(theme.displayLarge),
    displayMedium: weighted(theme.displayMedium),
    displaySmall: weighted(theme.displaySmall),
    headlineLarge: weighted(theme.headlineLarge),
    headlineMedium: weighted(theme.headlineMedium),
    headlineSmall: weighted(theme.headlineSmall),
    titleLarge: weighted(theme.titleLarge),
    titleMedium: weighted(theme.titleMedium),
    titleSmall: weighted(theme.titleSmall),
    bodyLarge: weighted(theme.bodyLarge),
    bodyMedium: weighted(theme.bodyMedium),
    bodySmall: weighted(theme.bodySmall),
    labelLarge: weighted(theme.labelLarge),
    labelMedium: weighted(theme.labelMedium),
    labelSmall: weighted(theme.labelSmall),
  );
}

/// V2-5a A34, §6.5: the type scale of both apps for a monospaced UI font:
/// smaller sizes, the same line heights in px (no vertical layout moves).
/// No colour and no family (the theme gives the family per platform); each
/// style sets its weight and `wght` together.
abstract final class ShellxTypeScale {
  /// A36: px added to every desktop size on Windows, line heights kept,
  /// should the legibility check of JetBrains Mono at 11–12 px fail. 0: off.
  static const double desktopWindowsBoost = 0;

  /// [style] (a `desktop*` style) as drawn on [platform]: on Windows,
  /// [boost] px larger with the same line height in px.
  static TextStyle desktopFor(
    TextStyle style,
    TargetPlatform platform, {
    double boost = desktopWindowsBoost,
  }) {
    if (platform != TargetPlatform.windows || boost == 0) return style;
    final size = style.fontSize!;
    final line = size * style.height!;
    return style.copyWith(
      fontSize: size + boost,
      height: line / (size + boost),
    );
  }

  // Desktop (`ShellxText`): size / line px, weight.
  /// 11/14, 500: shortcut hints in menus, tooltips; the context line.
  static const TextStyle desktopCaption = TextStyle(
    fontSize: 11,
    height: 14 / 11,
    fontWeight: FontWeight.w500,
    fontVariations: [FontVariation('wght', 500)],
  );

  /// 11.5/16, 400: pane headers, tooltips, chips.
  static const TextStyle desktopSmall = TextStyle(
    fontSize: 11.5,
    height: 16 / 11.5,
    fontWeight: FontWeight.w400,
    fontVariations: [FontVariation('wght', 400)],
  );

  /// 12/18, 400: tab names, strips, menu items, toasts.
  static const TextStyle desktopBody = TextStyle(
    fontSize: 12,
    height: 18 / 12,
    fontWeight: FontWeight.w400,
    fontVariations: [FontVariation('wght', 400)],
  );

  /// 12/18, 600: the selected tab, button labels.
  static const TextStyle desktopBodyStrong = TextStyle(
    fontSize: 12,
    height: 18 / 12,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation('wght', 600)],
  );

  /// 11.5/16, 600: field labels, the brand line.
  static const TextStyle desktopLabel = TextStyle(
    fontSize: 11.5,
    height: 16 / 11.5,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation('wght', 600)],
  );

  /// 13/20, 400: dialog bodies, field values, AI markdown.
  static const TextStyle desktopDialogBody = TextStyle(
    fontSize: 13,
    height: 20 / 13,
    fontWeight: FontWeight.w400,
    fontVariations: [FontVariation('wght', 400)],
  );

  /// 14/20, 600: empty-state titles.
  static const TextStyle desktopEmptyTitle = TextStyle(
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation('wght', 600)],
  );

  /// 16/22, 600: dialog titles.
  static const TextStyle desktopDialogTitle = TextStyle(
    fontSize: 16,
    height: 22 / 16,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation('wght', 600)],
  );

  /// 22/28, 600: for V2-5b (the AI home greeting).
  static const TextStyle desktopDisplay = TextStyle(
    fontSize: 22,
    height: 28 / 22,
    fontWeight: FontWeight.w600,
    fontVariations: [FontVariation('wght', 600)],
  );

  /// 12/17, 400: code in the AI pane (`kAiMono`), in the platform's family.
  static const TextStyle desktopCode = TextStyle(
    fontSize: 12,
    height: 17 / 12,
    fontWeight: FontWeight.w400,
    fontVariations: [FontVariation('wght', 400)],
  );

  // Phone (`AppTypography`): the old line px over the new size. Weight 400;
  // the getters' `.medium`, `.semiBold`, `.bold`, `.heavy` go through
  // [shellxWeight].
  static const TextStyle mobileDisplay56 = TextStyle(
    fontSize: 54,
    height: 56 * 1.4 / 54,
    fontWeight: FontWeight.w400,
    fontVariations: [FontVariation('wght', 400)],
  );
  static const TextStyle mobileDisplay42 = TextStyle(
    fontSize: 40,
    height: 42 * 1.5 / 40,
    fontWeight: FontWeight.w400,
    fontVariations: [FontVariation('wght', 400)],
  );
  static const TextStyle mobileDisplay36 = TextStyle(
    fontSize: 34,
    height: 36 * 1.5 / 34,
    fontWeight: FontWeight.w400,
    fontVariations: [FontVariation('wght', 400)],
  );
  static const TextStyle mobileDisplay32 = TextStyle(
    fontSize: 30,
    height: 32 * 1.5 / 30,
    fontWeight: FontWeight.w400,
    fontVariations: [FontVariation('wght', 400)],
  );
  static const TextStyle mobileHeading28 = TextStyle(
    fontSize: 26,
    height: 28 * 1.5 / 26,
    fontWeight: FontWeight.w400,
    fontVariations: [FontVariation('wght', 400)],
  );
  static const TextStyle mobileHeading26 = TextStyle(
    fontSize: 24,
    height: 26 * 1.5 / 24,
    fontWeight: FontWeight.w400,
    fontVariations: [FontVariation('wght', 400)],
  );
  static const TextStyle mobileHeading24 = TextStyle(
    fontSize: 22,
    height: 24 * 1.5 / 22,
    fontWeight: FontWeight.w400,
    fontVariations: [FontVariation('wght', 400)],
  );
  static const TextStyle mobileHeading20 = TextStyle(
    fontSize: 19,
    height: 20 * 1.6 / 19,
    fontWeight: FontWeight.w400,
    fontVariations: [FontVariation('wght', 400)],
  );
  static const TextStyle mobileTitle = TextStyle(
    fontSize: 17,
    height: 18 * 1.61 / 17,
    fontWeight: FontWeight.w400,
    fontVariations: [FontVariation('wght', 400)],
  );
  static const TextStyle mobileSubHeader = TextStyle(
    fontSize: 15,
    height: 16 * 1.625 / 15,
    fontWeight: FontWeight.w400,
    fontVariations: [FontVariation('wght', 400)],
  );
  static const TextStyle mobileSubHeader15 = TextStyle(
    fontSize: 14,
    height: 15 * 1.625 / 14,
    fontWeight: FontWeight.w400,
    fontVariations: [FontVariation('wght', 400)],
  );
  static const TextStyle mobileParagraph = TextStyle(
    fontSize: 13,
    height: 14 * 1.57 / 13,
    fontWeight: FontWeight.w400,
    fontVariations: [FontVariation('wght', 400)],
  );
  static const TextStyle mobileParagraph13 = TextStyle(
    fontSize: 13,
    height: 1.57,
    fontWeight: FontWeight.w400,
    fontVariations: [FontVariation('wght', 400)],
  );
  static const TextStyle mobileMetadata12 = TextStyle(
    fontSize: 12,
    height: 19 / 12,
    fontWeight: FontWeight.w400,
    fontVariations: [FontVariation('wght', 400)],
  );
  static const TextStyle mobileMetadata11 = TextStyle(
    fontSize: 11,
    height: 19 / 12,
    fontWeight: FontWeight.w400,
    fontVariations: [FontVariation('wght', 400)],
  );
  static const TextStyle mobileMetadata10 = TextStyle(
    fontSize: 10,
    height: 1.6,
    fontWeight: FontWeight.w400,
    fontVariations: [FontVariation('wght', 400)],
  );
  static const TextStyle mobileMetadata8 = TextStyle(
    fontSize: 8,
    height: 1.6,
    fontWeight: FontWeight.w400,
    fontVariations: [FontVariation('wght', 400)],
  );

  /// The phone's AppBar title: 16, 700 (was 17).
  static const TextStyle mobileAppBarTitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    fontVariations: [FontVariation('wght', 700)],
  );
}
