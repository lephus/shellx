import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shellx_agent/shellx_agent.dart';

import '../terminal_sharing/terminal_sharing_setup.dart';
import 'agent_controller_base.dart';
import 'agent_runtime.dart';
import 'agent_state.dart';
import 'agent_state_codec.dart';

/// A5b D12: the agent of a UI that attaches to the background service.
///
/// The state is the daemon's: the first `agent.get`, then every
/// `agent.state` event. A command is an `agent.call` and changes nothing
/// here by itself: the daemon applies it and the new state comes back as an
/// event (D13: no cached copy in this process, no second writer).
///
/// Errors: a daemon error or a lost link throws [MuxRemoteException].
/// Never logs arguments or results (they carry passwords and pairing
/// secrets).
final class RemoteAgentController extends AgentControllerBase {
  RemoteAgentController(MuxClient client) : _clientOf = (() => client);

  /// A window that (re)attaches to the service: [clientOf] is asked each
  /// time the controller is built, so a provider rebuild after a new
  /// connection reads the new service. Null (not attached yet): nothing is
  /// read and every command fails as a lost link.
  RemoteAgentController.lazy(MuxClient? Function() clientOf)
    : _clientOf = clientOf;

  final MuxClient? Function() _clientOf;
  MuxClient? _client;
  Future<void>? _first;

  @override
  AgentViewState build() {
    // A rebuilt notifier is the same object: what the last connection read
    // is forgotten.
    _client = _clientOf();
    _first = null;
    final sub = _client?.events.listen((m) {
      if (m.type != MuxType.agentState) return;
      _apply(m.get<Object?>('state'));
    });
    ref.onDispose(() => sub?.cancel());
    return const AgentViewState();
  }

  MuxClient get _link =>
      _client ?? (throw const MuxRemoteException('disconnected'));

  /// False when [wire] is not a state this app can read.
  bool _apply(Object? wire) {
    if (!ref.mounted) return true;
    if (wire is! Map<Object?, Object?>) return false;
    try {
      state = agentStateFromWire(wire);
      return true;
    } on Object catch (e) {
      // A state this app cannot read (a newer daemon): keep the last one.
      debugPrint('ShellX: unreadable agent state: ${e.runtimeType}');
      return false;
    }
  }

  /// Completes once the daemon's state has arrived (it never signs in or
  /// starts anything here: the daemon did that when it started).
  /// [watchForWake] belongs to the daemon.
  @override
  Future<void> bootstrap({bool watchForWake = true}) =>
      _first ??= _load().catchError((Object e) {
        _first = null; // a later call may try again
        throw e;
      });

  Future<void> _load() async {
    final reply = await _link.request(MuxType.agentGet);
    // The first state must be readable: a silent signed-out default would
    // show a wrong tray and ask for a sign-in the daemon already has.
    if (!_apply(reply.get<Object?>('state'))) {
      throw const FormatException('unreadable agent state');
    }
  }

  Future<Object?> _call(
    String name, [
    Map<String, Object?> args = const {},
  ]) async {
    final reply = await _link.request(MuxType.agentCall, {
      'm': name,
      'a': args,
    });
    return reply.fields['value'];
  }

  @override
  Future<void> signIn({
    required String email,
    required String password,
    required bool register,
  }) => _call('signIn', {
    'email': email,
    'password': password,
    'register': register,
  });

  @override
  Future<void> signOut() => _call('signOut');

  @override
  Future<void> changePassword(String newPassword) =>
      _call('changePassword', {'newPassword': newPassword});

  @override
  Future<void> setRemoteAccess(bool enabled) =>
      _call('setRemoteAccess', {'enabled': enabled});

  @override
  Future<void> setNotifyThreshold(int seconds) =>
      _call('setNotifyThreshold', {'seconds': seconds});

  @override
  Future<void> setDesktopNotifications(bool enabled) =>
      _call('setDesktopNotifications', {'enabled': enabled});

  @override
  Future<void> setDesktopNotificationsOnlyUnfocused(bool enabled) =>
      _call('setDesktopNotificationsOnlyUnfocused', {'enabled': enabled});

  @override
  Future<void> setKeepAwake(bool enabled) =>
      _call('setKeepAwake', {'enabled': enabled});

  @override
  Future<void> setLaunchAtStartup(bool enabled) =>
      _call('setLaunchAtStartup', {'enabled': enabled});

  @override
  Future<void> setCliControlEnabled(bool enabled) =>
      _call('setCliControlEnabled', {'enabled': enabled});

  @override
  Future<void> setCliAllowExternal(bool enabled) =>
      _call('setCliAllowExternal', {'enabled': enabled});

  @override
  Future<void> setSshRemoteHook(bool enabled) =>
      _call('setSshRemoteHook', {'enabled': enabled});

  @override
  Future<void> completeOnboarding() => _call('completeOnboarding');

  @override
  Future<PairingView?> startPairing() async {
    final v = await _call('startPairing');
    return v is Map<Object?, Object?> ? pairingFromWire(v) : null;
  }

  @override
  Future<void> cancelPairing() => _call('cancelPairing');

  @override
  Future<void> revoke(String mobileId) =>
      _call('revoke', {'mobileId': mobileId});

  @override
  Future<void> closeSession(int id) => _call('closeSession', {'id': id});

  @override
  Future<SharingPlan?> prepareTerminalSharing() async {
    final v = await _call('prepareTerminalSharing');
    return v is Map<Object?, Object?> ? sharingPlanFromWire(v) : null;
  }

  @override
  Future<bool> enableTerminalSharing(SharingPlan plan) async =>
      await _call('enableTerminalSharing', {
        'digest': sharingPlanDigest(plan),
      }) ==
      true;

  @override
  Future<void> disableTerminalSharing() => _call('disableTerminalSharing');

  @override
  Future<void> disconnectDesktopPhone(int id) =>
      _call('disconnectDesktopPhone', {'id': id});

  @override
  Future<void> closeAllSessions() => _call('closeAllSessions');

  @override
  Future<void> reconnect() => _call('reconnect');

  @override
  Future<void> checkForUpdate() => _call('checkForUpdate');

  /// Not an `agent.call`: ending the UI must not stop the daemon's relay
  /// link (only `daemon.quit` stops the service, A5b D14).
  @override
  Future<void> shutdown() async {}
}
