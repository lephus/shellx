import 'package:flutter/painting.dart';

import 'palette.dart';

/// V2-5a §5.5. Which one carries text (A20):
/// - any regular text, or bold text under 15 px: [accentStrong];
/// - bold (≥ 600) from 15 px, icons, areas without text: [accent].
/// Hover and pressed shade the gradient black ([hoverShade], [pressedShade]);
/// white over it would drop the contrast.
abstract final class ShellxGradients {
  /// White ≥ 3.12:1 everywhere: icons, bold text from 15 px, decoration.
  static const LinearGradient accent = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [ShellxPalette.accentLight, ShellxPalette.indigo],
  );

  /// White ≥ 4.65:1 everywhere: every other text.
  static const LinearGradient accentStrong = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [ShellxPalette.accentStrongLight, ShellxPalette.indigo],
  );

  /// The corner wedge (A30), top to bottom.
  static const LinearGradient wedge = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [ShellxPalette.accentLight, ShellxPalette.wedgeBottom],
  );

  /// Glass's 1 px border, dark: white 20 % to 4 %.
  static const LinearGradient glassBorderDark = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x33FFFFFF), Color(0x0AFFFFFF)],
  );

  /// Glass's 1 px border, light: navy 8 % to 2 %.
  static const LinearGradient glassBorderLight = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x14141A26), Color(0x05141A26)],
  );

  /// Hover over a gradient: black 8 %.
  static const Color hoverShade = Color(0x14000000);

  /// Pressed over a gradient: black 16 %.
  static const Color pressedShade = Color(0x29000000);
}
