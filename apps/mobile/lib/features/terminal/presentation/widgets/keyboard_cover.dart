import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/terminal/domain/cursor_shift.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_tab_controller.dart';
import 'package:xterm/xterm.dart';

/// A11 D31: how far the keyboard carries the bars up. The home indicator's safe area belongs to the bars
/// already, so only what is above it counts.
double keyboardLift(MediaQueryData media) => math.max(0.0, media.viewInsets.bottom - media.viewPadding.bottom);

/// The bars under the terminal (voice composer, extra keys) while the page keeps its size under the
/// keyboard ([Scaffold.resizeToAvoidBottomInset] false): they are laid out where they always are, so the
/// terminal above them keeps its size, and drawn, and hit-tested, [keyboardLift] higher, right above the
/// keyboard. Their safe-area padding stays that of the closed keyboard for the same reason.
class KeyboardAnchored extends StatelessWidget {
  const KeyboardAnchored({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(padding: media.padding.copyWith(bottom: media.viewPadding.bottom)),
      child: _Lifted(lift: keyboardLift(media), child: child),
    );
  }
}

class _Lifted extends SingleChildRenderObjectWidget {
  const _Lifted({required this.lift, required super.child});

  final double lift;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderLifted(lift);

  @override
  void updateRenderObject(BuildContext context, _RenderLifted renderObject) => renderObject.lift = lift;
}

/// Lays out its child as it is and draws it [lift] higher. A `Transform` would hit-test only inside the box
/// it was laid out in, so the lifted bars could not be tapped.
class _RenderLifted extends RenderProxyBox {
  _RenderLifted(this._lift);

  double _lift;

  set lift(double value) {
    if (value == _lift) return;
    _lift = value;
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child != null) context.paintChild(child, offset.translate(0, -_lift));
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.translateByDouble(0, -_lift, 0, 1);
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null || !size.contains(position.translate(0, _lift))) return false;
    final hit = result.addWithPaintOffset(
      offset: Offset(0, -_lift),
      position: position,
      hitTest: (result, transformed) => child.hitTest(result, position: transformed),
    );
    if (hit) result.add(BoxHitTestEntry(this, position));
    return hit;
  }
}

/// The terminal area while the keyboard covers its bottom (A11 D31): moved up by [cursorShift], so the row of
/// the cursor stays visible, without the terminal changing size. Clipped to the area, so rows pushed out of
/// the top do not draw over the bars above it.
class CursorShiftArea extends StatefulWidget {
  const CursorShiftArea({
    super.key,
    required this.tab,
    required this.cellHeight,
    required this.topPadding,
    required this.height,
    required this.child,
  });

  final TerminalTabController tab;

  /// One row of the terminal, and the padding above the first row.
  final double cellHeight;
  final double topPadding;

  /// The area's height.
  final double height;
  final Widget child;

  @override
  State<CursorShiftArea> createState() => _CursorShiftAreaState();
}

class _CursorShiftAreaState extends State<CursorShiftArea> {
  Terminal? _terminal;
  late void Function() _stopTerminal;
  int _cursorRow = 0;
  bool _covered = false;

  @override
  void initState() {
    super.initState();
    // `session.reset` swaps the terminal: follow the new one.
    _stopTerminal = widget.tab.terminal.subscribe(_follow);
    widget.tab.scroll.addListener(_onScroll);
  }

  void _follow(Terminal terminal) {
    _terminal?.removeListener(_onTerminal);
    _terminal = terminal..addListener(_onTerminal);
    _cursorRow = terminal.buffer.cursorY;
  }

  void _onTerminal() {
    final row = _terminal?.buffer.cursorY ?? 0;
    if (row == _cursorRow) return;
    _cursorRow = row;
    // Only worth a frame while the keyboard covers something.
    if (_covered && mounted) setState(() {});
  }

  @override
  void didUpdateWidget(CursorShiftArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.tab, widget.tab)) return;
    // Another tab in front: follow its terminal and its scroll, not the old one's.
    _stopTerminal();
    oldWidget.tab.scroll.removeListener(_onScroll);
    _terminal?.removeListener(_onTerminal);
    _terminal = null;
    _cursorRow = 0;
    _stopTerminal = widget.tab.terminal.subscribe(_follow);
    widget.tab.scroll.addListener(_onScroll);
  }

  void _onScroll() {
    if (_covered && mounted) setState(() {});
  }

  /// Scrolled up in the history, the cursor is not on screen: nothing to keep in view.
  bool get _atBottom {
    final scroll = widget.tab.scroll;
    if (!scroll.hasClients) return true;
    final position = scroll.position;
    return position.pixels >= position.maxScrollExtent - 1;
  }

  @override
  void dispose() {
    _stopTerminal();
    widget.tab.scroll.removeListener(_onScroll);
    _terminal?.removeListener(_onTerminal);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final lift = keyboardLift(media);
    _covered = lift > 0;
    final shift = lift <= 0 || !_atBottom
        ? 0.0
        : cursorShift(
            cursorBottom: widget.topPadding + (_cursorRow + 1) * widget.cellHeight,
            viewportHeight: widget.height,
            keyboardInset: lift,
          );
    return ClipRect(
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: shift),
        duration: media.disableAnimations ? Duration.zero : const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        builder: (context, value, child) => Transform.translate(
          key: const Key('terminal.shift'),
          offset: Offset(0, -value),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}
