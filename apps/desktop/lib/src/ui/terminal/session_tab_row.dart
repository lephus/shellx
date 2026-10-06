import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';

import '../../../l10n/app_localizations.dart';
import '../../terminal/terminal_tabs.dart';
import '../theme/shellx_desktop_theme.dart';
import 'shortcut_labels.dart';

/// UI §3.1 context menu ("Đóng tab  ⌘W") at [at] (global). Secondary
/// click, Shift+F10 and the Menu key open it; Esc closes it, ↑/↓ + Enter
/// operate it (the popup route's own keys).
Future<void> showTabContextMenu({
  required BuildContext context,
  required Offset at,
  required VoidCallback onClose,
}) async {
  final l10n = AppLocalizations.of(context);
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final local = overlay.globalToLocal(at);
  final choice = await showMenu<_TabMenuChoice>(
    context: context,
    color: ShellxDesktopColors.surface,
    surfaceTintColor: Colors.transparent,
    elevation: ShellxShadows.e1Elevation,
    shadowColor: ShellxShadows.e1ShadowColor,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(ShellxRadius.r8),
      side: const BorderSide(color: ShellxDesktopColors.border),
    ),
    menuPadding: const EdgeInsets.all(ShellxSpace.s4),
    position: RelativeRect.fromRect(
      local & const Size(1, 1),
      Offset.zero & overlay.size,
    ),
    constraints: const BoxConstraints(minWidth: ShellxSizes.menuMinWidth),
    popUpAnimationStyle: AnimationStyle(
      duration: ShellxMotion.of(context, ShellxMotion.base),
      reverseDuration: ShellxMotion.of(context, ShellxMotion.exit),
    ),
    items: [
      _TabMenuItem(
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

/// UI §3.1 menu item: 28 high, padding 0/10, `body`, hover (and keyboard
/// highlight) `rowSelected` with `r6` corners, shortcut hint right-aligned
/// in `caption` `textSecondary`.
class _TabMenuItem extends PopupMenuItem<_TabMenuChoice> {
  const _TabMenuItem({
    super.key,
    required _TabMenuChoice super.value,
    required this.label,
    required this.shortcut,
  }) : super(
         height: ShellxSizes.menuItem,
         padding: EdgeInsets.zero,
         child: null,
       );

  final String label;
  final String shortcut;

  @override
  PopupMenuItemState<_TabMenuChoice, _TabMenuItem> createState() =>
      _TabMenuItemState();
}

class _TabMenuItemState
    extends PopupMenuItemState<_TabMenuChoice, _TabMenuItem> {
  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: buildSemantics(
      child: InkWell(
        onTap: handleTap,
        borderRadius: BorderRadius.circular(ShellxRadius.r6),
        hoverColor: ShellxDesktopColors.rowSelected,
        focusColor: ShellxDesktopColors.rowSelected,
        highlightColor: ShellxDesktopColors.rowPressed,
        splashFactory: NoSplash.splashFactory,
        hoverDuration: ShellxMotion.of(context, ShellxMotion.fast),
        child: SizedBox(
          height: widget.height,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ShellxSizes.menuItemPaddingH,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ShellxText.body.copyWith(
                      color: ShellxDesktopColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: ShellxSpace.s16),
                ExcludeSemantics(
                  child: Text(
                    widget.shortcut,
                    style: ShellxText.caption.copyWith(
                      color: ShellxDesktopColors.textSecondary,
                    ),
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
                      left: 0,
                      top: (height - ShellxSizes.selectedBarHeight) / 2,
                      child: Container(
                        width: ShellxSizes.selectedBarWidth,
                        height: ShellxSizes.selectedBarHeight,
                        decoration: BoxDecoration(
                          color: ShellxDesktopColors.accent,
                          borderRadius: BorderRadius.circular(ShellxRadius.r4),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: ShellxSpace.s8,
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
                                  Icons.smartphone_outlined,
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

/// One line, ellipsis; the full title as a tooltip only when it is cut
/// (UI §3.1 hover).
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
      return Tooltip(message: text, excludeFromSemantics: true, child: title);
    },
  );
}

/// UI §3.1 status dot (8 px): idle filled `ok`, running a command filled
/// `accent`, exited non-zero a 1.5 px `err` ring. Shape and colour both
/// change; the meaning is in the row's semantics label.
class _Dot extends StatelessWidget {
  const _Dot(this.tab);
  final TerminalTab tab;

  @override
  Widget build(BuildContext context) => Container(
    width: ShellxSizes.dot,
    height: ShellxSizes.dot,
    decoration: tab.exited
        ? BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: ShellxDesktopColors.err,
              width: ShellxSizes.dotRing,
            ),
          )
        : BoxDecoration(
            shape: BoxShape.circle,
            color: tab.runningCommand
                ? ShellxDesktopColors.accent
                : ShellxDesktopColors.ok,
          ),
  );
}
