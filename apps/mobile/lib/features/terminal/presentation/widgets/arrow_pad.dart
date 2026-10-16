import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/extra_keys_controller.dart';
import 'package:shellx_mobile/shared/shared.dart';

enum PadDirection { up, down, left, right }

/// A11 D30: which way a drag of [delta] from where the finger went down points; null while the finger is
/// within [threshold] dp of the start. The dominant axis wins, a tie goes to the horizontal one.
///
/// With a [current] direction (the finger is already steering) the answer settles: the arrow is kept
/// until the finger comes back within [release] dp (a dead band under [threshold]), and the other axis
/// takes over only when it passes [threshold] and leads by [switchMargin] dp, so a diagonal or a shaky
/// finger keeps the arrow it has.
PadDirection? padDirection(
  Offset delta, {
  double threshold = 14,
  PadDirection? current,
  double release = 10,
  double switchMargin = 6,
}) {
  if (current != null) {
    final horizontal = current == PadDirection.left || current == PadDirection.right;
    final along = switch (current) {
      PadDirection.right => delta.dx,
      PadDirection.left => -delta.dx,
      PadDirection.down => delta.dy,
      PadDirection.up => -delta.dy,
    };
    if (along >= release) {
      final across = horizontal ? delta.dy : delta.dx;
      if (across.abs() >= threshold && across.abs() >= along + switchMargin) {
        return horizontal
            ? (across > 0 ? PadDirection.down : PadDirection.up)
            : (across > 0 ? PadDirection.right : PadDirection.left);
      }
      return current;
    }
  }
  final dx = delta.dx.abs();
  final dy = delta.dy.abs();
  if (dx < threshold && dy < threshold) return null;
  if (dx >= dy) return delta.dx > 0 ? PadDirection.right : PadDirection.left;
  return delta.dy > 0 ? PadDirection.down : PadDirection.up;
}

/// How often the arrow repeats at [distance] dp from the start: 4, 10 then 20 keys a second; null below 14 dp.
Duration? padInterval(double distance) {
  if (distance < 14) return null;
  if (distance < 28) return const Duration(milliseconds: 250);
  if (distance < 56) return const Duration(milliseconds: 100);
  return const Duration(milliseconds: 50);
}

ExtraKey _toKey(PadDirection direction) => switch (direction) {
  PadDirection.up => ExtraKey.up,
  PadDirection.down => ExtraKey.down,
  PadDirection.left => ExtraKey.left,
  PadDirection.right => ExtraKey.right,
};

/// Takes the pointer the moment it goes down, so the extra keys row does not scroll while the pad is
/// dragged; reports where it went down, where it moves and when it ends. One finger at a time.
class _PadRecognizer extends OneSequenceGestureRecognizer {
  void Function(Offset position)? onStart;
  void Function(Offset position)? onMove;
  VoidCallback? onEnd;
  int? _pointer;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (_pointer != null) return;
    _pointer = event.pointer;
    startTrackingPointer(event.pointer, event.transform);
    resolve(GestureDisposition.accepted);
    onStart?.call(event.position);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event.pointer != _pointer) return;
    if (event is PointerMoveEvent) {
      onMove?.call(event.position);
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _end();
    }
  }

  void _end() {
    final pointer = _pointer;
    if (pointer == null) return;
    _pointer = null;
    stopTrackingPointer(pointer);
    onEnd?.call();
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  void dispose() {
    _pointer = null;
    super.dispose();
  }

  @override
  String get debugDescription => 'arrow pad';
}

/// The pad key of the extra keys row (A11 D30): drag a finger from it in a direction to send that arrow, then
/// hold to repeat it, faster the further the finger is from where it started. A tap sends nothing. Screen
/// readers get one custom action per direction.
class ArrowPadKey extends StatefulWidget {
  const ArrowPadKey({super.key, required this.onKey});

  final ValueChanged<ExtraKey> onKey;

  @override
  State<ArrowPadKey> createState() => _ArrowPadKeyState();
}

class _ArrowPadKeyState extends State<ArrowPadKey> with WidgetsBindingObserver {
  Offset _origin = Offset.zero;
  Timer? _timer;
  PadDirection? _direction;
  Duration? _interval;

  void _stop() {
    _timer?.cancel();
    _timer = null;
    _direction = null;
    _interval = null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  /// A call, the lock screen or the app switcher: nothing keeps repeating behind the user's back.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _stop();
  }

  void _move(Offset position) {
    final delta = position - _origin;
    final direction = padDirection(delta, current: _direction);
    if (direction == null) {
      _stop();
      return;
    }
    // Held in the dead band the arrow repeats at the slowest rate; near a speed step the current rate stays.
    final distance = delta.distance;
    var interval = padInterval(distance) ?? const Duration(milliseconds: 250);
    if (_interval != null && interval != _interval && padInterval(distance - 3) != padInterval(distance + 3)) {
      interval = _interval!;
    }
    if (direction == _direction && interval == _interval) return;
    final changed = direction != _direction;
    _timer?.cancel();
    _direction = direction;
    _interval = interval;
    if (changed) widget.onKey(_toKey(direction));
    _timer = Timer.periodic(interval, (_) => widget.onKey(_toKey(direction)));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final s = S.of(context);
    return Semantics(
      label: s.arrowPadLabel,
      customSemanticsActions: {
        CustomSemanticsAction(label: s.arrowPadUp): () => widget.onKey(ExtraKey.up),
        CustomSemanticsAction(label: s.arrowPadDown): () => widget.onKey(ExtraKey.down),
        CustomSemanticsAction(label: s.arrowPadLeft): () => widget.onKey(ExtraKey.left),
        CustomSemanticsAction(label: s.arrowPadRight): () => widget.onKey(ExtraKey.right),
      },
      child: ExcludeSemantics(
        child: RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: {
            _PadRecognizer: GestureRecognizerFactoryWithHandlers<_PadRecognizer>(
              _PadRecognizer.new,
              (recognizer) => recognizer
                ..onStart = ((position) {
                  _origin = position;
                  _stop();
                })
                ..onMove = _move
                ..onEnd = _stop,
            ),
          },
          // Like the other caps: the whole bar height is the touch target, the cap itself is 38 pt tall.
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
            child: Container(
              constraints: const BoxConstraints(minWidth: 46),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.keyboardKey,
                borderRadius: BorderRadius.circular(9),
                boxShadow: const [BoxShadow(color: Color(0x47000000), offset: Offset(0, 1))],
              ),
              child: Text(
                '✥',
                style: TextStyle(
                  fontFamily: FontFamily.jetBrainsMono,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colors.keyboardInk,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
