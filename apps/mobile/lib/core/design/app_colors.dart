import 'package:flutter/material.dart';
import 'package:shellx_mobile/core/design/dark_colors.dart';
import 'light_colors.dart';

abstract class AppColors {
  Color get primary;
  Color get accent;
  Color get primaryText;
  Color get secondaryText;
  Color get disable;
  Color get border;
  Color get divider;
  Color get background;
  Color get surface;
  Color get white;
  Color get black;
  Color get error;
  Color get mainRed;
  Color get mediumRed;
  Color get lightRed;
  Color get mainGold;
  Color get lightGold;
  Color get mainGreen;
  Color get lightGreen;
  Color get mediumOrange;
  Color get blueGrey;
  Gradient get gradient;
  double get opacity => 0.12;

  // ShellX design (docs/superpowers/design/2026-09-25-shellx-mobile-ui.html, `--a-*` tokens).
  /// Text and icons on [primary].
  Color get onPrimary;

  /// Tinted background of soft buttons, badges and icon tiles.
  Color get primarySoft;

  /// "Online" text.
  Color get ok;

  /// The online dot.
  Color get okDot;

  /// Warning text (lost-connection banner).
  Color get warn;

  /// Warning background.
  Color get warnSoft;

  /// Error background (delete-account warning box, error icons).
  Color get errorSoft;

  /// Dimming behind sheets and dialogs.
  Color get scrim;

  /// Link and action text on [background], [surface] and [primarySoft] (≥ 4.5:1; light
  /// [primary] is only 3.0–3.5:1 there). Desktop UI doc §7.3: `--accent #007785`.
  Color get link;

  /// Fill under [onPrimary] text: filled buttons, a locked modifier key, the listening mic, a
  /// selected segment (≥ 4.5:1 with [onPrimary]; light [primary] with white is only 3.5:1).
  Color get primaryFill;

  /// Accent text and icons on a [keyboardKey] cap (a one-shot Ctrl/Alt, the mic glyph).
  Color get keyAccent;

  /// Link text on [keyboardBackground] ("Mở Cài đặt" in the voice composer).
  Color get keyboardLink;

  /// Error text on [keyboardBackground] (the voice composer's issue line).
  Color get keyboardError;

  /// Extra keys bar (`--kb-*`): it follows the system keyboard's light or dark look.
  Color get keyboardBackground;
  Color get keyboardKey;
  Color get keyboardInk;

  void setPrimaryColor(Color color);

  void setAccentColor(Color color);

  void setBackgroundColor(Color color);
}

extension BrightnessTheme on Brightness {
  AppColors get appColors {
    return this == Brightness.light ? LightColors() : DarkColors();
  }
}
