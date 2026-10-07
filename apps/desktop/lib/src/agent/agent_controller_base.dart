import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../terminal_sharing/terminal_sharing_setup.dart';
import 'agent_controller.dart';
import 'agent_runtime.dart';
import 'agent_state.dart';

/// The agent the tray and the windows talk to (A5b D12): [AgentController]
/// in the process that runs the relay and the sessions (the app today, the
/// background service next), `RemoteAgentController` in a UI that attaches
/// to it. Every command is asynchronous so both fit.
///
/// A command added here must also be added to [wireCommands], to the bridge
/// (`ControllerAgentBridge`) and to `RemoteAgentController`; the tests
/// check each name end to end.
abstract class AgentControllerBase extends Notifier<AgentViewState> {
  /// The names `agent.call` carries, one per command below. `bootstrap` and
  /// `shutdown` are here because the daemon's bridge serves them, but the
  /// remote controller handles them locally (its own `bootstrap` waits for
  /// the first state; the daemon is stopped by `daemon.quit`).
  static const Set<String> wireCommands = {
    'bootstrap',
    'signIn',
    'signOut',
    'changePassword',
    'setRemoteAccess',
    'setNotifyThreshold',
    'setDesktopNotifications',
    'setDesktopNotificationsOnlyUnfocused',
    'setKeepAwake',
    'setLaunchAtStartup',
    'setCliControlEnabled',
    'setCliAllowExternal',
    'setSshRemoteHook',
    'completeOnboarding',
    'startPairing',
    'cancelPairing',
    'revoke',
    'closeSession',
    'prepareTerminalSharing',
    'enableTerminalSharing',
    'disableTerminalSharing',
    'disconnectDesktopPhone',
    'closeAllSessions',
    'reconnect',
    'checkForUpdate',
    'shutdown',
  };

  Future<void> bootstrap({bool watchForWake = true});
  Future<void> signIn({
    required String email,
    required String password,
    required bool register,
  });
  Future<void> signOut();
  Future<void> changePassword(String newPassword);
  Future<void> setRemoteAccess(bool enabled);
  Future<void> setNotifyThreshold(int seconds);
  Future<void> setDesktopNotifications(bool enabled);
  Future<void> setDesktopNotificationsOnlyUnfocused(bool enabled);
  Future<void> setKeepAwake(bool enabled);
  Future<void> setLaunchAtStartup(bool enabled);

  /// A7 D26 "Cho phép điều khiển ShellX bằng dòng lệnh". Daemon-owned
  /// (D13): the host there rechecks its open connections at once.
  Future<void> setCliControlEnabled(bool enabled);

  /// A7 amendment "Cho phép terminal khác"; the host rechecks.
  Future<void> setCliAllowExternal(bool enabled);

  /// A8 D11 "Cài hook ShellX trên máy chủ"; only for opens from now on.
  Future<void> setSshRemoteHook(bool enabled);
  Future<void> completeOnboarding();
  Future<PairingView?> startPairing();
  Future<void> cancelPairing();
  Future<void> revoke(String mobileId);
  Future<void> closeSession(int id);
  Future<SharingPlan?> prepareTerminalSharing();
  Future<bool> enableTerminalSharing(SharingPlan plan);
  Future<void> disableTerminalSharing();
  Future<void> disconnectDesktopPhone(int id);
  Future<void> closeAllSessions();
  Future<void> reconnect();
  Future<void> checkForUpdate();
  Future<void> shutdown();
}

/// The in-process controller; a UI that attaches to the background service
/// overrides it with `RemoteAgentController` (Task 8).
final agentControllerProvider =
    NotifierProvider<AgentControllerBase, AgentViewState>(AgentController.new);
