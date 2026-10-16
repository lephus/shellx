import 'package:flutter/widgets.dart';

import '../elevation.dart';

/// V2-5a A28: an inset ("pressed in") box. [BoxShadow] has no inset, so the
/// inner [shadow] is painted inside the shape: fields on the phone, the
/// segmented track, the slider track. Its own layer ([RepaintBoundary]),
/// repainted only when its size or look changes.
class ShellxInsetBox extends StatelessWidget {
  const ShellxInsetBox({
    super.key,
    required this.color,
    required this.shadow,
    required this.borderRadius,
    this.border,
    this.padding,
    this.child,
  });

  final Color color;
  final ShellxInsetShadow shadow;
  final BorderRadius borderRadius;

  /// Drawn over the shadow (a field's outline).
  final BorderSide? border;
  final EdgeInsetsGeometry? padding;
  final Widget? child;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: ShellxInsetPainter(
        color: color,
        shadow: shadow,
        borderRadius: borderRadius,
        border: border,
      ),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    ),
  );
}

/// What [ShellxInsetBox] paints: the fill, each inner shadow, the border.
class ShellxInsetPainter extends CustomPainter {
  const ShellxInsetPainter({
    required this.color,
    required this.shadow,
    required this.borderRadius,
    this.border,
  });

  final Color color;
  final ShellxInsetShadow shadow;
  final BorderRadius borderRadius;
  final BorderSide? border;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = borderRadius.toRRect(rect);
    canvas.drawRRect(shape, Paint()..color = color);
    canvas.save();
    canvas.clipRRect(shape);
    for (final s in shadow.shadows) {
      // Everything outside the shape, moved by the offset and blurred: what
      // falls back inside is the inner shadow.
      final outside = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(rect.inflate(s.blurRadius * 2 + s.offset.distance + 1))
        ..addRRect(shape.shift(s.offset));
      canvas.drawPath(
        outside,
        Paint()
          ..color = s.color
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s.blurSigma),
      );
    }
    canvas.restore();
    final side = border;
    if (side != null && side.style != BorderStyle.none && side.width > 0) {
      canvas.drawRRect(shape.deflate(side.width / 2), side.toPaint());
    }
  }

  @override
  bool shouldRepaint(ShellxInsetPainter old) =>
      old.color != color ||
      old.shadow != shadow ||
      old.borderRadius != borderRadius ||
      old.border != border;
}
