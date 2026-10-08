import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../terminal/agent_names.dart';
import '../../terminal/agent_status.dart';
import '../theme/shellx_desktop_theme.dart';

/// The icon and colour of each state (A12 D12): never colour alone (the
/// icon differs and the word follows), and no animation: running is a
/// still dot.
({IconData icon, Color color}) agentBadgeLook(
  AgentState state,
) => switch (state) {
  AgentState.needsInput => (
    icon: Icons.warning_amber_rounded,
    color: ShellxDesktopColors.warn,
  ),
  AgentState.running => (icon: Icons.circle, color: ShellxDesktopColors.accent),
  AgentState.done => (icon: Icons.check_rounded, color: ShellxDesktopColors.ok),
  AgentState.idle || AgentState.unknown => (
    icon: Icons.circle_outlined,
    color: ShellxDesktopColors.textSecondary,
  ),
};

/// The state of an agent in a tab row ([large] = false) or a pane header
/// ([large]): icon and word; [compact] keeps the icon only. Its name and
/// state are in the tooltip and in the screen-reader label. The badge is
/// never a live region: the tab row speaks a question (once a minute).
class AgentBadge extends StatelessWidget {
  const AgentBadge({
    super.key,
    required this.state,
    required this.agent,
    this.large = false,
    this.compact = false,
  });

  final AgentState state;
  final AgentKind agent;
  final bool large;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = agentStatusLabel(l10n, agent, state);
    final look = agentBadgeLook(state);
    final icon = large
        ? ShellxSizes.agentBadgePaneIcon
        : ShellxSizes.agentBadgeRowIcon;
    return ExcludeFocus(
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: Semantics(
          label: label,
          excludeSemantics: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(look.icon, size: icon, color: look.color),
              if (!compact) ...[
                const SizedBox(width: ShellxSpace.s4),
                Text(
                  agentStateWord(l10n, state),
                  maxLines: 1,
                  softWrap: false,
                  style: ShellxText.caption.copyWith(
                    color: look.color,
                    fontWeight: FontWeight.w600,
                    height: 1,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
