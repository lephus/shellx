import 'package:flutter/material.dart';
import 'package:shellx_mobile/core/design/light_colors.dart';

/// Dark `--a-*` tokens of the ShellX design (the base only had a placeholder here).
class DarkColors extends LightColors {
  DarkColors() {
    // `primary` and `background` are fields of LightColors (they have setters).
    primary = const Color(0xFF2DBFCF);
    background = const Color(0xFF0D1315);
  }

  @override
  Color get primaryText => const Color(0xFFE8EFF1);

  @override
  Color get secondaryText => const Color(0xFFA7B6BA);

  @override
  Color get disable => const Color(0xFF6F8186);

  @override
  Color get border => const Color(0xFF2B373A);

  @override
  Color get divider => const Color(0xFF1F292C);

  @override
  Color get surface => const Color(0xFF172023);

  @override
  Color get error => const Color(0xFFF26A70);

  @override
  Color get mainRed => const Color(0xFFF26A70);

  @override
  Color get lightRed => const Color(0xFF3B1719);

  @override
  Color get mainGreen => const Color(0xFF7CC45E);

  @override
  Color get lightGold => const Color(0xFF33250F);

  @override
  Color get black => Colors.black;

  @override
  Color get onPrimary => const Color(0xFF04282D);

  @override
  Color get primarySoft => const Color(0xFF0E363C);

  @override
  Color get ok => const Color(0xFF7CC45E);

  @override
  Color get okDot => const Color(0xFF6BCB4E);

  @override
  Color get warn => const Color(0xFFF0A94A);

  @override
  Color get warnSoft => const Color(0xFF33250F);

  @override
  Color get errorSoft => const Color(0xFF3B1719);

  @override
  Color get scrim => const Color(0x99000000);

  @override
  Color get keyboardBackground => const Color(0xFF1E1F21);

  @override
  Color get keyboardKey => const Color(0xFF47484B);

  @override
  Color get keyboardInk => const Color(0xFFFFFFFF);
}
