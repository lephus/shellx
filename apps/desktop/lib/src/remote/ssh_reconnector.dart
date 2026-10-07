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
    this.needsSignIn = false,
  });

  final int attempt;
  final DateTime firstLost;

  /// When the next attempt starts (the strip's countdown); null while one
  /// runs or after giving up.
  final DateTime? nextAt;
  final bool retrying;

  /// D20: 30 minutes passed — only "Reconnect" now.
  final bool stopped;

  /// A8 D20: auto-retries ended because two in a row on this host did not
  /// get through sign-in (lockout protection); Enter retries by hand.
  final bool needsSignIn;

  RetryInfo copyWith({
    int? attempt,
    Object? nextAt = _keep,
    bool? retrying,
    bool? stopped,
    bool? needsSignIn,
  }) => RetryInfo(
    attempt: attempt ?? this.attempt,
    firstLost: firstLost,
    nextAt: identical(nextAt, _keep) ? this.nextAt : nextAt as DateTime?,
    retrying: retrying ?? this.retrying,
    stopped: stopped ?? this.stopped,
    needsSignIn: needsSignIn ?? this.needsSignIn,
  );

  @override
  bool operator ==(Object other) =>
      other is RetryInfo &&
      other.attempt == attempt &&
      other.firstLost == firstLost &&
      other.nextAt == nextAt &&
      other.retrying == retrying &&
      other.stopped == stopped &&
      other.needsSignIn == needsSignIn;

  @override
  int get hashCode =>
      Object.hash(attempt, firstLost, nextAt, retrying, stopped, needsSignIn);
}

const Object _keep = Object();

final reconnectClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

final sshReconnectorProvider =
    NotifierProvider<SshReconnector, Map<int, RetryInfo>>(SshReconnector.new);

/// One reconnect waiting for its host's turn.
final class _Turn {
  _Turn(this.id, {required this.manual, required this.withoutHook});
  final int id;
  final bool manual;
  final bool withoutHook;
}

/// What is going on for one host: at most one attempt at a time (a host
/// that asks for a password must not get N prompts at once).
final class _Chain {
  bool running = false;
  final waiting = <_Turn>[];

  /// Automatic attempts in a row that never reached `connected`.
  int failures = 0;
}

/// A8 D20: lost SSH panes come back by themselves — 3, 6, 12, 24, 48, 60…
/// seconds, at once after a wake, for 30 minutes; panes that never
/// connected only on request. Keyed by the pane's current session id.
/// One attempt per host at a time; two automatic sign-in failures in a row
/// stop the host's retries (lockout protection).
class SshReconnector extends Notifier<Map<int, RetryInfo>> {
  static const delays = [3, 6, 12, 24, 48, 60];
  static const giveUpAfter = Duration(minutes: 30);
  static const maxSignInFailures = 2;

  final _timers = <int, Timer>{};
  final _chains = <String, _Chain>{};
  final _outcomes = <int, Completer<bool>>{};

  /// Ids whose reconnect is under way: the old pane still looks lost until
  /// the new session takes its place.
  final _inFlight = <int>{};
  bool _stopped = false;

  DateTime _now() => ref.read(reconnectClockProvider)();
  TerminalTabs get _tabs => ref.read(terminalTabsProvider.notifier);

  @override
  Map<int, RetryInfo> build() {
    _stopped = false;
    final tabs = _tabs;
    final sub = tabs.paneReplacements.listen(_replaced);
    tabs.setReconnectRequest(reconnectNow);
    ref.listen<TerminalTabsState>(terminalTabsProvider, (_, next) {
      _scan(next);
    });
    ref.onDispose(() {
      unawaited(sub.cancel());
      tabs.clearReconnectRequest(reconnectNow);
      _halt();
    });
    // Panes already lost when this starts (state is not writable in build).
    Future.microtask(() {
      if (ref.mounted) _scan(ref.read(terminalTabsProvider));
    });
    return const {};
  }

  /// A8 D40: Quit — nothing starts or retries from here on.
  void stop() {
    _stopped = true;
    _halt();
  }

  void _halt() {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    _chains.clear();
    final pending = _outcomes.values.toList();
    _outcomes.clear();
    for (final c in pending) {
      if (!c.isCompleted) c.complete(false);
    }
  }

  bool get _off => _stopped || !ref.mounted;

  String? _hostOf(int id) => ref
      .read(terminalTabsProvider)
      .tabOfSession(id)
      ?.panes[id]
      ?.remote
      ?.hostKey;

  PaneSession? _paneOf(int id) =>
      ref.read(terminalTabsProvider).tabOfSession(id)?.panes[id];

  bool _busy(int id) =>
      _inFlight.contains(id) ||
      _chains.values.any((c) => c.waiting.any((t) => t.id == id));

  void _scan(TerminalTabsState tabs) {
    if (_off) return;
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
            }
          case RemoteState.failed:
            // Never connected: stays lost until asked.
            if (info != null &&
                !_busy(pane.id) &&
                !_outcomes.containsKey(pane.id)) {
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
    for (final chain in _chains.values) {
      chain.waiting.removeWhere((t) => !present.contains(t.id));
    }
    if (!mapEquals(next, state)) state = next;
    for (final id in _outcomes.keys.toList()) {
      final result = _peek(id);
      if (result != null) _outcomes.remove(id)?.complete(result);
    }
  }

  RetryInfo _schedule(int id, RetryInfo info, DateTime now) {
    _timers.remove(id)?.cancel();
    if (now.difference(info.firstLost) >= giveUpAfter) {
      return info.copyWith(stopped: true, nextAt: null, retrying: false);
    }
    final delay = Duration(
      seconds: delays[min(info.attempt, delays.length - 1)],
    );
    _timers[id] = Timer(delay, () => unawaited(_request(id)));
    return info.copyWith(nextAt: now.add(delay), retrying: false);
  }

  /// Asks for an attempt on pane [id]: runs it now, or waits for its host's
  /// running one to end.
  Future<void> _request(
    int id, {
    bool manual = false,
    bool withoutHook = false,
  }) async {
    if (_off || _busy(id)) return;
    final host = _hostOf(id);
    if (host == null) return;
    _timers.remove(id)?.cancel();
    final chain = _chains.putIfAbsent(host, _Chain.new);
    if (manual) {
      chain.failures = 0;
      state = {
        ...state,
        id: RetryInfo(attempt: 0, firstLost: _now(), retrying: true),
      };
    } else {
      final info = state[id];
      if (info == null) return;
      state = {...state, id: info.copyWith(retrying: true, nextAt: null)};
    }
    final turn = _Turn(id, manual: manual, withoutHook: withoutHook);
    if (chain.running) {
      chain.waiting.add(turn);
      return;
    }
    chain.running = true;
    try {
      _Turn? current = turn;
      while (current != null && !_off) {
        if (!await _runTurn(host, chain, current)) break;
        current = chain.waiting.isEmpty ? null : chain.waiting.removeAt(0);
      }
    } finally {
      chain.running = false;
    }
  }

  /// One attempt; true when it connected (the host's next turn may go).
  Future<bool> _runTurn(String host, _Chain chain, _Turn turn) async {
    final pane = _paneOf(turn.id);
    if (pane == null || !pane.canReconnect) {
      // Gone or back meanwhile: nothing to do, the next one goes.
      if (state.containsKey(turn.id) && pane?.canReconnect != true) {
        state = {...state}..remove(turn.id);
      }
      return true;
    }
    _inFlight.add(turn.id);
    int? fresh;
    try {
      fresh = await _tabs.reconnect(turn.id, withoutHook: turn.withoutHook);
    } finally {
      _inFlight.remove(turn.id);
    }
    if (_off) return false;
    if (fresh == null) {
      // Busy or the open failed: no ssh ran, nobody's step is spent but this.
      _failChain(chain, turn.id, openFailed: true);
      return false;
    }
    final connected = await _outcome(fresh);
    if (_off) return false;
    if (connected) {
      chain.failures = 0;
      return true;
    }
    if (!turn.manual) chain.failures++;
    _failChain(chain, fresh);
    return false;
  }

  /// The host's attempt ended without a connection: [failedId] and every
  /// waiting pane go to the next back-off step together, or stop for good
  /// after repeated sign-in failures.
  void _failChain(_Chain chain, int failedId, {bool openFailed = false}) {
    final ids = [failedId, ...chain.waiting.map((t) => t.id)];
    chain.waiting.clear();
    final now = _now();
    final next = Map.of(state);
    for (final id in ids) {
      final info = next[id];
      if (info == null) continue;
      final pane = _paneOf(id);
      if (pane == null || pane.remoteState != RemoteState.disconnected) {
        next.remove(id); // failed pane or gone: only on request
        continue;
      }
      if (chain.failures >= maxSignInFailures) {
        _timers.remove(id)?.cancel();
        next[id] = info.copyWith(
          stopped: true,
          needsSignIn: true,
          retrying: false,
          nextAt: null,
        );
        continue;
      }
      final step = id == failedId ? info.attempt + 1 : info.attempt;
      next[id] = _schedule(
        id,
        info.copyWith(attempt: openFailed ? step : info.attempt + 1),
        now,
      );
    }
    state = next;
  }

  /// Whether pane [id]'s new session reached `connected` (true), ended
  /// (false), or is still deciding (null; a password prompt waits here).
  bool? _peek(int id) => switch (_paneOf(id)?.remoteState) {
    null => false,
    RemoteState.connected => true,
    RemoteState.disconnected ||
    RemoteState.failed ||
    RemoteState.exited => false,
    RemoteState.connecting => null,
  };

  Future<bool> _outcome(int id) {
    final now = _peek(id);
    if (now != null) return Future.value(now);
    final c = Completer<bool>();
    _outcomes[id] = c;
    return c.future;
  }

  void _replaced(PaneReplacement r) {
    final info = state[r.from];
    _timers.remove(r.from)?.cancel();
    if (info == null) return;
    state = {...state}
      ..remove(r.from)
      ..[r.to] = info;
  }

  /// D20: the computer woke — every waiting pane now (not given-up ones),
  /// one host at a time.
  void onWake() {
    if (_off) return;
    for (final entry in state.entries.toList()) {
      if (entry.value.retrying || entry.value.stopped) continue;
      unawaited(_request(entry.key));
    }
  }

  /// Enter, the strip's button, the row menu: now (after the host's
  /// running attempt), with a fresh 30 minutes and a fresh sign-in count.
  Future<void> reconnectNow(int sessionId, {bool withoutHook = false}) =>
      _request(sessionId, manual: true, withoutHook: withoutHook);

  /// UI-A8 §2.3 "Reconnect all panes".
  Future<void> reconnectAll(String workspaceId) async {
    final members = ref.read(sidebarWorkspacesProvider).tabsOf(workspaceId);
    final all = <Future<void>>[];
    for (final tab in ref.read(terminalTabsProvider).tabs) {
      if (!members.contains(tab.id)) continue;
      for (final pane in tab.panes.values.toList()) {
        if (pane.canReconnect) all.add(reconnectNow(pane.id));
      }
    }
    await Future.wait(all);
  }
}
