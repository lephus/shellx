import 'package:flutter/material.dart';

class AppTypography {
  final FontWeight fontWeight = FontWeight.w400;
  Color color = Colors.black;

  TextStyle get display56 => TextStyle(
    fontSize: 56,
    fontWeight: fontWeight,
    height: 1.4,
    color: color,
  );

  //42
  TextStyle get display42 => TextStyle(
    fontSize: 42,
    color: color,
    height: 1.5,
    fontWeight: fontWeight,
  );

  //36
  TextStyle get display36 => TextStyle(
    fontSize: 36,
    color: color,
    height: 1.5,
    fontWeight: fontWeight,
  );
  //32
  TextStyle get display32 => TextStyle(
    fontSize: 32,
    color: color,
    height: 1.5,
    fontWeight: fontWeight,
  );

  //28
  TextStyle get heading28 => TextStyle(
    fontSize: 28,
    color: color,
    height: 1.5,
    fontWeight: fontWeight,
  );

  //28
  TextStyle get heading26 => TextStyle(
    fontSize: 26,
    color: color,
    height: 1.5,
    fontWeight: fontWeight,
  );

  //24
  TextStyle get heading24 => TextStyle(
    fontSize: 24,
    color: color,
    height: 1.5,
    fontWeight: fontWeight,
  );

  //20
  TextStyle get heading20 => TextStyle(
    fontSize: 20,
    color: color,
    height: 1.6,
    fontWeight: fontWeight,
  );

  //18
  TextStyle get title => TextStyle(
    fontSize: 18,
    color: color,
    height: 1.61,
    fontWeight: fontWeight,
  );

  //16
  TextStyle get subHeader => TextStyle(
    fontSize: 16,
    color: color,
    height: 1.625,
    fontWeight: fontWeight,
  );
  //16
  TextStyle get subHeader15 => TextStyle(
    fontSize: 15,
    color: color,
    height: 1.625,
    fontWeight: fontWeight,
  );

  //14
  TextStyle get paragraph => TextStyle(
    fontSize: 14,
    color: color,
    height: 1.57,
    fontWeight: fontWeight,
  );

  TextStyle get paragraph13 => TextStyle(
    fontSize: 13,
    color: color,
    height: 1.57,
    fontWeight: fontWeight,
  );

  //12
  TextStyle get metadata12 => TextStyle(
    fontSize: 12,
    color: color,
    height: 19 / 12,
    fontWeight: fontWeight,
  );

  //12
  TextStyle get metadata11 => TextStyle(
    fontSize: 11,
    color: color,
    height: 19 / 12,
    fontWeight: fontWeight,
  );

  //10
  TextStyle get metadata10 => TextStyle(
    fontSize: 10,
    color: color,
    height: 1.6,
    fontWeight: fontWeight,
  );

  //10
  TextStyle get metadata8 => TextStyle(
    fontSize: 8,
    color: color,
    height: 1.6,
    fontWeight: fontWeight,
  );

  AppTypography._internal();

  static AppTypography instance = _instance;

  static final AppTypography _instance = AppTypography._internal();

  void setColor(Color color) {
    this.color = color;
  }
}

extension ColorTextStyle on TextStyle {
  TextStyle mergeColor(Color color) {
    return copyWith(color: color);
  }

  TextStyle get heavy {
    return copyWith(fontWeight: FontWeight.w800);
  }

  TextStyle get semiBold {
    return copyWith(fontWeight: FontWeight.w600);
  }

  TextStyle get bold {
    return copyWith(fontWeight: FontWeight.w700);
  }

  TextStyle get medium {
    return copyWith(fontWeight: FontWeight.w500);
  }

  TextStyle get underline {
    return copyWith(
      decoration: TextDecoration.underline,
      decorationColor: color,
    );
  }

  TextStyle get italic {
    return copyWith(fontStyle: FontStyle.italic);
  }

  TextStyle get white => copyWith(color: Colors.white, decorationColor: Colors.white);
}
