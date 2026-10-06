import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../terminal/terminal_tabs.dart';
import '../theme/shellx_desktop_theme.dart';
import 'session_tab_row.dart';

// UI-A2 §6: the pieces of a sidebar row drag (the sidebar owns the state).

/// UI-A2 §6 drop line: 2 px `accent`, radius 1, as wide as the row.
class SidebarDropLine extends StatelessWidget {
  const SidebarDropLine({super.key});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      key: const Key('drop.line'),
      height: ShellxSizes.dropLine,
      decoration: BoxDecoration(
        color: ShellxDesktopColors.accent,
        borderRadius: BorderRadius.circular(ShellxSizes.dropLine / 2),
      ),
    ),
  );
}

/// UI-A2 §6: a row starts dragging once the pointer moved more than 4 px
/// with the left button held, so a click with a slight jitter still
/// selects (Flutter's mouse slop is 1 px).
class SidebarRowDraggable extends Draggable<int> {
  const SidebarRowDraggable({
    super.key,
    required super.data,
    required super.feedback,
    required super.child,
    super.childWhenDragging,
    super.dragAnchorStrategy,
    super.onDragStarted,
    super.onDragEnd,
    super.onDraggableCanceled,
    super.maxSimultaneousDrags,
  });

  @override
  MultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) => _RowDragRecognizer()..onStart = onStart;
}

class _RowDragRecognizer extends MultiDragGestureRecognizer {
  _RowDragRecognizer() : super(debugOwner: null);

  @override
  MultiDragPointerState createNewPointerState(PointerDownEvent event) =>
      _RowDragPointerState(event.position, event.kind, gestureSettings);

  @override
  String get debugDescription => 'sidebar row drag';
}

class _RowDragPointerState extends MultiDragPointerState {
  _RowDragPointerState(
    super.initialPosition,
    super.kind,
    super.gestureSettings,
  );

  static const double _slop = 4;

  @override
  void checkForResolutionAfterMove() {
    if (pendingDelta!.distance > _slop) {
      resolve(GestureDisposition.accepted);
    }
  }

  @override
  void accepted(GestureMultiDragStartCallback starter) =>
      starter(initialPosition);
}

/// Where the drag chip goes (V1), all in global coordinates: the pointer,
/// the list it must stay inside, and what it must not cover (the drop
/// line, or the header or empty group under the pointer).
@immutable
final class DragGhostPlacement {
  const DragGhostPlacement({
    required this.pointer,
    required this.bounds,
    this.avoid,
  });
  final Offset pointer;
  final Rect bounds;
  final Rect? avoid;
}

/// V1: the chip's top-left: [ShellxSizes.dragGhostOffsetX]/`Y` right of and
/// below the pointer, kept inside the list; moved below what it would
/// cover (or above it when below leaves the list).
Offset dragGhostTopLeft(DragGhostPlacement p, Size chip) {
  final margin = ShellxSizes.listMarginH;
  final minX = p.bounds.left + margin;
  final maxX = max(minX, p.bounds.right - margin - chip.width);
  final x = (p.pointer.dx + ShellxSizes.dragGhostOffsetX).clamp(minX, maxX);
  var y = p.pointer.dy + ShellxSizes.dragGhostOffsetY;
  final avoid = p.avoid;
  if (avoid != null && (Offset(x, y) & chip).overlaps(avoid)) {
    y = avoid.bottom + ShellxSizes.dragGhostClearance;
    if (y + chip.height > p.bounds.bottom) {
      y = avoid.top - ShellxSizes.dragGhostClearance - chip.height;
    }
  }
  // Never outside the list, vertically either.
  final maxY = max(p.bounds.top, p.bounds.bottom - chip.height);
  return Offset(x, y.clamp(p.bounds.top, maxY));
}

/// UI-A2 §6 (V1) drag feedback: a compact chip — the status dot and the
/// title on one 30 px line, at most 208 wide — opaque on `rowSelected`
/// with a 1 px `border`, `r6` and `e1`. It hangs off the pointer (the
/// draggable anchors its origin there) at [dragGhostTopLeft], so it never
/// hides the drop line or the target, and never leaves the list.
class SidebarDragFeedback extends StatelessWidget {
  const SidebarDragFeedback({
    super.key,
    required this.tab,
    required this.placement,
  });
  final TerminalTab tab;
  final ValueListenable<DragGhostPlacement> placement;

  /// The chip's size for [tab]'s title at [scaler].
  static Size sizeFor(
    TerminalTab tab,
    TextScaler scaler,
    TextStyle style,
    TextDirection direction,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: tab.label, style: style),
      textDirection: direction,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final title = painter.width;
    painter.dispose();
    final width = min(
      ShellxSizes.dragGhostMaxWidth,
      ShellxSpace.s8 +
          ShellxSizes.dotSlot +
          ShellxSpace.s8 +
          title +
          ShellxSpace.s8 +
          2, // the 1 px border on both sides
    );
    return Size(width, SessionTabRow.heightFor(scaler));
  }

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final style = DefaultTextStyle.of(context).style.merge(
      ShellxText.body.copyWith(color: ShellxDesktopColors.textPrimary),
    );
    final size = sizeFor(tab, scaler, style, Directionality.of(context));
    final chip = Container(
      key: const Key('drag.ghost'),
      width: size.width,
      height: size.height,
      padding: const EdgeInsets.symmetric(horizontal: ShellxSpace.s8),
      decoration: BoxDecoration(
        color: ShellxDesktopColors.rowSelected,
        borderRadius: BorderRadius.circular(ShellxRadius.r6),
        border: Border.all(color: ShellxDesktopColors.border),
        boxShadow: ShellxShadows.e1,
      ),
      child: Row(
        children: [
          SizedBox(
            width: ShellxSizes.dotSlot,
            child: Center(child: TabStatusDot(tab)),
          ),
          const SizedBox(width: ShellxSpace.s8),
          Flexible(
            child: Text(
              tab.label,
              style: style,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
    return ExcludeSemantics(
      child: IgnorePointer(
        child: Material(
          type: MaterialType.transparency,
          // The feedback's origin is the pointer; the chip is drawn off it.
          child: SizedBox.shrink(
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: 0,
              minHeight: 0,
              maxWidth: double.infinity,
              maxHeight: double.infinity,
              child: ValueListenableBuilder<DragGhostPlacement>(
                valueListenable: placement,
                builder: (context, p, child) => Transform.translate(
                  offset: dragGhostTopLeft(p, size) - p.pointer,
                  child: child,
                ),
                child: chip,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
