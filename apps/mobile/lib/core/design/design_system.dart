import 'package:flutter/material.dart';
import 'package:shellx_mobile/core/design/app_colors.dart';
import 'package:shellx_mobile/core/design/typography.dart';

class DesignSystem extends InheritedWidget {
  final AppTypography typography;
  final AppColors appColors;
  final Brightness brightness;

  DesignSystem({
    super.key,
    required super.child,
    required this.appColors,
    required this.typography,
    required this.brightness,
  }) {
    typography.setColor(appColors.primaryText);
  }

  @override
  bool updateShouldNotify(covariant DesignSystem oldWidget) {
    final isChanged = brightness != oldWidget.brightness;
    if (isChanged) {
      typography.setColor(appColors.primaryText);
    }
    return isChanged;
  }

  static DesignSystem of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<DesignSystem>()!;
  }
}

extension DesignSystemContext on BuildContext {
  //
  AppTypography get typo => DesignSystem.of(this).typography;

  AppColors get colors => DesignSystem.of(this).appColors;
}
