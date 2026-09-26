import 'package:flutter/material.dart';

class AppTypography {
  final FontWeight fontWeight = FontWeight.w400;
  Color color = Colors.black;

  /// ShellX design: Raleway with lining numerals, so times and versions sit on the line.
  static const List<FontFeature> liningFigures = [FontFeature.liningFigures()];

  TextStyle get display56 => TextStyle(
    fontFeatures: liningFigures,
    fontSize: 56,
    fontWeight: fontWeight,
    height: 1.4,
    color: color,
  );

  //42
  TextStyle get display42 => TextStyle(
    fontFeatures: liningFigures,
    fontSize: 42,
    color: color,
    height: 1.5,
    fontWeight: fontWeight,
  );

  //36
  TextStyle get display36 => TextStyle(
    fontFeatures: liningFigures,
    fontSize: 36,
    color: color,
    height: 1.5,
    fontWeight: fontWeight,
  );
  //32
  TextStyle get display32 => TextStyle(
    fontFeatures: liningFigures,
    fontSize: 32,
    color: color,
    height: 1.5,
    fontWeight: fontWeight,
  );

  //28
  TextStyle get heading28 => TextStyle(
    fontFeatures: liningFigures,
    fontSize: 28,
    color: color,
    height: 1.5,
    fontWeight: fontWeight,
  );

  //28
  TextStyle get heading26 => TextStyle(
    fontFeatures: liningFigures,
    fontSize: 26,
    color: color,
    height: 1.5,
    fontWeight: fontWeight,
  );

  //24
  TextStyle get heading24 => TextStyle(
    fontFeatures: liningFigures,
    fontSize: 24,
    color: color,
    height: 1.5,
    fontWeight: fontWeight,
  );

  //20
  TextStyle get heading20 => TextStyle(
    fontFeatures: liningFigures,
    fontSize: 20,
    color: color,
    height: 1.6,
    fontWeight: fontWeight,
  );

  //18
  TextStyle get title => TextStyle(
    fontFeatures: liningFigures,
    fontSize: 18,
    color: color,
    height: 1.61,
    fontWeight: fontWeight,
  );

  //16
  TextStyle get subHeader => TextStyle(
    fontFeatures: liningFigures,
    fontSize: 16,
    color: color,
    height: 1.625,
    fontWeight: fontWeight,
  );
  //16
  TextStyle get subHeader15 => TextStyle(
    fontFeatures: liningFigures,
    fontSize: 15,
    color: color,
    height: 1.625,
    fontWeight: fontWeight,
  );

  //14
  TextStyle get paragraph => TextStyle(
    fontFeatures: liningFigures,
    fontSize: 14,
    color: color,
    height: 1.57,
    fontWeight: fontWeight,
  );

  TextStyle get paragraph13 => TextStyle(
    fontFeatures: liningFigures,
    fontSize: 13,
    color: color,
    height: 1.57,
    fontWeight: fontWeight,
  );

  //12
  TextStyle get metadata12 => TextStyle(
    fontFeatures: liningFigures,
    fontSize: 12,
    color: color,
    height: 19 / 12,
    fontWeight: fontWeight,
  );

  //12
  TextStyle get metadata11 => TextStyle(
    fontFeatures: liningFigures,
    fontSize: 11,
    color: color,
    height: 19 / 12,
    fontWeight: fontWeight,
  );

  //10
  TextStyle get metadata10 => TextStyle(
    fontFeatures: liningFigures,
    fontSize: 10,
    color: color,
    height: 1.6,
    fontWeight: fontWeight,
  );

  //10
  TextStyle get metadata8 => TextStyle(
    fontFeatures: liningFigures,
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
