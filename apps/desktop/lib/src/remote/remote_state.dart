import 'package:shellx_agent/shellx_agent.dart';

/// A8 D17, as the pane shows it.
enum RemoteState { connecting, connected, disconnected, failed, exited }

/// UI-A8 §3.2 "Try without the hook" (D11).
SessionLaunch launchWithoutHook(SessionLaunch launch) => launch.withHook(false);

/// Null for a local shell and a tmux client on this computer (A1 rules).
RemoteState? remoteStateOf({
  required SessionRemote? remote,
  required int? exitCode,
  required bool everConnected,
}) {
  if (remote == null || remote.launch.host == null) return null;
  if (exitCode != null) {
    if (!everConnected) return RemoteState.failed;
    return exitCode == 255 ? RemoteState.disconnected : RemoteState.exited;
  }
  return remote.connected ? RemoteState.connected : RemoteState.connecting;
}
