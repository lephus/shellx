import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ui/window_focus.dart';
import 'agent_status.dart';
import 'terminal_tabs.dart';

/// The clock of the agent status (tests set it).
final agentStatusClockProvider = Provider<DateTime Function()>(
  (_) => DateTime.now,
);

/// A12 D9: the agent in each pane, by pane (session) id. Records whose
/// state is [AgentState.unknown] (restored, Task 9) are kept but never
/// shown ([agentStateVisible]).
final agentStatusProvider =
    NotifierProvider<AgentStatusNotifier, Map<int, AgentPane>>(
      AgentStatusNotifier.new,
    );

/// What a tab shows: the most urgent state of its panes' agents; null when
/// none shows.
final agentTabStateProvider = Provider.family<AgentState?, int>((ref, tabId) {
  final tab = ref
      .watch(terminalTabsProvider)
      .tabs
      .where((t) => t.id == tabId)
      .firstOrNull;
  if (tab == null) return null;
  final records = ref.watch(agentStatusProvider);
  final states = [
    for (final id in tab.panes.keys)
      if (records[id] case final r? when agentStateVisible(r.state)) r.state,
  ];
  return states.isEmpty ? null : aggregate(states);
});

/// A visible change of one pane's agent (what `agent.status` reports);
/// [state] null = the record is gone. Shows nothing in [toString].
@immutable
final class AgentStatusChange {
  const AgentStatusChange({
    required this.pane,
    required this.tab,
    required this.agent,
    required this.state,
  });
  final int pane;
  final int? tab;
  final AgentKind agent;
  final AgentState? state;

  @override
  String toString() => '…';
}

/// A12 D3, D9: applies [AgentEvent]s to the panes' records and keeps them
/// true: a record goes with its pane, follows a reconnect, a quiet pane
/// stops "running" after [kAgentQuietDecay], typing answers a question and
/// looking at a finished pane reads it. Never logs an event's contents.
class AgentStatusNotifier extends Notifier<Map<int, AgentPane>> {
  final _changes = StreamController<AgentStatusChange>.broadcast(sync: true);
  final _quiet = <int, Timer>{};
  final _lastOutput = <int, DateTime>{};
  final _recent = <int, List<DateTime>>{};

  /// Visible changes, for the event bus. Open as long as the notifier.
  Stream<AgentStatusChange> get changes => _changes.stream;

  DateTime get _now => ref.read(agentStatusClockProvider)();

  @override
  Map<int, AgentPane> build() {
    final tabs = ref.read(terminalTabsProvider.notifier);
    final subs = [
      tabs.paneReplacements.listen((r) => _moveRecord(r.from, r.to)),
      tabs.paneOutputs.listen(_output),
      tabs.userInputs.listen(_userInput),
    ];
    ref.listen<TerminalTabsState>(terminalTabsProvider, (_, _) => _review());
    ref.listen<bool>(windowFocusProvider, (_, _) => _review());
    ref.onDispose(() {
      for (final s in subs) {
        unawaited(s.cancel());
      }
      for (final t in _quiet.values) {
        t.cancel();
      }
      _quiet.clear();
      unawaited(_changes.close());
    });
    return const {};
  }

  /// D9 "watched": the window is in front, the pane's tab is selected and
  /// the pane is that tab's focused one.
  bool paneVisible(int pane) {
    final tabs = ref.read(terminalTabsProvider);
    final tab = tabs.tabOfSession(pane);
    return tab != null &&
        tabs.selectedId == tab.id &&
        tab.focusedPaneId == pane &&
        readWindowActive(ref.read);
  }

  /// Applies [e]. False when it was dropped: the pane is not a pane of this
  /// window (or its shell ended), or it sent more than
  /// [kAgentEventsPerSecond] in a second. Never throws.
  bool ingest(AgentEvent e) {
    if (!ref.mounted) return false;
    final pane = ref
        .read(terminalTabsProvider)
        .tabOfSession(e.pane)
        ?.panes[e.pane];
    if (pane == null || pane.exited) {
      return false;
    }
    final now = _now;
    final recent = _recent.putIfAbsent(e.pane, () => <DateTime>[])
      ..removeWhere((t) => now.difference(t) >= const Duration(seconds: 1));
    if (recent.length >= kAgentEventsPerSecond) return false;
    recent.add(now);
    final before = state[e.pane];
    final after = reduceAgent(before, e, paneVisible: paneVisible(e.pane));
    if (e.kind == AgentEventKind.running ||
        (after?.state == AgentState.running &&
            before?.state != AgentState.running)) {
      _lastOutput[e.pane] = now;
    }
    _store(e.pane, after);
    return true;
  }

  /// The human typed into [pane] (not a script's `send`): a question
  /// answered.
  void _userInput(int pane) {
    final p = state[pane];
    if (p == null || p.state != AgentState.needsInput) return;
    _store(pane, userTyped(p, _now));
  }

  // ---- internals ----------------------------------------------------------

  /// Writes pane [id]'s record ([next] null = none), reports a visible
  /// change and keeps the quiet timer right.
  void _store(int id, AgentPane? next) {
    final before = state[id];
    if (identical(before, next)) return;
    if (next == null) {
      state = {
        for (final e in state.entries)
          if (e.key != id) e.key: e.value,
      };
    } else {
      state = {...state, id: next};
    }
    _armQuiet(id, next);
    final was = _shown(before);
    final now = _shown(next);
    if (was != now || (now != null && before?.agent != next?.agent)) {
      final record = next ?? before!;
      _changes.add(
        AgentStatusChange(
          pane: id,
          tab: ref.read(terminalTabsProvider).tabOfSession(id)?.id,
          agent: record.agent,
          state: now,
        ),
      );
    }
  }

  static AgentState? _shown(AgentPane? p) =>
      p != null && agentStateVisible(p.state) ? p.state : null;

  void _armQuiet(int id, AgentPane? p) {
    if (p == null || p.state != AgentState.running) {
      _quiet.remove(id)?.cancel();
      _lastOutput.remove(id);
      return;
    }
    if (_quiet[id]?.isActive ?? false) return;
    _lastOutput.putIfAbsent(id, () => _now);
    _quiet[id] = Timer(kAgentQuietDecay, () => _decay(id));
  }

  void _output(int id) {
    if (state[id]?.state == AgentState.running) _lastOutput[id] = _now;
  }

  /// The pane may be silent: stops "running" when it has been for the whole
  /// of [kAgentQuietDecay], else waits for the rest.
  void _decay(int id) {
    _quiet.remove(id);
    final p = state[id];
    if (!ref.mounted || p == null || p.state != AgentState.running) return;
    final now = _now;
    final quiet = now.difference(_lastOutput[id] ?? p.since);
    if (quiet >= kAgentQuietDecay) {
      _store(id, quietFor(p, now));
    } else {
      _quiet[id] = Timer(kAgentQuietDecay - quiet, () => _decay(id));
    }
  }

  /// A8 D22: a reconnect gave pane [from] the id [to]; nothing visible
  /// changes.
  void _moveRecord(int from, int to) {
    final p = state[from];
    _recent.remove(from);
    if (p == null) return;
    _quiet.remove(from)?.cancel();
    final out = _lastOutput.remove(from);
    state = {
      for (final e in state.entries)
        if (e.key != from) e.key: e.value,
      to: p,
    };
    if (out != null) _lastOutput[to] = out;
    _armQuiet(to, p);
  }

  /// Panes that went (or whose shell ended) lose their record; a finished
  /// agent in a pane now in view is read.
  void _review() {
    if (!ref.mounted || state.isEmpty) return;
    final tabs = ref.read(terminalTabsProvider);
    for (final id in state.keys.toList()) {
      final pane = tabs.tabOfSession(id)?.panes[id];
      // A lost server pane keeps its record: a reconnect gives it a new id
      // and the record follows (A8 D22).
      if (pane == null || (pane.exited && !pane.canReconnect)) {
        _store(id, null);
        _recent.remove(id);
        continue;
      }
      final p = state[id];
      if (p != null && p.state == AgentState.done && paneVisible(id)) {
        _store(id, paneSeen(p, _now));
      }
    }
  }
}
