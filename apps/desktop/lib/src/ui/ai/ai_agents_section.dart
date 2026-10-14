import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_acp/shellx_acp.dart' show AuthMethodTerminal;
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/shellx_ai.dart';

import '../../../l10n/app_localizations.dart';
import '../../ai/ai_agents.dart';
import '../../ai/ai_host_provider.dart';
import '../../ai/ai_runtimes.dart';
import '../../terminal/local_sessions_provider.dart' show homeDirectoryProvider;
import '../../terminal/terminal_tabs.dart';
import '../settings/pages/page_parts.dart';
import '../text_editing_shortcuts.dart';
import '../theme/shellx_desktop_theme.dart';
import 'ai_run_sheet.dart';

/// D12: "Delete all restore points" (every project's). A seam: widget tests
/// never delete folders under fake async.
final aiDeleteCheckpointsProvider = Provider<Future<void> Function()>(
  (ref) =>
      () => ref.read(aiHostProvider).checkpoints.deleteAll(),
);

/// D7's words for an agent's state ("Checking…" until its first check).
String aiAgentStatus(
  AppLocalizations l10n,
  AgentReadiness? r, {
  required bool needsLogin,
  required bool failed,
}) {
  if (failed) return l10n.aiAgentError;
  return switch (r) {
    null => l10n.aiAgentChecking,
    AgentReady() => needsLogin ? l10n.aiAgentNeedsLogin : l10n.aiAgentReady,
    AgentNeedsNode(:final required) => l10n.aiAgentNeedsNode(required),
    AgentNeedsInstall() || AgentNotFound() => l10n.aiAgentNotInstalled,
  };
}

/// V2-1 D7, D21, D23, D12: Settings › Agents › "AI interface".
/// - The Claude switch (`ai-agent-claude`).
/// - One row per agent with its state (Ready / Needs Node N / Not installed /
///   Needs sign-in / Error), and Install or Sign in, which run in the run
///   sheet (D8), never in a terminal tab. Sign in uses the session that
///   met the sign-in (only it knows the agent's methods).
/// - The default agent; custom agents (name, command, args, env) to add
///   and remove.
/// - How long restore points stay, and "Delete all restore points".
/// The agents are checked again when the section opens.
class AiAgentsSection extends ConsumerStatefulWidget {
  const AiAgentsSection({super.key});

  @override
  ConsumerState<AiAgentsSection> createState() => _AiAgentsSectionState();
}

class _AiAgentsSectionState extends ConsumerState<AiAgentsSection> {
  String? _note;

  @override
  void initState() {
    super.initState();
    // Not while building: the check runs the login shell and probes.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(ref.read(aiReadinessProvider.notifier).refresh());
    });
  }

  Future<void> _sheet(Widget Function(VoidCallback close) build) =>
      showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          child: SizedBox(
            width: 720,
            height: 440,
            child: build(() => Navigator.of(context).pop()),
          ),
        ),
      );

  Future<void> _install(AgentSpec agent, AgentCommand install) {
    final l10n = AppLocalizations.of(context);
    final folder = install.workingDirectory;
    return _sheet(
      (close) => AiRunSheet(
        title: l10n.aiRunSheetInstall(agent.name),
        command: install,
        workingDirectory: folder ?? ref.read(homeDirectoryProvider),
        makeFolder: folder != null,
        onDone: () {
          close();
          unawaited(ref.read(aiReadinessProvider.notifier).refresh());
        },
        onClose: close,
      ),
    );
  }

  /// A live session of [agentId] that is waiting for a sign-in.
  AiRuntime? _signingIn(String agentId) {
    final runtimes = ref.read(aiRuntimesProvider.notifier);
    for (final tab in ref.read(terminalTabsProvider).tabs) {
      final ai = tab.ai;
      if (ai == null || ai.agentId != agentId) continue;
      final runtime = runtimes.existing(ai.id);
      if (runtime?.state.phase == AgentPhase.needsAuth) return runtime;
    }
    return null;
  }

  Future<void> _signIn(AgentSpec agent) async {
    final l10n = AppLocalizations.of(context);
    final runtime = _signingIn(agent.id);
    final method = runtime?.state.authMethods
        .whereType<AuthMethodTerminal>()
        .firstOrNull;
    final command = method == null ? null : runtime!.loginCommand(method);
    if (runtime == null || command == null) return;
    await _sheet(
      (close) => AiRunSheet(
        title: l10n.aiRunSheetLogin(agent.name),
        command: command,
        workingDirectory: runtime.state.cwd,
        failureNote: l10n.aiLoginFailed,
        onDone: () {
          close();
          unawaited(runtime.retry());
        },
        onClose: close,
      ),
    );
  }

  Future<void> _deleteCheckpoints() async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.aiDeleteCheckpointsTitle),
        content: Text(l10n.aiDeleteCheckpointsBody),
        actions: [
          TextButton(
            key: const Key('ai.checkpoints.cancel'),
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            key: const Key('ai.checkpoints.delete'),
            style: destructiveButtonStyle(),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.aiDeleteCheckpoints),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(aiDeleteCheckpointsProvider)();
      if (mounted) setState(() => _note = l10n.aiDeleteCheckpointsDone);
    } on Object catch (error) {
      debugPrint('ShellX: restore points not deleted: ${error.runtimeType}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final agents = ref.watch(aiAgentsProvider);
    final readiness = ref.watch(aiReadinessProvider);
    final failed = ref.read(aiReadinessProvider.notifier).failed;
    final needsLogin = ref.watch(aiNeedsLoginProvider);
    final custom = {for (final c in ref.watch(aiCustomAgentsProvider)) c.id};
    final chosen = ref.watch(aiDefaultAgentProvider);
    // Keeps Settings in step with a session that meets a sign-in.
    ref.watch(terminalTabsProvider.select((t) => t.tabs.length));
    return Column(
      key: const Key('ai.settings'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(l10n.aiSettingsSection),
        settingWidget(settingById('ai-agent-claude')),
        for (final agent in agents)
          _AgentRow(
            agent: agent,
            status: aiAgentStatus(
              l10n,
              readiness[agent.id],
              needsLogin: needsLogin.contains(agent.id),
              failed: failed.contains(agent.id),
            ),
            readiness: readiness[agent.id],
            onInstall: switch (readiness[agent.id]) {
              AgentNeedsInstall(:final install?) => () => unawaited(
                _install(agent, install),
              ),
              _ => null,
            },
            onSignIn:
                needsLogin.contains(agent.id) && _signingIn(agent.id) != null
                ? () => unawaited(_signIn(agent))
                : null,
            onRemove: custom.contains(agent.id)
                ? () => unawaited(
                    ref.read(aiCustomAgentsProvider.notifier).remove(agent.id),
                  )
                : null,
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.aiDefaultAgent,
                  style: ShellxText.body.copyWith(
                    color: ShellxDesktopColors.textPrimary,
                  ),
                ),
              ),
              DropdownButton<String>(
                key: const Key('ai.defaultAgent'),
                value: chosen?.id,
                items: [
                  for (final a in agents)
                    DropdownMenuItem(value: a.id, child: Text(a.name)),
                ],
                onChanged: (id) {
                  if (id == null) return;
                  unawaited(
                    ref.read(aiDefaultAgentChoiceProvider.notifier).set(id),
                  );
                },
              ),
            ],
          ),
        ),
        const _CustomAgentForm(),
        settingWidget(settingById('ai-checkpoint-days')),
        ActionRow(
          key: const Key('ai.checkpoints'),
          label: l10n.aiDeleteCheckpoints,
          button: l10n.aiDeleteCheckpoints,
          caption: _note,
          onPressed: () => unawaited(_deleteCheckpoints()),
        ),
      ],
    );
  }
}

class _AgentRow extends StatelessWidget {
  const _AgentRow({
    required this.agent,
    required this.status,
    required this.readiness,
    required this.onInstall,
    required this.onSignIn,
    required this.onRemove,
  });

  final AgentSpec agent;
  final String status;
  final AgentReadiness? readiness;
  final VoidCallback? onInstall;
  final VoidCallback? onSignIn;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ready = readiness is AgentReady && onSignIn == null;
    final captions = [
      if (readiness case AgentNotFound(:final command, :final shimOnly)) ...[
        l10n.aiCommandMissing(command),
        if (shimOnly) l10n.aiCommandShimOnly,
      ],
      if (readiness case AgentNeedsInstall(install: null)) l10n.aiNoNpm,
    ];
    final small = ShellxText.small.copyWith(
      color: ShellxDesktopColors.textSecondary,
    );
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Padding(
        key: Key('ai.agent.${agent.id}'),
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
                    children: [
                      Text(
                        agent.name,
                        style: ShellxText.body.copyWith(
                          color: ShellxDesktopColors.textPrimary,
                        ),
                      ),
                      // An icon and a word: never colour alone.
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ExcludeSemantics(
                            child: Icon(
                              ready
                                  ? Icons.check_circle_outline
                                  : Icons.circle_outlined,
                              size: ShellxSizes.icon,
                              color: ready
                                  ? ShellxDesktopColors.ok
                                  : ShellxDesktopColors.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            status,
                            key: Key('ai.agent.status.${agent.id}'),
                            style: small,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (onInstall case final install?)
                  OutlinedButton(
                    key: Key('ai.agent.install.${agent.id}'),
                    onPressed: install,
                    child: Text(l10n.aiInstall),
                  ),
                if (onSignIn case final signIn?)
                  OutlinedButton(
                    key: Key('ai.agent.signin.${agent.id}'),
                    onPressed: signIn,
                    child: Text(l10n.aiAgentLogin),
                  ),
                if (onRemove case final remove?)
                  TextButton(
                    key: Key('ai.agent.remove.${agent.id}'),
                    onPressed: remove,
                    child: Text(l10n.aiCustomRemove),
                  ),
              ],
            ),
            for (final c in captions) Text(c, style: small),
          ],
        ),
      ),
    );
  }
}

/// D7 (4): a custom agent — any program that speaks ACP on stdin/stdout.
class _CustomAgentForm extends ConsumerStatefulWidget {
  const _CustomAgentForm();

  @override
  ConsumerState<_CustomAgentForm> createState() => _CustomAgentFormState();
}

class _CustomAgentFormState extends ConsumerState<_CustomAgentForm> {
  final _name = TextEditingController();
  final _command = TextEditingController();
  final _args = TextEditingController();
  final _env = TextEditingController();
  var _invalid = false;

  @override
  void dispose() {
    _name.dispose();
    _command.dispose();
    _args.dispose();
    _env.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final command = _command.text.trim();
    if (name.isEmpty || command.isEmpty) {
      setState(() => _invalid = true);
      return;
    }
    final env = <String, String>{};
    for (final line in _env.text.split('\n')) {
      final eq = line.indexOf('=');
      final key = eq <= 0 ? '' : line.substring(0, eq).trim();
      if (key.isNotEmpty) env[key] = line.substring(eq + 1);
    }
    await ref
        .read(aiCustomAgentsProvider.notifier)
        .add(
          name: name,
          command: command,
          args: [
            for (final a in _args.text.split('\n'))
              if (a.trim().isNotEmpty) a.trim(),
          ],
          env: env,
        );
    if (!mounted) return;
    _name.clear();
    _command.clear();
    _args.clear();
    _env.clear();
    setState(() => _invalid = false);
    unawaited(ref.read(aiReadinessProvider.notifier).refresh());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Widget field(
      TextEditingController c,
      String label,
      Key key, {
      int? lines,
    }) => Padding(
      padding: const EdgeInsets.only(top: ShellxSpace.s6),
      child: Shortcuts(
        shortcuts: textEditingShortcuts(),
        child: TextField(
          key: key,
          controller: c,
          minLines: lines,
          maxLines: lines == null ? 1 : lines + 2,
          decoration: InputDecoration(labelText: label, isDense: true),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.aiAddCustomAgent,
            style: ShellxText.body.copyWith(
              color: ShellxDesktopColors.textPrimary,
            ),
          ),
          field(_name, l10n.aiCustomName, const Key('ai.custom.name')),
          field(_command, l10n.aiCustomCommand, const Key('ai.custom.command')),
          field(
            _args,
            l10n.aiCustomArgs,
            const Key('ai.custom.args'),
            lines: 2,
          ),
          field(_env, l10n.aiCustomEnv, const Key('ai.custom.env'), lines: 2),
          if (_invalid)
            Padding(
              padding: const EdgeInsets.only(top: ShellxSpace.s4),
              child: Text(
                l10n.aiCustomInvalid,
                key: const Key('ai.custom.invalid'),
                style: ShellxText.small.copyWith(
                  color: ShellxDesktopColors.err,
                ),
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(top: ShellxSpace.s8),
              child: FilledButton(
                key: const Key('ai.custom.save'),
                onPressed: () => unawaited(_save()),
                child: Text(l10n.aiCustomSave),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
