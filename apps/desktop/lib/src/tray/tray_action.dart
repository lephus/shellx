/// Everything the tray menu can ask for.
sealed class TrayAction {
  const TrayAction();
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

/// Menu item keys. Dynamic keys embed the session id / mobile device id.
abstract final class TrayKeys {
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

  static String session(int id) => 'session:$id';
  static String closeSession(int id) => 'session_close:$id';
  static String device(String mobileId) => 'device:$mobileId';
  static String revoke(String mobileId) => 'revoke:$mobileId';
}

TrayAction? trayActionForKey(String? key) {
  if (key == null) return null;
  const closePrefix = 'session_close:';
  const revokePrefix = 'revoke:';
  if (key.startsWith(closePrefix)) {
    final id = int.tryParse(key.substring(closePrefix.length));
    return id == null ? null : CloseSession(id);
  }
  if (key.startsWith(revokePrefix)) {
    final mobileId = key.substring(revokePrefix.length);
    return mobileId.isEmpty ? null : RevokeDevice(mobileId);
  }
  return switch (key) {
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
    _ => null,
  };
}
