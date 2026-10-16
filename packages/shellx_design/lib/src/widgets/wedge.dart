import 'package:flutter/widgets.dart';

import '../gradients.dart';

/// The corner a [ShellxWedge] sits in.
enum ShellxWedgeCorner { topLeft, topRight, bottomLeft, bottomRight }

/// V2-5a A30: the diagonal blue wedge of the reference, a right triangle in
/// a corner ([widthFactor] of the width along the edge, [heightFactor] of
/// the height down the side), filled with [ShellxGradients.wedge]. Only on
/// empty states, the splash, sign-in and onboarding (and V2-5b/C's places);
/// never behind the terminal, a web view or long text, and only bold white
/// text from 15 px may sit on it. Not hit-testable, no semantics, its own
/// layer.
class ShellxWedge extends StatelessWidget {
  const ShellxWedge({
    super.key,
    this.corner = ShellxWedgeCorner.topRight,
    this.widthFactor = 0.45,
    this.heightFactor = 0.7,
  });

  final ShellxWedgeCorner corner;
  final double widthFactor;
  final double heightFactor;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: ShellxWedgePainter(
            corner: corner,
            widthFactor: widthFactor,
            heightFactor: heightFactor,
          ),
        ),
      ),
    ),
  );
}

/// What [ShellxWedge] paints.
class ShellxWedgePainter extends CustomPainter {
  const ShellxWedgePainter({
    required this.corner,
    required this.widthFactor,
    required this.heightFactor,
  });

  final ShellxWedgeCorner corner;
  final double widthFactor;
  final double heightFactor;

  /// The triangle in [size]: the corner itself, a point along the top or
  /// bottom edge and a point down or up the side.
  List<Offset> points(Size size) {
    final w = size.width * widthFactor;
    final h = size.height * heightFactor;
    final right = size.width;
    final bottom = size.height;
    return switch (corner) {
      ShellxWedgeCorner.topRight => [
        Offset(right - w, 0),
        Offset(right, 0),
        Offset(right, h),
      ],
      ShellxWedgeCorner.topLeft => [Offset(w, 0), Offset.zero, Offset(0, h)],
      ShellxWedgeCorner.bottomRight => [
        Offset(right - w, bottom),
        Offset(right, bottom),
        Offset(right, bottom - h),
      ],
      ShellxWedgeCorner.bottomLeft => [
        Offset(w, bottom),
        Offset(0, bottom),
        Offset(0, bottom - h),
      ],
    };
  }

  @override
  void paint(Canvas canvas, Size size) {
    final p = points(size);
    final bounds = Rect.fromPoints(
      p[0],
      p[2],
    ).expandToInclude(Rect.fromPoints(p[1], p[1]));
    final path = Path()..addPolygon(p, true);
    canvas.drawPath(
      path,
      Paint()..shader = ShellxGradients.wedge.createShader(bounds),
    );
  }

  @override
  bool shouldRepaint(ShellxWedgePainter old) =>
      old.corner != corner ||
      old.widthFactor != widthFactor ||
      old.heightFactor != heightFactor;
}
