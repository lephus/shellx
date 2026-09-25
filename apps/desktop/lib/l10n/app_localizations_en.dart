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
      'Forgot your password? Open ShellX on a computer that is still signed in and choose “Change password…” from its menu.';

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
          'ShellX now lives in the menu bar. Choose “Pair phone…” there to connect your phone.',
      'other':
          'ShellX now lives in the system tray. Choose “Pair phone…” there to connect your phone.',
    });
    return '$_temp0';
  }

  @override
  String get onboardingFinish => 'Finish';

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
  String confirmRemoteOffBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count open sessions will be closed.',
      one: '1 open session will be closed.',
    );
    return '$_temp0';
  }

  @override
  String get confirmRemoteOffAction => 'Turn off';

  @override
  String get confirmSignOutTitle => 'Sign out of ShellX?';

  @override
  String get confirmSignOutBody =>
      'All sessions will be closed and every paired phone will be removed. After signing in again you must pair your phones again.';

  @override
  String get confirmSignOutAction => 'Sign out';

  @override
  String confirmRevokeTitle(String device) {
    return 'Revoke $device?';
  }

  @override
  String get confirmRevokeBody =>
      'This phone loses access to this computer immediately and its sessions are closed. To use it again you must pair it again.';

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
          '$count open sessions will be closed. Your phones cannot reach this computer until ShellX runs again.',
      one:
          '1 open session will be closed. Your phones cannot reach this computer until ShellX runs again.',
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
  String get notifyAlreadyRunningTitle => 'ShellX is already running';

  @override
  String notifyAlreadyRunningBody(String platform) {
    String _temp0 = intl.Intl.selectLogic(platform, {
      'macos': 'Find it in the menu bar.',
      'other': 'Find it in the system tray.',
    });
    return '$_temp0';
  }

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
  String get startupFailed =>
      'ShellX could not start. Open it again; if this keeps happening, restart your computer.';

  @override
  String get windowsVersionUnsupported =>
      'ShellX requires Windows 10 version 1809 or later.';
}
