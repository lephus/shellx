import 'package:flutter/widgets.dart';
import 'package:shellx_mobile/core/settings/app_settings.dart';

/// Two-finger pinch → terminal font size (spec §9.4). Pure logic fed with
/// raw pointer events, so it never competes with the terminal's own scroll
/// and selection gestures.
final class PinchZoomTracker {
  PinchZoomTracker({
    this.min = AppSettings.minFontSize,
    this.max = AppSettings.maxFontSize,
    this.step = 0.5,
  });

  final double min;
  final double max;
  final double step;
  final Map<int, Offset> _pointers = {};
  double? _startDistance;
  double _startSize = 0;
  double _current = 0;

  void down(int pointer, Offset position, double currentSize) {
    _pointers[pointer] = position;
    _current = currentSize;
    _rebaseline();
  }

  /// The new font size, or null when it did not change by a whole [step].
  double? move(int pointer, Offset position) {
    if (!_pointers.containsKey(pointer)) return null;
    _pointers[pointer] = position;
    final start = _startDistance;
    if (start == null || start == 0) return null;
    final raw = _startSize * _distance() / start;
    final size = ((raw / step).round() * step).clamp(min, max).toDouble();
    if (size == _current) return null;
    _current = size;
    return size;
  }

  void up(int pointer) {
    _pointers.remove(pointer);
    _rebaseline();
  }

  void _rebaseline() {
    if (_pointers.length == 2) {
      _startDistance = _distance();
      _startSize = _current;
    } else {
      _startDistance = null;
    }
  }

  double _distance() {
    final points = _pointers.values.toList();
    return (points[0] - points[1]).distance;
  }
}

class PinchToZoom extends StatefulWidget {
  const PinchToZoom({super.key, required this.fontSize, required this.onFontSize, required this.child});

  final double fontSize;
  final ValueChanged<double> onFontSize;
  final Widget child;

  @override
  State<PinchToZoom> createState() => _PinchToZoomState();
}

class _PinchToZoomState extends State<PinchToZoom> {
  final PinchZoomTracker _tracker = PinchZoomTracker();

  @override
  Widget build(BuildContext context) {
    return Listener(
      // Observe pointers without taking them from the terminal's own gestures.
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) => _tracker.down(event.pointer, event.position, widget.fontSize),
      onPointerMove: (event) {
        final size = _tracker.move(event.pointer, event.position);
        if (size != null) widget.onFontSize(size);
      },
      onPointerUp: (event) => _tracker.up(event.pointer),
      onPointerCancel: (event) => _tracker.up(event.pointer),
      child: widget.child,
    );
  }
}
