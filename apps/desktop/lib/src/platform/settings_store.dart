import 'package:shared_preferences/shared_preferences.dart';

/// Non-secret switches (spec §8.4: shared_preferences).
abstract final class SettingKeys {
  static const String remoteAccess = 'remote_access_enabled';
  static const String keepAwake = 'keep_awake_enabled';
  static const String launchAtStartup = 'launch_at_startup_enabled';
  static const String onboardingDone = 'onboarding_done';
  static const String terminalSharing = 'terminal_sharing_enabled';

  /// Startup files the last enable changed (a string list): disable cleans
  /// them even when PowerShell no longer reports a profile.
  static const String terminalSharingFiles = 'terminal_sharing_files';

  /// Push spec §7: "Thông báo khi lệnh chạy lâu xong", in seconds (0 = off;
  /// missing = the default, see `notify_threshold.dart`).
  static const String notifyThreshold = 'command_notify_threshold_seconds';

  /// Terminal font size in points (UI §1.3: 9–28, default 13).
  static const String terminalFontSize = 'terminal_font_size';

  /// The terminal window's last bounds (A1 D9), logical pixels.
  static const String windowX = 'window_x';
  static const String windowY = 'window_y';
  static const String windowWidth = 'window_width';
  static const String windowHeight = 'window_height';

  /// The window was maximized or full screen when last moved or resized:
  /// the next launch maximizes it again over the last normal bounds.
  static const String windowMaximized = 'window_maximized';

  /// A2 D17: the sidebar's workspaces, in order — one JSON object
  /// `{"id","name","collapsed"}` per entry. Membership is not stored.
  static const String terminalWorkspaces = 'terminal_workspaces';

  /// A4 D20: "Thông báo trên máy tính" (default on).
  static const String desktopNotifications = 'desktop_notifications_enabled';

  /// A4 D20: "Chỉ khi cửa sổ không ở phía trước" (default on).
  static const String desktopNotificationsOnlyUnfocused =
      'desktop_notifications_only_unfocused';

  /// A5a D13: "Lưu nội dung terminal khi thoát" (default on).
  static const String terminalRestoreScrollback = 'terminal_restore_scrollback';

  /// A7 D26: "Cho phép điều khiển ShellX bằng dòng lệnh" (default on).
  static const String cliControlEnabled = 'cli_control_enabled';

  /// A7 D8: the `shellx` link/PATH entry for other terminals is installed.
  static const String cliPathInstalled = 'cli_path_installed';

  /// A7 amendment: "Cho phép terminal khác" — clients without the
  /// per-launch `SHELLX_CLI_TOKEN` get full access (default off).
  static const String cliAllowExternal = 'cli_allow_external';

  /// A9 D4: "Đang dùng font và màu từ cấu hình Ghostty" was shown once.
  static const String configGhosttyNoticeShown = 'config_ghostty_notice_shown';

  /// A8 D6: the last 10 servers connected to, newest first.
  static const String sshRecentTargets = 'ssh_recent_targets';

  /// A8 D11: servers that get no ShellX hook.
  static const String sshPlainTargets = 'ssh_plain_targets';

  /// A8 D11: tray "Install the ShellX hook on servers" (default on).
  static const String sshRemoteHook = 'ssh_remote_hook';

  /// A5b D14: the first-quit explanation ("Thoát" leaves the background
  /// service running) was shown once. UI-owned.
  static const String quitKeepsSessionsExplained =
      'quit_keeps_sessions_explained';

  /// A5b D13 ruling: "Giữ shell chạy khi đóng cửa sổ". Off (default): the
  /// app runs its shells itself, as before A5b. On: at the next launch the
  /// UI attaches to the background service. UI-owned.
  static const String backgroundService = 'background_service_enabled';

  /// The one default of [backgroundService]: read it through
  /// [backgroundServiceEnabled] (the launch decision and the tray menu).
  static const bool backgroundServiceDefault = false;

  /// A11 D24: the first-run tour was finished or skipped. UI-owned.
  static const String tourDone = 'tour_done';

  /// A11 D23: the release (without the build number) the window last
  /// started on, a one-element string list. UI-owned.
  static const String lastSeenVersion = 'last_seen_version';

  /// A12 D17: the SHA-256 (hex) of each `agent-event-command` string the
  /// user allowed, newest last, at most 20. Never the string. UI-owned.
  static const String agentCommandApproved = 'agent_command_approved';

  /// A12 D19: the app language, a one-element string list: `system`, `en`
  /// or `vi` (missing or anything else: `system`). Read once at start, so a
  /// change shows after a restart. UI-owned.
  static const String appLanguage = 'app_language';

  /// V2-1 D4: the one-time "how do you want to work?" card was answered or
  /// closed. UI-owned.
  static const String aiIntroShown = 'ai_intro_shown';

  /// V2-1 D23: the agent "New AI session" starts, a one-element list (an
  /// agent id); missing: the first ready one. UI-owned.
  static const String aiDefaultAgent = 'ai_default_agent';

  /// V2-1 D7: the user's own agents, one JSON object per element. UI-owned.
  static const String aiCustomAgents = 'ai_custom_agents';

  /// V2-1 D11: the remembered choices per agent, one
  /// `agent<TAB>config<TAB>json value` per element. UI-owned.
  static const String aiAgentConfig = 'ai_agent_config';

  /// V2-3 D2: the personal tools of every workspace, one JSON object
  /// `{id, ws, name, url, phone}` per element. UI-owned.
  static const String workspaceTools = 'workspace_tools';

  static const Set<String> all = {
    remoteAccess,
    keepAwake,
    launchAtStartup,
    onboardingDone,
    terminalSharing,
    terminalSharingFiles,
    notifyThreshold,
    terminalFontSize,
    windowX,
    windowY,
    windowWidth,
    windowHeight,
    windowMaximized,
    terminalWorkspaces,
    desktopNotifications,
    desktopNotificationsOnlyUnfocused,
    terminalRestoreScrollback,
    cliControlEnabled,
    cliPathInstalled,
    cliAllowExternal,
    configGhosttyNoticeShown,
    sshRecentTargets,
    sshPlainTargets,
    sshRemoteHook,
    quitKeepsSessionsExplained,
    backgroundService,
    tourDone,
    lastSeenVersion,
    agentCommandApproved,
    appLanguage,
    aiIntroShown,
    aiDefaultAgent,
    aiCustomAgents,
    aiAgentConfig,
    workspaceTools,
  };
}

/// A5b D13: with the background service, two processes share one
/// preferences file but each keeps its own cache, so every key has exactly
/// one process that writes and reads it. The daemon's keys are the ones the
/// service itself needs; the UI reads and toggles them through
/// `AgentViewState` and `agent.call`, never through its own store.
///
/// Beyond the spec's nine: the CLI host (daemon) reads `cli_control_enabled`
/// and `cli_allow_external`, and sessions the daemon spawns decide the ssh
/// hook (`ssh_remote_hook`), while the tray (UI) only toggles them.
abstract final class DaemonSettingKeys {
  static const Set<String> all = {
    SettingKeys.remoteAccess,
    SettingKeys.keepAwake,
    SettingKeys.launchAtStartup,
    SettingKeys.onboardingDone,
    SettingKeys.terminalSharing,
    SettingKeys.terminalSharingFiles,
    SettingKeys.notifyThreshold,
    SettingKeys.desktopNotifications,
    SettingKeys.desktopNotificationsOnlyUnfocused,
    SettingKeys.cliControlEnabled,
    SettingKeys.cliAllowExternal,
    SettingKeys.sshRemoteHook,
  };
}

/// Everything else: the window, the terminal, the sidebar, the restore and
/// config notices, the ssh target lists (A8 D6, D11) and `cli_path_installed`
/// (the `shellx` link is installed from the UI).
abstract final class UiSettingKeys {
  static const Set<String> all = {
    SettingKeys.terminalFontSize,
    SettingKeys.windowX,
    SettingKeys.windowY,
    SettingKeys.windowWidth,
    SettingKeys.windowHeight,
    SettingKeys.windowMaximized,
    SettingKeys.terminalWorkspaces,
    SettingKeys.terminalRestoreScrollback,
    SettingKeys.cliPathInstalled,
    SettingKeys.configGhosttyNoticeShown,
    SettingKeys.sshRecentTargets,
    SettingKeys.sshPlainTargets,
    SettingKeys.quitKeepsSessionsExplained,
    SettingKeys.backgroundService,
    SettingKeys.tourDone,
    SettingKeys.lastSeenVersion,
    SettingKeys.agentCommandApproved,
    SettingKeys.appLanguage,
    SettingKeys.aiIntroShown,
    SettingKeys.aiDefaultAgent,
    SettingKeys.aiCustomAgents,
    SettingKeys.aiAgentConfig,
    SettingKeys.workspaceTools,
  };
}

abstract interface class SettingsStore {
  bool getBool(String key, {required bool defaultValue});
  Future<void> setBool(String key, bool value);
  List<String> getStrings(String key);
  Future<void> setStrings(String key, List<String> values);
  int? getInt(String key);
  Future<void> setInt(String key, int value);
}

final class SharedPrefsSettingsStore implements SettingsStore {
  SharedPrefsSettingsStore._(this._prefs);

  static Future<SharedPrefsSettingsStore> open() async {
    final prefs = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(
        allowList: SettingKeys.all,
      ),
    );
    return SharedPrefsSettingsStore._(prefs);
  }

  final SharedPreferencesWithCache _prefs;

  @override
  bool getBool(String key, {required bool defaultValue}) =>
      _prefs.getBool(key) ?? defaultValue;

  @override
  Future<void> setBool(String key, bool value) => _prefs.setBool(key, value);

  /// A value of another type (an older or corrupted install) reads as
  /// empty: `getStringList` would throw a cast error at startup.
  @override
  List<String> getStrings(String key) => switch (_prefs.get(key)) {
    final List<Object?> list => [
      for (final value in list)
        if (value is String) value,
    ],
    _ => const [],
  };

  @override
  Future<void> setStrings(String key, List<String> values) =>
      _prefs.setStringList(key, values);

  @override
  int? getInt(String key) => _prefs.getInt(key);

  @override
  Future<void> setInt(String key, int value) => _prefs.setInt(key, value);
}

final class InMemorySettingsStore implements SettingsStore {
  InMemorySettingsStore([Map<String, bool>? values]) : values = values ?? {};

  final Map<String, bool> values;

  /// Simulates a storage failure (a tray action that fails, Task 9).
  bool fail = false;

  @override
  bool getBool(String key, {required bool defaultValue}) =>
      values[key] ?? defaultValue;

  @override
  Future<void> setBool(String key, bool value) async {
    if (fail) throw StateError('settings write failed');
    values[key] = value;
  }

  final Map<String, List<String>> strings = {};

  @override
  List<String> getStrings(String key) => strings[key] ?? const [];

  @override
  Future<void> setStrings(String key, List<String> values) async {
    if (fail) throw StateError('settings write failed');
    strings[key] = List.of(values);
  }

  final Map<String, int> ints = {};

  @override
  int? getInt(String key) => ints[key];

  @override
  Future<void> setInt(String key, int value) async {
    if (fail) throw StateError('settings write failed');
    ints[key] = value;
  }
}

/// The stored "keep shells running when the window closes" switch, with its
/// single default.
bool backgroundServiceEnabled(SettingsStore settings) => settings.getBool(
  SettingKeys.backgroundService,
  defaultValue: SettingKeys.backgroundServiceDefault,
);
