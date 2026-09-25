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

  void setPrimaryColor(Color color);

  void setAccentColor(Color color);

  void setBackgroundColor(Color color);
}

extension BrightnessTheme on Brightness {
  AppColors get appColors {
    return this == Brightness.light ? LightColors() : DarkColors();
  }
}
