import 'package:flutter/material.dart';

import '../theme/shellx_desktop_theme.dart';

/// One item of a UI §3.1 context menu.
final class ShellxMenuEntry<T> {
  const ShellxMenuEntry({
    required this.value,
    required this.label,
    this.shortcut,
    this.enabled = true,
    this.key,
    this.dividerBefore = false,
    this.tooltip,
    this.heading = false,
    this.checked = false,
  });

  final T value;
  final String label;

  /// The platform shortcut hint (`⌘C` / `Ctrl+Shift+C`), right-aligned.
  final String? shortcut;

  /// Disabled items stay in place at 38 % (UI §3) so the menu keeps its
  /// shape (Copy without a selection).
  final bool enabled;
  final Key? key;

  /// UI-A2 §5: a 1 px `line` separator above this item (4 px above/below).
  final bool dividerBefore;

  /// V12: why a disabled item is disabled ("Default can't be deleted"),
  /// shown on hover and read by screen readers.
  final String? tooltip;

  /// V6: a title line naming what the menu acts on ("Move “api” to"):
  /// `caption` `textSecondary`, never selectable (not at 38 %: it is
  /// meant to be read).
  final bool heading;

  /// A11 D18: the current choice of a list (the tab status): a check mark
  /// at the end and "checked" for screen readers.
  final bool checked;
}

/// UI §3.1 context menu at [at] (global): `surface`, 1 px `border`, `r8`,
/// padding 4, min width 180, `e1`. Esc closes it; ↑/↓ + Enter operate it
/// (the popup route's own keys). Null when dismissed.
Future<T?> showShellxMenu<T>({
  required BuildContext context,
  required Offset at,
  required List<ShellxMenuEntry<T>> entries,
}) {
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final local = overlay.globalToLocal(at);
  return showMenu<T>(
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
      for (final entry in entries) ...[
        if (entry.dividerBefore)
          const PopupMenuDivider(
            height: ShellxSizes.menuDivider,
            thickness: 1,
            color: ShellxDesktopColors.line,
          ),
        _ShellxMenuItem<T>(entry),
      ],
    ],
  );
}

/// UI §3.1 menu item: 28 high, padding 0/10, `body`, hover (and keyboard
/// highlight) `rowSelected` with `r6` corners, shortcut hint right-aligned
/// in `caption` `textSecondary`.
class _ShellxMenuItem<T> extends PopupMenuItem<T> {
  _ShellxMenuItem(this.entry)
    : super(
        key: entry.key,
        value: entry.value,
        enabled: entry.enabled && !entry.heading,
        height: ShellxSizes.menuItem,
        padding: EdgeInsets.zero,
        child: null,
      );

  final ShellxMenuEntry<T> entry;

  @override
  PopupMenuItemState<T, _ShellxMenuItem<T>> createState() =>
      _ShellxMenuItemState<T>();
}

class _ShellxMenuItemState<T>
    extends PopupMenuItemState<T, _ShellxMenuItem<T>> {
  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final shortcut = entry.shortcut;
    if (entry.heading) {
      return SizedBox(
        height: widget.height,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ShellxSizes.menuItemPaddingH,
          ),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              entry.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ShellxText.caption.copyWith(
                color: ShellxDesktopColors.textSecondary,
              ),
            ),
          ),
        ),
      );
    }
    final row = Row(
      children: [
        Expanded(
          child: Text(
            entry.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ShellxText.body.copyWith(
              color: ShellxDesktopColors.textPrimary,
            ),
          ),
        ),
        if (entry.checked) ...[
          const SizedBox(width: ShellxSpace.s16),
          const Icon(
            Icons.check,
            size: 14,
            color: ShellxDesktopColors.textSecondary,
          ),
        ],
        if (shortcut != null) ...[
          const SizedBox(width: ShellxSpace.s16),
          ExcludeSemantics(
            child: Text(
              shortcut,
              style: ShellxText.caption.copyWith(
                color: ShellxDesktopColors.textSecondary,
              ),
            ),
          ),
        ],
      ],
    );
    final tooltip = entry.tooltip;
    final item = MergeSemantics(
      child: buildSemantics(
        child: InkWell(
          onTap: entry.enabled ? handleTap : null,
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
              child: entry.enabled
                  ? row
                  : Opacity(
                      opacity: ShellxDesktopColors.disabledOpacity,
                      child: row,
                    ),
            ),
          ),
        ),
      ),
    );
    if (tooltip == null) return item;
    return Tooltip(message: tooltip, child: item);
  }
}
