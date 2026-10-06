import '../agent/notify_threshold.dart';

/// Everything the tray menu can ask for.
sealed class TrayAction {
  const TrayAction();
}

/// A1 D11: the first tray item.
final class OpenTerminalWindow extends TrayAction {
  const OpenTerminalWindow();
}

final class ToggleRemoteAccess extends TrayAction {
  const ToggleRemoteAccess();
}

final class CloseSession extends TrayAction {
  const CloseSession(this.id);
  final int id;
}

final class CloseAllSessions extends TrayAction {
  const CloseAllSessions();
}

final class PairPhone extends TrayAction {
  const PairPhone();
}

final class RevokeDevice extends TrayAction {
  const RevokeDevice(this.mobileId);
  final String mobileId;
}

final class ToggleKeepAwake extends TrayAction {
  const ToggleKeepAwake();
}

final class ToggleLaunchAtStartup extends TrayAction {
  const ToggleLaunchAtStartup();
}

final class OpenChangePassword extends TrayAction {
  const OpenChangePassword();
}

final class SignOut extends TrayAction {
  const SignOut();
}

final class SignIn extends TrayAction {
  const SignIn();
}

final class DownloadUpdate extends TrayAction {
  const DownloadUpdate();
}

/// Spec §12 forbids the relay from reconnecting on its own after a 4001
/// (`replaced`) close; this explicit tray action is the only way back
/// (binding ruling, Task 8). Routes to `AgentController.reconnect()`.
final class Reconnect extends TrayAction {
  const Reconnect();
}

final class Quit extends TrayAction {
  const Quit();
}

/// The terminal-sharing switch (spec §7.6, §10.1, §10.5).
final class ToggleTerminalSharing extends TrayAction {
  const ToggleTerminalSharing();
}

/// The "needs to be set up again" warning: the enable flow once more.
final class SetUpTerminalSharing extends TrayAction {
  const SetUpTerminalSharing();
}

/// "Thông báo khi lệnh chạy lâu xong" (push spec §7): one of the choices,
/// in seconds (0 = off).
final class SetNotifyThreshold extends TrayAction {
  const SetNotifyThreshold(this.seconds);
  final int seconds;
}

/// "Disconnect phone" on a desktop terminal; never ends the terminal.
final class DisconnectDesktopPhone extends TrayAction {
  const DisconnectDesktopPhone(this.id);
  final int id;
}

/// Menu item keys. Dynamic keys embed the session id / mobile device id.
abstract final class TrayKeys {
  static const String openTerminal = 'open_terminal';
  static const String status = 'status';
  static const String downloadUpdate = 'download_update';
  static const String reconnect = 'reconnect';
  static const String remoteAccess = 'remote_access';
  static const String sessions = 'sessions';
  static const String closeAll = 'sessions_close_all';
  static const String pair = 'pair';
  static const String devices = 'devices';
  static const String noDevices = 'devices_none';
  static const String keepAwake = 'keep_awake';
  static const String launchAtStartup = 'launch_at_startup';
  static const String changePassword = 'change_password';
  static const String signOut = 'sign_out';
  static const String signIn = 'sign_in';
  static const String quit = 'quit';
  static const String terminalSharing = 'terminal_sharing';
  static const String terminalSharingSetup = 'terminal_sharing_setup';
  static const String desktopTerminals = 'desktop_terminals';
  static const String notifyThreshold = 'notify_threshold';

  static String session(int id) => 'session:$id';
  static String closeSession(int id) => 'session_close:$id';
  static String device(String mobileId) => 'device:$mobileId';
  static String revoke(String mobileId) => 'revoke:$mobileId';
  static String desktopTerminal(int id) => 'desktop_terminal:$id';
  static String disconnectPhone(int id) => 'desktop_disconnect:$id';
  static String notifyThresholdChoice(int seconds) =>
      'notify_threshold:$seconds';
}

TrayAction? trayActionForKey(String? key) {
  if (key == null) return null;
  const closePrefix = 'session_close:';
  const revokePrefix = 'revoke:';
  const disconnectPrefix = 'desktop_disconnect:';
  const thresholdPrefix = 'notify_threshold:';
  if (key.startsWith(thresholdPrefix)) {
    final seconds = int.tryParse(key.substring(thresholdPrefix.length));
    return seconds == null || !kNotifyThresholdChoices.contains(seconds)
        ? null
        : SetNotifyThreshold(seconds);
  }
  if (key.startsWith(disconnectPrefix)) {
    final id = int.tryParse(key.substring(disconnectPrefix.length));
    return id == null ? null : DisconnectDesktopPhone(id);
  }
  if (key.startsWith(closePrefix)) {
    final id = int.tryParse(key.substring(closePrefix.length));
    return id == null ? null : CloseSession(id);
  }
  if (key.startsWith(revokePrefix)) {
    final mobileId = key.substring(revokePrefix.length);
    return mobileId.isEmpty ? null : RevokeDevice(mobileId);
  }
  return switch (key) {
    TrayKeys.openTerminal => const OpenTerminalWindow(),
    TrayKeys.remoteAccess => const ToggleRemoteAccess(),
    TrayKeys.closeAll => const CloseAllSessions(),
    TrayKeys.pair => const PairPhone(),
    TrayKeys.keepAwake => const ToggleKeepAwake(),
    TrayKeys.launchAtStartup => const ToggleLaunchAtStartup(),
    TrayKeys.changePassword => const OpenChangePassword(),
    TrayKeys.signOut => const SignOut(),
    TrayKeys.signIn => const SignIn(),
    TrayKeys.downloadUpdate => const DownloadUpdate(),
    TrayKeys.reconnect => const Reconnect(),
    TrayKeys.quit => const Quit(),
    TrayKeys.terminalSharing => const ToggleTerminalSharing(),
    TrayKeys.terminalSharingSetup => const SetUpTerminalSharing(),
    _ => null,
  };
}
