import 'package:flutter/material.dart';
import 'app_colors.dart';

class LightColors extends AppColors {
  @override
  Color primary = const Color(0xff0097A8);

  @override
  Color accent = const Color(0xFF7AAB3C);

  @override
  Color primaryText = const Color(0xFF111111);

  @override
  Color secondaryText = const Color(0xFF434B56);

  @override
  Color disable = const Color(0xFF8B8F95);

  @override
  Color border = const Color(0xFFD8D9DB);

  @override
  Color divider = const Color(0xFFEBECED);

  @override
  Color background = const Color(0xffF2F7F8);

  @override
  Color white = const Color(0xFFFFFFFF);

  @override
  Color surface = const Color(0xFFFFFFFF);

  @override
  Color error = const Color(0xFFCB232B);

  @override
  Color mainRed = const Color(0xFFCB232B);

  @override
  Color lightRed = const Color(0xFFFAE9EA);

  @override
  Color mainGold = const Color(0xFFE17E00);

  @override
  Color lightGold = const Color(0xFFFCF2E5);

  @override
  Color mainGreen = const Color(0xFF5A9B3D);

  @override
  Color lightGreen = const Color(0xFFEEF5EC);

  @override
  Gradient gradient = const LinearGradient(
    colors: [Color(0xFFDD801A), Color(0xFFDE3915)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  @override
  Color mediumRed = const Color(0xFFDE3915);

  @override
  Color mediumOrange = const Color(0xFFDD801A);

  @override
  Color black = Colors.black;

  @override
  Color blueGrey = const Color.fromARGB(255, 6, 35, 47);

  @override
  void setAccentColor(Color color) {
    accent = color;
  }

  @override
  void setBackgroundColor(Color color) {
    background = color;
  }

  @override
  void setPrimaryColor(Color color) {
    primary = color;
  }
}
