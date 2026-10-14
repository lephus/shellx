import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/shellx_ai.dart';

import '../terminal/agent_status.dart';
import '../terminal/agent_status_notifier.dart';
import '../terminal/sidebar_workspaces.dart' show settingsStoreProvider;
import '../terminal/terminal_tabs.dart';
import 'ai_agents.dart';
import 'ai_host_provider.dart';

/// What an AI pane needs to start its agent (D6, D11, D14).
@immutable
final class AiRuntimeRequest {
  const AiRuntimeRequest({
    required this.agent,
    required this.cwd,
    this.resumeSessionId,
    this.preferredConfig = const {},
  });

  final AgentSpec agent;
  final String cwd;

  /// `session/load` this session (a restored or a history tab, D14/D15).
  final String? resumeSessionId;

  /// D11: the remembered choices (never "Bypass permissions", R6).
  final Map<String, Object> preferredConfig;

  @override
  String toString() => '…';
}

/// The tab label of one session (D2), asked of the session again only when
/// it can have changed. `AiSessionState.label` reads the whole first prompt
/// (spaces collapsed: ~2 ms for a 200 KB paste) and the tab asks after every
/// burst of streamed chunks. The label follows the session title and the
/// prompts; a prompt only grows while it is the last item (a replayed
/// message arrives in chunks), so the title, the number of items and the last
/// prompt's revision cover every change.
final class AiLabelCache {
  AiLabelCache([String? Function(AiSessionState state)? read])
    : _read = read ?? _label;

  static String? _label(AiSessionState state) => state.label;

  final String? Function(AiSessionState state) _read;
  ({String? title, int items, int prompt})? _key;
  String? _value;

  String? of(AiSessionState state) {
    final items = state.timeline.items;
    final last = items.isEmpty ? null : items.last;
    final key = (
      title: state.title,
      items: items.length,
      prompt: last is UserItem ? last.rev : -1,
    );
    if (key == _key) return _value;
    _key = key;
    return _value = _read(state);
  }
}

/// How a session's tab label is read; tests count the reads.
final aiLabelReaderProvider = Provider<String? Function(AiSessionState state)>(
  (ref) =>
      (state) => state.label,
);

/// Makes one AI pane's runtime. Tests swap it for runtimes over
/// `FakeLauncher` (`test/support/ai_fakes.dart`): no process, no login
/// shell, no git.
final aiRuntimeFactoryProvider =
    Provider<AiRuntime Function(AiRuntimeRequest request)>(
      (ref) =>
          (r) => ref
              .read(aiHostProvider)
              .runtime(
                agent: r.agent,
                cwd: r.cwd,
                resumeSessionId: r.resumeSessionId,
                preferredConfig: r.preferredConfig,
              ),
    );

/// The runtime of every AI pane: made on first use, stopped when its pane
/// goes, all stopped on quit. It also carries each runtime's news into the
/// rest of the app:
/// - the session title and id into the tab (sidebar, window, `layout.json`);
/// - its status into A12 (badges, A4 notifications, CLI events, D13).
final aiRuntimesProvider = NotifierProvider<AiRuntimes, void>(AiRuntimes.new);

class AiRuntimes extends Notifier<void> {
  final _runtimes = <int, AiRuntime>{};
  final _agentOf = <int, String>{};
  final _labels = <int, AiLabelCache>{};
  final _last = <int, AiStatus>{};
  final _listeners = <int, void Function()>{};
  final _queued = <int>{};
  final _stopping = <Future<void>>{};

  /// [stopAll] ran: the app is quitting, no runtime is made any more.
  var _stopped = false;

  @override
  void build() {
    _stopped = false;
    ref.listen<TerminalTabsState>(terminalTabsProvider, (_, next) {
      for (final id in [..._runtimes.keys]) {
        if (next.tabOfPane(id) == null) _drop(id);
      }
    });
    // D21: an agent switched off (`ai-agent-claude = off`) or removed stops
    // at once; its panes say why.
    ref.listen<List<AgentSpec>>(aiAgentsProvider, (_, next) {
      for (final id in [..._runtimes.keys]) {
        if (aiAgentById(next, _agentOf[id] ?? '') == null) _drop(id);
      }
    });
    // D3: a close asks first while a turn runs.
    ref.read(terminalTabsProvider.notifier).aiBusy = busy;
    ref.onDispose(() {
      for (final id in [..._runtimes.keys]) {
        _drop(id);
      }
    });
  }

  /// The runtime of AI pane [paneId] if one was made.
  AiRuntime? existing(int paneId) => _runtimes[paneId];

  /// The pane chose another folder (D5, §6): its runtime stops; the next
  /// [runtimeFor] makes one in the new folder.
  void forget(int paneId) => _drop(paneId);

  /// The runtime of AI pane [paneId], made (not started) on the first call.
  /// Null while the pane has no folder (D5), is gone, or its agent is not
  /// offered (switched off, removed), and once [stopAll] ran. Never call it
  /// while building: it may make a runtime.
  AiRuntime? runtimeFor(int paneId) {
    final made = _runtimes[paneId];
    if (made != null) return made;
    // Quitting: a runtime made during the wait would outlive the stop.
    if (_stopped) return null;
    final pane = ref
        .read(terminalTabsProvider)
        .tabOfPane(paneId)
        ?.aiPanes[paneId];
    final cwd = pane?.cwd;
    if (pane == null || cwd == null) return null;
    final agent = aiAgentById(ref.read(aiAgentsProvider), pane.agentId);
    if (agent == null) return null;
    final runtime = ref.read(aiRuntimeFactoryProvider)(
      AiRuntimeRequest(
        agent: agent,
        cwd: cwd,
        resumeSessionId: pane.sessionId,
        preferredConfig: rememberedConfig(
          ref.read(settingsStoreProvider),
          agent.id,
        ),
      ),
    );
    _runtimes[paneId] = runtime;
    _agentOf[paneId] = agent.id;
    _labels[paneId] = AiLabelCache(ref.read(aiLabelReaderProvider));
    runtime.onStatus = (status) => _report(paneId, status);
    void listener() => _queueSync(paneId);
    _listeners[paneId] = listener;
    runtime.state.addListener(listener);
    return runtime;
  }

  /// D3: tab [tabId]'s AI pane runs a turn.
  bool busy(int tabId) {
    final tab = ref
        .read(terminalTabsProvider)
        .tabs
        .where((t) => t.id == tabId)
        .firstOrNull;
    final ai = tab?.ai;
    return ai != null && _runtimes[ai.id]?.state.turn != null;
  }

  /// Quit (§6): every agent stops — stdin closed, 2 s, then its process
  /// tree. Completes when all have. The registry is closed from the first
  /// moment: [runtimeFor] makes no more.
  Future<void> stopAll() async {
    _stopped = true;
    for (final id in [..._runtimes.keys]) {
      _drop(id);
    }
    await Future.wait([..._stopping]);
  }

  void _drop(int paneId) {
    final runtime = _runtimes.remove(paneId);
    if (runtime == null) return;
    final listener = _listeners.remove(paneId);
    if (listener != null) runtime.state.removeListener(listener);
    runtime.onStatus = null;
    _agentOf.remove(paneId);
    _labels.remove(paneId);
    _last.remove(paneId);
    late final Future<void> stop;
    stop = runtime
        .dispose()
        .catchError((Object error) {
          debugPrint('ShellX: agent stop failed: ${error.runtimeType}');
        })
        .whenComplete(() => _stopping.remove(stop));
    _stopping.add(stop);
  }

  /// The tab follows its session: title and id. Once per burst of updates
  /// (a streaming answer touches the state hundreds of times a second).
  void _queueSync(int paneId) {
    if (!_queued.add(paneId)) return;
    scheduleMicrotask(() {
      _queued.remove(paneId);
      final runtime = _runtimes[paneId];
      if (runtime == null || !ref.mounted) return;
      final s = runtime.state;
      ref
          .read(terminalTabsProvider.notifier)
          .updateAiPane(
            paneId,
            (p) => p.copyWith(
              title: _labels[paneId]?.of(s) ?? p.title,
              sessionId: s.sessionId ?? p.sessionId,
            ),
          );
      final agentId = _agentOf[paneId];
      if (agentId == null) return;
      // D7: Settings › Agents says "Needs sign-in" until a session opens.
      final login = ref.read(aiNeedsLoginProvider.notifier);
      if (s.phase == AgentPhase.needsAuth) {
        login.set(agentId, true);
      } else if (s.phase == AgentPhase.ready) {
        login.set(agentId, false);
      }
    });
  }

  /// D13: the runtime's status, as A12 events for the pane.
  void _report(int paneId, AiStatus status) {
    final kind = agentKindOf(_agentOf[paneId] ?? '');
    if (kind == null || !ref.mounted) return; // B5: a custom agent
    final notifier = ref.read(agentStatusProvider.notifier);
    // The A12 clock, as every other event's: a test drives it, and it is the
    // one the long-turn threshold is measured on.
    final clock = ref.read(agentStatusClockProvider);
    void send(AgentEventKind k) => notifier.ingest(
      AgentEvent(pane: paneId, agent: kind, kind: k, at: clock()),
    );
    final last = _last[paneId];
    if (last == null && status != AiStatus.ended) send(AgentEventKind.start);
    switch (status) {
      case AiStatus.running:
        send(AgentEventKind.running);
      case AiStatus.needsInput:
        send(AgentEventKind.needsInput);
      case AiStatus.idle:
        // Review Focus 1: A12 keeps "needs input" through an idle; a
        // question the turn's end cancelled is no longer asked.
        if (last == AiStatus.needsInput) send(AgentEventKind.running);
        send(AgentEventKind.idle);
      case AiStatus.ended:
        send(AgentEventKind.end);
    }
    if (status == AiStatus.ended) {
      _last.remove(paneId);
    } else {
      _last[paneId] = status;
    }
  }
}
