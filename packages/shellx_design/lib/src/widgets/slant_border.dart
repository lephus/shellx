import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// V2-5a §7.1: the phone bottom bar's active tile — a rounded rectangle
/// whose top edge rises [slant] px from left to right, as in the
/// reference.
class ShellxSlantBorder extends OutlinedBorder {
  const ShellxSlantBorder({super.side, this.radius = 10, this.slant = 4});

  final double radius;
  final double slant;

  /// The corners, clockwise from the top left; the top edge slopes.
  List<Offset> corners(Rect rect) => [
    Offset(rect.left, rect.top + slant),
    rect.topRight,
    rect.bottomRight,
    rect.bottomLeft,
  ];

  Path _path(Rect rect) {
    final points = corners(rect);
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final previous = points[(i + points.length - 1) % points.length];
      final corner = points[i];
      final next = points[(i + 1) % points.length];
      final r = math.min(
        radius,
        math.min((corner - previous).distance, (next - corner).distance) / 2,
      );
      final from = corner + _unit(previous - corner) * r;
      final to = corner + _unit(next - corner) * r;
      if (i == 0) {
        path.moveTo(from.dx, from.dy);
      } else {
        path.lineTo(from.dx, from.dy);
      }
      path.quadraticBezierTo(corner.dx, corner.dy, to.dx, to.dy);
    }
    return path..close();
  }

  static Offset _unit(Offset o) => o.distance == 0 ? o : o / o.distance;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _path(rect.deflate(side.width));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => _path(rect);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width == 0) return;
    canvas.drawPath(_path(rect.deflate(side.width / 2)), side.toPaint());
  }

  @override
  ShellxSlantBorder scale(double t) => ShellxSlantBorder(
    side: side.scale(t),
    radius: radius * t,
    slant: slant * t,
  );

  @override
  ShellxSlantBorder copyWith({BorderSide? side}) =>
      ShellxSlantBorder(side: side ?? this.side, radius: radius, slant: slant);

  @override
  bool operator ==(Object other) =>
      other is ShellxSlantBorder &&
      other.side == side &&
      other.radius == radius &&
      other.slant == slant;

  @override
  int get hashCode => Object.hash(side, radius, slant);
}
