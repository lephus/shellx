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

/// UI-A2 §6 drag feedback: a copy of the row, 208 wide, on `rowSelected`
/// with a 1 px `border`, `r6` and `e1`, at 92 %.
class SidebarDragFeedback extends StatelessWidget {
  const SidebarDragFeedback({super.key, required this.tab, required this.home});
  final TerminalTab tab;
  final String home;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IgnorePointer(
      child: Material(
        type: MaterialType.transparency,
        child: Opacity(
          opacity: 0.92,
          child: Container(
            width: ShellxSizes.sidebarWidth - 2 * ShellxSizes.listMarginH,
            decoration: BoxDecoration(
              color: ShellxDesktopColors.rowSelected,
              borderRadius: BorderRadius.circular(ShellxRadius.r6),
              boxShadow: ShellxShadows.e1,
            ),
            foregroundDecoration: BoxDecoration(
              border: Border.all(color: ShellxDesktopColors.border),
              borderRadius: BorderRadius.circular(ShellxRadius.r6),
            ),
            child: SessionTabRow(
              tab: tab,
              selected: false,
              position: 1,
              count: 1,
              home: home,
              onSelect: () {},
              onClose: () {},
            ),
          ),
        ),
      ),
    ),
  );
}
