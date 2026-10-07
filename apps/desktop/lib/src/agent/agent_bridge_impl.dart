import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_agent/shellx_agent.dart';

import 'agent_controller_base.dart';
import 'agent_state_codec.dart';

/// A5b D12: the daemon's [AgentBridge]: `agent.get` reads [current],
/// `agent.state` events follow [states] (a change is sent at most once per
/// [coalesce]), `agent.call` runs the named command of the real
/// controller. Arguments arrive as CBOR values (a plan as a map); a bad
/// name or argument throws (the server answers `internal` or `bad_request`
/// with the exception's type only).
///
/// Never logs arguments or results.
final class ControllerAgentBridge implements AgentBridge {
  ControllerAgentBridge(
    this._container, {
    this.coalesce = const Duration(milliseconds: 16),
  }) {
    _subscription = _container.listen(
      agentControllerProvider,
      (_, _) => _schedule(),
    );
  }

  final ProviderContainer _container;
  final Duration coalesce;
  final _states = StreamController<Map<String, Object?>>.broadcast();
  late final ProviderSubscription<Object?> _subscription;
  Timer? _timer;

  AgentControllerBase get _agent =>
      _container.read(agentControllerProvider.notifier);

  @override
  Stream<Map<String, Object?>> get states => _states.stream;

  @override
  Map<String, Object?> get current =>
      agentStateToWire(_container.read(agentControllerProvider));

  void _schedule() {
    _timer ??= Timer(coalesce, () {
      _timer = null;
      if (!_states.isClosed) _states.add(current);
    });
  }

  /// Stops listening; no more states.
  void close() {
    _timer?.cancel();
    _timer = null;
    _subscription.close();
    unawaited(_states.close());
  }

  @override
  Future<Object?> call(String method, Map<String, Object?> args) async {
    final a = _agent;
    bool enabled() => args['enabled']! as bool;
    switch (method) {
      case 'bootstrap':
        await a.bootstrap(watchForWake: args['watchForWake'] as bool? ?? true);
      case 'signIn':
        await a.signIn(
          email: args['email']! as String,
          password: args['password']! as String,
          register: args['register']! as bool,
        );
      case 'signOut':
        await a.signOut();
      case 'changePassword':
        await a.changePassword(args['newPassword']! as String);
      case 'setRemoteAccess':
        await a.setRemoteAccess(enabled());
      case 'setNotifyThreshold':
        await a.setNotifyThreshold(args['seconds']! as int);
      case 'setDesktopNotifications':
        await a.setDesktopNotifications(enabled());
      case 'setDesktopNotificationsOnlyUnfocused':
        await a.setDesktopNotificationsOnlyUnfocused(enabled());
      case 'setKeepAwake':
        await a.setKeepAwake(enabled());
      case 'setLaunchAtStartup':
        await a.setLaunchAtStartup(enabled());
      case 'setCliControlEnabled':
        await a.setCliControlEnabled(enabled());
      case 'setCliAllowExternal':
        await a.setCliAllowExternal(enabled());
      case 'setSshRemoteHook':
        await a.setSshRemoteHook(enabled());
      case 'completeOnboarding':
        await a.completeOnboarding();
      case 'startPairing':
        final view = await a.startPairing();
        return view == null ? null : pairingToWire(view);
      case 'cancelPairing':
        await a.cancelPairing();
      case 'revoke':
        await a.revoke(args['mobileId']! as String);
      case 'closeSession':
        await a.closeSession(args['id']! as int);
      case 'prepareTerminalSharing':
        final plan = await a.prepareTerminalSharing();
        return plan == null ? null : sharingPlanToWire(plan);
      case 'enableTerminalSharing':
        return a.enableTerminalSharing(
          sharingPlanFromWire(args['plan']! as Map<Object?, Object?>),
        );
      case 'disableTerminalSharing':
        await a.disableTerminalSharing();
      case 'disconnectDesktopPhone':
        await a.disconnectDesktopPhone(args['id']! as int);
      case 'closeAllSessions':
        await a.closeAllSessions();
      case 'reconnect':
        await a.reconnect();
      case 'checkForUpdate':
        await a.checkForUpdate();
      case 'shutdown':
        await a.shutdown();
      default:
        throw ArgumentError.value(method, 'method', 'unknown');
    }
    return null;
  }
}
