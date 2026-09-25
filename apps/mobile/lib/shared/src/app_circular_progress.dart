import 'package:flutter/material.dart';
import 'package:shellx_mobile/core/design/design_system.dart';

class AppCircularProgress extends StatelessWidget {
  final double strokeWidth;
  final double? value;
  final Color? color;
  final Color? valueColor;
  final double? size;

  const AppCircularProgress({
    super.key,
    this.strokeWidth = 4.0,
    this.value,
    this.color,
    this.valueColor,
    this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: size,
        height: size,
        child: FittedBox(
          child: CircularProgressIndicator.adaptive(
            value: value,
            strokeWidth: strokeWidth,
            strokeCap: StrokeCap.round,
            valueColor: AlwaysStoppedAnimation<Color>(
              valueColor ?? context.colors.primary,
            ),
          ),
        ),
      ),
    );
  }
}
