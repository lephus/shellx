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
  const Quit({this.confirm = true});

  /// False for the Windows Restart Manager quit (A5a D18 amended): the
  /// system asked the app to close and the save is done; nothing to ask.
  final bool confirm;
}

/// A5b D14 "Thoát hoàn toàn": every shell and the background service end.
/// (`Quit` leaves them running.) Without the background service it is
/// `Quit`.
final class QuitAll extends TrayAction {
  const QuitAll();
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

/// A4 D20: "Thông báo trên máy tính".
final class ToggleDesktopNotifications extends TrayAction {
  const ToggleDesktopNotifications();
}

/// A4 D20: "Chỉ khi cửa sổ không ở phía trước".
final class ToggleDesktopNotificationsOnlyUnfocused extends TrayAction {
  const ToggleDesktopNotificationsOnlyUnfocused();
}

/// A5a D13: "Lưu nội dung terminal khi thoát".
final class ToggleRestoreScrollback extends TrayAction {
  const ToggleRestoreScrollback();
}

/// A5b ruling: "Giữ shell chạy khi đóng cửa sổ" (applies at the next
/// launch).
final class ToggleBackgroundService extends TrayAction {
  const ToggleBackgroundService();
}

/// A5a D13: "Xóa nội dung đã lưu".
final class ClearSavedScrollback extends TrayAction {
  const ClearSavedScrollback();
}

/// A7 D26: "Cho phép điều khiển ShellX bằng dòng lệnh".
final class ToggleCliControl extends TrayAction {
  const ToggleCliControl();
}

/// A7 amendment: "Cho phép terminal khác".
final class ToggleCliAllowExternal extends TrayAction {
  const ToggleCliAllowExternal();
}

/// A7 D8: "Cài lệnh shellx cho mọi terminal…" / "Gỡ lệnh shellx khỏi
/// terminal khác".
final class ToggleCliPath extends TrayAction {
  const ToggleCliPath();
}

/// A7 D26: "Sao chép lệnh cài skill cho agent".
final class CopySkillsCommand extends TrayAction {
  const CopySkillsCommand();
}

/// A9 D45: the "Cấu hình" submenu. Each brings the window to the front.
final class OpenConfigFile extends TrayAction {
  const OpenConfigFile();
}

final class ReloadConfig extends TrayAction {
  const ReloadConfig();
}

/// A11 D3: the Settings window.
final class OpenSettings extends TrayAction {
  const OpenSettings();
}

final class ShowShortcutsFromTray extends TrayAction {
  const ShowShortcutsFromTray();
}

final class ShowConfigProblemsFromTray extends TrayAction {
  const ShowConfigProblemsFromTray();
}

/// A8 D41, UI-A8 §5.3: the "SSH" submenu. The first two bring the window
/// to the front, then open "Connect to a server" on its SSH / tmux tab.
final class OpenSshConnect extends TrayAction {
  const OpenSshConnect();
}

final class OpenTmuxAttach extends TrayAction {
  const OpenTmuxAttach();
}

/// A8 D11: "Cài hook ShellX trên máy chủ".
final class ToggleSshHook extends TrayAction {
  const ToggleSshHook();
}

/// A8 D6: "Xóa danh sách máy gần đây".
final class ClearRecentServers extends TrayAction {
  const ClearRecentServers();
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
  static const String quitAll = 'quit_all';
  static const String terminalSharing = 'terminal_sharing';
  static const String terminalSharingSetup = 'terminal_sharing_setup';
  static const String desktopTerminals = 'desktop_terminals';
  static const String notifyThreshold = 'notify_threshold';
  static const String notifications = 'notifications';
  static const String desktopNotifications = 'desktop_notifications';
  static const String desktopNotificationsOnlyUnfocused =
      'desktop_notifications_only_unfocused';
  static const String terminal = 'terminal';
  static const String restoreScrollback = 'restore_scrollback';
  static const String backgroundService = 'background_service';
  static const String clearSavedScrollback = 'clear_saved_scrollback';
  static const String commandLine = 'command_line';
  static const String cliControl = 'cli_control';
  static const String cliAllowExternal = 'cli_allow_external';
  static const String cliPath = 'cli_path';
  static const String cliSkills = 'cli_skills';
  static const String ssh = 'ssh';
  static const String sshConnect = 'ssh_connect';
  static const String tmuxAttach = 'tmux_attach';
  static const String sshHook = 'ssh_hook';
  static const String sshClearRecent = 'ssh_clear_recent';
  static const String config = 'config';
  static const String configSettings = 'config_settings';
  static const String configOpen = 'config_open';
  static const String configReload = 'config_reload';
  static const String configShortcuts = 'config_shortcuts';
  static const String configProblems = 'config_problems';

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
    TrayKeys.quitAll => const QuitAll(),
    TrayKeys.terminalSharing => const ToggleTerminalSharing(),
    TrayKeys.terminalSharingSetup => const SetUpTerminalSharing(),
    TrayKeys.desktopNotifications => const ToggleDesktopNotifications(),
    TrayKeys.desktopNotificationsOnlyUnfocused =>
      const ToggleDesktopNotificationsOnlyUnfocused(),
    TrayKeys.restoreScrollback => const ToggleRestoreScrollback(),
    TrayKeys.backgroundService => const ToggleBackgroundService(),
    TrayKeys.clearSavedScrollback => const ClearSavedScrollback(),
    TrayKeys.cliControl => const ToggleCliControl(),
    TrayKeys.cliAllowExternal => const ToggleCliAllowExternal(),
    TrayKeys.cliPath => const ToggleCliPath(),
    TrayKeys.cliSkills => const CopySkillsCommand(),
    TrayKeys.sshConnect => const OpenSshConnect(),
    TrayKeys.tmuxAttach => const OpenTmuxAttach(),
    TrayKeys.sshHook => const ToggleSshHook(),
    TrayKeys.sshClearRecent => const ClearRecentServers(),
    TrayKeys.configSettings => const OpenSettings(),
    TrayKeys.configOpen => const OpenConfigFile(),
    TrayKeys.configReload => const ReloadConfig(),
    TrayKeys.configShortcuts => const ShowShortcutsFromTray(),
    TrayKeys.configProblems => const ShowConfigProblemsFromTray(),
    _ => null,
  };
}
