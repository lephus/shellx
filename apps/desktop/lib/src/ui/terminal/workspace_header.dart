import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../l10n/app_localizations.dart';
import '../theme/shellx_desktop_theme.dart';
import 'inline_name_field.dart';

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

  /// UI-A2 §1.3: max(28, 16·s + 12).
  static double heightFor(TextScaler scaler) => max(
    ShellxSizes.workspaceHeader,
    scaler.scale(ShellxSizes.workspaceHeaderText) + 12,
  );

  @override
  State<WorkspaceHeader> createState() => WorkspaceHeaderState();
}

class WorkspaceHeaderState extends State<WorkspaceHeader> {
  bool _hover = false;
  bool _pressed = false;

  /// Shift+F10 from the sidebar: the menu under the header's left edge.
  void openMenu() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    widget.onMenu(box.localToGlobal(Offset(ShellxSpace.s8, box.size.height)));
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
        : _pressed
        ? ShellxDesktopColors.rowPressed
        : _hover
        ? ShellxDesktopColors.rowHover
        : Colors.transparent;
    final showAdd = !renaming && (_hover || widget.focused);
    final label = [
      l10n.workspaceHeaderSemantics(widget.name, widget.count),
      if (widget.containsSelected) l10n.workspaceContainsSelected,
    ].join(', ');

    // |4| chevron 20 |4| name |4| count ≥ 16 |2| + 24 |4| (UI-A2 §3.1).
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
        // Hidden while renaming; the slot stays (UI-A2 §3.2).
        Visibility(
          visible: !renaming,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: ShellxSizes.headerCountMin,
            ),
            child: Text(
              '${widget.count}',
              textAlign: TextAlign.right,
              style: ShellxText.caption.copyWith(
                color: ShellxDesktopColors.textSecondary,
              ),
            ),
          ),
        ),
        // The `+` slot: the button itself sits above (see below).
        const SizedBox(
          width: ShellxSpace.s2 + ShellxSizes.headerAddHit + ShellxSpace.s4,
        ),
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
                          : (d) => widget.onMenu(d.globalPosition),
                      child: row,
                    ),
                  ),
                ),
                if (widget.collapsed && widget.containsSelected)
                  Positioned(
                    left: 0,
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
                  right: ShellxSpace.s4,
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
