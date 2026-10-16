import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/shellx_desktop_theme.dart' show ShellxSizes;

/// The thinnest crisp line at [devicePixelRatio], in device pixels: one
/// pixel below 2×, two at 2× (final ruling S-2). A 1 logical px line at
/// 1.25× would cover 1.25 device pixels and smear over two.
int hairlineDevicePixels(double devicePixelRatio) =>
    math.max(1, devicePixelRatio.floor());

/// UI-A3 §2.1 focus outline (final ruling S-2): a hairline border drawn
/// inside this box, with every edge snapped to a whole device pixel of the
/// window (not of the pane area, whose origin may sit between pixels), so
/// it stays one solid accent line at any scale. Paint only.
class DevicePixelOutline extends LeafRenderObjectWidget {
  const DevicePixelOutline({
    super.key,
    required this.color,
    required this.devicePixelRatio,
  });

  final Color color;
  final double devicePixelRatio;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderDevicePixelOutline(color, devicePixelRatio);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderDevicePixelOutline renderObject,
  ) => renderObject
    ..color = color
    ..devicePixelRatio = devicePixelRatio;
}

/// UI-A3 §2.2 divider line (final rulings S-1, S-2): a band of
/// [devicePixels] across, centred on the 1 px layout line that runs through
/// the middle of this box (the divider's hit area), snapped to whole device
/// pixels. [vertical]: a line between panes side by side.
class DevicePixelLine extends LeafRenderObjectWidget {
  const DevicePixelLine({
    super.key,
    required this.vertical,
    required this.color,
    required this.devicePixels,
    required this.devicePixelRatio,
  });

  final bool vertical;
  final Color color;
  final int devicePixels;
  final double devicePixelRatio;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderDevicePixelLine(vertical, color, devicePixels, devicePixelRatio);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderDevicePixelLine renderObject,
  ) => renderObject
    ..vertical = vertical
    ..color = color
    ..devicePixels = devicePixels
    ..devicePixelRatio = devicePixelRatio;
}

/// Fills the whole box; paints in window device pixels.
abstract class _RenderDevicePixelBox extends RenderBox {
  _RenderDevicePixelBox(this._color, this._devicePixelRatio);

  Color _color;
  set color(Color value) {
    if (value == _color) return;
    _color = value;
    markNeedsPaint();
  }

  double _devicePixelRatio;
  double get devicePixelRatio => _devicePixelRatio > 0 ? _devicePixelRatio : 1;
  set devicePixelRatio(double value) {
    if (value == _devicePixelRatio) return;
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  bool hitTestSelf(Offset position) => false;

  double snap(double logical) =>
      (logical * devicePixelRatio).roundToDouble() / devicePixelRatio;

  /// [global] rectangles (window logical px, already snapped) drawn at
  /// [offset], the paint origin of this box.
  void fill(PaintingContext context, Offset offset, List<Rect> global) {
    final origin = localToGlobal(Offset.zero);
    final paint = Paint()..color = _color;
    for (final r in global) {
      if (r.isEmpty) continue;
      context.canvas.drawRect(r.shift(offset - origin), paint);
    }
  }
}

class RenderDevicePixelOutline extends _RenderDevicePixelBox {
  RenderDevicePixelOutline(super.color, super.devicePixelRatio);

  @override
  void paint(PaintingContext context, Offset offset) {
    final b = localToGlobal(Offset.zero) & size;
    final r = Rect.fromLTRB(
      snap(b.left),
      snap(b.top),
      snap(b.right),
      snap(b.bottom),
    );
    final w = hairlineDevicePixels(devicePixelRatio) / devicePixelRatio;
    fill(context, offset, [
      Rect.fromLTRB(r.left, r.top, r.right, r.top + w),
      Rect.fromLTRB(r.left, r.bottom - w, r.right, r.bottom),
      Rect.fromLTRB(r.left, r.top + w, r.left + w, r.bottom - w),
      Rect.fromLTRB(r.right - w, r.top + w, r.right, r.bottom - w),
    ]);
  }
}

class RenderDevicePixelLine extends _RenderDevicePixelBox {
  RenderDevicePixelLine(
    this._vertical,
    super.color,
    this._devicePixels,
    super.devicePixelRatio,
  );

  bool _vertical;
  set vertical(bool value) {
    if (value == _vertical) return;
    _vertical = value;
    markNeedsPaint();
  }

  int _devicePixels;
  set devicePixels(int value) {
    if (value == _devicePixels) return;
    _devicePixels = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final dpr = devicePixelRatio;
    final b = localToGlobal(Offset.zero) & size;
    // Where the 1 px layout line starts, on a device pixel; the band grows
    // evenly around a hairline from there.
    final centre = _vertical ? b.center.dx : b.center.dy;
    final hairline = hairlineDevicePixels(dpr);
    final start =
        ((centre - ShellxSizes.paneDivider / 2) * dpr).roundToDouble() -
        ((_devicePixels - hairline) / 2).floorToDouble();
    final (from, to) = (start / dpr, (start + _devicePixels) / dpr);
    fill(context, offset, [
      _vertical
          ? Rect.fromLTRB(from, snap(b.top), to, snap(b.bottom))
          : Rect.fromLTRB(snap(b.left), from, snap(b.right), to),
    ]);
  }
}
