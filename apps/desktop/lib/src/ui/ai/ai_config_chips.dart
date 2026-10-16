import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_acp/shellx_acp.dart';

import '../../../l10n/app_localizations.dart';
import '../../ai/ai_agents.dart' show kClaudeAgentId, rememberConfig;
import '../../ai/ai_no_approval.dart';
import '../../terminal/sidebar_workspaces.dart' show settingsStoreProvider;
import '../terminal/shellx_menu.dart';
import '../theme/shellx_desktop_theme.dart';
import 'ai_scope.dart';

/// The mode that lets an agent act without asking (D11, ruling R6).
const String kAiBypassMode = 'bypassPermissions';

/// D11: Claude's known mode ids in the app's words; any other agent's
/// modes keep the agent's own names.
String aiModeName(
  AppLocalizations l10n, {
  required String agentId,
  required String id,
  required String name,
}) => agentId != kClaudeAgentId
    ? name
    : switch (id) {
        'default' => l10n.aiModeDefault,
        'acceptEdits' => l10n.aiModeAcceptEdits,
        'plan' => l10n.aiModePlan,
        'auto' => l10n.aiModeAuto,
        kAiBypassMode => l10n.aiModeBypass,
        _ => name,
      };

bool _isMode(ConfigOption o) => o.category == 'mode' || o.id == 'mode';

/// D11: "Turn on “Bypass permissions”?" — Cancel (the first focus) / Turn
/// on (destructive). True: turn it on.
Future<bool> confirmAiBypass(BuildContext context, String agent) async {
  final on = await showDialog<bool>(
    context: context,
    builder: (context) {
      final l10n = AppLocalizations.of(context);
      return AlertDialog(
        title: Text(l10n.aiBypassTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.aiBypassConfirm(agent)),
            const SizedBox(height: ShellxSpace.s8),
            Text(
              l10n.aiBypassNote,
              style: ShellxText.small.copyWith(
                color: ShellxDesktopColors.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            key: const Key('ai.bypass.cancel'),
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            key: const Key('ai.bypass.on'),
            style: destructiveButtonStyle(),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.aiBypassTurnOn),
          ),
        ],
      );
    },
  );
  return on ?? false;
}

/// D11, spec §4.1: the session's settings as chips in the composer's row —
/// mode, model, thinking and the agent's others (`configOptions`), or the
/// legacy `modes`. A choice goes to the agent (`session/set_config_option`
/// or `session/set_mode`) and is remembered for the agent's next sessions,
/// except a mode that acts without asking ("Bypass permissions", Codex's
/// "full-access", Gemini's "yolo": `aiIsNoApprovalMode`), which always asks
/// first and is never remembered (R6). Rebuilt only when the options change.
class AiConfigChips extends ConsumerWidget {
  const AiConfigChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = AiPaneScope.of(context);
    return AiSelect<(List<ConfigOption>?, SessionModes?)>(
      frames: scope.frames,
      select: (s) => (s.configOptions, s.modes),
      builder: (context, v) {
        final (options, modes) = v;
        final chips = <Widget>[
          if (options != null)
            for (final o in options)
              if (o.kind != ConfigKind.other) _OptionChip(option: o),
          if (options == null && modes != null) _ModeChip(modes: modes),
        ];
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: chips),
        );
      },
    );
  }
}

Offset _below(BuildContext context) {
  final box = context.findRenderObject()! as RenderBox;
  return box.localToGlobal(Offset(0, box.size.height));
}

Widget _chip(String label, VoidCallback onPressed, Key key) => TextButton(
  key: key,
  style: TextButton.styleFrom(
    visualDensity: VisualDensity.compact,
    padding: const EdgeInsets.symmetric(horizontal: ShellxSpace.s6),
    foregroundColor: ShellxDesktopColors.textSecondary,
  ),
  onPressed: onPressed,
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: ShellxText.caption),
      const Icon(Icons.expand_more, size: 12),
    ],
  ),
);

class _OptionChip extends ConsumerWidget {
  const _OptionChip({required this.option});
  final ConfigOption option;

  String _choiceName(AppLocalizations l10n, String agentId, ConfigChoice c) =>
      _isMode(option)
      ? aiModeName(l10n, agentId: agentId, id: c.value, name: c.name)
      : c.name;

  String _label(AppLocalizations l10n, String agentId) {
    final o = option;
    if (o.kind == ConfigKind.boolean) {
      return l10n.aiConfigOther(
        o.name,
        o.currentValue == true ? l10n.aiSettingOn : l10n.aiSettingOff,
      );
    }
    final current = o.choices.where((c) => c.value == o.currentValue);
    final name = current.isEmpty
        ? '${o.currentValue ?? ''}'
        : _choiceName(l10n, agentId, current.first);
    return switch (o.category) {
      _ when _isMode(o) => name,
      'model' => l10n.aiConfigModel(name),
      'thought_level' => l10n.aiConfigEffort(name),
      _ => l10n.aiConfigOther(o.name, name),
    };
  }

  Future<void> _apply(
    BuildContext context,
    WidgetRef ref,
    AiPaneScope scope,
    Object value,
  ) async {
    if (aiTurnsOnNoApproval(configId: option.id, value: value) &&
        !await confirmAiBypass(context, scope.state.agentName)) {
      return;
    }
    try {
      await scope.runtime.setConfig(option.id, value);
      await rememberConfig(
        ref.read(settingsStoreProvider),
        scope.state.agentId,
        option.id,
        value,
      );
    } on Object catch (error) {
      debugPrint('ShellX: setting not applied: ${error.runtimeType}');
    }
  }

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final scope = AiPaneScope.of(context);
    final o = option;
    if (o.kind == ConfigKind.boolean) {
      return _apply(context, ref, scope, o.currentValue != true);
    }
    final agentId = scope.state.agentId;
    final choice = await showShellxMenu<String>(
      context: context,
      at: _below(context),
      entries: [
        for (final c in o.choices)
          ShellxMenuEntry(
            key: Key('ai.config.${o.id}.${c.value}'),
            value: c.value,
            label: _choiceName(l10n, agentId, c),
            checked: c.value == o.currentValue,
          ),
      ],
    );
    if (choice == null || choice == o.currentValue || !context.mounted) return;
    await _apply(context, ref, scope, choice);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final agentId = AiPaneScope.of(context).state.agentId;
    return Builder(
      builder: (context) => _chip(
        _label(l10n, agentId),
        () => unawaited(_pick(context, ref)),
        Key('ai.config.${option.id}'),
      ),
    );
  }
}

/// An agent with legacy `modes` only (D11): `session/set_mode`.
class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.modes});
  final SessionModes modes;

  Future<void> _pick(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final scope = AiPaneScope.of(context);
    final agentId = scope.state.agentId;
    final choice = await showShellxMenu<String>(
      context: context,
      at: _below(context),
      entries: [
        for (final m in modes.available)
          ShellxMenuEntry(
            key: Key('ai.config.mode.${m.id}'),
            value: m.id,
            label: aiModeName(l10n, agentId: agentId, id: m.id, name: m.name),
            checked: m.id == modes.currentModeId,
          ),
      ],
    );
    if (choice == null || choice == modes.currentModeId || !context.mounted) {
      return;
    }
    if (aiIsNoApprovalMode(choice) &&
        !await confirmAiBypass(context, scope.state.agentName)) {
      return;
    }
    try {
      await scope.runtime.setMode(choice);
    } on Object catch (error) {
      debugPrint('ShellX: mode not applied: ${error.runtimeType}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final agentId = AiPaneScope.of(context).state.agentId;
    final current = modes.available
        .where((m) => m.id == modes.currentModeId)
        .firstOrNull;
    return _chip(
      aiModeName(
        l10n,
        agentId: agentId,
        id: modes.currentModeId,
        name: current?.name ?? modes.currentModeId,
      ),
      () => unawaited(_pick(context)),
      const Key('ai.config.mode'),
    );
  }
}
