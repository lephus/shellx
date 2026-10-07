import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../terminal/sidebar_workspaces.dart';
import '../terminal/terminal_tabs.dart';
import 'remote_state.dart';

/// Where one lost pane stands in its retries (UI-A8 §3.3 strip).
@immutable
final class RetryInfo {
  const RetryInfo({
    required this.attempt,
    required this.firstLost,
    this.nextAt,
    this.retrying = false,
    this.stopped = false,
  });

  final int attempt;
  final DateTime firstLost;

  /// When the next attempt starts (the strip's countdown); null while one
  /// runs or after giving up.
  final DateTime? nextAt;
  final bool retrying;

  /// D20: 30 minutes passed — only "Reconnect" now.
  final bool stopped;

  RetryInfo copyWith({
    int? attempt,
    Object? nextAt = _keep,
    bool? retrying,
    bool? stopped,
  }) => RetryInfo(
    attempt: attempt ?? this.attempt,
    firstLost: firstLost,
    nextAt: identical(nextAt, _keep) ? this.nextAt : nextAt as DateTime?,
    retrying: retrying ?? this.retrying,
    stopped: stopped ?? this.stopped,
  );

  @override
  bool operator ==(Object other) =>
      other is RetryInfo &&
      other.attempt == attempt &&
      other.firstLost == firstLost &&
      other.nextAt == nextAt &&
      other.retrying == retrying &&
      other.stopped == stopped;

  @override
  int get hashCode =>
      Object.hash(attempt, firstLost, nextAt, retrying, stopped);
}

const Object _keep = Object();

final reconnectClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

final sshReconnectorProvider =
    NotifierProvider<SshReconnector, Map<int, RetryInfo>>(SshReconnector.new);

/// A8 D20: lost SSH panes come back by themselves — 3, 6, 12, 24, 48, 60…
/// seconds, at once after a wake, for 30 minutes; panes that never
/// connected only on request. Keyed by the pane's current session id.
class SshReconnector extends Notifier<Map<int, RetryInfo>> {
  static const delays = [3, 6, 12, 24, 48, 60];
  static const giveUpAfter = Duration(minutes: 30);

  final _timers = <int, Timer>{};

  /// Ids whose reconnect is under way: the old pane still looks lost until
  /// the new session takes its place, which is not "the attempt failed".
  final _inFlight = <int>{};

  DateTime _now() => ref.read(reconnectClockProvider)();
  TerminalTabs get _tabs => ref.read(terminalTabsProvider.notifier);

  @override
  Map<int, RetryInfo> build() {
    final tabs = _tabs;
    final sub = tabs.paneReplacements.listen(_replaced);
    tabs.setReconnectRequest(reconnectNow);
    ref.listen<TerminalTabsState>(terminalTabsProvider, (_, next) {
      _scan(next);
    });
    ref.onDispose(() {
      unawaited(sub.cancel());
      tabs.clearReconnectRequest(reconnectNow);
      for (final t in _timers.values) {
        t.cancel();
      }
      _timers.clear();
    });
    // Panes already lost when this starts (state is not writable in build).
    Future.microtask(() {
      if (ref.mounted) _scan(ref.read(terminalTabsProvider));
    });
    return const {};
  }

  void _scan(TerminalTabsState tabs) {
    if (!ref.mounted) return;
    final now = _now();
    final next = Map.of(state);
    final present = <int>{};
    for (final tab in tabs.tabs) {
      for (final pane in tab.panes.values) {
        present.add(pane.id);
        final info = next[pane.id];
        switch (pane.remoteState) {
          case RemoteState.connected:
            if (info != null) {
              next.remove(pane.id);
              _timers.remove(pane.id)?.cancel();
            }
          case RemoteState.disconnected:
            if (info == null) {
              next[pane.id] = _schedule(
                pane.id,
                RetryInfo(attempt: 0, firstLost: now),
                now,
              );
            } else if (info.retrying && !_inFlight.contains(pane.id)) {
              // The attempt got a session that ended again.
              next[pane.id] = _schedule(
                pane.id,
                info.copyWith(attempt: info.attempt + 1, retrying: false),
                now,
              );
            }
          case RemoteState.failed:
            // Never connected: a manual try that failed again stays lost.
            if (info != null && !_inFlight.contains(pane.id)) {
              next.remove(pane.id);
              _timers.remove(pane.id)?.cancel();
            }
          case _:
            break;
        }
      }
    }
    for (final id in next.keys.toList()) {
      if (!present.contains(id)) {
        next.remove(id);
        _timers.remove(id)?.cancel();
      }
    }
    if (!mapEquals(next, state)) state = next;
  }

  RetryInfo _schedule(int id, RetryInfo info, DateTime now) {
    _timers.remove(id)?.cancel();
    if (now.difference(info.firstLost) >= giveUpAfter) {
      return info.copyWith(stopped: true, nextAt: null, retrying: false);
    }
    final delay = Duration(
      seconds: delays[min(info.attempt, delays.length - 1)],
    );
    _timers[id] = Timer(delay, () => unawaited(_attempt(id)));
    return info.copyWith(nextAt: now.add(delay));
  }

  Future<int?> _open(int id, {bool withoutHook = false}) async {
    _inFlight.add(id);
    try {
      return await _tabs.reconnect(id, withoutHook: withoutHook);
    } finally {
      _inFlight.remove(id);
    }
  }

  Future<void> _attempt(int id) async {
    _timers.remove(id)?.cancel();
    final info = state[id];
    if (info == null || !ref.mounted) return;
    state = {...state, id: info.copyWith(retrying: true, nextAt: null)};
    final fresh = await _open(id);
    if (fresh == null && ref.mounted) _afterFailedOpen(id);
  }

  /// The open did not happen (busy, failed, pane gone): wait for the next
  /// back-off step, unless the pane is gone or never connected.
  void _afterFailedOpen(int id) {
    final current = state[id];
    if (current == null) return;
    final pane = ref.read(terminalTabsProvider).tabOfSession(id)?.panes[id];
    if (pane == null || pane.remoteState != RemoteState.disconnected) {
      state = {...state}..remove(id);
      return;
    }
    state = {
      ...state,
      id: _schedule(
        id,
        current.copyWith(attempt: current.attempt + 1, retrying: false),
        _now(),
      ),
    };
  }

  void _replaced(PaneReplacement r) {
    final info = state[r.from];
    _timers.remove(r.from)?.cancel();
    if (info == null) return;
    state = {...state}
      ..remove(r.from)
      ..[r.to] = info;
  }

  /// D20: the computer woke — every waiting pane now (not given-up ones).
  void onWake() {
    for (final entry in state.entries.toList()) {
      if (entry.value.retrying || entry.value.stopped) continue;
      unawaited(_attempt(entry.key));
    }
  }

  /// Enter, the strip's button, the row menu: now, with a fresh 30 minutes.
  Future<void> reconnectNow(int sessionId, {bool withoutHook = false}) async {
    _timers.remove(sessionId)?.cancel();
    state = {
      ...state,
      sessionId: RetryInfo(attempt: 0, firstLost: _now(), retrying: true),
    };
    final fresh = await _open(sessionId, withoutHook: withoutHook);
    if (fresh == null && ref.mounted) _afterFailedOpen(sessionId);
  }

  /// UI-A8 §2.3 "Reconnect all panes".
  Future<void> reconnectAll(String workspaceId) async {
    final members = ref.read(sidebarWorkspacesProvider).tabsOf(workspaceId);
    for (final tab in ref.read(terminalTabsProvider).tabs) {
      if (!members.contains(tab.id)) continue;
      for (final pane in tab.panes.values.toList()) {
        if (pane.canReconnect) await reconnectNow(pane.id);
      }
    }
  }
}
