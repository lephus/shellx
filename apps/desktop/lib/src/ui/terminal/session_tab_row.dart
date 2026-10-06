import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';

import '../../../l10n/app_localizations.dart';
import '../../terminal/terminal_tabs.dart';
import '../theme/shellx_desktop_theme.dart';
import 'shellx_menu.dart';
import 'shortcut_labels.dart';
import 'terminal_overlays.dart';

/// UI §3.1 context menu ("Đóng tab  ⌘W") at [at] (global). Secondary
/// click, Shift+F10 and the Menu key open it.
Future<void> showTabContextMenu({
  required BuildContext context,
  required Offset at,
  required VoidCallback onClose,
}) async {
  final l10n = AppLocalizations.of(context);
  final choice = await showShellxMenu<_TabMenuChoice>(
    context: context,
    at: at,
    entries: [
      ShellxMenuEntry(
        key: const Key('menu.closeTab'),
        value: _TabMenuChoice.close,
        label: l10n.terminalCloseTab,
        shortcut: closeTabShortcutLabel(),
      ),
    ],
  );
  if (choice == _TabMenuChoice.close) onClose();
}

enum _TabMenuChoice { close }

/// One sidebar row (UI §2.2 anatomy, §3.1 states, §3.7 semantics).
class SessionTabRow extends StatefulWidget {
  const SessionTabRow({
    super.key,
    required this.tab,
    required this.selected,
    required this.position,
    required this.count,
    required this.onSelect,
    required this.onClose,
    this.focused = false,
  });

  final TerminalTab tab;
  final bool selected;

  /// 1-based place in the list, for the "tab 2 of 4" semantics.
  final int position;
  final int count;
  final VoidCallback onSelect;
  final VoidCallback onClose;

  /// The list has keyboard focus and this is its current row: draw the
  /// focus ring (UI §3, keyboard focus only).
  final bool focused;

  /// UI §1.3: max(30, 18 · scale + 12). The sidebar uses it to scroll a
  /// row it has not built yet into view.
  static double heightFor(TextScaler textScaler) => max(
    ShellxSizes.row,
    textScaler.scale(ShellxSizes.rowTextLine) + ShellxSizes.rowTextPadding,
  );

  @override
  State<SessionTabRow> createState() => SessionTabRowState();
}

class SessionTabRowState extends State<SessionTabRow> {
  bool _hover = false;
  bool _pressed = false;

  /// Selection changes are instant (UI §1.5); only hover/pressed fade.
  bool _instant = true;

  @override
  void didUpdateWidget(SessionTabRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    _instant = oldWidget.selected != widget.selected;
  }

  /// UI §3.7: title · status · [origin] · [viewing/driving] · position.
  String _semanticsLabel(AppLocalizations l10n) {
    final tab = widget.tab;
    final parts = <String>[
      tab.label,
      if (tab.exited)
        l10n.sidebarStatusExited(tab.exitCode!)
      else if (tab.runningCommand)
        l10n.sidebarStatusRunning
      else
        l10n.sidebarStatusIdle,
      if (tab.origin == SessionOrigin.phone) l10n.sidebarPhoneOriginSemantics,
      if (tab.phoneAttached)
        tab.driver == DriverSide.phone
            ? l10n.sidebarPhoneDrivingSemantics
            : l10n.sidebarPhoneViewingSemantics,
      l10n.sidebarPosition(widget.position, widget.count),
    ];
    return parts.join(', ');
  }

  /// Shift+F10 / Menu key (from the sidebar): the menu under the row's
  /// left edge.
  void openMenu() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    _menu(box.localToGlobal(Offset(ShellxSpace.s8, box.size.height)));
  }

  void _menu(Offset at) =>
      showTabContextMenu(context: context, at: at, onClose: widget.onClose);

  void _setHover(bool value) {
    if (_hover == value) return;
    setState(() {
      _hover = value;
      _instant = false;
    });
  }

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() {
      _pressed = value;
      _instant = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tab = widget.tab;
    final height = SessionTabRow.heightFor(MediaQuery.textScalerOf(context));
    final background = _pressed
        ? ShellxDesktopColors.rowPressed
        : widget.selected
        ? ShellxDesktopColors.rowSelected
        : _hover
        ? ShellxDesktopColors.rowHover
        : Colors.transparent;
    final titleStyle =
        (widget.selected ? ShellxText.bodyStrong : ShellxText.body).copyWith(
          color: tab.exited
              ? ShellxDesktopColors.textSecondary
              : widget.selected
              ? ShellxDesktopColors.textTitle
              : ShellxDesktopColors.textPrimary,
        );
    final driving = tab.driver == DriverSide.phone;
    // UI §2.2: the close button shows on hover and on the selected row;
    // its slot is always kept, so a title never re-truncates on hover.
    final showClose = _hover || widget.selected;
    final shortcut = closeTabShortcutLabel();

    return Semantics(
      button: true,
      selected: widget.selected,
      label: _semanticsLabel(l10n),
      onTap: widget.onSelect,
      customSemanticsActions: {
        CustomSemanticsAction(label: l10n.terminalCloseTab): widget.onClose,
      },
      excludeSemantics: true,
      child: Listener(
        // UI §3.1: a middle click closes, with the same rules as ⌘W.
        onPointerDown: (event) {
          if (event.kind == PointerDeviceKind.mouse &&
              event.buttons & kMiddleMouseButton != 0) {
            widget.onClose();
          }
        },
        child: MouseRegion(
          onEnter: (_) => _setHover(true),
          onExit: (_) => _setHover(false),
          child: GestureDetector(
            onTap: widget.onSelect,
            onTapDown: (_) => _setPressed(true),
            onTapUp: (_) => _setPressed(false),
            onTapCancel: () => _setPressed(false),
            onSecondaryTapUp: (details) => _menu(details.globalPosition),
            child: AnimatedContainer(
              duration: _instant
                  ? Duration.zero
                  : ShellxMotion.of(context, ShellxMotion.fast),
              curve: ShellxMotion.fastCurve,
              height: height,
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(ShellxRadius.r6),
              ),
              foregroundDecoration: widget.focused
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(ShellxRadius.r6),
                      border: Border.all(
                        color: ShellxDesktopColors.accent,
                        width: ShellxSizes.focusRing,
                      ),
                    )
                  : null,
              child: Stack(
                children: [
                  if (widget.selected)
                    Positioned(
                      // With the keyboard ring on the row's edge, the bar
                      // moves inside it so both stay visible (UI §3.1).
                      left: widget.focused
                          ? ShellxSizes.focusRing + ShellxSizes.selectedBarGap
                          : 0,
                      top: (height - ShellxSizes.selectedBarHeight) / 2,
                      child: Container(
                        key: const Key('row.selectedBar'),
                        width: ShellxSizes.selectedBarWidth,
                        height: ShellxSizes.selectedBarHeight,
                        decoration: BoxDecoration(
                          color: ShellxDesktopColors.accent,
                          borderRadius: BorderRadius.circular(ShellxRadius.r4),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(
                      left: ShellxSpace.s8,
                      // 8 px to the close button's 20 px visual.
                      right:
                          ShellxSpace.s8 -
                          (ShellxSizes.rowCloseHit -
                                  ShellxSizes.rowCloseVisual) /
                              2,
                    ),
                    // A2 adds the context line as a second child (UI §2.2).
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            SizedBox(
                              width: ShellxSizes.dotSlot,
                              child: Center(child: _Dot(tab)),
                            ),
                            const SizedBox(width: ShellxSpace.s8),
                            Expanded(child: _Title(tab.label, titleStyle)),
                            if (tab.origin == SessionOrigin.phone) ...[
                              const SizedBox(width: ShellxSpace.s4),
                              Tooltip(
                                message: l10n.sidebarPhoneOrigin,
                                excludeFromSemantics: true,
                                child: const Icon(
                                  kPhoneIcon,
                                  size: ShellxSizes.mark,
                                  color: ShellxDesktopColors.textSecondary,
                                ),
                              ),
                            ],
                            if (tab.phoneAttached) ...[
                              const SizedBox(width: ShellxSpace.s4),
                              Tooltip(
                                message: driving
                                    ? l10n.sidebarPhoneDriving
                                    : l10n.sidebarPhoneViewing,
                                excludeFromSemantics: true,
                                child: Icon(
                                  Icons.visibility_outlined,
                                  size: ShellxSizes.mark,
                                  color: driving
                                      ? ShellxDesktopColors.warn
                                      : ShellxDesktopColors.accent,
                                ),
                              ),
                            ],
                            const SizedBox(width: ShellxSpace.s4 - 2),
                            Visibility(
                              visible: showClose,
                              maintainSize: true,
                              maintainAnimation: true,
                              maintainState: true,
                              child: _RowCloseButton(
                                tooltip: shortcutTooltip(
                                  l10n.terminalCloseTabTooltip(shortcut),
                                  shortcut,
                                ),
                                onPressed: widget.onClose,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The row's "×" (UI §2.2): 24 hit, 20 visual, `Icons.close` 14; hover
/// `rowPressed` + `textPrimary`. Not a tab stop (the list is one stop;
/// ⌘W and the row's menu close from the keyboard) and not in semantics
/// (the row's "Đóng tab" action is).
class _RowCloseButton extends StatefulWidget {
  const _RowCloseButton({required this.tooltip, required this.onPressed});
  final InlineSpan tooltip;
  final VoidCallback onPressed;

  @override
  State<_RowCloseButton> createState() => _RowCloseButtonState();
}

class _RowCloseButtonState extends State<_RowCloseButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => Tooltip(
    richMessage: widget.tooltip,
    excludeFromSemantics: true,
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        key: const Key('row.close'),
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: SizedBox.square(
          dimension: ShellxSizes.rowCloseHit,
          child: Center(
            child: AnimatedContainer(
              duration: ShellxMotion.of(context, ShellxMotion.fast),
              curve: ShellxMotion.fastCurve,
              width: ShellxSizes.rowCloseVisual,
              height: ShellxSizes.rowCloseVisual,
              decoration: BoxDecoration(
                color: _hover
                    ? ShellxDesktopColors.rowPressed
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(ShellxRadius.r4),
              ),
              child: Icon(
                Icons.close,
                size: ShellxSizes.rowCloseGlyph,
                color: _hover
                    ? ShellxDesktopColors.textPrimary
                    : ShellxDesktopColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// One line, ellipsis; the full title as a tooltip only when it is cut
/// (UI §3.1 hover). The tooltip opens right of the sidebar, level with the
/// row, so it never covers the next tab (or its marks).
class _Title extends StatelessWidget {
  const _Title(this.text, this.style);
  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final title = Text(
        text,
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: DefaultTextStyle.of(context).style.merge(style),
        ),
        maxLines: 1,
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: constraints.maxWidth);
      final cut = painter.didExceedMaxLines;
      painter.dispose();
      if (!cut) return title;
      return Tooltip(
        message: text,
        excludeFromSemantics: true,
        constraints: const BoxConstraints(
          maxWidth: ShellxSizes.titleTooltipMaxWidth,
        ),
        positionDelegate: besideSidebar,
        child: title,
      );
    },
  );
}

/// Right of the sidebar ([ShellxSizes.sidebarWidth] + 6), vertically
/// centred on the row, kept inside the window.
Offset besideSidebar(TooltipPositionContext context) {
  final overlay = context.overlaySize;
  final size = context.tooltipSize;
  final double x = (ShellxSizes.sidebarWidth + ShellxSpace.s6).clamp(
    0.0,
    max(0.0, overlay.width - size.width - ShellxSpace.s8),
  );
  final double y = (context.target.dy - size.height / 2).clamp(
    0.0,
    max(0.0, overlay.height - size.height),
  );
  return Offset(x, y);
}

/// UI §3.1 status dot (8 px), three shapes so it never relies on colour
/// alone (WCAG 1.4.1): idle a filled `ok` dot; running a command an
/// `accent` ring with a 4 px centre (a target); exited non-zero a hollow
/// 1.5 px `err` ring. The meaning is also in the row's semantics label.
class _Dot extends StatelessWidget {
  const _Dot(this.tab);
  final TerminalTab tab;

  @override
  Widget build(BuildContext context) {
    if (tab.exited) {
      return Container(
        key: const Key('dot.exited'),
        width: ShellxSizes.dot,
        height: ShellxSizes.dot,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: ShellxDesktopColors.err,
            width: ShellxSizes.dotRing,
          ),
        ),
      );
    }
    if (tab.runningCommand) {
      return Container(
        key: const Key('dot.running'),
        width: ShellxSizes.dot,
        height: ShellxSizes.dot,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: ShellxDesktopColors.accent,
            width: ShellxSizes.dotRing,
          ),
        ),
        child: Container(
          width: ShellxSizes.dotCentre,
          height: ShellxSizes.dotCentre,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: ShellxDesktopColors.accent,
          ),
        ),
      );
    }
    return Container(
      key: const Key('dot.idle'),
      width: ShellxSizes.dot,
      height: ShellxSizes.dot,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: ShellxDesktopColors.ok,
      ),
    );
  }
}
