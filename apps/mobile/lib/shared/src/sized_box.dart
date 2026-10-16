import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

extension SizedBoxInt on int {
  SizedBox get sizedHeight => SizedBox(height: toDouble());
  SizedBox get sizedWidth => SizedBox(width: toDouble());
}

extension SizedBoxDouble on double {
  SizedBox get sizedHeight => SizedBox(height: this);
  SizedBox get sizedWidth => SizedBox(width: this);
}

extension WidgetExt on Widget {
  //
  SliverToBoxAdapter get sliver => SliverToBoxAdapter(child: this);
  Flexible get flexible => Flexible(child: this);
  Expanded get expanded => Expanded(child: this);
  Center get center => Center(child: this);

  Positioned positioned({
    double? top,
    double? bottom,
    double? left,
    double? right,
  }) =>
      Positioned(
        top: top,
        bottom: bottom,
        left: left,
        right: right,
        child: Center(child: this),
      );
}

extension GradientExt on Gradient {
  Gradient opacity(double opacity) {
    return LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: colors.map((color) => color.withValues(alpha: opacity * 255)).toList(growable: false),
      stops: stops,
    );
  }
}
