// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'ShellX';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionClose => 'Close';

  @override
  String get authSignInTitle => 'Sign in to ShellX';

  @override
  String get authRegisterTitle => 'Create a ShellX account';

  @override
  String get authEmailLabel => 'Email';

  @override
  String get authPasswordLabel => 'Password';

  @override
  String get authConfirmPasswordLabel => 'Re-enter password';

  @override
  String get authSignInButton => 'Sign in';

  @override
  String get authRegisterButton => 'Create account';

  @override
  String get authSwitchToRegister => 'No account yet? Create one';

  @override
  String get authSwitchToSignIn => 'Already have an account? Sign in';

  @override
  String get authForgotPasswordHint =>
      'Forgot your password? On another computer that is still signed in to ShellX, choose “Change password…” in the tray menu.';

  @override
  String get authSignedOutNotice => 'You were signed out. Sign in again.';

  @override
  String get errorEmailInvalid => 'Enter a valid email address.';

  @override
  String get errorPasswordLength => 'Password must be 8–128 characters.';

  @override
  String get errorPasswordMismatch => 'Passwords do not match.';

  @override
  String get errorDisposableEmail =>
      'Temporary email addresses are not allowed. Use a permanent address.';

  @override
  String get errorEmailTaken =>
      'This email is already registered. Sign in instead.';

  @override
  String get errorInvalidCredentials => 'Incorrect email or password.';

  @override
  String get errorRateLimited => 'Try again in a few minutes.';

  @override
  String get errorNetwork =>
      'Cannot reach the ShellX server. Check your Internet connection.';

  @override
  String get errorAgentOnly =>
      'Only a signed-in computer can change the password.';

  @override
  String errorUnexpected(String code) {
    return 'Something went wrong ($code). Try again.';
  }

  @override
  String get onboardingTitle => 'Almost done';

  @override
  String get onboardingLaunchAtStartup =>
      'Start ShellX when the computer starts';

  @override
  String get onboardingFullDiskTitle => 'Full Disk Access (optional)';

  @override
  String get onboardingFullDiskBody =>
      'Commands that touch Desktop, Documents or Downloads make macOS show a permission prompt on this computer\'s screen, which you cannot answer from your phone. Give ShellX Full Disk Access to avoid it.';

  @override
  String get onboardingOpenSettings => 'Open System Settings';

  @override
  String get onboardingSleepTitle => 'Sleep';

  @override
  String get onboardingSleepBody =>
      'ShellX keeps the computer from sleeping while idle. Closing the laptop lid still puts it to sleep, and then your phone cannot reach it.';

  @override
  String onboardingTrayHint(String platform) {
    String _temp0 = intl.Intl.selectLogic(platform, {
      'macos':
          'Your terminal is in the ShellX window. ShellX also stays in the menu bar: choose “Pair phone…” there to connect your phone.',
      'other':
          'Your terminal is in the ShellX window. ShellX also stays in the system tray: choose “Pair phone…” there to connect your phone.',
    });
    return '$_temp0';
  }

  @override
  String get onboardingFinish => 'Finish';

  @override
  String get trayOpenTerminal => 'Open terminal window';

  @override
  String windowTitle(String title) {
    return '$title — ShellX';
  }

  @override
  String get dialogClose => 'Close';

  @override
  String get trayTooltip => 'ShellX';

  @override
  String trayStatusConnected(String email) {
    return 'Connected — $email';
  }

  @override
  String trayStatusConnecting(String email) {
    return 'Connecting — $email';
  }

  @override
  String get trayStatusReconnecting => 'Disconnected — retrying…';

  @override
  String get trayStatusRemoteOff => 'Remote access is off';

  @override
  String get trayStatusReplaced =>
      'Another copy of ShellX took over this computer';

  @override
  String get trayStatusSignedOut => 'Not signed in';

  @override
  String get trayReconnect => 'Reconnect';

  @override
  String get trayRemoteAccess => 'Allow remote access';

  @override
  String traySessions(int count) {
    return 'Active sessions ($count)';
  }

  @override
  String traySessionItem(String shell, int index) {
    return '$shell $index';
  }

  @override
  String traySessionItemAttached(String shell, int index, String device) {
    return '$shell $index — $device';
  }

  @override
  String get traySessionClose => 'Close';

  @override
  String get trayCloseAll => 'Close all';

  @override
  String get trayPairPhone => 'Pair phone…';

  @override
  String get trayPairedDevices => 'Paired devices';

  @override
  String get trayRevoke => 'Revoke';

  @override
  String get trayNoDevices => 'No paired devices';

  @override
  String get trayKeepAwake => 'Keep computer awake';

  @override
  String get trayLaunchAtStartup => 'Start with system';

  @override
  String get trayChangePassword => 'Change password…';

  @override
  String get traySignOut => 'Sign out';

  @override
  String get traySignIn => 'Sign in…';

  @override
  String get trayQuit => 'Quit';

  @override
  String trayDownloadUpdate(String version) {
    return 'Download ShellX $version…';
  }

  @override
  String get confirmRemoteOffTitle => 'Turn off remote access?';

  @override
  String get confirmRemoteOffBody =>
      'Connected phones will be disconnected. Terminal tabs on this computer keep running.';

  @override
  String get confirmRemoteOffAction => 'Turn off';

  @override
  String get confirmSignOutTitle => 'Sign out of ShellX?';

  @override
  String get confirmSignOutBody =>
      'Connected phones will be disconnected and every paired phone will be removed. Terminal tabs on this computer keep running. After signing in again you must pair your phones again.';

  @override
  String get confirmSignOutAction => 'Sign out';

  @override
  String confirmRevokeTitle(String device) {
    return 'Revoke $device?';
  }

  @override
  String get confirmRevokeBody =>
      'This phone loses access to this computer immediately and the sessions it opened are closed. Tabs opened on this computer keep running. To use it again you must pair it again.';

  @override
  String get confirmRevokeAction => 'Revoke';

  @override
  String get confirmQuitTitle => 'Quit ShellX?';

  @override
  String confirmQuitBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count open tabs will be closed. Your phones cannot reach this computer until ShellX runs again.',
      one:
          '1 open tab will be closed. Your phones cannot reach this computer until ShellX runs again.',
    );
    return '$_temp0';
  }

  @override
  String get confirmQuitAction => 'Quit';

  @override
  String get pairingTitle => 'Pair a phone';

  @override
  String get pairingInstructions =>
      'Open ShellX on your phone (signed in to the same account), tap this computer and scan the code.';

  @override
  String pairingExpiresIn(String time) {
    return 'Code expires in $time';
  }

  @override
  String get pairingExpired => 'This code has expired.';

  @override
  String get pairingNewCode => 'Create new code';

  @override
  String get pairingOfflineWarning =>
      'Not connected to the ShellX server. Your phone can pair once the connection is back.';

  @override
  String get pairingSecretWarning =>
      'Anyone who scans this code while signed in to your account can control this computer. Do not share it.';

  @override
  String get changePasswordTitle => 'Change password';

  @override
  String get changePasswordNew => 'New password';

  @override
  String get changePasswordConfirm => 'Re-enter new password';

  @override
  String get changePasswordSubmit => 'Change password';

  @override
  String get changePasswordNote =>
      'Other devices will be signed out. Pairings are kept.';

  @override
  String get changePasswordDone =>
      'Password changed. Your phones must sign in again with the new password.';

  @override
  String notifySessionOpened(String device) {
    return '$device opened a terminal session';
  }

  @override
  String notifyPaired(String device) {
    return 'Paired with $device';
  }

  @override
  String notifyUpdateAvailableTitle(String version) {
    return 'ShellX $version is available';
  }

  @override
  String get notifyUpdateAvailableBody => 'Click to download.';

  @override
  String get notifyUpdateRequiredTitle => 'ShellX needs to be updated';

  @override
  String notifyUpdateRequiredBody(String version) {
    return 'This version is no longer supported. Click to download ShellX $version.';
  }

  @override
  String get notifySignedOutTitle => 'ShellX was signed out';

  @override
  String get notifySignedOutBody => 'Sign in again to allow remote access.';

  @override
  String get notifyTerminalProblemTitle =>
      'Processes from a terminal session may still be running';

  @override
  String notifyTerminalProblemBody(int count, String pids) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Shell process IDs: $pids',
      one: 'Shell process ID: $pids',
    );
    return '$_temp0';
  }

  @override
  String get notifyStorageUnreadableTitle =>
      'ShellX could not read your saved sign-in';

  @override
  String get notifySignOutIncompleteTitle =>
      'Signed out, but some saved sign-in data could not be deleted';

  @override
  String get trayTerminalSharing => 'Share terminals with phone (experimental)';

  @override
  String get trayNotifyThreshold => 'Notify when long commands finish';

  @override
  String get trayNotifyOff => 'Off';

  @override
  String trayNotifySeconds(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count seconds',
      one: '1 second',
    );
    return '$_temp0';
  }

  @override
  String trayNotifyMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutes',
      one: '1 minute',
    );
    return '$_temp0';
  }

  @override
  String trayDesktopTerminals(int count) {
    return 'Computer terminals ($count)';
  }

  @override
  String get trayDisconnectPhone => 'Disconnect phone';

  @override
  String get trayTerminalSharingNeedsSetup =>
      'Terminal sharing needs to be set up again…';

  @override
  String notifyDesktopTerminalWatched(String device, String terminal) {
    return '$device is viewing terminal $terminal';
  }

  @override
  String get notifyTerminalSharingFailedTitle =>
      'Could not turn on terminal sharing';

  @override
  String get notifyTerminalSharingFailedBody =>
      'Nothing was changed. Try again.';

  @override
  String get notifyTerminalSharingStartFailedTitle =>
      'Terminal sharing could not start';

  @override
  String get notifyTerminalSharingDisableIncompleteTitle =>
      'Terminal sharing is off, but the ShellX block could not be removed from some files';

  @override
  String get confirmSharingTitle => 'Share terminals with your phone?';

  @override
  String get confirmSharingIntro =>
      'Every terminal window you open from now on can be viewed and typed into from your paired phones. Windows that are already open are not shared.';

  @override
  String get confirmSharingFiles =>
      'ShellX will change these files (each existing file is backed up once as <name>.shellx-backup):';

  @override
  String confirmSharingFileCreated(String path) {
    return '$path (new file)';
  }

  @override
  String confirmSharingBinary(String path) {
    return 'and copy shellx-term to $path.';
  }

  @override
  String get confirmSharingBashSkipped =>
      'There is no ~/.bashrc or ~/.bash_profile, so bash windows are not shared.';

  @override
  String get confirmSharingMacNote =>
      'Note: Terminal.app (and possibly iTerm2) will no longer ask for confirmation when you close a window that is running a command.';

  @override
  String get confirmSharingWindowsNote =>
      'Each PowerShell window will open a little slower and use some extra memory.';

  @override
  String confirmSharingPowerShellBlocked(String name) {
    return '$name: running scripts is not allowed, so its profile will not run until local scripts are allowed.';
  }

  @override
  String confirmSharingPowerShellGroupPolicy(String name) {
    return '$name: the script policy is set by your organization (Group Policy), so this PowerShell will not be shared.';
  }

  @override
  String get confirmSharingNoPowerShell =>
      'No PowerShell was found on this computer.';

  @override
  String get confirmSharingAction => 'Turn on';

  @override
  String get confirmAllowScriptsTitle => 'Allow local scripts?';

  @override
  String confirmAllowScriptsBody(String names) {
    return '$names: running scripts is not allowed, so the ShellX block in the profile cannot run. This sets the policy to RemoteSigned for your account only (Set-ExecutionPolicy -Scope CurrentUser RemoteSigned).';
  }

  @override
  String get confirmAllowScriptsAction => 'Allow local scripts for my account';

  @override
  String notifyTerminalSharingFailedFile(String path) {
    return 'ShellX could not change $path. Nothing was changed.';
  }

  @override
  String notifyAllowScriptsFailedTitle(String name) {
    return 'Could not allow local scripts for $name';
  }

  @override
  String get startupFailed =>
      'ShellX could not start. Open it again; if this keeps happening, restart your computer.';

  @override
  String get windowsVersionUnsupported =>
      'ShellX requires Windows 10 version 1809 or later.';

  @override
  String terminalExitedLine(int code) {
    return '[Process exited with code $code] — press Enter to close';
  }

  @override
  String get terminalNewTab => 'New tab';

  @override
  String terminalNewTabTooltip(String shortcut) {
    return 'New tab  $shortcut';
  }

  @override
  String get terminalCloseTab => 'Close tab';

  @override
  String get terminalDriverPhone =>
      'Your phone is using this terminal — type to take it back';

  @override
  String get terminalSignedOutStrip =>
      'Sign in to use this computer from your phone';

  @override
  String get terminalSignedOutAction => 'Sign in…';

  @override
  String get terminalEmptyTitle => 'No tabs open';

  @override
  String get terminalEmptyBody =>
      'Open a tab to start a new shell. Sessions you open from your phone show up here too.';

  @override
  String get terminalEmptyAction => 'Open new tab';

  @override
  String terminalSessionLimit(int max) {
    return 'You\'ve reached the limit of $max sessions. Close a tab to open a new one.';
  }

  @override
  String terminalSpawnFailed(String reason) {
    String _temp0 = intl.Intl.selectLogic(reason, {
      'notFound': 'shell not found',
      'denied': 'permission denied',
      'other': 'system error',
    });
    return 'Couldn\'t start the shell: $_temp0. Try again.';
  }

  @override
  String get toastDismiss => 'Dismiss';

  @override
  String confirmCloseRunningTitle(String title) {
    return 'Close “$title”?';
  }

  @override
  String get confirmCloseRunningBody =>
      'The command running in this tab will be stopped.';

  @override
  String get confirmCloseRunningAction => 'Close tab';

  @override
  String get sidebarLabel => 'Tabs';

  @override
  String get sidebarStatusIdle => 'idle';

  @override
  String get sidebarStatusRunning => 'running a command';

  @override
  String sidebarStatusExited(int code) {
    return 'exited with code $code';
  }

  @override
  String get sidebarPhoneOrigin => 'Opened from your phone';

  @override
  String get sidebarPhoneViewing => 'Your phone is viewing';

  @override
  String get sidebarPhoneDriving => 'Your phone is using it';

  @override
  String get sidebarPhoneOriginSemantics => 'opened from your phone';

  @override
  String get sidebarPhoneViewingSemantics => 'your phone is viewing';

  @override
  String get sidebarPhoneDrivingSemantics => 'your phone is using it';

  @override
  String sidebarPosition(int index, int count) {
    return 'tab $index of $count';
  }

  @override
  String terminalPaneLabel(String title) {
    return 'Terminal $title';
  }

  @override
  String confirmCloseAllTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Close all $count tabs?',
      one: 'Close 1 tab?',
    );
    return '$_temp0';
  }

  @override
  String get confirmCloseAllBody =>
      'Every shell in these tabs will be stopped, with any command still running.';

  @override
  String get confirmCloseAllAction => 'Close all';

  @override
  String terminalCloseTabTooltip(String shortcut) {
    return 'Close tab  $shortcut';
  }

  @override
  String get terminalDriverPhoneShort => 'Phone in control — type to take over';

  @override
  String get terminalCopy => 'Copy';

  @override
  String get terminalPaste => 'Paste';

  @override
  String get terminalSelectAll => 'Select all';

  @override
  String get workspaceDefaultName => 'Default';

  @override
  String workspaceNumberedName(int n) {
    return 'Workspace $n';
  }

  @override
  String get workspaceNew => 'New workspace';

  @override
  String get workspaceNewTab => 'New tab in this workspace';

  @override
  String get workspaceRename => 'Rename workspace';

  @override
  String get workspaceDelete => 'Delete workspace';

  @override
  String get workspaceCollapse => 'Collapse';

  @override
  String get workspaceExpand => 'Expand';

  @override
  String get workspaceEmptyHint => 'Empty — drag a tab here';

  @override
  String get workspaceDeleteDefaultReason =>
      'The Default workspace can\'t be deleted';

  @override
  String get workspaceNameField => 'Workspace name';

  @override
  String workspaceDeleted(String name, String defaultName) {
    return 'Deleted workspace “$name”. Its tabs moved to $defaultName.';
  }

  @override
  String workspaceHeaderSemantics(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tabs',
      one: '1 tab',
    );
    return 'Workspace $name, $_temp0';
  }

  @override
  String get workspaceContainsSelected => 'contains the selected tab';

  @override
  String get workspaceCollapsedState => 'collapsed';

  @override
  String get workspaceExpandedState => 'expanded';

  @override
  String get tabRename => 'Rename tab';

  @override
  String get tabNameField => 'Tab name';

  @override
  String get tabUseAutomaticName => 'Use automatic name';

  @override
  String get tabMoveTo => 'Move to workspace…';

  @override
  String tabMoveToTitle(String name) {
    return 'Move “$name” to';
  }

  @override
  String get tabOpenPortMenu => 'Open port in browser…';

  @override
  String get tabMoveUp => 'Move up';

  @override
  String get tabMoveDown => 'Move down';

  @override
  String tabOpenPort(int port) {
    return 'Open port $port in browser';
  }

  @override
  String portOpenTooltip(int port) {
    return 'Open http://localhost:$port';
  }

  @override
  String portsMoreTooltip(String ports) {
    return 'Listening ports: $ports';
  }

  @override
  String get portOpenFailed => 'Couldn\'t open the browser.';

  @override
  String sidebarBranch(String branch) {
    return 'branch $branch';
  }

  @override
  String sidebarFolder(String path) {
    return 'folder $path';
  }

  @override
  String sidebarPorts(int count, String ports) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ports $ports',
      one: 'port $ports',
    );
    return '$_temp0';
  }

  @override
  String sidebarPositionInWorkspace(int index, int count, String workspace) {
    return 'tab $index of $count in $workspace';
  }

  @override
  String get attentionBell => 'Bell';

  @override
  String attentionBellRepeat(int count) {
    return 'Bell ×$count';
  }

  @override
  String get attentionBellBody => 'Bell in this tab';

  @override
  String attentionUnreadCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count unread notifications',
      one: '1 unread notification',
    );
    return '$_temp0';
  }

  @override
  String attentionRowSemantics(int count, String text) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count unread notifications',
      one: '1 unread notification',
    );
    return '$_temp0, latest: $text';
  }

  @override
  String get attentionMarkRead => 'Mark as read';

  @override
  String get attentionMarkAllRead => 'Mark all as read';

  @override
  String attentionAnnounce(String tab, String text) {
    return 'New notification from $tab: $text';
  }

  @override
  String get workspaceHasUnread => 'has unread notifications';

  @override
  String terminalPaneUnreadLabel(String title) {
    return 'Terminal $title, has unread notifications';
  }

  @override
  String get notificationsPanelTitle => 'Notifications';

  @override
  String notificationsPanelTooltip(String shortcut) {
    return 'Notifications  $shortcut';
  }

  @override
  String get notificationsPanelEmptyTitle => 'No notifications yet';

  @override
  String get notificationsPanelEmptyBody =>
      'Programs in your tabs send notifications with OSC 9, 99, 777 or the shellx notify command.';

  @override
  String notificationsPanelNextHint(String shortcut) {
    return 'Next unread  $shortcut';
  }

  @override
  String notificationsPanelOpened(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Notifications, $count items',
      one: 'Notifications, 1 item',
    );
    return '$_temp0';
  }

  @override
  String get notificationsTabClosed => 'Tab closed';

  @override
  String get notificationsTimeNow => 'now';

  @override
  String notificationsTimeMinutes(int count) {
    return '$count min';
  }

  @override
  String notificationsTimeHours(int count) {
    return '$count h';
  }

  @override
  String notificationsTimeYesterday(String time) {
    return 'Yesterday $time';
  }

  @override
  String notificationsTimeDate(
    String month,
    String day,
    String dayPadded,
    String time,
  ) {
    return '$month $day, $time';
  }

  @override
  String notificationsMonthShort(String month) {
    String _temp0 = intl.Intl.selectLogic(month, {
      'm1': 'Jan',
      'm2': 'Feb',
      'm3': 'Mar',
      'm4': 'Apr',
      'm5': 'May',
      'm6': 'Jun',
      'm7': 'Jul',
      'm8': 'Aug',
      'm9': 'Sep',
      'm10': 'Oct',
      'm11': 'Nov',
      'm12': 'Dec',
      'other': '',
    });
    return '$_temp0';
  }

  @override
  String get notificationsItemUnread => 'unread';

  @override
  String get noUnreadNotifications => 'No unread notifications';

  @override
  String systemNotifyCoalesced(int count, String text) {
    return '$count new notifications · $text';
  }

  @override
  String get trayNotifications => 'Notifications';

  @override
  String get trayDesktopNotifications => 'Notifications on this computer';

  @override
  String get trayDesktopNotificationsUnfocused =>
      'Only when the window isn\'t in front';

  @override
  String get paneSplitRight => 'Split right';

  @override
  String get paneSplitDown => 'Split down';

  @override
  String get paneZoom => 'Zoom pane';

  @override
  String get paneUnzoom => 'Unzoom pane';

  @override
  String get paneEqualize => 'Equalize panes';

  @override
  String get paneClose => 'Close pane';

  @override
  String paneCloseTooltip(String shortcut) {
    return 'Close pane  $shortcut';
  }

  @override
  String paneZoomedIndicator(int index, int count) {
    return 'Zoomed · $index/$count';
  }

  @override
  String paneRegionLabel(int index, int count, String title) {
    return 'Pane $index of $count — $title';
  }

  @override
  String paneRegionUnreadLabel(int index, int count, String title) {
    return 'Pane $index of $count — $title, has unread notifications';
  }

  @override
  String get paneDividerLabel => 'Pane divider';

  @override
  String get paneSplitNoRoom => 'Not enough room to split this pane';

  @override
  String paneAnnounceSplit(int index, int count) {
    return 'Split, pane $index of $count';
  }

  @override
  String paneAnnounceClosed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Pane closed, $count left',
      one: 'Pane closed, 1 left',
    );
    return '$_temp0';
  }

  @override
  String get paneAnnounceZoomed => 'Pane zoomed';

  @override
  String get paneAnnounceUnzoomed => 'Pane unzoomed';

  @override
  String sidebarPaneCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count panes',
      one: '1 pane',
    );
    return '$_temp0';
  }

  @override
  String get terminalCloseTabAllPanes => 'Close tab (all panes)';

  @override
  String get confirmCloseRunningPaneBody =>
      'The command running in this pane will be stopped.';

  @override
  String get confirmCloseRunningPaneAction => 'Close pane';

  @override
  String confirmCloseRunningPanesBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'The commands running in $count panes will be stopped.',
      one: 'The command running in 1 pane will be stopped.',
    );
    return '$_temp0';
  }

  @override
  String get confirmCloseAlwaysBody => 'The shell in this tab will close.';

  @override
  String confirmCloseAlwaysPanesBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count panes in this tab will close.',
      one: '1 pane in this tab will close.',
    );
    return '$_temp0';
  }

  @override
  String get confirmClosePaneAlwaysBody => 'The shell in this pane will close.';

  @override
  String terminalRestoredDivider(String time) {
    return '— Session restored · $time —';
  }

  @override
  String restoreTimeYesterday(String time) {
    return 'yesterday $time';
  }

  @override
  String get trayTerminal => 'Terminal';

  @override
  String get trayRestoreScrollback => 'Save terminal contents on quit';

  @override
  String get trayClearSavedScrollback => 'Clear saved contents';

  @override
  String restoreAbnormalStrip(int count, String time) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tabs',
      one: '1 tab',
    );
    return 'ShellX didn\'t close normally last time. Reopened $_temp0; contents as of $time.';
  }

  @override
  String restoreAbnormalNoText(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tabs',
      one: '1 tab',
    );
    return 'ShellX didn\'t close normally last time. Reopened $_temp0.';
  }

  @override
  String get restoreStripCloseLabel => 'Dismiss restore notice';

  @override
  String restorePanesFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Couldn\'t reopen $count panes',
      one: 'Couldn\'t reopen 1 pane',
    );
    return '$_temp0';
  }

  @override
  String get cliNoticeSource => 'Command line';

  @override
  String get trayCommandLine => 'Command line';

  @override
  String get trayCliControl => 'Allow controlling ShellX from the command line';

  @override
  String get trayCliAllowExternal => 'Allow other terminals';

  @override
  String get trayCliInstallPath =>
      'Install the shellx command for all terminals…';

  @override
  String get trayCliRemovePath =>
      'Remove the shellx command from other terminals';

  @override
  String get trayCliCopySkills => 'Copy the agent skill install command';

  @override
  String get cliSkillsCopied =>
      'Copied “shellx skills install” — paste it in a terminal';

  @override
  String get cliPathInstalled =>
      'Installed the shellx command. To let other terminals control ShellX, also tick “Allow other terminals” in the tray’s Command line menu.';

  @override
  String cliPathFailed(String path) {
    return 'Couldn’t install the shellx command. Add $path to your PATH.';
  }

  @override
  String cliPathRemoveFailed(String path) {
    return 'Couldn’t remove the shellx command. Remove $path yourself.';
  }

  @override
  String get agentChip => 'Agent';

  @override
  String get agentChipTooltip =>
      'A program is controlling this tab through the ShellX command line';

  @override
  String cliAnnounceAgent(String tab) {
    return 'An agent is controlling $tab';
  }

  @override
  String cliPathNotOnPath(String file, String line) {
    return 'Installed the shellx command in /usr/local/bin, but your shell doesn’t look there. Add this line to $file: $line';
  }

  @override
  String get userCommandNoTerminal => 'There\'s no terminal to run this in';

  @override
  String configOpenFailed(String path) {
    return 'Couldn\'t open $path';
  }

  @override
  String sequencePending(String shortcut) {
    return '$shortcut …';
  }

  @override
  String sequencePendingAnnounce(String shortcut) {
    return '$shortcut pressed, waiting for the next key';
  }

  @override
  String configProblemsToast(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count problems in the configuration',
      one: '1 problem in the configuration',
    );
    return '$_temp0';
  }

  @override
  String get configProblemsShow => 'Show';

  @override
  String get configReloaded => 'Configuration reloaded';

  @override
  String get configGhosttyNotice =>
      'Using fonts and colours from your Ghostty config (turn off with ghostty-config = false)';

  @override
  String get configProblemsTitle => 'Configuration problems';

  @override
  String get configProblemsNone => 'No problems in the configuration.';

  @override
  String configProblemWhere(String file, int line) {
    return '$file, line $line';
  }

  @override
  String configProblemLine(int line) {
    return 'line $line';
  }

  @override
  String get configSeverityError => 'Error';

  @override
  String get configSeverityWarning => 'Warning';

  @override
  String get configSeverityInfo => 'Note';

  @override
  String get configOpenFile => 'Open configuration file';

  @override
  String get configReload => 'Reload configuration';

  @override
  String get configProblemSyntax => 'Line has no “=” (expected key = value)';

  @override
  String configProblemBadKey(String key) {
    return '“$key” is not a valid key name';
  }

  @override
  String configProblemUnknownKey(String key) {
    return 'ShellX has no key “$key”';
  }

  @override
  String configProblemBadValue(String key, String value, String hint) {
    return '$key: “$value” is not valid (expected $hint)';
  }

  @override
  String configProblemOutOfRange(
    String key,
    String value,
    String hint,
    String detail,
  ) {
    return '$key: $value is outside $hint, using $detail';
  }

  @override
  String configProblemDuplicate(String key, String detail) {
    return '$key: replaces line $detail';
  }

  @override
  String configProblemIncludeMissing(String value) {
    return 'File “$value” not found';
  }

  @override
  String configProblemIncludeCycle(String value) {
    return '“$value” is already loaded (config-file loop)';
  }

  @override
  String get configProblemIncludeDepth =>
      'config-file is nested more than 4 levels';

  @override
  String get configProblemIncludeLimit =>
      'More than 64 config files — the rest are ignored';

  @override
  String get configProblemUnreadable =>
      'Can\'t read the file — keeping the previous configuration';

  @override
  String get configProblemNotUtf8 =>
      'The file isn\'t UTF-8 — keeping the previous configuration';

  @override
  String get configProblemTooLarge =>
      'The file is larger than 256 KiB — keeping the previous configuration';

  @override
  String configProblemThemeNotFound(String value) {
    return 'Theme “$value” not found';
  }

  @override
  String configProblemFontNotFound(String value) {
    return 'Font “$value” not found — using JetBrains Mono';
  }

  @override
  String configProblemFontNotMonospace(String value) {
    return 'Font “$value” isn\'t monospaced — columns may not line up';
  }

  @override
  String configProblemLowContrast(String detail) {
    return 'Low text/background contrast ($detail:1, aim for 4.5:1)';
  }

  @override
  String configProblemUnsupportedValue(String key, String value, String hint) {
    return '$key = $value isn\'t supported (using $hint)';
  }

  @override
  String configProblemNotOnThisPlatform(String key) {
    return '$key only has an effect on macOS';
  }

  @override
  String configProblemBadTrigger(String value) {
    return '“$value” is not a valid key combination';
  }

  @override
  String configProblemUnknownAction(String value) {
    return 'There\'s no action “$value”';
  }

  @override
  String configProblemBadActionParam(String value, String hint) {
    return '“$value” is not valid (expected $hint)';
  }

  @override
  String configProblemReservedTrigger(String value) {
    return '$value is reserved by the system';
  }

  @override
  String configProblemPlainKeyTrigger(String value) {
    return '$value is for typing — add Ctrl, Alt or ⌘';
  }

  @override
  String get configProblemRegionTrigger =>
      'F6 and Shift+F6 always move between regions';

  @override
  String configProblemShellKeyTrigger(String value) {
    return '$value will no longer reach the shell';
  }

  @override
  String configProblemOptionKeyTrigger(String value) {
    return '$value will no longer type its Option character';
  }

  @override
  String configProblemAltGrTrigger(String value) {
    return '$value works with the left Alt only; AltGr still types characters';
  }

  @override
  String configProblemMissionControlTrigger(String value) {
    return 'Mission Control may take $value';
  }

  @override
  String configProblemUnsupportedPrefix(String value) {
    return 'The “$value” prefix isn\'t supported';
  }

  @override
  String get configProblemSequenceTooLong =>
      'Key sequences have at most 2 steps';

  @override
  String configProblemSequencePrefixShadows(String value) {
    return '$value starts a key sequence, so it no longer works on its own';
  }

  @override
  String configProblemSequenceRepeatsPrefix(String value) {
    return 'This sequence can\'t fire: pressing $value twice sends it';
  }

  @override
  String configProblemUnknownCommand(String value) {
    return 'There\'s no command “$value”';
  }

  @override
  String get configProblemCommandLimit =>
      'More than 200 commands — the rest are ignored';

  @override
  String configProblemLimit(String detail) {
    return '$detail problems — showing the first 100';
  }

  @override
  String get configProblemInternal =>
      'Unexpected error — keeping the previous configuration';

  @override
  String get trayConfig => 'Configuration';

  @override
  String get trayConfigOpen => 'Open configuration file';

  @override
  String get trayConfigReload => 'Reload configuration';

  @override
  String get trayConfigShortcuts => 'Keyboard shortcuts…';

  @override
  String trayConfigProblems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '⚠ $count configuration problems…',
      one: '⚠ 1 configuration problem…',
    );
    return '$_temp0';
  }

  @override
  String get paletteTitle => 'Command palette';

  @override
  String get paletteSearchLabel => 'Search commands';

  @override
  String get paletteSearchHint => 'Type a command…';

  @override
  String get paletteNoResults => 'No matching commands';

  @override
  String paletteResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count commands',
      one: '1 command',
    );
    return '$_temp0';
  }

  @override
  String get paletteKindUserCommand => 'Your command';

  @override
  String get paletteKindSnippet => 'Snippet';

  @override
  String get paletteKindConfig => 'Configuration';

  @override
  String get actionNewTab => 'New tab';

  @override
  String get actionCloseSurface => 'Close pane or tab';

  @override
  String get actionCloseTab => 'Close whole tab';

  @override
  String get actionNewWorkspace => 'New workspace';

  @override
  String get actionToggleNotifications => 'Notifications';

  @override
  String get actionJumpToUnread => 'Jump to unread';

  @override
  String get actionCopy => 'Copy';

  @override
  String get actionPaste => 'Paste';

  @override
  String get actionSelectAll => 'Select all';

  @override
  String actionGotoTab(String n) {
    return 'Go to tab $n';
  }

  @override
  String get actionNextTab => 'Next tab';

  @override
  String get actionPreviousTab => 'Previous tab';

  @override
  String get actionSplitRight => 'Split right';

  @override
  String get actionSplitDown => 'Split down';

  @override
  String actionFocusPane(String direction) {
    String _temp0 = intl.Intl.selectLogic(direction, {
      'left': 'Focus pane on the left',
      'right': 'Focus pane on the right',
      'up': 'Focus pane above',
      'other': 'Focus pane below',
    });
    return '$_temp0';
  }

  @override
  String actionResizePane(String direction) {
    String _temp0 = intl.Intl.selectLogic(direction, {
      'left': 'Move divider left',
      'right': 'Move divider right',
      'up': 'Move divider up',
      'other': 'Move divider down',
    });
    return '$_temp0';
  }

  @override
  String get actionToggleZoom => 'Zoom or unzoom pane';

  @override
  String get actionEqualize => 'Equalize panes';

  @override
  String get actionFontBigger => 'Bigger text';

  @override
  String get actionFontSmaller => 'Smaller text';

  @override
  String get actionFontReset => 'Default text size';

  @override
  String get actionNextRegion => 'Next region';

  @override
  String get actionPreviousRegion => 'Previous region';

  @override
  String get actionReloadConfig => 'Reload configuration';

  @override
  String get actionOpenConfig => 'Open configuration file';

  @override
  String get actionCommandPalette => 'Command palette';

  @override
  String get actionShowShortcuts => 'Keyboard shortcuts…';

  @override
  String get actionShowConfigProblems => 'Show configuration problems';

  @override
  String actionRunCommand(String name) {
    return 'Run “$name”';
  }

  @override
  String get actionSendText => 'Send text to the terminal';

  @override
  String get actionIgnore => 'Ignore key';

  @override
  String get shortcutsTitle => 'Keyboard shortcuts';

  @override
  String get shortcutsSearchLabel => 'Search shortcuts';

  @override
  String shortcutsGroup(String group) {
    String _temp0 = intl.Intl.selectLogic(group, {
      'tabs': 'Tabs',
      'panes': 'Panes',
      'notifications': 'Notifications',
      'editing': 'Editing',
      'font': 'Text size',
      'browser': 'Browser',
      'window': 'Window',
      'config': 'Configuration',
      'other': 'Your commands',
    });
    return '$_temp0';
  }

  @override
  String get shortcutsAdd => 'Add shortcut';

  @override
  String shortcutsAddFor(String action) {
    return 'Add a shortcut for “$action”';
  }

  @override
  String get shortcutsReset => 'Reset';

  @override
  String shortcutsResetFor(String action) {
    return 'Reset “$action”';
  }

  @override
  String shortcutsRemove(String shortcut) {
    return 'Remove $shortcut';
  }

  @override
  String get shortcutsNone => 'Not set';

  @override
  String get shortcutsRecording => 'Press a key combination… (Esc to cancel)';

  @override
  String shortcutsHeld(String keys) {
    return '$keys…';
  }

  @override
  String shortcutsConflict(String shortcut, String action) {
    return '$shortcut is used by “$action”.';
  }

  @override
  String get shortcutsReplace => 'Replace';

  @override
  String get shortcutsCancel => 'Cancel';

  @override
  String shortcutsOverridden(String file, int line) {
    return 'A later line in $file:$line overrides this';
  }

  @override
  String shortcutsFromFile(int line) {
    return 'Set in the configuration file, line $line';
  }

  @override
  String shortcutsAssigned(String shortcut, String action) {
    return '$shortcut now runs “$action”';
  }

  @override
  String shortcutsRemoved(String shortcut) {
    return 'Removed $shortcut';
  }

  @override
  String shortcutsResetDone(String action) {
    return '“$action” reset';
  }

  @override
  String get shortcutsFooter => 'Shortcuts written in the file are kept.';

  @override
  String configWriteFailed(String path) {
    return 'Couldn\'t save the shortcut to $path';
  }

  @override
  String get sshConnectMenu => 'Connect over SSH…';

  @override
  String get tmuxAttachMenu => 'Attach tmux session…';

  @override
  String get sshDialogTitle => 'Connect to a server';

  @override
  String get sshDialogTabSsh => 'SSH';

  @override
  String get sshDialogTabTmux => 'tmux';

  @override
  String get sshHostLabel => 'Server';

  @override
  String get sshHostHint => 'devbox or user@host:2222';

  @override
  String get sshHostInvalid => 'Not a valid server name';

  @override
  String get sshSuggestionsConfig => 'In ~/.ssh/config';

  @override
  String get sshSuggestionsRecent => 'Recent';

  @override
  String sshSuggestionsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count suggestions',
      one: '1 suggestion',
    );
    return '$_temp0';
  }

  @override
  String get sshRemoteDirLabel => 'Folder on the server (optional)';

  @override
  String get sshRemoteDirInvalid => 'The path must start with / or ~';

  @override
  String get sshNoHookLabel => 'Don’t install the ShellX hook on this server';

  @override
  String get sshNoHookHelp =>
      'The hook tells ShellX the folder, branch and ports on the server. Turn it off for servers that aren’t Unix.';

  @override
  String get sshConnectAction => 'Connect';

  @override
  String get sshUnavailable => 'Can’t find the ssh command on this computer';

  @override
  String get sshUnavailableWindows =>
      'Can’t find ssh. Turn on “OpenSSH Client” in Settings → Apps → Optional features.';

  @override
  String get tmuxSourceLabel => 'tmux sessions on';

  @override
  String get tmuxSourceLocal => 'This computer';

  @override
  String get tmuxLoading => 'Loading sessions…';

  @override
  String get tmuxEmpty => 'No tmux sessions yet';

  @override
  String tmuxUnavailable(String where) {
    return 'tmux isn’t installed on $where';
  }

  @override
  String get tmuxUnavailableLocal => 'tmux isn’t installed on this computer';

  @override
  String tmuxListFailed(String where) {
    return 'Couldn’t list sessions on $where. Connect to it over SSH once (so no password is needed), then try again.';
  }

  @override
  String get tmuxRetry => 'Try again';

  @override
  String tmuxWindows(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count windows',
      one: '1 window',
    );
    return '$_temp0';
  }

  @override
  String get tmuxAttachedElsewhere => 'attached elsewhere';

  @override
  String tmuxLastActive(String time) {
    return 'active $time';
  }

  @override
  String get tmuxAttachAction => 'Attach';

  @override
  String get tmuxNewLabel => 'New session name';

  @override
  String get tmuxNameInvalid => 'Use up to 64 characters, without “:” or “.”';

  @override
  String get tmuxCreateAction => 'Create and attach';

  @override
  String sidebarRemoteMark(String host) {
    return 'SSH: $host';
  }

  @override
  String sidebarTmuxMark(String name) {
    return 'tmux: $name';
  }

  @override
  String sidebarTmuxRemoteMark(String name, String host) {
    return 'tmux: $name · $host';
  }

  @override
  String sshStateConnecting(String host) {
    return 'Connecting to $host';
  }

  @override
  String sshStateDisconnected(String host) {
    return 'Lost connection to $host';
  }

  @override
  String sshStateFailed(String host) {
    return 'Couldn’t connect to $host';
  }

  @override
  String sshRetryIn(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: 'Retrying in $seconds seconds',
      one: 'Retrying in 1 second',
    );
    return '$_temp0';
  }

  @override
  String get sshRetrying => 'Reconnecting…';

  @override
  String get sshAutoRetryStopped => 'Stopped retrying';

  @override
  String get sshFailedHookHint => 'The server may not support the ShellX hook';

  @override
  String get sshReconnectAction => 'Reconnect';

  @override
  String get sshRetryAction => 'Try again';

  @override
  String get sshRetryPlainAction => 'Try without the hook';

  @override
  String get sshClosePaneAction => 'Close pane';

  @override
  String get sshTmuxHint =>
      'Run inside tmux to keep programs running when the connection drops';

  @override
  String sshDisconnectedLine(String host) {
    return '[Lost connection to $host] — press Enter to reconnect';
  }

  @override
  String sshFailedLine(String host) {
    return '[Couldn’t connect to $host] — press Enter to try again';
  }

  @override
  String sshReconnectedDivider(String time) {
    return '— Reconnected · $time —';
  }

  @override
  String workspaceNewRemoteTab(String host) {
    return 'New SSH tab on $host';
  }

  @override
  String get workspaceNewLocalTab => 'New local tab';

  @override
  String get workspaceReconnectAll => 'Reconnect all panes';

  @override
  String workspaceRemoteLabel(String host) {
    return 'SSH workspace $host';
  }

  @override
  String get rowReconnect => 'Reconnect';

  @override
  String get paneSplitLocalRight => 'Split right on this computer';

  @override
  String remotePortTooltip(int port, String host) {
    return 'Open port $port on $host (forwarded over SSH)';
  }

  @override
  String remotePortForwarded(int local, String host, int port) {
    return 'localhost:$local → $host:$port';
  }

  @override
  String remotePortForwardFailed(int port) {
    return 'Couldn’t forward port $port';
  }

  @override
  String get sshTrayMenu => 'SSH';

  @override
  String get sshTrayHook =>
      'Install the ShellX hook on servers (folder, branch, ports)';

  @override
  String get sshTrayClearRecent => 'Clear recent servers';

  @override
  String get sshRecentCleared => 'Recent servers cleared';

  @override
  String sshAnnounceConnected(String host) {
    return 'Connected to $host';
  }

  @override
  String sshAnnounceDisconnected(String host) {
    return 'Lost connection to $host';
  }

  @override
  String sshAnnounceReconnected(String host) {
    return 'Reconnected to $host';
  }

  @override
  String paneRemoteSuffix(String host) {
    return ', on $host';
  }
}
