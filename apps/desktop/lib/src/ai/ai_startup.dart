import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shellx_agent/shellx_agent.dart' show PtyFactory;
import 'package:shellx_ai/host.dart';

import '../config/config_controller.dart' show shellxConfigProvider;
import '../platform/process_tree.dart';
import 'ai_agents.dart';
import 'ai_host_provider.dart';
import 'ai_runtimes.dart';

/// V2-1 D8: the PTYs of the run sheet (sign-ins, installs). `main.dart`
/// gives it the app's own factory; tests a fake one.
final aiPtyFactoryProvider = Provider<PtyFactory>(
  (ref) => throw StateError('aiPtyFactoryProvider is set by main.dart'),
);

/// The app's AI host: agents and restore points under `<support>/ai` (D6,
/// D12). A stopped agent's whole process tree goes, and so does that of an
/// agent a crash left behind (§6): the package's defaults kill the process
/// alone.
AiHost buildAiHost({required String supportDir, required String version}) =>
    AiHost(
      supportDir: supportDir,
      clientVersion: version,
      killTree: killProcessTree,
      running: RunningAgents(
        File(p.join(supportDir, 'ai', 'running.json')),
        killPid: killProcessTreeByPid,
      ),
    );

/// After the first frame (smoothness: warm start), once per launch and never
/// skipped: V2-1a's `AiHost.launch` waits for this sweep. The agents a crash
/// left behind stop (§6), restore points older than `ai-checkpoint-days` go
/// (D12), then the login environment and every agent's readiness resolve,
/// so the first "New AI session" waits for none of it. Never throws.
Future<void> startAi(ProviderContainer container) async {
  final days = container.read(shellxConfigProvider).config.aiCheckpointDays;
  try {
    final stopped = await container
        .read(aiHostProvider)
        .startup(retention: Duration(days: days));
    if (stopped > 0) debugPrint('ShellX: stopped $stopped stray agent(s)');
  } on Object catch (error) {
    debugPrint('ShellX: AI startup failed: ${error.runtimeType}');
  }
  await container.read(aiReadinessProvider.notifier).warmUp();
}

/// [startAi], once the first frame is drawn: `main` calls it right after
/// `runApp`, so the crash sweep is in flight before anything a user can open
/// (a tab restored from the last run, ⌘⇧E at once) launches an agent; it does
/// not wait for the sign-in check, the restore or the first layout. [start]
/// is the one thing a test swaps. Never throws.
void startAiAfterFirstFrame(
  ProviderContainer container, {
  Future<void> Function(ProviderContainer container) start = startAi,
}) {
  WidgetsBinding.instance
    ..addPostFrameCallback((_) {
      unawaited(
        start(container).catchError((Object error) {
          debugPrint('ShellX: AI startup failed: ${error.runtimeType}');
        }),
      );
    })
    ..ensureVisualUpdate();
}

/// Quit (§6): every agent stops before the app exits.
Future<void> stopAi(ProviderContainer container) =>
    container.read(aiRuntimesProvider.notifier).stopAll();
