import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shellx_acp/shellx_acp.dart' show Redacted;

import '../model/session_state.dart';
import 'agent_catalog.dart';
import 'agent_process.dart';
import 'agent_resolver.dart';
import 'ai_runtime.dart';
import 'checkpoint_store.dart';
import 'login_shell_env.dart';
import 'running_agents.dart';

/// The AI services of the app, one per app; the desktop builds it at
/// startup (V2-1b).
final class AiHost with Redacted {
  AiHost({
    required this.supportDir,
    required this.clientVersion,
    LoginShellEnv? env,
    AgentResolver? resolver,
    CheckpointStores? checkpoints,
    RunningAgents? running,
    KillTree killTree = killOnly,
    DateTime Function()? now,
  }) : env = env ?? LoginShellEnv(),
       resolver =
           resolver ??
           AgentResolver(agentsDir: p.join(supportDir, 'ai', 'agents')),
       checkpoints =
           checkpoints ??
           CheckpointStores(root: p.join(supportDir, 'ai', 'checkpoints')),
       running =
           running ??
           RunningAgents(File(p.join(supportDir, 'ai', 'running.json'))),
       _killTree = killTree,
       _now = now ?? DateTime.now;

  /// `<app support>` (macOS `~/Library/Application Support/pro.shellx.desktop`,
  /// Windows `%LOCALAPPDATA%\ShellX`).
  final String supportDir;
  final String clientVersion;
  final LoginShellEnv env;
  final AgentResolver resolver;
  final CheckpointStores checkpoints;
  final RunningAgents running;
  final KillTree _killTree;
  final DateTime Function() _now;

  /// The one [startup], and the sweep inside it that [launch] waits for.
  Future<int>? _startup;
  Future<int>? _sweep;

  /// Starts an agent process and keeps `running.json` in step (spec §6).
  ///
  /// Waits for the [startup] sweep if one was started: a sweep that ran beside
  /// a launch could take the new agent for a leftover and stop it. The record
  /// is best effort: without it only a crash cleanup is lost, and the agent
  /// still runs.
  Future<AgentChannel> launch(
    AgentCommand command, {
    required String cwd,
  }) async {
    final sweep = _sweep;
    if (sweep != null) {
      try {
        await sweep;
      } on Object {
        // A sweep that failed is startup's error; the launch goes on.
      }
    }
    final process = await AgentProcess.start(
      command,
      cwd: cwd,
      killTree: _killTree,
    );
    try {
      await running.add(
        RunningRecord(
          pid: process.pid,
          command: command.executable,
          startedAt: _now(),
        ),
      );
    } on Object {
      // The registry could not be written (a locked file, a full disk).
    }
    unawaited(
      process.exitCode
          .then((_) => running.remove(process.pid))
          .catchError((Object _) {}),
    );
    return process;
  }

  /// The runtime of one AI tab.
  AiRuntime runtime({
    required AgentSpec agent,
    required String cwd,
    String? resumeSessionId,
    Map<String, Object> preferredConfig = const {},
  }) => AiRuntime(
    state: AiSessionState(agentId: agent.id, agentName: agent.name, cwd: cwd),
    resolve: () async => resolver.resolve(agent, await env.resolve()),
    launch: launch,
    clientVersion: clientVersion,
    checkpoints: () async => checkpoints.forProject(cwd, await env.resolve()),
    resumeSessionId: resumeSessionId,
    preferredConfig: preferredConfig,
  );

  /// At app start: stop the agents a crash left behind (spec §6), then
  /// prune old checkpoints in the background (spec D12). Returns how many
  /// agents were stopped.
  ///
  /// Once per host: a second call returns the first one's result and does not
  /// sweep again (it would meet the agents this run has started). Call it
  /// before any tab can launch an agent; [launch] waits for it.
  Future<int> startup({Duration retention = const Duration(days: 14)}) =>
      _startup ??= _startupOnce(retention);

  Future<int> _startupOnce(Duration retention) async {
    final sweep = _sweep = running.sweep();
    final stopped = await sweep;
    unawaited(_prune(retention));
    return stopped;
  }

  Future<void> _prune(Duration retention) async {
    try {
      await checkpoints.pruneAll(retention, await env.resolve());
    } on Object {
      // Old checkpoints stay until the next start.
    }
  }
}
