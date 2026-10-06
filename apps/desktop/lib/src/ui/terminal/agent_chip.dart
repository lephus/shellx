import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../theme/shellx_desktop_theme.dart';

/// A7 D27 (A6 UI §2.1): "Agent" for 10 s after the command line acted on a
/// tab (its sidebar row) or a pane (its header, [large]). Not a focus stop;
/// its meaning is read in the row's / pane's own label, and shown in a
/// tooltip.
class AgentChip extends StatelessWidget {
  const AgentChip({super.key, required this.large});

  /// The pane header's size (20 high, icon 14) instead of the row's (16,
  /// 12).
  final bool large;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ExcludeFocus(
      child: Tooltip(
        message: l10n.agentChipTooltip,
        excludeFromSemantics: true,
        child: Semantics(
          label: l10n.agentChipTooltip,
          excludeSemantics: true,
          // At least the UI height; large text grows it, never cuts it.
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: large
                  ? ShellxSizes.agentChipPaneHeight
                  : ShellxSizes.agentChipRowHeight,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: ShellxDesktopColors.warnBg,
                border: Border.all(color: ShellxDesktopColors.warnBorder),
                borderRadius: BorderRadius.circular(ShellxRadius.pill),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: large
                      ? ShellxSizes.agentChipPanePadH
                      : ShellxSizes.agentChipRowPadH,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.smart_toy_outlined,
                      size: large
                          ? ShellxSizes.agentChipPaneIcon
                          : ShellxSizes.agentChipRowIcon,
                      color: ShellxDesktopColors.warn,
                    ),
                    const SizedBox(width: ShellxSpace.s4),
                    Text(
                      l10n.agentChip,
                      maxLines: 1,
                      softWrap: false,
                      style: ShellxText.caption.copyWith(
                        color: ShellxDesktopColors.warn,
                        fontWeight: FontWeight.w600,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
