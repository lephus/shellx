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
  void show(String agentId, String machineName) {
    if (_hasMachineList) {
      _go(agentId, machineName);
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
      scheduleMicrotask(() => _go(agentId, machineName));
    };
    _router.addListener(listener);
    timer = Timer(_firstPageWait, stop);
  }

  bool get _hasMachineList => _router.stack.any((route) => route.name == MachineListRoute.name);

  void _go(String agentId, String machineName) {
    _router.popUntilRouteWithName(MachineListRoute.name);
    // Completes when the page pops: not awaited.
    unawaited(_router.push(TerminalRoute(agentId: agentId, machineName: machineName)));
  }
}

/// A tapped notification (push spec §6): opens the machine `agent_id`, and switches to the tab of
/// `session_id` when that tab is open. A machine that is not paired on this phone (another
/// account's, or unpaired since) and a signed-out app open nothing.
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
      final sessionId = message.sessionId;
      if (sessionId != null) {
        final workspace = _registry.forMachine(agentId);
        final index = workspace.tabs.peek().indexWhere((tab) => tab.id == sessionId);
        if (index >= 0) workspace.select(index);
      }
      if (_navigator.isShowing(agentId)) return;
      final name = await _machineName(backend, agentId, message);
      if (!identical(_session.backend.peek(), backend)) return;
      _navigator.show(agentId, name);
    } catch (error) {
      if (kDebugMode) debugPrint('NotificationOpener error: ${error.runtimeType}');
    }
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
