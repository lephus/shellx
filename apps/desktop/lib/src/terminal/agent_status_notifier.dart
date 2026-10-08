import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:shellx_agent/shellx_agent.dart'
    show SessionNotice, SessionNoticeKind;

import '../agent/notify_threshold.dart';
import '../config/config_controller.dart' show shellxConfigProvider;
import '../integrations/agent_command_runner.dart';
import '../ui/window_focus.dart';
import 'agent_names.dart';
import 'agent_notify_policy.dart';
import 'agent_status.dart';
import 'local_sessions_provider.dart';
import 'sidebar_workspaces.dart' show settingsStoreProvider;
import 'terminal_tabs.dart';

/// The clock of the agent status (tests set it).
final agentStatusClockProvider = Provider<DateTime Function()>(
  (_) => DateTime.now,
);

/// A12 D9: the agent in each pane, by pane (session) id. Records whose
/// state is [AgentState.unknown] (restored, Task 9) are kept but never
/// shown ([agentStateVisible]).
/// D12: a tab speaks a question at most this often.
const Duration kAgentAnnounceGap = Duration(seconds: 60);

/// A reordered event older than an `end` is ignored for this long.
const Duration kAgentEndedMemory = Duration(seconds: 5);

final agentStatusProvider =
    NotifierProvider<AgentStatusNotifier, Map<int, AgentPane>>(
      AgentStatusNotifier.new,
    );

/// What a badge shows: the state and whose it is.
typedef AgentBadgeInfo = ({AgentState state, AgentKind agent});

AgentBadgeInfo? _badgeOf(AgentPane? r) =>
    r != null && agentStateVisible(r.state)
    ? (state: r.state, agent: r.agent)
    : null;

/// What a pane's header shows; null when it shows nothing.
final agentPaneBadgeProvider = Provider.family<AgentBadgeInfo?, int>(
  (ref, pane) =>
      _badgeOf(ref.watch(agentStatusProvider.select((m) => m[pane]))),
);

/// What a tab's row shows: the most urgent of its panes' agents (ties go
/// to the first pane); null when none shows.
final agentTabBadgeProvider = Provider.family<AgentBadgeInfo?, int>((
  ref,
  tabId,
) {
  final tab = ref
      .watch(terminalTabsProvider)
      .tabs
      .where((t) => t.id == tabId)
      .firstOrNull;
  if (tab == null) return null;
  final records = ref.watch(agentStatusProvider);
  AgentBadgeInfo? best;
  for (final id in tab.paneOrder) {
    final b = _badgeOf(records[id]);
    if (b == null) continue;
    if (best == null || aggregate([best.state, b.state]) != best.state) {
      best = b;
    }
  }
  return best;
});

/// What a tab shows: the most urgent state of its panes' agents; null when
/// none shows.
final agentTabStateProvider = Provider.family<AgentState?, int>(
  (ref, tabId) => ref.watch(agentTabBadgeProvider(tabId))?.state,
);

/// A12 D12: tabs whose row may speak a question now (a live region). A
/// tab speaks at most once per [kAgentAnnounceGap]; the flag stays while a
/// pane of the tab still waits for the answer.
final agentLiveTabsProvider = NotifierProvider<AgentLiveTabs, Set<int>>(
  AgentLiveTabs.new,
);

class AgentLiveTabs extends Notifier<Set<int>> {
  @override
  Set<int> build() => const {};

  void set(int tab, bool live) {
    if (state.contains(tab) == live) return;
    state = live ? {...state, tab} : ({...state}..remove(tab));
  }
}

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

  /// D10: when each pane last had a hook event (the OSC merge), and when
  /// it last got a hook notification (the 5 s gap, by event time).
  final _hookAt = <int, DateTime>{};
  final _noticeAt = <int, DateTime>{};

  /// D10: the notifications made here, to tell them from a program's own
  /// when they come back on the notice stream.
  final _own = <int, List<({String title, String body, DateTime at})>>{};

  /// D10: when a pane's own program last sent an OSC / bell notice (the
  /// merge when it comes before the hook event).
  final _oscAt = <int, DateTime>{};

  /// A pane's last `end`: a reordered older event must not bring it back.
  final _ended = <int, DateTime>{};
  final _endedEventAt = <int, DateTime>{};

  /// D12: when each tab last spoke a question.
  final _spoke = <int, DateTime>{};

  /// Panes with any bookkeeping left (tests: nothing outlives its pane).
  @visibleForTesting
  Set<int> get trackedPanes => {
    ...state.keys,
    ..._recent.keys,
    ..._hookAt.keys,
    ..._noticeAt.keys,
    ..._own.keys,
    ..._oscAt.keys,
    ..._ended.keys,
    ..._lastOutput.keys,
    ..._quiet.keys,
  };

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
    final ended = _ended[e.pane];
    if (ended != null) {
      if (now.difference(ended) >= kAgentEndedMemory) {
        _ended.remove(e.pane);
      } else if (e.kind != AgentEventKind.start &&
          e.at.isBefore(_endedEventAt[e.pane]!)) {
        return true; // a straggler of the session that ended
      }
    }
    final before = state[e.pane];
    final visible = paneVisible(e.pane);
    final after = reduceAgent(before, e, paneVisible: visible);
    if (e.kind == AgentEventKind.running ||
        (after?.state == AgentState.running &&
            before?.state != AgentState.running)) {
      _lastOutput[e.pane] = now;
    }
    _hookAt[e.pane] = now;
    if (e.kind == AgentEventKind.end && after == null) {
      _ended[e.pane] = now;
      _endedEventAt[e.pane] = e.at;
    } else if (e.kind == AgentEventKind.start) {
      _ended.remove(e.pane);
      _endedEventAt.remove(e.pane);
    }
    _cause = e;
    try {
      _store(e.pane, after);
    } finally {
      _cause = null;
    }
    // An event that came late changed nothing and tells nothing.
    if (before == null || !e.at.isBefore(before.lastEventAt)) {
      _tell(e, before, visible);
    }
    return true;
  }

  /// D10: a notification through the same entry as `shellx notify --pane`,
  /// so the ring, the focused-pane rule, the 20 a minute and the phone
  /// push are the ones of A4.
  void _tell(AgentEvent e, AgentPane? before, bool visible) {
    final decision = AgentNotifyPolicy.decide(
      e,
      before,
      paneVisible: visible,
      threshold: notifyThreshold(ref.read(settingsStoreProvider)),
      lastNoticeAt: _noticeAt[e.pane],
    );
    final kind = decision.text;
    if (kind == null) return;
    // The program's own OSC / bell a moment ago already told it.
    final osc = _oscAt[e.pane];
    if (osc != null && _now.difference(osc) < kAgentOscMerge) return;
    final l10n = ref.read(appL10nProvider);
    final name = agentDisplayName(l10n, e.agent);
    final body = switch (kind) {
      AgentNoticeText.needsInput =>
        decision.message ?? l10n.agentNotifyNeedsInput(name),
      AgentNoticeText.done => l10n.agentNotifyDone(name),
      AgentNoticeText.message => decision.message!,
    };
    _noticeAt[e.pane] = e.at;
    final now = _now;
    final own = _own.putIfAbsent(e.pane, () => [])
      ..removeWhere((o) => now.difference(o.at) >= kAgentNoticeGap)
      ..add((title: name, body: body, at: now));
    if (!ref
        .read(localSessionsProvider)
        .notify(e.pane, title: name, body: body)) {
      own.removeLast(); // nobody will send it back
    }
  }

  /// D10: whether [n], a notice from the pane's own program (OSC 9 / 99 /
  /// 777 or the bell), is the news a hook event gave in the last
  /// [kAgentOscMerge]. The notice made by [_tell] itself is let through.
  bool swallowNotice(SessionNotice n) {
    if (n.kind == SessionNoticeKind.command) return false;
    final now = _now;
    final own = _own[n.sessionId];
    if (own != null && n.kind == SessionNoticeKind.message) {
      own.removeWhere((o) => now.difference(o.at) >= kAgentNoticeGap);
      final i = own.indexWhere((o) => o.title == n.title && o.body == n.body);
      if (i >= 0) {
        own.removeAt(i);
        return false;
      }
    }
    _oscAt[n.sessionId] = now;
    final hook = _hookAt[n.sessionId];
    return hook != null && now.difference(hook) < kAgentOscMerge;
  }

  /// A12 D13–D14: the record of a session saved before a restart: state
  /// [AgentState.unknown] (never shown), so a later snapshot saves the id
  /// again and the next event of the real agent replaces it. Nothing when
  /// the pane has a record already or is not a live pane of this window.
  void seedRestored(int pane, AgentKind agent, String session) {
    if (!ref.mounted || state.containsKey(pane)) return;
    final p = ref.read(terminalTabsProvider).tabOfSession(pane)?.panes[pane];
    if (p == null || p.exited || !isValidSessionId(session)) return;
    _store(
      pane,
      AgentPane(
        agent: agent,
        state: AgentState.unknown,
        since: _now,
        // Older than any event: the first one applies.
        lastEventAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        session: session,
      ),
    );
  }

  /// The user declined the offer: forgets a restored record, never a real
  /// one.
  void dropRestored(int pane) {
    if (state[pane]?.state == AgentState.unknown) _store(pane, null);
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
    _updateLive(id, before, next);
    final was = _shown(before);
    final now = _shown(next);
    if (was != now || (now != null && before?.agent != next?.agent)) {
      final record = next ?? before!;
      final tab = ref.read(terminalTabsProvider).tabOfSession(id)?.id;
      _changes.add(
        AgentStatusChange(pane: id, tab: tab, agent: record.agent, state: now),
      );
      _runUserCommand(id, tab, record.agent, now);
    }
  }

  /// The event being applied (its words go to the user's command).
  AgentEvent? _cause;

  /// A12 D17: the user's `agent-event-command`, on a visible change. The
  /// runner checks the approval, the limits and the environment; nothing
  /// here reads the command's text.
  void _runUserCommand(int pane, int? tab, AgentKind agent, AgentState? state) {
    if (!ref.mounted) return;
    if (ref.read(shellxConfigProvider).config.agentEventCommand.isEmpty) return;
    final event = switch (state) {
      null => 'end',
      AgentState.running => 'running',
      AgentState.needsInput => 'needs_input',
      AgentState.idle => 'idle',
      AgentState.done => 'done',
      AgentState.unknown => null,
    };
    if (event == null) return;
    ref
        .read(agentCommandRunnerProvider)
        .emit(
          AgentCommandEvent(
            event: event,
            agent: agent.name,
            pane: pane,
            tab: tab,
            status: state == null ? 'none' : event,
            message: _cause?.message,
          ),
        );
  }

  /// D12: a question is spoken by its tab's row, at most once a minute.
  void _updateLive(int id, AgentPane? before, AgentPane? next) {
    final tab = ref.read(terminalTabsProvider).tabOfSession(id);
    if (tab == null) return;
    final live = ref.read(agentLiveTabsProvider.notifier);
    final asks = next?.state == AgentState.needsInput;
    if (asks && before?.state != AgentState.needsInput) {
      final now = _now;
      final last = _spoke[tab.id];
      if (last == null || now.difference(last) >= kAgentAnnounceGap) {
        _spoke[tab.id] = now;
        live.set(tab.id, true);
      }
    } else if (!asks) {
      final others = tab.panes.keys.any(
        (p) => p != id && state[p]?.state == AgentState.needsInput,
      );
      if (!others) live.set(tab.id, false);
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
    _moveBook(_recent, from, to);
    _moveBook(_hookAt, from, to);
    _moveBook(_noticeAt, from, to);
    _moveBook(_own, from, to);
    _moveBook(_oscAt, from, to);
    _moveBook(_ended, from, to);
    _moveBook(_endedEventAt, from, to);
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

  static void _moveBook<T>(Map<int, T> book, int from, int to) {
    final v = book.remove(from);
    if (v != null) book[to] = v;
  }

  void _forget(int id) {
    if (state.containsKey(id)) _store(id, null);
    _quiet.remove(id)?.cancel();
    _lastOutput.remove(id);
    _recent.remove(id);
    _hookAt.remove(id);
    _noticeAt.remove(id);
    _own.remove(id);
    _oscAt.remove(id);
    _ended.remove(id);
    _endedEventAt.remove(id);
  }

  /// Panes that went (or whose shell ended) lose their record; a finished
  /// agent in a pane now in view is read.
  void _review() {
    if (!ref.mounted) return;
    final tabs = ref.read(terminalTabsProvider);
    // Bookkeeping lives as long as its pane (a lost server pane included).
    for (final id in trackedPanes) {
      if (tabs.tabOfSession(id) == null) _forget(id);
    }
    for (final id in _spoke.keys.toList()) {
      if (!tabs.tabs.any((t) => t.id == id)) {
        _spoke.remove(id);
        ref.read(agentLiveTabsProvider.notifier).set(id, false);
      }
    }
    for (final id in state.keys.toList()) {
      final pane = tabs.tabOfSession(id)?.panes[id];
      // A lost server pane keeps its record: a reconnect gives it a new id
      // and the record follows (A8 D22).
      if (pane == null || (pane.exited && !pane.canReconnect)) {
        _store(id, null);
        _forget(id);
        continue;
      }
      final p = state[id];
      if (p != null && p.state == AgentState.done && paneVisible(id)) {
        _store(id, paneSeen(p, _now));
      }
    }
  }
}
