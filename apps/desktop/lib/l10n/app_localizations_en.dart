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
}
