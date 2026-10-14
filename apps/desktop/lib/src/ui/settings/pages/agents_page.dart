import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../integrations/integration_probe.dart';
import '../../../config/config_controller.dart' show shellxConfigProvider;
import '../../../integrations/integration_status.dart';
import '../../../integrations/pr_status.dart' show ghFoundProvider;
import '../../../terminal/agent_names.dart';
import '../../../terminal/agent_status.dart';
import '../../../tray/tray_action.dart';
import '../../../tray/tray_actions.dart';
import '../../ai/ai_agents_section.dart';
import '../../theme/shellx_desktop_theme.dart';
import '../settings_row.dart' show SettingsScope;
import 'page_parts.dart';

/// Agents: notifications, the long-command threshold, resuming a session
/// after a restart, the agents' hooks, the `shellx` command line and the SSH
/// hook. Every switch is the tray's own (or a key of the configuration
/// file).
class AgentsPage extends ConsumerWidget {
  const AgentsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return PageFrame(
      children: [
        settingWidget(settingById('desktop-notifications')),
        settingWidget(settingById('desktop-notifications-only-unfocused')),
        settingWidget(settingById('notify-threshold')),
        SectionHeader(l10n.trayCommandLine),
        settingWidget(settingById('cli-control')),
        settingWidget(settingById('cli-allow-external')),
        settingWidget(settingById('cli-path')),
        ActionRow(
          key: const Key('setting.cli-skills'),
          label: l10n.trayCliCopySkills,
          button: l10n.trayCliCopySkills,
          onPressed: () => unawaited(
            ref.read(trayActionsProvider).handle(const CopySkillsCommand()),
          ),
        ),
        SectionHeader(l10n.sshTrayMenu),
        settingWidget(settingById('ssh-hook')),
        const _IntegrationsSection(),
        settingWidget(settingById('agent-resume')),
        _PrStatusRow(),
        const _AgentCommandRow(),
        // V2-1 D7: the AI interface's agents (last, so the rows above keep
        // their place).
        const AiAgentsSection(),
      ],
    );
  }
}

/// A12 D16: the pull request switch; when it is on and `gh` cannot be
/// found, the row says so.
class _PrStatusRow extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final on = ref.watch(shellxConfigProvider.select((s) => s.config.prStatus));
    final found = on ? ref.watch(ghFoundProvider).value : null;
    return settingWidget(
      settingById('pr-status'),
      note: found == false ? l10n.settingPrStatusNoGh : null,
    );
  }
}

/// A12 D17: what `agent-event-command` is for. It is set in the file (an
/// edit here would put a command line in front of the user without the
/// approval dialog), so this row only says so.
class _AgentCommandRow extends StatelessWidget {
  const _AgentCommandRow();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      key: const Key('setting.agent-event-command'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.settingAgentCommand,
            style: ShellxText.body.copyWith(
              color: ShellxDesktopColors.textPrimary,
            ),
          ),
          Text(
            l10n.settingAgentCommandDesc,
            style: ShellxText.small.copyWith(
              color: ShellxDesktopColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// A12 D6, D23: whether each agent has ShellX's hooks, and a button that
/// opens a terminal tab where the CLI shows the change and asks. The page
/// only reads; nothing here ever writes an agent's file.
class _IntegrationsSection extends ConsumerStatefulWidget {
  const _IntegrationsSection();

  @override
  ConsumerState<_IntegrationsSection> createState() =>
      _IntegrationsSectionState();
}

class _IntegrationsSectionState extends ConsumerState<_IntegrationsSection> {
  @override
  void initState() {
    super.initState();
    // Not while building: the probe reads files.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(integrationStatusProvider.notifier).refresh());
    });
  }

  Future<void> _run(AgentKind agent, {required bool remove}) async {
    final scope = SettingsScope.of(context);
    final opened = await ref
        .read(integrationStatusProvider.notifier)
        .runInTerminal(agent, remove: remove);
    // The tab is behind Settings: step aside so it can be seen.
    if (opened) scope.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = ref.watch(integrationStatusProvider);
    final cli = ref.watch(shellxCliFoundProvider) ?? true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(l10n.settingsAgentIntegrations),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            l10n.settingsAgentIntegrationsHint,
            style: ShellxText.small.copyWith(
              color: ShellxDesktopColors.textSecondary,
            ),
          ),
        ),
        for (final agent in AgentKind.values)
          _IntegrationRow(
            agent: agent,
            status: status?[agent],
            cliFound: cli,
            onRun: (remove) => unawaited(_run(agent, remove: remove)),
          ),
      ],
    );
  }
}

class _IntegrationRow extends StatelessWidget {
  const _IntegrationRow({
    required this.agent,
    required this.status,
    required this.cliFound,
    required this.onRun,
  });
  final bool cliFound;
  final AgentKind agent;

  /// Null until the first look.
  final IntegrationStatus? status;
  final void Function(bool remove) onRun;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final name = agentDisplayName(l10n, agent);
    final installed = status?.installed ?? false;
    final chipText = status == null
        ? null
        : installed
        ? l10n.integrationInstalled
        : l10n.integrationNotInstalled;
    final captions = [
      if (agent == AgentKind.codex) l10n.integrationLimit,
      if (status?.notFound ?? false) l10n.integrationNotFound(name),
      if (!cliFound && status != null) l10n.integrationNeedsCli,
    ];
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Padding(
        key: Key('integration.row.${agent.name}'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 2,
                    children: [
                      Text(
                        name,
                        style: ShellxText.body.copyWith(
                          color: ShellxDesktopColors.textPrimary,
                        ),
                      ),
                      if (chipText != null)
                        // An icon and a word: never colour alone.
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ExcludeSemantics(
                              child: Icon(
                                installed
                                    ? Icons.check_circle_outline
                                    : Icons.circle_outlined,
                                size: ShellxSizes.icon,
                                color: installed
                                    ? ShellxDesktopColors.ok
                                    : ShellxDesktopColors.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              chipText,
                              style: ShellxText.small.copyWith(
                                color: ShellxDesktopColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (status != null)
                  installed
                      ? OutlinedButton(
                          key: Key('integration.remove.${agent.name}'),
                          onPressed: cliFound ? () => onRun(true) : null,
                          child: Text(l10n.integrationRemove),
                        )
                      : OutlinedButton(
                          key: Key('integration.setup.${agent.name}'),
                          onPressed: cliFound ? () => onRun(false) : null,
                          child: Text(l10n.integrationSetUp),
                        ),
              ],
            ),
            for (final c in captions)
              Text(
                c,
                style: ShellxText.small.copyWith(
                  color: ShellxDesktopColors.textSecondary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
