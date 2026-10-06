import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../l10n/app_localizations.dart';
import '../theme/shellx_desktop_theme.dart';
import 'inline_name_field.dart';
import 'session_tab_row.dart' show besideSidebar;

/// UI-A2 §3: a workspace's header row — chevron, name, tab count, `+` on
/// hover/focus; click toggles, double-click renames, secondary click /
/// Shift+F10 opens the menu (the sidebar owns the menu and the keys).
class WorkspaceHeader extends StatefulWidget {
  const WorkspaceHeader({
    super.key,
    required this.name,
    required this.count,
    required this.collapsed,
    required this.containsSelected,
    required this.focused,
    required this.renaming,
    required this.dropTarget,
    required this.deletable,
    required this.onToggle,
    required this.onStartRename,
    required this.onRename,
    required this.onCancelRename,
    required this.onNewTab,
    required this.onMenu,
    required this.onDelete,
    this.workspaceId,
    this.menuOpen = false,
  });

  final String name;
  final int count;
  final bool collapsed;

  /// Collapsed and holding the selected tab: accent mark, brighter name.
  final bool containsSelected;

  /// Keyboard focus ring (the list's cursor is on this header, D14).
  final bool focused;
  final bool renaming;

  /// A dragged tab is over this header (UI-A2 §3.2).
  final bool dropTarget;
  final bool deletable;
  final VoidCallback onToggle;
  final VoidCallback onStartRename;
  final void Function(String text) onRename;
  final VoidCallback onCancelRename;
  final VoidCallback onNewTab;
  final void Function(Offset at) onMenu;
  final VoidCallback onDelete;

  /// Identifies the name field (see [InlineNameField.identity]).
  final String? workspaceId;

  /// V6: this header's context menu is open: it keeps the pressed fill and
  /// a 1 px outline until the menu closes, so the menu's target is plain.
  final bool menuOpen;

  /// UI-A2 §1.3: max(28, 16·s + 12).
  static double heightFor(TextScaler scaler) => max(
    ShellxSizes.workspaceHeader,
    scaler.scale(ShellxSizes.workspaceHeaderText) + 12,
  );

  @override
  State<WorkspaceHeader> createState() => WorkspaceHeaderState();
}

/// Right of the count/`+` slot: the rows' × hit area ends 6 px in
/// (8 − (24 − 20) / 2), so the slot sits in the same column.
const double _trailing =
    ShellxSpace.s8 - (ShellxSizes.rowCloseHit - ShellxSizes.rowCloseVisual) / 2;

class WorkspaceHeaderState extends State<WorkspaceHeader> {
  bool _hover = false;
  bool _pressed = false;

  /// Shift+F10 from the sidebar: the menu under the header's left edge.
  void openMenu() => _openMenuBeside();

  /// Polish 7: right of the sidebar, level with the header (as the
  /// sidebar's tooltips), so the menu never hides the name it acts on.
  void _openMenuBeside() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final top = box.localToGlobal(Offset.zero).dy;
    widget.onMenu(Offset(ShellxSizes.sidebarWidth + ShellxSpace.s6, top));
  }

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final height = WorkspaceHeader.heightFor(scaler);
    final renaming = widget.renaming;
    final nameStyle = ShellxText.small.copyWith(
      fontWeight: FontWeight.w600,
      color: widget.containsSelected
          ? ShellxDesktopColors.textPrimary
          : ShellxDesktopColors.textSecondary,
    );
    final background = widget.dropTarget
        ? ShellxDesktopColors.primarySoft
        : _pressed || widget.menuOpen
        ? ShellxDesktopColors.rowPressed
        : _hover
        ? ShellxDesktopColors.rowHover
        : Colors.transparent;
    // V4: an empty group always shows its `+` (the quickest way to fill
    // it); V10: otherwise the count holds the slot until hover or focus.
    final showAdd =
        !renaming && (_hover || widget.focused || widget.count == 0);
    final label = [
      l10n.workspaceHeaderSemantics(widget.name, widget.count),
      if (widget.containsSelected) l10n.workspaceContainsSelected,
    ].join(', ');

    // |4| chevron 20 |4| name |4| [count | +] 24 |6| (UI-A2 §3.1, V10):
    // the count and the `+` share one slot in the rows' × column, so the
    // name never gives up width to a hidden button.
    final row = Row(
      children: [
        const SizedBox(width: ShellxSpace.s4),
        SizedBox(
          width: ShellxSizes.chevronHit,
          // `chevron_right` turned a quarter is `expand_more`: one icon
          // turns 90° between the two states (UI-A2 §3.1).
          child: AnimatedRotation(
            turns: widget.collapsed ? 0 : 0.25,
            duration: ShellxMotion.of(context, ShellxMotion.base),
            curve: ShellxMotion.baseCurve,
            child: const Icon(
              Icons.chevron_right,
              size: ShellxSizes.mark,
              color: ShellxDesktopColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: ShellxSpace.s4),
        Expanded(
          child: renaming
              ? InlineNameField(
                  initial: widget.name,
                  style: nameStyle,
                  label: l10n.workspaceNameField,
                  identity: widget.workspaceId == null
                      ? null
                      : ('ws', widget.workspaceId),
                  onCommit: widget.onRename,
                  onCancel: widget.onCancelRename,
                )
              // Double-click on the name renames (UI-A2 §3.3). Only the
              // name waits for a second click; the chevron and the rest
              // of the header toggle on the first.
              : Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: GestureDetector(
                    onDoubleTap: widget.onStartRename,
                    child: Text(
                      widget.name,
                      style: nameStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
        ),
        const SizedBox(width: ShellxSpace.s4),
        // The slot: the count shows here unless the `+` (drawn above, see
        // below) does; both hidden while renaming, the slot kept.
        SizedBox(
          width: ShellxSizes.headerAddHit,
          child: Visibility(
            visible: !renaming && !showAdd,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: Text(
              '${widget.count}',
              key: const Key('header.count'),
              textAlign: TextAlign.center,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              style: ShellxText.caption.copyWith(
                color: ShellxDesktopColors.textSecondary,
              ),
            ),
          ),
        ),
        const SizedBox(width: _trailing),
      ],
    );

    return Semantics(
      header: true,
      button: !renaming,
      expanded: !widget.collapsed,
      label: label,
      // The list's tree cursor (D14): the list node holds the keyboard,
      // the header is where screen readers place it.
      focused: widget.focused,
      onTap: renaming ? null : widget.onToggle,
      customSemanticsActions: {
        CustomSemanticsAction(label: l10n.workspaceRename):
            widget.onStartRename,
        CustomSemanticsAction(label: l10n.workspaceNewTab): widget.onNewTab,
        if (widget.deletable)
          CustomSemanticsAction(label: l10n.workspaceDelete): widget.onDelete,
      },
      // While renaming, the name field is the header's one child node
      // ("Workspace name", UI-A2 §4).
      excludeSemantics: !renaming,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() {
          _hover = false;
          _pressed = false;
        }),
        // The ring and the drop border are drawn in front, outside the
        // animation: the keyboard ring switches at once (UI §1.5, §3) and
        // a border never shifts the content. Never null, so the subtree
        // (and an open name field) stays put.
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: widget.focused
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(ShellxRadius.r6),
                  border: Border.all(
                    color: ShellxDesktopColors.accent,
                    width: ShellxSizes.focusRing,
                  ),
                )
              : widget.dropTarget
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(ShellxRadius.r6),
                  border: Border.all(color: ShellxDesktopColors.accent),
                )
              : widget.menuOpen
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(ShellxRadius.r6),
                  border: Border.all(color: ShellxDesktopColors.border),
                )
              : const BoxDecoration(),
          child: AnimatedContainer(
            duration: ShellxMotion.of(context, ShellxMotion.fast),
            curve: ShellxMotion.fastCurve,
            height: height,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(ShellxRadius.r6),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  // Pressed shows on the button going down, not when the
                  // gesture is decided.
                  child: Listener(
                    onPointerDown: (e) => _setPressed(
                      !renaming && e.buttons & kPrimaryButton != 0,
                    ),
                    onPointerUp: (_) => _setPressed(false),
                    onPointerCancel: (_) => _setPressed(false),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      // A click toggles; on the name it waits for the
                      // double-tap timeout first (UI-A2 §3.3: the first
                      // click of a double-click must not collapse). While
                      // renaming, clicks belong to the field.
                      onTap: renaming ? null : widget.onToggle,
                      onSecondaryTapUp: renaming
                          ? null
                          : (_) => _openMenuBeside(),
                      child: row,
                    ),
                  ),
                ),
                if (widget.collapsed && widget.containsSelected)
                  Positioned(
                    // V3: inside the keyboard ring, as the rows' bar does,
                    // so the mark stays visible under focus.
                    left: widget.focused
                        ? ShellxSizes.focusRing + ShellxSizes.selectedBarGap
                        : 0,
                    top: (height - ShellxSizes.collapsedMarkHeight) / 2,
                    child: IgnorePointer(
                      child: Container(
                        key: const Key('header.collapsedMark'),
                        width: ShellxSizes.selectedBarWidth,
                        height: ShellxSizes.collapsedMarkHeight,
                        decoration: BoxDecoration(
                          color: ShellxDesktopColors.accent,
                          borderRadius: BorderRadius.circular(ShellxRadius.r4),
                        ),
                      ),
                    ),
                  ),
                // Above the header's own gestures, so a click on `+` is the
                // button's at once (not held by the header's double-tap).
                Positioned(
                  top: 0,
                  bottom: 0,
                  right: _trailing,
                  child: Center(
                    child: Visibility(
                      visible: showAdd,
                      maintainSize: true,
                      maintainAnimation: true,
                      maintainState: true,
                      child: _HeaderAdd(
                        tooltip: l10n.workspaceNewTab,
                        onPressed: widget.onNewTab,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// UI-A2 §3.1 `+`: 24 hit, 20 visual (`r4`), `Icons.add` 14; hover
/// `rowPressed` + `textPrimary`. Not a tab stop and not in semantics (the
/// header's "New tab in this workspace" action is).
class _HeaderAdd extends StatefulWidget {
  const _HeaderAdd({required this.tooltip, required this.onPressed});
  final String tooltip;
  final VoidCallback onPressed;

  @override
  State<_HeaderAdd> createState() => _HeaderAddState();
}

class _HeaderAddState extends State<_HeaderAdd> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: widget.tooltip,
    excludeFromSemantics: true,
    // V11: beside the sidebar, as every sidebar tooltip (never over the
    // group's first row).
    positionDelegate: besideSidebar,
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        key: const Key('header.add'),
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: SizedBox.square(
          dimension: ShellxSizes.headerAddHit,
          child: Center(
            child: AnimatedContainer(
              duration: ShellxMotion.of(context, ShellxMotion.fast),
              curve: ShellxMotion.fastCurve,
              width: ShellxSizes.headerAddVisual,
              height: ShellxSizes.headerAddVisual,
              decoration: BoxDecoration(
                color: _hover
                    ? ShellxDesktopColors.rowPressed
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(ShellxRadius.r4),
              ),
              child: Icon(
                Icons.add,
                size: ShellxSizes.mark,
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
