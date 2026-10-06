import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A7 D27: how long the "Agent" chip stays after the last command.
const kAgentMarkFor = Duration(seconds: 10);

/// A7 D27: at most one spoken announcement per this long.
const kAgentAnnounceGap = Duration(seconds: 60);

final agentMarksClockProvider = Provider<DateTime Function()>(
  (_) => DateTime.now,
);

@immutable
final class AgentMarksState {
  const AgentMarksState({this.tabs = const {}, this.panes = const {}});

  /// When the command line last acted on each tab / pane.
  final Map<int, DateTime> tabs;
  final Map<int, DateTime> panes;

  bool tabActive(int id, DateTime now) => _active(tabs[id], now);
  bool paneActive(int id, DateTime now) => _active(panes[id], now);

  static bool _active(DateTime? at, DateTime now) =>
      at != null && now.difference(at) < kAgentMarkFor;
}

final agentMarksProvider = NotifierProvider<AgentMarks, AgentMarksState>(
  AgentMarks.new,
);

/// A7 D27: the "Agent" chip on a tab's sidebar row and a pane's header for
/// [kAgentMarkFor] after the last command-line action on them; expired
/// entries are dropped.
class AgentMarks extends Notifier<AgentMarksState> {
  Timer? _expiry;
  DateTime? _lastAnnounce;

  /// Set by the window: announces "Agent is controlling {tab}", at most
  /// once per [kAgentAnnounceGap].
  void Function(int tabId)? onAnnounce;

  DateTime get _now => ref.read(agentMarksClockProvider)();

  @override
  AgentMarksState build() {
    ref.onDispose(() => _expiry?.cancel());
    return const AgentMarksState();
  }

  void touch({required int tab, int? pane}) {
    final now = _now;
    state = AgentMarksState(
      tabs: {...state.tabs, tab: now},
      panes: {...state.panes, ?pane: now},
    );
    final last = _lastAnnounce;
    if (last == null || now.difference(last) >= kAgentAnnounceGap) {
      _lastAnnounce = now;
      onAnnounce?.call(tab);
    }
    _expiry?.cancel();
    _expiry = Timer(kAgentMarkFor, _prune);
  }

  void _prune() {
    final now = _now;
    Map<int, DateTime> live(Map<int, DateTime> marks) => {
      for (final e in marks.entries)
        if (AgentMarksState._active(e.value, now)) e.key: e.value,
    };
    state = AgentMarksState(tabs: live(state.tabs), panes: live(state.panes));
    if (state.tabs.isNotEmpty || state.panes.isNotEmpty) {
      _expiry = Timer(const Duration(seconds: 1), _prune);
    }
  }
}
