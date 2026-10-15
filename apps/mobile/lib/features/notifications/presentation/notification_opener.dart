import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/notifications/domain/push_messaging.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_workspace.dart';

/// Shows a machine's terminal page; the router in production, a fake in tests.
abstract interface class MachineNavigator {
  /// The terminal page of [agentId] is the top page.
  bool isShowing(String agentId);

  /// Back to the machine list, then that machine's terminal page. At launch it waits a few seconds
  /// for the machine list to appear; it does nothing when it never does (signed out, an outdated
  /// app).
  void show(String agentId, String machineName);

  /// V2-2: AI session [sid] of [agentId] is the top page.
  bool isShowingAi(String agentId, String sid);

  /// V2-2: back to the machine list, then AI session [sid] of the machine (like [show]).
  void showAi(String agentId, String machineName, String sid);
}

@LazySingleton(as: MachineNavigator)
final class RouterMachineNavigator implements MachineNavigator {
  RouterMachineNavigator(this._router);

  final AppRouter _router;

  @override
  bool isShowing(String agentId) {
    final top = _router.topRoute;
    final args = top.args;
    return top.name == TerminalRoute.name && args is TerminalRouteArgs && args.agentId == agentId;
  }

  /// How long a launch may take to show its first page (its guards are asynchronous).
  static const Duration _firstPageWait = Duration(seconds: 5);

  @override
  bool isShowingAi(String agentId, String sid) {
    final top = _router.topRoute;
    final args = top.args;
    return top.name == AiSessionRoute.name && args is AiSessionRouteArgs && args.agentId == agentId && args.sid == sid;
  }

  /// Keyed by its session (V2-2b B23): a page that takes the place of another session's page is a new page,
  /// not the old one's state with new arguments.
  @override
  void showAi(String agentId, String machineName, String sid) => _whenListed(
    () => _push(
      AiSessionRoute(key: ValueKey('ai:$agentId/$sid'), agentId: agentId, machineName: machineName, sid: sid),
    ),
  );

  @override
  void show(String agentId, String machineName) =>
      _whenListed(() => _push(TerminalRoute(agentId: agentId, machineName: machineName)));

  /// Runs [go] once the machine list is on the stack (at launch it may still be resolving).
  void _whenListed(void Function() go) {
    if (_hasMachineList) {
      go();
      return;
    }
    // A notification that launched the app arrives while the first page may still be resolving.
    Timer? timer;
    late final void Function() listener;
    void stop() {
      _router.removeListener(listener);
      timer?.cancel();
    }

    listener = () {
      if (!_hasMachineList) return;
      stop();
      // Not from inside the router's own notification.
      scheduleMicrotask(go);
    };
    _router.addListener(listener);
    timer = Timer(_firstPageWait, stop);
  }

  bool get _hasMachineList => _router.stack.any((route) => route.name == MachineListRoute.name);

  void _push(PageRouteInfo route) {
    _router.popUntilRouteWithName(MachineListRoute.name);
    // Completes when the page pops: not awaited.
    unawaited(_router.push(route));
  }
}

/// A tapped notification (push spec §6): opens the machine `agent_id`, and switches to the tab of
/// `session_id` when that tab is open, or as soon as it opens (within 30 s). A push with `ai_session` (V2-2 D11)
/// opens that AI session instead, over the machine list, and never twice: one already on top is left as it
/// is — or, for a session of a previous run of ShellX on the computer, the session it is now (V2-2b B23).
/// Opening only shows; it answers nothing. A machine that is not paired on this phone (another account's,
/// or unpaired since) and a signed-out app open nothing.
@lazySingleton
class NotificationOpener {
  NotificationOpener(this._session, this._registry, this._navigator);

  final SessionHolder _session;
  final WorkspaceRegistry _registry;
  final MachineNavigator _navigator;

  /// Bounds the `GET /v1/devices` that names the machine.
  static const Duration _nameTimeout = Duration(seconds: 3);

  /// Never throws.
  Future<void> open(PushMessage message) async {
    final agentId = message.agentId;
    final backend = _session.backend.peek();
    if (agentId == null || backend == null) return;
    try {
      final pinned = await backend.pinnedMachines();
      if (!pinned.any((machine) => machine.agentId == agentId)) return;
      if (!identical(_session.backend.peek(), backend)) return;
      // V2-2 D11: an AI session's push opens that session, over the machine list.
      final aiSession = message.aiSession;
      if (aiSession != null) {
        if (_navigator.isShowingAi(agentId, aiSession)) return;
        final name = await _machineName(backend, agentId, message);
        if (!identical(_session.backend.peek(), backend)) return;
        final sid = _aiSessionNow(agentId, aiSession);
        if (sid == null) {
          // B23: a session of a previous run that is none of today's (or several): the machine, as an
          // older phone opens it.
          if (!_navigator.isShowing(agentId)) _navigator.show(agentId, name);
          return;
        }
        // The same push may have opened it while the machine was being named.
        if (_navigator.isShowingAi(agentId, sid)) return;
        _navigator.showAi(agentId, name, sid);
        return;
      }
      final sessionId = message.sessionId;
      // Selects now when the tab is open; else when it appears (the phone may still be reconnecting).
      if (sessionId != null) _registry.forMachine(agentId).pendingSelect(sessionId);
      if (_navigator.isShowing(agentId)) return;
      final name = await _machineName(backend, agentId, message);
      if (!identical(_session.backend.peek(), backend)) return;
      _navigator.show(agentId, name);
    } catch (error) {
      if (kDebugMode) debugPrint('NotificationOpener error: ${error.runtimeType}');
    }
  }

  /// V2-2b B23: what AI session [sid] of [agentId] is now. A sid this phone saw in a listing of the
  /// machine (in this run of the app) that the listing held now no longer names is of a previous run of
  /// ShellX on the computer (or of a tab closed since): the one session of the same agent session, agent
  /// and folder it was seen with, else null (none, or several: the machine's page). Any other sid is
  /// itself: named by the listing, newer than the listing the phone holds (a tab opened while the phone
  /// slept), or one nothing can tell about (no listing held, no window serving AI) — the page finds out,
  /// and B22 follows it.
  String? _aiSessionNow(String agentId, String sid) {
    final TerminalWorkspace workspace;
    try {
      workspace = _registry.forMachine(agentId);
    } on StateError {
      return sid;
    }
    final listing = workspace.aiListing;
    if (listing == null || !listing.available || listing.sessions.any((s) => s.sid == sid)) return sid;
    final was = workspace.machine.ai.seen(sid);
    if (was == null) return sid;
    final acp = was.acpSessionId;
    if (acp == null) return null;
    final now = [
      for (final s in listing.sessions)
        if (s.acpSessionId == acp && s.agentId == was.agentId && s.cwd == was.cwd) s,
    ];
    return now.length == 1 ? now.single.sid : null;
  }

  /// The name from `GET /v1/devices`; offline, the first part of the title (`<machine> · …`,
  /// push spec §4.2), else empty.
  Future<String> _machineName(ShellxBackend backend, String agentId, PushMessage message) async {
    try {
      final devices = await backend.devices().timeout(_nameTimeout);
      for (final RemoteDevice device in devices) {
        if (device.id == agentId) return device.name;
      }
    } catch (error) {
      if (kDebugMode) debugPrint('NotificationOpener devices error: ${error.runtimeType}');
    }
    final title = message.title ?? '';
    final separator = title.indexOf(' · ');
    return separator > 0 ? title.substring(0, separator) : '';
  }
}
