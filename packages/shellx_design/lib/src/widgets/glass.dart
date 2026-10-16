import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../gradients.dart';
import '../palette.dart';
import '../radii.dart';

/// V2-5a A29: frosted glass — [ShellxPalette.glassFill] (light: white 80 %)
/// with a 1 px gradient border. [blur] (σ 16) only where what is behind
/// stays still (the wedge, the page); over content that moves (a list, the
/// AI transcript) it is false. Only `textPrimary` or brighter text sits on
/// it. The app's only [BackdropFilter].
class ShellxGlass extends StatelessWidget {
  const ShellxGlass({
    super.key,
    required this.child,
    this.blur = true,
    this.borderRadius = const BorderRadius.all(
      Radius.circular(ShellxRadii.card),
    ),
    this.padding,
  });

  final Widget child;
  final bool blur;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;

  /// σ of [blur].
  static const double sigma = 16;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final panel = CustomPaint(
      foregroundPainter: ShellxGradientBorderPainter(
        gradient: dark
            ? ShellxGradients.glassBorderDark
            : ShellxGradients.glassBorderLight,
        borderRadius: borderRadius,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: dark ? ShellxPalette.glassFill : ShellxLightPalette.glassFill,
          borderRadius: borderRadius,
        ),
        child: padding == null
            ? child
            : Padding(padding: padding!, child: child),
      ),
    );
    if (!blur) return panel;
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: panel,
      ),
    );
  }
}

/// A 1 px border of [gradient] around a rounded rectangle.
class ShellxGradientBorderPainter extends CustomPainter {
  const ShellxGradientBorderPainter({
    required this.gradient,
    required this.borderRadius,
    this.width = 1,
  });

  final Gradient gradient;
  final BorderRadius borderRadius;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRRect(
      borderRadius.toRRect(rect).deflate(width / 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..shader = gradient.createShader(rect),
    );
  }

  @override
  bool shouldRepaint(ShellxGradientBorderPainter old) =>
      old.gradient != gradient ||
      old.borderRadius != borderRadius ||
      old.width != width;
}
