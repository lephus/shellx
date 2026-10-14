import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_ai/host.dart';

import '../config/config_controller.dart' show shellxConfigProvider;
import '../platform/settings_store.dart';
import '../terminal/agent_status.dart' show AgentKind;
import '../terminal/sidebar_workspaces.dart' show settingsStoreProvider;
import 'ai_host_provider.dart';

/// The catalog id of Claude (D21: `ai-agent-claude = off` hides it).
const kClaudeAgentId = 'claude';

/// V2-1 D7: an agent the user added in Settings › Agents — any program that
/// speaks ACP on stdin/stdout. Its environment is the user's own setting:
/// never logged ([toString] is `…`).
@immutable
final class CustomAgent {
  const CustomAgent({
    required this.id,
    required this.name,
    required this.command,
    this.args = const [],
    this.env = const {},
  });

  /// `custom-` and 8 hex digits.
  final String id;
  final String name;

  /// An absolute path, or a name found on the login shell's PATH.
  final String command;
  final List<String> args;
  final Map<String, String> env;

  AgentSpec get spec => AgentSpec(
    id: id,
    name: name,
    launch: CustomLaunch(command: command, args: args, env: env),
  );

  String encode() => jsonEncode({
    'id': id,
    'name': name,
    'command': command,
    'args': args,
    'env': env,
  });

  /// Null for anything that is not one (a hand edit, a damaged entry).
  static CustomAgent? decode(String raw) {
    try {
      final m = jsonDecode(raw);
      if (m is! Map<String, Object?>) return null;
      final id = m['id'];
      final name = m['name'];
      final command = m['command'];
      if (id is! String || !id.startsWith('custom-')) return null;
      if (name is! String || name.trim().isEmpty) return null;
      if (command is! String || command.trim().isEmpty) return null;
      final args = m['args'];
      final env = m['env'];
      return CustomAgent(
        id: id,
        name: name,
        command: command,
        args: args is List
            ? [for (final a in args) ?(a is String ? a : null)]
            : const [],
        env: env is Map
            ? {
                for (final e in env.entries)
                  if (e.key is String && e.value is String)
                    e.key as String: e.value as String,
              }
            : const {},
      );
    } on FormatException {
      return null;
    }
  }

  @override
  String toString() => '…';
}

/// V2-1 D7: the user's agents, kept in the settings store.
final aiCustomAgentsProvider =
    NotifierProvider<AiCustomAgents, List<CustomAgent>>(AiCustomAgents.new);

class AiCustomAgents extends Notifier<List<CustomAgent>> {
  @override
  List<CustomAgent> build() => [
    for (final raw
        in ref
            .watch(settingsStoreProvider)
            .getStrings(SettingKeys.aiCustomAgents))
      ?CustomAgent.decode(raw),
  ];

  /// Adds an agent called [name] that runs [command]; returns it.
  Future<CustomAgent> add({
    required String name,
    required String command,
    List<String> args = const [],
    Map<String, String> env = const {},
  }) async {
    final r = Random.secure();
    final hex = [
      for (var i = 0; i < 4; i++)
        r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
    final agent = CustomAgent(
      id: 'custom-$hex',
      name: name.trim(),
      command: command.trim(),
      args: args,
      env: env,
    );
    await _save([...state, agent]);
    return agent;
  }

  Future<void> remove(String id) => _save([
    for (final a in state)
      if (a.id != id) a,
  ]);

  Future<void> _save(List<CustomAgent> next) async {
    state = next;
    await ref.read(settingsStoreProvider).setStrings(
      SettingKeys.aiCustomAgents,
      [for (final a in next) a.encode()],
    );
  }
}

/// V2-1 D23: the agents of the AI interface in their default order —
/// Claude (unless `ai-agent-claude = off`, D21), Codex, Gemini CLI,
/// OpenCode — then the user's own.
final aiAgentsProvider = Provider<List<AgentSpec>>((ref) {
  final claude = ref.watch(
    shellxConfigProvider.select((s) => s.config.aiAgentClaude),
  );
  return [
    for (final a in kKnownAgents)
      if (claude || a.id != kClaudeAgentId) a,
    for (final c in ref.watch(aiCustomAgentsProvider)) c.spec,
  ];
});

AgentSpec? aiAgentById(List<AgentSpec> agents, String id) =>
    agents.where((a) => a.id == id).firstOrNull;

/// A12's kind for an AI agent; null for a custom agent (ruling B5).
AgentKind? agentKindOf(String agentId) => switch (agentId) {
  'claude' => AgentKind.claude,
  'codex' => AgentKind.codex,
  'gemini' => AgentKind.gemini,
  'opencode' => AgentKind.opencode,
  _ => null,
};

/// V2-1 D7/D23: how an agent's readiness is learned; tests swap it.
final aiReadinessSourceProvider =
    Provider<Future<AgentReadiness> Function(AgentSpec agent)>(
      (ref) => (agent) async {
        // Read when asked: a window without the AI host (a test of
        // something else) gets a failed check, never a broken provider.
        final host = ref.read(aiHostProvider);
        return host.resolver.resolve(agent, await host.env.resolve());
      },
    );

/// V2-1 D7/D23: each agent's readiness as last resolved; absent: not known
/// yet.
final aiReadinessProvider =
    NotifierProvider<AiReadiness, Map<String, AgentReadiness>>(AiReadiness.new);

class AiReadiness extends Notifier<Map<String, AgentReadiness>> {
  Future<void>? _warm;

  /// Agents whose last check failed: Settings › Agents says "Error".
  final failed = <String>{};

  @override
  Map<String, AgentReadiness> build() => const {};

  /// Smoothness (warm start): once per run, after the first frame. The login
  /// shell and every agent's checks run in the background, so the first
  /// "New AI session" never waits for them.
  Future<void> warmUp() => _warm ??= refresh();

  /// Resolves every offered agent again (Settings › Agents, after an
  /// install or a sign-in).
  Future<void> refresh() async {
    final source = ref.read(aiReadinessSourceProvider);
    for (final agent in ref.read(aiAgentsProvider)) {
      try {
        final r = await source(agent);
        if (!ref.mounted) return;
        failed.remove(agent.id);
        state = {...state, agent.id: r};
      } on Object catch (error) {
        debugPrint('ShellX: agent check failed: ${error.runtimeType}');
        if (!ref.mounted) return;
        failed.add(agent.id);
        state = {...state}..remove(agent.id);
      }
    }
  }
}

/// V2-1 D7: agents a session found signed out (`-32000`): Settings ›
/// Agents says "Needs sign-in" for them until a session opens.
final aiNeedsLoginProvider = NotifierProvider<AiNeedsLogin, Set<String>>(
  AiNeedsLogin.new,
);

class AiNeedsLogin extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void set(String agentId, bool needed) {
    if (state.contains(agentId) == needed) return;
    state = needed ? {...state, agentId} : ({...state}..remove(agentId));
  }
}

/// V2-1 D23: the user's choice of default agent (an id), kept in the
/// settings store; null: none.
final aiDefaultAgentChoiceProvider =
    NotifierProvider<AiDefaultAgentChoice, String?>(AiDefaultAgentChoice.new);

class AiDefaultAgentChoice extends Notifier<String?> {
  @override
  String? build() => ref
      .watch(settingsStoreProvider)
      .getStrings(SettingKeys.aiDefaultAgent)
      .firstOrNull;

  Future<void> set(String agentId) async {
    state = agentId;
    await ref.read(settingsStoreProvider).setStrings(
      SettingKeys.aiDefaultAgent,
      [agentId],
    );
  }
}

/// V2-1 D23: what "New AI session" starts — the user's choice while it is
/// offered, else the first agent known to be ready, else the first one
/// (Claude). Never a wait (smoothness: instant feedback); null only with
/// no agent at all.
final aiDefaultAgentProvider = Provider<AgentSpec?>((ref) {
  final agents = ref.watch(aiAgentsProvider);
  final chosen = ref.watch(aiDefaultAgentChoiceProvider);
  final readiness = ref.watch(aiReadinessProvider);
  return (chosen == null ? null : aiAgentById(agents, chosen)) ??
      agents.where((a) => readiness[a.id] is AgentReady).firstOrNull ??
      agents.firstOrNull;
});

/// V2-1 D11: the choices remembered for [agentId]'s new sessions.
Map<String, Object> rememberedConfig(SettingsStore store, String agentId) {
  final out = <String, Object>{};
  for (final line in store.getStrings(SettingKeys.aiAgentConfig)) {
    final parts = line.split('\t');
    if (parts.length != 3 || parts[0] != agentId) continue;
    try {
      final value = jsonDecode(parts[2]);
      if (value is String || value is bool) out[parts[1]] = value as Object;
    } on FormatException {
      continue;
    }
  }
  return out;
}

/// V2-1 D11: remembers [value] of [configId] for [agentId]'s new sessions.
/// "Bypass permissions" is never remembered (ruling R6, never auto-allow).
Future<void> rememberConfig(
  SettingsStore store,
  String agentId,
  String configId,
  Object value,
) async {
  if (value == 'bypassPermissions') return;
  final prefix = '$agentId\t$configId\t';
  await store.setStrings(SettingKeys.aiAgentConfig, [
    for (final line in store.getStrings(SettingKeys.aiAgentConfig))
      if (!line.startsWith(prefix)) line,
    '$prefix${jsonEncode(value)}',
  ]);
}
