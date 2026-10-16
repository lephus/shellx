import '../../l10n/app_localizations.dart';
import 'agent_status.dart';

/// The agent's name as shown ("Claude Code", "Codex", "Gemini CLI",
/// "OpenCode": the same in every language).
String agentDisplayName(AppLocalizations l10n, AgentKind kind) =>
    switch (kind) {
      AgentKind.claude => l10n.agentNamesClaude,
      AgentKind.codex => l10n.agentNamesCodex,
      AgentKind.gemini => l10n.agentNamesGemini,
      AgentKind.opencode => l10n.agentNamesOpencode,
    };

/// "Running", "Needs input", "Idle", "Done".
String agentStateWord(AppLocalizations l10n, AgentState state) =>
    switch (state) {
      AgentState.running => l10n.agentStateRunning,
      AgentState.needsInput => l10n.agentStateNeedsInput,
      AgentState.idle || AgentState.unknown => l10n.agentStateIdle,
      AgentState.done => l10n.agentStateDone,
    };

/// What a screen reader and a tooltip say about an agent's state; for a
/// question it is the sentence of the live region.
String agentStatusLabel(
  AppLocalizations l10n,
  AgentKind kind,
  AgentState state,
) => agentStatusLabelNamed(l10n, agentDisplayName(l10n, kind), state);

/// [agentStatusLabel] for an agent called [name]: an AI pane's own agent
/// ("Claude", V2-1 B6).
String agentStatusLabelNamed(
  AppLocalizations l10n,
  String name,
  AgentState state,
) => state == AgentState.needsInput
    ? l10n.agentStatusAnnounce(name)
    : l10n.agentStatusTooltip(name, agentStateWord(l10n, state));
