import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_agent/shellx_agent.dart';

import '../terminal/agent_status.dart';
import '../terminal/agent_status_notifier.dart';
import '../terminal/local_sessions_provider.dart';
import '../terminal/sidebar_workspaces.dart';
import '../terminal/terminal_tabs.dart';

final cliEventBusProvider = Provider<CliEventBus>((ref) {
  final bus = CliEventBus._(ref);
  ref.onDispose(bus._dispose);
  return bus;
});

/// A7 D24: what changed in the window, as small maps, built by diffing
/// successive tab and sidebar states. A broadcast stream with no history:
/// each listener gets what happens after it came, and the CLI host keeps
/// its own per-client queue (D24: 1000, then `overflow`). Nothing is
/// worked out while nobody listens.
///
/// The first pane of a new tab is reported only by `tab.opened` (its id is
/// the tab's, A3 D1); `pane.opened` is for panes a split added. A pane
/// whose shell ended with 0 leaves at once (A3 D7): `pane.exited` then
/// `pane.closed` (or `tab.closed`). Never logs anything.
final class CliEventBus {
  CliEventBus._(this._ref) {
    // Not sync: a listener that changes the window gets its own events
    // later, never inside another event's delivery.
    _out = StreamController<Map<String, Object?>>.broadcast(onCancel: _forget);
    _subs
      ..add(_ref.listen<TerminalTabsState>(terminalTabsProvider, _tabs))
      ..add(_ref.listen<SidebarState>(sidebarWorkspacesProvider, _side))
      ..add(
        _ref.listen<LocalSessions>(localSessionsProvider, (_, local) {
          unawaited(_notices?.cancel());
          _notices = local.notices.listen(_notice);
        }, fireImmediately: true),
      );
    // Announced before the tab changes, synchronously (A8 D22).
    _replacements = _ref
        .read(terminalTabsProvider.notifier)
        .paneReplacements
        .listen(_replaced);
    // A11 D20: likewise, a pane that changed tab.
    _movements = _ref
        .read(terminalTabsProvider.notifier)
        .paneMoves
        .listen(_movedPane);
    // A12 D11: only when what shows changes.
    _agents = _ref
        .read(agentStatusProvider.notifier)
        .changes
        .listen(_agentChanged);
  }

  final Ref _ref;
  late final StreamController<Map<String, Object?>> _out;
  final _subs = <ProviderSubscription<Object?>>[];
  StreamSubscription<SessionNotice>? _notices;
  StreamSubscription<PaneReplacement>? _replacements;
  StreamSubscription<PaneMove>? _movements;
  StreamSubscription<AgentStatusChange>? _agents;

  /// A11 D20: panes moved to another tab that the next tab diff has not
  /// seen yet, by pane id. The move is `pane.moved`, not a close and an
  /// open: the pane (and its shell) never went away.
  final _moved = <int, PaneMove>{};

  /// A8 D22, D4: replaced panes the next tab diff has not seen yet, by
  /// the old id. Their swap is `pane.replaced`, not a close and an open.
  final _swapped = <int, PaneReplacement>{};

  /// D24 `pane.changed`: per pane, the values last sent (or seen before
  /// the first change), the latest values waiting, and the 250 ms timer.
  final _lastSent = <int, Map<String, Object?>>{};
  final _waiting = <int, Map<String, Object?>>{};
  final _timers = <int, Timer>{};

  /// New tabs the sidebar has not placed yet: `tab.opened` waits for
  /// their workspace, and their other events wait for `tab.opened`.
  final _unplaced = <int>{};
  final _deferred = <int, List<Map<String, Object?>>>{};

  static const _changeWindow = Duration(milliseconds: 250);

  Stream<Map<String, Object?>> get events => _out.stream;

  bool get _listened => _out.hasListener;

  void _emit(Map<String, Object?> e) {
    if (_listened) _out.add(e);
  }

  /// An event about [tab]: held while the tab waits for its `tab.opened`.
  void _emitFor(int tab, Map<String, Object?> e) {
    if (_unplaced.contains(tab)) {
      (_deferred[tab] ??= []).add(e);
    } else {
      _emit(e);
    }
  }

  /// The last listener left: nothing pending is kept.
  void _forget() {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    _waiting.clear();
    _lastSent.clear();
    _unplaced.clear();
    _deferred.clear();
    _swapped.clear();
    _moved.clear();
  }

  // ---- tabs and panes -----------------------------------------------------

  void _replaced(PaneReplacement r) {
    if (!_listened) return;
    _swapped[r.from] = r;
    // A8 D22: what was sent for the old id stands for the new one (the same
    // pane to the listener): its next change is compared with it.
    _timers.remove(r.from)?.cancel();
    _waiting.remove(r.from);
    final sent = _lastSent.remove(r.from);
    if (sent != null) _lastSent[r.to] = {...sent, 'pane': r.to};
    _emitFor(r.tabId, {
      'kind': 'pane.replaced',
      'old': r.from,
      'new': r.to,
      'tab': r.tabId,
    });
  }

  void _movedPane(PaneMove m) {
    if (!_listened) return;
    _moved[m.pane] = m;
    // The pane's `pane.changed` state travels with it: a new tab alone is
    // not a change.
    final sent = _lastSent[m.pane];
    if (sent != null) _lastSent[m.pane] = {...sent, 'tab': m.toTab};
    _timers.remove(m.pane)?.cancel();
    _waiting.remove(m.pane);
  }

  bool _isSwapTarget(int id) => _swapped.values.any((r) => r.to == id);

  /// Where a pane id ended up after the swaps of this diff.
  int _swappedEnd(int id) {
    var current = id;
    for (var i = 0; i < 64; i++) {
      final next = _swapped[current];
      if (next == null) break;
      current = next.to;
    }
    return current;
  }

  void _tabs(TerminalTabsState? before, TerminalTabsState after) {
    if (!_listened || before == null) return;
    final old = {for (final t in before.tabs) t.id: t};
    final now = {for (final t in after.tabs) t.id: t};
    final tabs = _ref.read(terminalTabsProvider.notifier);
    final selected = after.selectedId;
    final reselected = selected != null && before.selectedId != selected;
    // A tab that was there: selected before its pane's focus; a new one:
    // after its `tab.opened`.
    if (reselected && old.containsKey(selected)) {
      _emitFor(selected, {'kind': 'tab.selected', 'tab': selected});
    }
    for (final t in after.tabs) {
      final o = old[t.id];
      if (o == null) {
        _opened(t.id);
        continue;
      }
      // A rename (custom title set or cleared); automatic titles follow
      // the panes' `pane.changed`.
      if (o.customTitle != t.customTitle) {
        _emitFor(t.id, {'kind': 'tab.renamed', 'tab': t.id, 'title': t.label});
      }
      for (final p in t.panes.values) {
        final op = o.panes[p.id];
        if (op == null) {
          if (!_isSwapTarget(p.id) && !_moved.containsKey(p.id)) {
            _emitFor(t.id, {'kind': 'pane.opened', 'pane': p.id, 'tab': t.id});
          }
          continue;
        }
        if (!op.exited && p.exited) {
          _emitFor(t.id, {
            'kind': 'pane.exited',
            'pane': p.id,
            'tab': t.id,
            'exitCode': p.exitCode,
          });
        }
        _lastSent.putIfAbsent(p.id, () => _snapshot(t.id, op));
        _changed(t.id, p);
      }
      for (final op in o.panes.values) {
        if (!t.panes.containsKey(op.id)) {
          if (_moved.containsKey(op.id)) continue; // alive, in another tab
          _exitedGone(tabs, op, t.id);
          if (!_swapped.containsKey(op.id)) {
            _emitFor(t.id, {'kind': 'pane.closed', 'pane': op.id, 'tab': t.id});
          }
        }
      }
      // V2-1 §4.7: never for an AI pane (negative id).
      if (o.focusedPaneId != t.focusedPaneId &&
          !isAiPaneId(t.focusedPaneId) &&
          _swappedEnd(o.focusedPaneId) != t.focusedPaneId) {
        _emitFor(t.id, {
          'kind': 'pane.focused',
          'pane': t.focusedPaneId,
          'tab': t.id,
        });
      }
    }
    for (final o in old.values) {
      if (now.containsKey(o.id)) continue;
      // Never announced: it goes without a word (no orphan tab.closed).
      final silent = _unplaced.remove(o.id);
      _deferred.remove(o.id);
      for (final op in o.panes.values) {
        if (_moved.containsKey(op.id)) continue; // alive, in another tab
        _exitedGone(tabs, op, o.id, silent: silent);
      }
      if (!silent) _emit({'kind': 'tab.closed', 'tab': o.id});
    }
    if (reselected && !old.containsKey(selected)) {
      _emitFor(selected, {'kind': 'tab.selected', 'tab': selected});
    }
    for (final m in _moved.values) {
      if (!now.containsKey(m.toTab)) continue;
      _emitFor(m.toTab, {
        'kind': 'pane.moved',
        'pane': m.pane,
        'from': m.fromTab,
        'to': m.toTab,
      });
    }
    _moved.clear(); // each move is announced just before its own diff
    _swapped.clear(); // each swap is announced just before its own diff
  }

  /// `tab.opened` with its workspace; when the sidebar has not placed the
  /// tab yet, once it has ([_side]).
  void _opened(int tab) {
    final ws = _ref.read(sidebarWorkspacesProvider).workspaceOf(tab);
    if (ws == null) {
      _unplaced.add(tab);
      return;
    }
    _emit({'kind': 'tab.opened', 'tab': tab, 'workspace': ws});
  }

  /// A pane that left: its exit, when its shell ended (exit 0 removes the
  /// pane at once); forgets its `pane.changed` state.
  void _exitedGone(
    TerminalTabs tabs,
    PaneSession p,
    int tab, {
    bool silent = false,
  }) {
    final code = tabs.lastExitCode(p.id);
    if (!silent && !p.exited && code != null) {
      _emitFor(tab, {
        'kind': 'pane.exited',
        'pane': p.id,
        'tab': tab,
        'exitCode': code,
      });
    }
    _timers.remove(p.id)?.cancel();
    _waiting.remove(p.id);
    _lastSent.remove(p.id);
  }

  static Map<String, Object?> _snapshot(int tab, PaneSession p) => {
    'kind': 'pane.changed',
    'pane': p.id,
    'tab': tab,
    'title': p.automaticLabel,
    'cwd': p.cwd,
    'branch': p.gitBranch,
    'ports': p.ports,
    'running': p.runningCommand,
  };

  /// D24: at most one `pane.changed` per pane per 250 ms, with the latest
  /// values, and only when they differ from what was last sent.
  void _changed(int tab, PaneSession p) {
    final snap = _snapshot(tab, p);
    if (!_timers.containsKey(p.id)) {
      if (_same(_lastSent[p.id], snap)) return;
      _timers[p.id] = Timer(_changeWindow, () => _flushChange(p.id));
    }
    _waiting[p.id] = snap;
  }

  void _flushChange(int pane) {
    _timers.remove(pane);
    final snap = _waiting.remove(pane);
    if (snap == null || _same(_lastSent[pane], snap)) return;
    _lastSent[pane] = snap;
    _emitFor(snap['tab']! as int, snap);
  }

  static bool _same(Map<String, Object?>? a, Map<String, Object?> b) {
    if (a == null) return false;
    for (final MapEntry(:key, :value) in b.entries) {
      final was = a[key];
      if (value is List<int> && was is List<int>) {
        if (value.length != was.length) return false;
        for (var i = 0; i < value.length; i++) {
          if (value[i] != was[i]) return false;
        }
      } else if (value != was) {
        return false;
      }
    }
    return true;
  }

  // ---- workspaces ---------------------------------------------------------

  void _side(SidebarState? before, SidebarState after) {
    if (!_listened || before == null) return;
    final names = _ref.read(sidebarWorkspacesProvider.notifier);
    final old = {for (final w in before.workspaces) w.id: w};
    for (final w in after.workspaces) {
      final o = old[w.id];
      if (o == null) {
        _emit({
          'kind': 'workspace.created',
          'workspace': w.id,
          'name': names.displayName(w.id),
        });
      } else if (o.name != w.name) {
        _emit({
          'kind': 'workspace.renamed',
          'workspace': w.id,
          'name': names.displayName(w.id),
        });
      }
    }
    for (final w in before.workspaces) {
      if (after.workspace(w.id) == null) {
        _emit({'kind': 'workspace.deleted', 'workspace': w.id});
      }
    }
    // After the workspace it went into was announced; then what waited.
    for (final tab in [..._unplaced]) {
      final ws = after.workspaceOf(tab);
      if (ws != null) {
        _unplaced.remove(tab);
        _emit({'kind': 'tab.opened', 'tab': tab, 'workspace': ws});
        _deferred.remove(tab)?.forEach(_emit);
      }
    }
    for (final w in after.workspaces) {
      for (final tab in after.tabsOf(w.id)) {
        final was = before.workspaceOf(tab);
        if (was != null && was != w.id) {
          _emit({'kind': 'tab.moved', 'tab': tab, 'workspace': w.id});
        }
      }
    }
  }

  // ---- notices (A4) -------------------------------------------------------

  void _notice(SessionNotice n) {
    if (!_listened) return;
    final tab = _ref.read(terminalTabsProvider).tabOfSession(n.sessionId)?.id;
    _emit({
      'kind': 'notice',
      'pane': n.sessionId,
      'tab': ?tab,
      'type': n.kind.name,
      'title': ?n.title,
      'body': ?n.body,
    });
  }

  // ---- agents (A12 D11) -----------------------------------------------------

  void _agentChanged(AgentStatusChange c) {
    if (!_listened) return;
    final tab = c.tab;
    final e = <String, Object?>{
      'kind': 'agent.status',
      'pane': c.pane,
      'tab': ?tab,
      'agent': c.agent.name,
      // `none`: the agent ended or its pane went.
      'status': c.state == null ? 'none' : agentStateWire(c.state!),
    };
    tab == null ? _emit(e) : _emitFor(tab, e);
  }

  void _dispose() {
    unawaited(_agents?.cancel());
    for (final s in _subs) {
      s.close();
    }
    unawaited(_notices?.cancel());
    unawaited(_replacements?.cancel());
    unawaited(_movements?.cancel());
    _forget();
    unawaited(_out.close());
  }
}
