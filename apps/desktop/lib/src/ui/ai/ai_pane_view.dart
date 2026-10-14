import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../terminal/terminal_tabs.dart';
import '../theme/shellx_desktop_theme.dart';

/// V2-1 D3: an AI pane, the negative leaf of an AI tab. Until the runtime
/// is wired (V2-1b Task 17) it shows the agent and the title, and holds the
/// keyboard the window gives it ([focusNode] is the window's terminal
/// focus while this pane is the selected tab's focused pane).
class AiPaneView extends StatelessWidget {
  const AiPaneView({
    super.key,
    required this.tab,
    required this.pane,
    required this.selected,
    this.focusNode,
  });

  final TerminalTab tab;
  final AiPaneState pane;

  /// The pane's tab is the selected one.
  final bool selected;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      container: true,
      label: l10n.aiPaneLabel(pane.agentName),
      child: ColoredBox(
        color: ShellxDesktopColors.bgTerminal,
        child: Focus(
          focusNode: focusNode,
          autofocus: focusNode != null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 34,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ShellxSpace.s12,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.auto_awesome,
                        size: ShellxSizes.icon,
                        color: ShellxDesktopColors.accent,
                      ),
                      const SizedBox(width: ShellxSpace.s6),
                      Text(
                        pane.agentName,
                        style: ShellxText.bodyStrong.copyWith(
                          color: ShellxDesktopColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: ShellxSpace.s8),
                      Expanded(
                        child: Text(
                          tab.label,
                          key: const Key('ai.header.title'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ShellxText.small.copyWith(
                            color: ShellxDesktopColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, color: ShellxDesktopColors.line),
              const Expanded(child: SizedBox.expand()),
            ],
          ),
        ),
      ),
    );
  }
}
