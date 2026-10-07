import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_vi.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('vi'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'ShellX'**
  String get appTitle;

  /// No description provided for @actionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get actionCancel;

  /// No description provided for @actionClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get actionClose;

  /// No description provided for @authSignInTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in to ShellX'**
  String get authSignInTitle;

  /// No description provided for @authRegisterTitle.
  ///
  /// In en, this message translates to:
  /// **'Create a ShellX account'**
  String get authRegisterTitle;

  /// No description provided for @authEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get authEmailLabel;

  /// No description provided for @authPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get authPasswordLabel;

  /// No description provided for @authConfirmPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Re-enter password'**
  String get authConfirmPasswordLabel;

  /// No description provided for @authSignInButton.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get authSignInButton;

  /// No description provided for @authRegisterButton.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get authRegisterButton;

  /// No description provided for @authSwitchToRegister.
  ///
  /// In en, this message translates to:
  /// **'No account yet? Create one'**
  String get authSwitchToRegister;

  /// No description provided for @authSwitchToSignIn.
  ///
  /// In en, this message translates to:
  /// **'Already have an account? Sign in'**
  String get authSwitchToSignIn;

  /// No description provided for @authForgotPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Forgot your password? On another computer that is still signed in to ShellX, choose “Change password…” in the tray menu.'**
  String get authForgotPasswordHint;

  /// No description provided for @authSignedOutNotice.
  ///
  /// In en, this message translates to:
  /// **'You were signed out. Sign in again.'**
  String get authSignedOutNotice;

  /// No description provided for @errorEmailInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address.'**
  String get errorEmailInvalid;

  /// No description provided for @errorPasswordLength.
  ///
  /// In en, this message translates to:
  /// **'Password must be 8–128 characters.'**
  String get errorPasswordLength;

  /// No description provided for @errorPasswordMismatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match.'**
  String get errorPasswordMismatch;

  /// No description provided for @errorDisposableEmail.
  ///
  /// In en, this message translates to:
  /// **'Temporary email addresses are not allowed. Use a permanent address.'**
  String get errorDisposableEmail;

  /// No description provided for @errorEmailTaken.
  ///
  /// In en, this message translates to:
  /// **'This email is already registered. Sign in instead.'**
  String get errorEmailTaken;

  /// No description provided for @errorInvalidCredentials.
  ///
  /// In en, this message translates to:
  /// **'Incorrect email or password.'**
  String get errorInvalidCredentials;

  /// No description provided for @errorRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Try again in a few minutes.'**
  String get errorRateLimited;

  /// No description provided for @errorNetwork.
  ///
  /// In en, this message translates to:
  /// **'Cannot reach the ShellX server. Check your Internet connection.'**
  String get errorNetwork;

  /// No description provided for @errorAgentOnly.
  ///
  /// In en, this message translates to:
  /// **'Only a signed-in computer can change the password.'**
  String get errorAgentOnly;

  /// No description provided for @errorUnexpected.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong ({code}). Try again.'**
  String errorUnexpected(String code);

  /// No description provided for @onboardingTitle.
  ///
  /// In en, this message translates to:
  /// **'Almost done'**
  String get onboardingTitle;

  /// No description provided for @onboardingLaunchAtStartup.
  ///
  /// In en, this message translates to:
  /// **'Start ShellX when the computer starts'**
  String get onboardingLaunchAtStartup;

  /// No description provided for @onboardingFullDiskTitle.
  ///
  /// In en, this message translates to:
  /// **'Full Disk Access (optional)'**
  String get onboardingFullDiskTitle;

  /// No description provided for @onboardingFullDiskBody.
  ///
  /// In en, this message translates to:
  /// **'Commands that touch Desktop, Documents or Downloads make macOS show a permission prompt on this computer\'s screen, which you cannot answer from your phone. Give ShellX Full Disk Access to avoid it.'**
  String get onboardingFullDiskBody;

  /// No description provided for @onboardingOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open System Settings'**
  String get onboardingOpenSettings;

  /// No description provided for @onboardingSleepTitle.
  ///
  /// In en, this message translates to:
  /// **'Sleep'**
  String get onboardingSleepTitle;

  /// No description provided for @onboardingSleepBody.
  ///
  /// In en, this message translates to:
  /// **'ShellX keeps the computer from sleeping while idle. Closing the laptop lid still puts it to sleep, and then your phone cannot reach it.'**
  String get onboardingSleepBody;

  /// No description provided for @onboardingTrayHint.
  ///
  /// In en, this message translates to:
  /// **'{platform, select, macos{Your terminal is in the ShellX window. ShellX also stays in the menu bar: choose “Pair phone…” there to connect your phone.} other{Your terminal is in the ShellX window. ShellX also stays in the system tray: choose “Pair phone…” there to connect your phone.}}'**
  String onboardingTrayHint(String platform);

  /// No description provided for @onboardingFinish.
  ///
  /// In en, this message translates to:
  /// **'Finish'**
  String get onboardingFinish;

  /// No description provided for @trayOpenTerminal.
  ///
  /// In en, this message translates to:
  /// **'Open terminal window'**
  String get trayOpenTerminal;

  /// No description provided for @windowTitle.
  ///
  /// In en, this message translates to:
  /// **'{title} — ShellX'**
  String windowTitle(String title);

  /// No description provided for @dialogClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get dialogClose;

  /// No description provided for @trayTooltip.
  ///
  /// In en, this message translates to:
  /// **'ShellX'**
  String get trayTooltip;

  /// No description provided for @trayStatusConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected — {email}'**
  String trayStatusConnected(String email);

  /// No description provided for @trayStatusConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting — {email}'**
  String trayStatusConnecting(String email);

  /// No description provided for @trayStatusReconnecting.
  ///
  /// In en, this message translates to:
  /// **'Disconnected — retrying…'**
  String get trayStatusReconnecting;

  /// No description provided for @trayStatusRemoteOff.
  ///
  /// In en, this message translates to:
  /// **'Remote access is off'**
  String get trayStatusRemoteOff;

  /// No description provided for @trayStatusReplaced.
  ///
  /// In en, this message translates to:
  /// **'Another copy of ShellX took over this computer'**
  String get trayStatusReplaced;

  /// No description provided for @trayStatusSignedOut.
  ///
  /// In en, this message translates to:
  /// **'Not signed in'**
  String get trayStatusSignedOut;

  /// No description provided for @trayReconnect.
  ///
  /// In en, this message translates to:
  /// **'Reconnect'**
  String get trayReconnect;

  /// No description provided for @trayRemoteAccess.
  ///
  /// In en, this message translates to:
  /// **'Allow remote access'**
  String get trayRemoteAccess;

  /// No description provided for @traySessions.
  ///
  /// In en, this message translates to:
  /// **'Active sessions ({count})'**
  String traySessions(int count);

  /// No description provided for @traySessionItem.
  ///
  /// In en, this message translates to:
  /// **'{shell} {index}'**
  String traySessionItem(String shell, int index);

  /// No description provided for @traySessionItemAttached.
  ///
  /// In en, this message translates to:
  /// **'{shell} {index} — {device}'**
  String traySessionItemAttached(String shell, int index, String device);

  /// No description provided for @traySessionClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get traySessionClose;

  /// No description provided for @trayCloseAll.
  ///
  /// In en, this message translates to:
  /// **'Close all'**
  String get trayCloseAll;

  /// No description provided for @trayPairPhone.
  ///
  /// In en, this message translates to:
  /// **'Pair phone…'**
  String get trayPairPhone;

  /// No description provided for @trayPairedDevices.
  ///
  /// In en, this message translates to:
  /// **'Paired devices'**
  String get trayPairedDevices;

  /// No description provided for @trayRevoke.
  ///
  /// In en, this message translates to:
  /// **'Revoke'**
  String get trayRevoke;

  /// No description provided for @trayNoDevices.
  ///
  /// In en, this message translates to:
  /// **'No paired devices'**
  String get trayNoDevices;

  /// No description provided for @trayKeepAwake.
  ///
  /// In en, this message translates to:
  /// **'Keep computer awake'**
  String get trayKeepAwake;

  /// No description provided for @trayLaunchAtStartup.
  ///
  /// In en, this message translates to:
  /// **'Start with system'**
  String get trayLaunchAtStartup;

  /// No description provided for @trayChangePassword.
  ///
  /// In en, this message translates to:
  /// **'Change password…'**
  String get trayChangePassword;

  /// No description provided for @traySignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get traySignOut;

  /// No description provided for @traySignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in…'**
  String get traySignIn;

  /// No description provided for @trayQuit.
  ///
  /// In en, this message translates to:
  /// **'Quit'**
  String get trayQuit;

  /// No description provided for @trayDownloadUpdate.
  ///
  /// In en, this message translates to:
  /// **'Download ShellX {version}…'**
  String trayDownloadUpdate(String version);

  /// No description provided for @confirmRemoteOffTitle.
  ///
  /// In en, this message translates to:
  /// **'Turn off remote access?'**
  String get confirmRemoteOffTitle;

  /// No description provided for @confirmRemoteOffBody.
  ///
  /// In en, this message translates to:
  /// **'Connected phones will be disconnected. Terminal tabs on this computer keep running.'**
  String get confirmRemoteOffBody;

  /// No description provided for @confirmRemoteOffAction.
  ///
  /// In en, this message translates to:
  /// **'Turn off'**
  String get confirmRemoteOffAction;

  /// No description provided for @confirmSignOutTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign out of ShellX?'**
  String get confirmSignOutTitle;

  /// No description provided for @confirmSignOutBody.
  ///
  /// In en, this message translates to:
  /// **'Connected phones will be disconnected and every paired phone will be removed. Terminal tabs on this computer keep running. After signing in again you must pair your phones again.'**
  String get confirmSignOutBody;

  /// No description provided for @confirmSignOutAction.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get confirmSignOutAction;

  /// No description provided for @confirmRevokeTitle.
  ///
  /// In en, this message translates to:
  /// **'Revoke {device}?'**
  String confirmRevokeTitle(String device);

  /// No description provided for @confirmRevokeBody.
  ///
  /// In en, this message translates to:
  /// **'This phone loses access to this computer immediately and the sessions it opened are closed. Tabs opened on this computer keep running. To use it again you must pair it again.'**
  String get confirmRevokeBody;

  /// No description provided for @confirmRevokeAction.
  ///
  /// In en, this message translates to:
  /// **'Revoke'**
  String get confirmRevokeAction;

  /// No description provided for @confirmQuitTitle.
  ///
  /// In en, this message translates to:
  /// **'Quit ShellX?'**
  String get confirmQuitTitle;

  /// No description provided for @confirmQuitBody.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 open tab will be closed. Your phones cannot reach this computer until ShellX runs again.} other{{count} open tabs will be closed. Your phones cannot reach this computer until ShellX runs again.}}'**
  String confirmQuitBody(int count);

  /// No description provided for @confirmQuitAction.
  ///
  /// In en, this message translates to:
  /// **'Quit'**
  String get confirmQuitAction;

  /// No description provided for @pairingTitle.
  ///
  /// In en, this message translates to:
  /// **'Pair a phone'**
  String get pairingTitle;

  /// No description provided for @pairingInstructions.
  ///
  /// In en, this message translates to:
  /// **'Open ShellX on your phone (signed in to the same account), tap this computer and scan the code.'**
  String get pairingInstructions;

  /// No description provided for @pairingExpiresIn.
  ///
  /// In en, this message translates to:
  /// **'Code expires in {time}'**
  String pairingExpiresIn(String time);

  /// No description provided for @pairingExpired.
  ///
  /// In en, this message translates to:
  /// **'This code has expired.'**
  String get pairingExpired;

  /// No description provided for @pairingNewCode.
  ///
  /// In en, this message translates to:
  /// **'Create new code'**
  String get pairingNewCode;

  /// No description provided for @pairingOfflineWarning.
  ///
  /// In en, this message translates to:
  /// **'Not connected to the ShellX server. Your phone can pair once the connection is back.'**
  String get pairingOfflineWarning;

  /// No description provided for @pairingSecretWarning.
  ///
  /// In en, this message translates to:
  /// **'Anyone who scans this code while signed in to your account can control this computer. Do not share it.'**
  String get pairingSecretWarning;

  /// No description provided for @changePasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Change password'**
  String get changePasswordTitle;

  /// No description provided for @changePasswordNew.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get changePasswordNew;

  /// No description provided for @changePasswordConfirm.
  ///
  /// In en, this message translates to:
  /// **'Re-enter new password'**
  String get changePasswordConfirm;

  /// No description provided for @changePasswordSubmit.
  ///
  /// In en, this message translates to:
  /// **'Change password'**
  String get changePasswordSubmit;

  /// No description provided for @changePasswordNote.
  ///
  /// In en, this message translates to:
  /// **'Other devices will be signed out. Pairings are kept.'**
  String get changePasswordNote;

  /// No description provided for @changePasswordDone.
  ///
  /// In en, this message translates to:
  /// **'Password changed. Your phones must sign in again with the new password.'**
  String get changePasswordDone;

  /// No description provided for @notifySessionOpened.
  ///
  /// In en, this message translates to:
  /// **'{device} opened a terminal session'**
  String notifySessionOpened(String device);

  /// No description provided for @notifyPaired.
  ///
  /// In en, this message translates to:
  /// **'Paired with {device}'**
  String notifyPaired(String device);

  /// No description provided for @notifyUpdateAvailableTitle.
  ///
  /// In en, this message translates to:
  /// **'ShellX {version} is available'**
  String notifyUpdateAvailableTitle(String version);

  /// No description provided for @notifyUpdateAvailableBody.
  ///
  /// In en, this message translates to:
  /// **'Click to download.'**
  String get notifyUpdateAvailableBody;

  /// No description provided for @notifyUpdateRequiredTitle.
  ///
  /// In en, this message translates to:
  /// **'ShellX needs to be updated'**
  String get notifyUpdateRequiredTitle;

  /// No description provided for @notifyUpdateRequiredBody.
  ///
  /// In en, this message translates to:
  /// **'This version is no longer supported. Click to download ShellX {version}.'**
  String notifyUpdateRequiredBody(String version);

  /// No description provided for @notifySignedOutTitle.
  ///
  /// In en, this message translates to:
  /// **'ShellX was signed out'**
  String get notifySignedOutTitle;

  /// No description provided for @notifySignedOutBody.
  ///
  /// In en, this message translates to:
  /// **'Sign in again to allow remote access.'**
  String get notifySignedOutBody;

  /// No description provided for @notifyTerminalProblemTitle.
  ///
  /// In en, this message translates to:
  /// **'Processes from a terminal session may still be running'**
  String get notifyTerminalProblemTitle;

  /// No description provided for @notifyTerminalProblemBody.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Shell process ID: {pids}} other{Shell process IDs: {pids}}}'**
  String notifyTerminalProblemBody(int count, String pids);

  /// No description provided for @notifyStorageUnreadableTitle.
  ///
  /// In en, this message translates to:
  /// **'ShellX could not read your saved sign-in'**
  String get notifyStorageUnreadableTitle;

  /// No description provided for @notifySignOutIncompleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Signed out, but some saved sign-in data could not be deleted'**
  String get notifySignOutIncompleteTitle;

  /// No description provided for @trayTerminalSharing.
  ///
  /// In en, this message translates to:
  /// **'Share terminals with phone (experimental)'**
  String get trayTerminalSharing;

  /// No description provided for @trayNotifyThreshold.
  ///
  /// In en, this message translates to:
  /// **'Notify when long commands finish'**
  String get trayNotifyThreshold;

  /// No description provided for @trayNotifyOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get trayNotifyOff;

  /// No description provided for @trayNotifySeconds.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 second} other{{count} seconds}}'**
  String trayNotifySeconds(int count);

  /// No description provided for @trayNotifyMinutes.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 minute} other{{count} minutes}}'**
  String trayNotifyMinutes(int count);

  /// No description provided for @trayDesktopTerminals.
  ///
  /// In en, this message translates to:
  /// **'Computer terminals ({count})'**
  String trayDesktopTerminals(int count);

  /// No description provided for @trayDisconnectPhone.
  ///
  /// In en, this message translates to:
  /// **'Disconnect phone'**
  String get trayDisconnectPhone;

  /// No description provided for @trayTerminalSharingNeedsSetup.
  ///
  /// In en, this message translates to:
  /// **'Terminal sharing needs to be set up again…'**
  String get trayTerminalSharingNeedsSetup;

  /// No description provided for @notifyDesktopTerminalWatched.
  ///
  /// In en, this message translates to:
  /// **'{device} is viewing terminal {terminal}'**
  String notifyDesktopTerminalWatched(String device, String terminal);

  /// No description provided for @notifyTerminalSharingFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Could not turn on terminal sharing'**
  String get notifyTerminalSharingFailedTitle;

  /// No description provided for @notifyTerminalSharingFailedBody.
  ///
  /// In en, this message translates to:
  /// **'Nothing was changed. Try again.'**
  String get notifyTerminalSharingFailedBody;

  /// No description provided for @notifyTerminalSharingStartFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Terminal sharing could not start'**
  String get notifyTerminalSharingStartFailedTitle;

  /// No description provided for @notifyTerminalSharingDisableIncompleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Terminal sharing is off, but the ShellX block could not be removed from some files'**
  String get notifyTerminalSharingDisableIncompleteTitle;

  /// No description provided for @confirmSharingTitle.
  ///
  /// In en, this message translates to:
  /// **'Share terminals with your phone?'**
  String get confirmSharingTitle;

  /// No description provided for @confirmSharingIntro.
  ///
  /// In en, this message translates to:
  /// **'Every terminal window you open from now on can be viewed and typed into from your paired phones. Windows that are already open are not shared.'**
  String get confirmSharingIntro;

  /// No description provided for @confirmSharingFiles.
  ///
  /// In en, this message translates to:
  /// **'ShellX will change these files (each existing file is backed up once as <name>.shellx-backup):'**
  String get confirmSharingFiles;

  /// No description provided for @confirmSharingFileCreated.
  ///
  /// In en, this message translates to:
  /// **'{path} (new file)'**
  String confirmSharingFileCreated(String path);

  /// No description provided for @confirmSharingBinary.
  ///
  /// In en, this message translates to:
  /// **'and copy shellx-term to {path}.'**
  String confirmSharingBinary(String path);

  /// No description provided for @confirmSharingBashSkipped.
  ///
  /// In en, this message translates to:
  /// **'There is no ~/.bashrc or ~/.bash_profile, so bash windows are not shared.'**
  String get confirmSharingBashSkipped;

  /// No description provided for @confirmSharingMacNote.
  ///
  /// In en, this message translates to:
  /// **'Note: Terminal.app (and possibly iTerm2) will no longer ask for confirmation when you close a window that is running a command.'**
  String get confirmSharingMacNote;

  /// No description provided for @confirmSharingWindowsNote.
  ///
  /// In en, this message translates to:
  /// **'Each PowerShell window will open a little slower and use some extra memory.'**
  String get confirmSharingWindowsNote;

  /// No description provided for @confirmSharingPowerShellBlocked.
  ///
  /// In en, this message translates to:
  /// **'{name}: running scripts is not allowed, so its profile will not run until local scripts are allowed.'**
  String confirmSharingPowerShellBlocked(String name);

  /// No description provided for @confirmSharingPowerShellGroupPolicy.
  ///
  /// In en, this message translates to:
  /// **'{name}: the script policy is set by your organization (Group Policy), so this PowerShell will not be shared.'**
  String confirmSharingPowerShellGroupPolicy(String name);

  /// No description provided for @confirmSharingNoPowerShell.
  ///
  /// In en, this message translates to:
  /// **'No PowerShell was found on this computer.'**
  String get confirmSharingNoPowerShell;

  /// No description provided for @confirmSharingAction.
  ///
  /// In en, this message translates to:
  /// **'Turn on'**
  String get confirmSharingAction;

  /// No description provided for @confirmAllowScriptsTitle.
  ///
  /// In en, this message translates to:
  /// **'Allow local scripts?'**
  String get confirmAllowScriptsTitle;

  /// No description provided for @confirmAllowScriptsBody.
  ///
  /// In en, this message translates to:
  /// **'{names}: running scripts is not allowed, so the ShellX block in the profile cannot run. This sets the policy to RemoteSigned for your account only (Set-ExecutionPolicy -Scope CurrentUser RemoteSigned).'**
  String confirmAllowScriptsBody(String names);

  /// No description provided for @confirmAllowScriptsAction.
  ///
  /// In en, this message translates to:
  /// **'Allow local scripts for my account'**
  String get confirmAllowScriptsAction;

  /// No description provided for @notifyTerminalSharingFailedFile.
  ///
  /// In en, this message translates to:
  /// **'ShellX could not change {path}. Nothing was changed.'**
  String notifyTerminalSharingFailedFile(String path);

  /// No description provided for @notifyAllowScriptsFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Could not allow local scripts for {name}'**
  String notifyAllowScriptsFailedTitle(String name);

  /// No description provided for @startupFailed.
  ///
  /// In en, this message translates to:
  /// **'ShellX could not start. Open it again; if this keeps happening, restart your computer.'**
  String get startupFailed;

  /// No description provided for @windowsVersionUnsupported.
  ///
  /// In en, this message translates to:
  /// **'ShellX requires Windows 10 version 1809 or later.'**
  String get windowsVersionUnsupported;

  /// No description provided for @terminalExitedLine.
  ///
  /// In en, this message translates to:
  /// **'[Process exited with code {code}] — press Enter to close'**
  String terminalExitedLine(int code);

  /// No description provided for @terminalNewTab.
  ///
  /// In en, this message translates to:
  /// **'New tab'**
  String get terminalNewTab;

  /// No description provided for @terminalNewTabTooltip.
  ///
  /// In en, this message translates to:
  /// **'New tab  {shortcut}'**
  String terminalNewTabTooltip(String shortcut);

  /// No description provided for @terminalCloseTab.
  ///
  /// In en, this message translates to:
  /// **'Close tab'**
  String get terminalCloseTab;

  /// No description provided for @terminalDriverPhone.
  ///
  /// In en, this message translates to:
  /// **'Your phone is using this terminal — type to take it back'**
  String get terminalDriverPhone;

  /// No description provided for @terminalSignedOutStrip.
  ///
  /// In en, this message translates to:
  /// **'Sign in to use this computer from your phone'**
  String get terminalSignedOutStrip;

  /// No description provided for @terminalSignedOutAction.
  ///
  /// In en, this message translates to:
  /// **'Sign in…'**
  String get terminalSignedOutAction;

  /// No description provided for @terminalEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No tabs open'**
  String get terminalEmptyTitle;

  /// No description provided for @terminalEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Open a tab to start a new shell. Sessions you open from your phone show up here too.'**
  String get terminalEmptyBody;

  /// No description provided for @terminalEmptyAction.
  ///
  /// In en, this message translates to:
  /// **'Open new tab'**
  String get terminalEmptyAction;

  /// No description provided for @terminalSessionLimit.
  ///
  /// In en, this message translates to:
  /// **'You\'ve reached the limit of {max} sessions. Close a tab to open a new one.'**
  String terminalSessionLimit(int max);

  /// No description provided for @terminalSpawnFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t start the shell: {reason, select, notFound{shell not found} denied{permission denied} other{system error}}. Try again.'**
  String terminalSpawnFailed(String reason);

  /// No description provided for @toastDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get toastDismiss;

  /// No description provided for @confirmCloseRunningTitle.
  ///
  /// In en, this message translates to:
  /// **'Close “{title}”?'**
  String confirmCloseRunningTitle(String title);

  /// No description provided for @confirmCloseRunningBody.
  ///
  /// In en, this message translates to:
  /// **'The command running in this tab will be stopped.'**
  String get confirmCloseRunningBody;

  /// No description provided for @confirmCloseRunningAction.
  ///
  /// In en, this message translates to:
  /// **'Close tab'**
  String get confirmCloseRunningAction;

  /// No description provided for @sidebarLabel.
  ///
  /// In en, this message translates to:
  /// **'Tabs'**
  String get sidebarLabel;

  /// No description provided for @sidebarStatusIdle.
  ///
  /// In en, this message translates to:
  /// **'idle'**
  String get sidebarStatusIdle;

  /// No description provided for @sidebarStatusRunning.
  ///
  /// In en, this message translates to:
  /// **'running a command'**
  String get sidebarStatusRunning;

  /// No description provided for @sidebarStatusExited.
  ///
  /// In en, this message translates to:
  /// **'exited with code {code}'**
  String sidebarStatusExited(int code);

  /// No description provided for @sidebarPhoneOrigin.
  ///
  /// In en, this message translates to:
  /// **'Opened from your phone'**
  String get sidebarPhoneOrigin;

  /// No description provided for @sidebarPhoneViewing.
  ///
  /// In en, this message translates to:
  /// **'Your phone is viewing'**
  String get sidebarPhoneViewing;

  /// No description provided for @sidebarPhoneDriving.
  ///
  /// In en, this message translates to:
  /// **'Your phone is using it'**
  String get sidebarPhoneDriving;

  /// No description provided for @sidebarPhoneOriginSemantics.
  ///
  /// In en, this message translates to:
  /// **'opened from your phone'**
  String get sidebarPhoneOriginSemantics;

  /// No description provided for @sidebarPhoneViewingSemantics.
  ///
  /// In en, this message translates to:
  /// **'your phone is viewing'**
  String get sidebarPhoneViewingSemantics;

  /// No description provided for @sidebarPhoneDrivingSemantics.
  ///
  /// In en, this message translates to:
  /// **'your phone is using it'**
  String get sidebarPhoneDrivingSemantics;

  /// No description provided for @sidebarPosition.
  ///
  /// In en, this message translates to:
  /// **'tab {index} of {count}'**
  String sidebarPosition(int index, int count);

  /// No description provided for @terminalPaneLabel.
  ///
  /// In en, this message translates to:
  /// **'Terminal {title}'**
  String terminalPaneLabel(String title);

  /// No description provided for @confirmCloseAllTitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Close 1 tab?} other{Close all {count} tabs?}}'**
  String confirmCloseAllTitle(int count);

  /// No description provided for @confirmCloseAllBody.
  ///
  /// In en, this message translates to:
  /// **'Every shell in these tabs will be stopped, with any command still running.'**
  String get confirmCloseAllBody;

  /// No description provided for @confirmCloseAllAction.
  ///
  /// In en, this message translates to:
  /// **'Close all'**
  String get confirmCloseAllAction;

  /// No description provided for @terminalCloseTabTooltip.
  ///
  /// In en, this message translates to:
  /// **'Close tab  {shortcut}'**
  String terminalCloseTabTooltip(String shortcut);

  /// No description provided for @terminalDriverPhoneShort.
  ///
  /// In en, this message translates to:
  /// **'Phone in control — type to take over'**
  String get terminalDriverPhoneShort;

  /// No description provided for @terminalCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get terminalCopy;

  /// No description provided for @terminalPaste.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get terminalPaste;

  /// No description provided for @terminalSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get terminalSelectAll;

  /// No description provided for @workspaceDefaultName.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get workspaceDefaultName;

  /// No description provided for @workspaceNumberedName.
  ///
  /// In en, this message translates to:
  /// **'Workspace {n}'**
  String workspaceNumberedName(int n);

  /// No description provided for @workspaceNew.
  ///
  /// In en, this message translates to:
  /// **'New workspace'**
  String get workspaceNew;

  /// No description provided for @workspaceNewTab.
  ///
  /// In en, this message translates to:
  /// **'New tab in this workspace'**
  String get workspaceNewTab;

  /// No description provided for @workspaceRename.
  ///
  /// In en, this message translates to:
  /// **'Rename workspace'**
  String get workspaceRename;

  /// No description provided for @workspaceDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete workspace'**
  String get workspaceDelete;

  /// No description provided for @workspaceCollapse.
  ///
  /// In en, this message translates to:
  /// **'Collapse'**
  String get workspaceCollapse;

  /// No description provided for @workspaceExpand.
  ///
  /// In en, this message translates to:
  /// **'Expand'**
  String get workspaceExpand;

  /// No description provided for @workspaceEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Empty — drag a tab here'**
  String get workspaceEmptyHint;

  /// No description provided for @workspaceDeleteDefaultReason.
  ///
  /// In en, this message translates to:
  /// **'The Default workspace can\'t be deleted'**
  String get workspaceDeleteDefaultReason;

  /// No description provided for @workspaceNameField.
  ///
  /// In en, this message translates to:
  /// **'Workspace name'**
  String get workspaceNameField;

  /// No description provided for @workspaceDeleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted workspace “{name}”. Its tabs moved to {defaultName}.'**
  String workspaceDeleted(String name, String defaultName);

  /// No description provided for @workspaceHeaderSemantics.
  ///
  /// In en, this message translates to:
  /// **'Workspace {name}, {count, plural, =1{1 tab} other{{count} tabs}}'**
  String workspaceHeaderSemantics(String name, int count);

  /// No description provided for @workspaceContainsSelected.
  ///
  /// In en, this message translates to:
  /// **'contains the selected tab'**
  String get workspaceContainsSelected;

  /// No description provided for @workspaceCollapsedState.
  ///
  /// In en, this message translates to:
  /// **'collapsed'**
  String get workspaceCollapsedState;

  /// No description provided for @workspaceExpandedState.
  ///
  /// In en, this message translates to:
  /// **'expanded'**
  String get workspaceExpandedState;

  /// No description provided for @tabRename.
  ///
  /// In en, this message translates to:
  /// **'Rename tab'**
  String get tabRename;

  /// No description provided for @tabNameField.
  ///
  /// In en, this message translates to:
  /// **'Tab name'**
  String get tabNameField;

  /// No description provided for @tabUseAutomaticName.
  ///
  /// In en, this message translates to:
  /// **'Use automatic name'**
  String get tabUseAutomaticName;

  /// No description provided for @tabMoveTo.
  ///
  /// In en, this message translates to:
  /// **'Move to workspace…'**
  String get tabMoveTo;

  /// No description provided for @tabMoveToTitle.
  ///
  /// In en, this message translates to:
  /// **'Move “{name}” to'**
  String tabMoveToTitle(String name);

  /// No description provided for @tabOpenPortMenu.
  ///
  /// In en, this message translates to:
  /// **'Open port in browser…'**
  String get tabOpenPortMenu;

  /// No description provided for @tabMoveUp.
  ///
  /// In en, this message translates to:
  /// **'Move up'**
  String get tabMoveUp;

  /// No description provided for @tabMoveDown.
  ///
  /// In en, this message translates to:
  /// **'Move down'**
  String get tabMoveDown;

  /// No description provided for @tabOpenPort.
  ///
  /// In en, this message translates to:
  /// **'Open port {port} in browser'**
  String tabOpenPort(int port);

  /// No description provided for @portOpenTooltip.
  ///
  /// In en, this message translates to:
  /// **'Open http://localhost:{port}'**
  String portOpenTooltip(int port);

  /// No description provided for @portsMoreTooltip.
  ///
  /// In en, this message translates to:
  /// **'Listening ports: {ports}'**
  String portsMoreTooltip(String ports);

  /// No description provided for @portOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the browser.'**
  String get portOpenFailed;

  /// No description provided for @sidebarBranch.
  ///
  /// In en, this message translates to:
  /// **'branch {branch}'**
  String sidebarBranch(String branch);

  /// No description provided for @sidebarFolder.
  ///
  /// In en, this message translates to:
  /// **'folder {path}'**
  String sidebarFolder(String path);

  /// No description provided for @sidebarPorts.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{port {ports}} other{ports {ports}}}'**
  String sidebarPorts(int count, String ports);

  /// No description provided for @sidebarPositionInWorkspace.
  ///
  /// In en, this message translates to:
  /// **'tab {index} of {count} in {workspace}'**
  String sidebarPositionInWorkspace(int index, int count, String workspace);

  /// No description provided for @attentionBell.
  ///
  /// In en, this message translates to:
  /// **'Bell'**
  String get attentionBell;

  /// No description provided for @attentionBellRepeat.
  ///
  /// In en, this message translates to:
  /// **'Bell ×{count}'**
  String attentionBellRepeat(int count);

  /// No description provided for @attentionBellBody.
  ///
  /// In en, this message translates to:
  /// **'Bell in this tab'**
  String get attentionBellBody;

  /// No description provided for @attentionUnreadCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 unread notification} other{{count} unread notifications}}'**
  String attentionUnreadCount(int count);

  /// No description provided for @attentionRowSemantics.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 unread notification} other{{count} unread notifications}}, latest: {text}'**
  String attentionRowSemantics(int count, String text);

  /// No description provided for @attentionMarkRead.
  ///
  /// In en, this message translates to:
  /// **'Mark as read'**
  String get attentionMarkRead;

  /// No description provided for @attentionMarkAllRead.
  ///
  /// In en, this message translates to:
  /// **'Mark all as read'**
  String get attentionMarkAllRead;

  /// No description provided for @attentionAnnounce.
  ///
  /// In en, this message translates to:
  /// **'New notification from {tab}: {text}'**
  String attentionAnnounce(String tab, String text);

  /// No description provided for @workspaceHasUnread.
  ///
  /// In en, this message translates to:
  /// **'has unread notifications'**
  String get workspaceHasUnread;

  /// No description provided for @terminalPaneUnreadLabel.
  ///
  /// In en, this message translates to:
  /// **'Terminal {title}, has unread notifications'**
  String terminalPaneUnreadLabel(String title);

  /// No description provided for @notificationsPanelTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notificationsPanelTitle;

  /// No description provided for @notificationsPanelTooltip.
  ///
  /// In en, this message translates to:
  /// **'Notifications  {shortcut}'**
  String notificationsPanelTooltip(String shortcut);

  /// No description provided for @notificationsPanelEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No notifications yet'**
  String get notificationsPanelEmptyTitle;

  /// No description provided for @notificationsPanelEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Programs in your tabs send notifications with OSC 9, 99, 777 or the shellx notify command.'**
  String get notificationsPanelEmptyBody;

  /// No description provided for @notificationsPanelNextHint.
  ///
  /// In en, this message translates to:
  /// **'Next unread  {shortcut}'**
  String notificationsPanelNextHint(String shortcut);

  /// No description provided for @notificationsPanelOpened.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Notifications, 1 item} other{Notifications, {count} items}}'**
  String notificationsPanelOpened(int count);

  /// No description provided for @notificationsTabClosed.
  ///
  /// In en, this message translates to:
  /// **'Tab closed'**
  String get notificationsTabClosed;

  /// No description provided for @notificationsTimeNow.
  ///
  /// In en, this message translates to:
  /// **'now'**
  String get notificationsTimeNow;

  /// No description provided for @notificationsTimeMinutes.
  ///
  /// In en, this message translates to:
  /// **'{count} min'**
  String notificationsTimeMinutes(int count);

  /// No description provided for @notificationsTimeHours.
  ///
  /// In en, this message translates to:
  /// **'{count} h'**
  String notificationsTimeHours(int count);

  /// Panel time of an entry from yesterday (older than 24 h); time is HH:mm.
  ///
  /// In en, this message translates to:
  /// **'Yesterday {time}'**
  String notificationsTimeYesterday(String time);

  /// Panel time of an entry older than yesterday: en 'MMM d, HH:mm', vi 'dd/MM HH:mm'. month is notificationsMonthShort; day is unpadded, dayPadded two digits; time is HH:mm.
  ///
  /// In en, this message translates to:
  /// **'{month} {day}, {time}'**
  String notificationsTimeDate(
    String month,
    String day,
    String dayPadded,
    String time,
  );

  /// Month in notificationsTimeDate: m1 (January) to m12.
  ///
  /// In en, this message translates to:
  /// **'{month, select, m1{Jan} m2{Feb} m3{Mar} m4{Apr} m5{May} m6{Jun} m7{Jul} m8{Aug} m9{Sep} m10{Oct} m11{Nov} m12{Dec} other{}}'**
  String notificationsMonthShort(String month);

  /// No description provided for @notificationsItemUnread.
  ///
  /// In en, this message translates to:
  /// **'unread'**
  String get notificationsItemUnread;

  /// No description provided for @noUnreadNotifications.
  ///
  /// In en, this message translates to:
  /// **'No unread notifications'**
  String get noUnreadNotifications;

  /// No description provided for @systemNotifyCoalesced.
  ///
  /// In en, this message translates to:
  /// **'{count} new notifications · {text}'**
  String systemNotifyCoalesced(int count, String text);

  /// No description provided for @trayNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get trayNotifications;

  /// No description provided for @trayDesktopNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications on this computer'**
  String get trayDesktopNotifications;

  /// No description provided for @trayDesktopNotificationsUnfocused.
  ///
  /// In en, this message translates to:
  /// **'Only when the window isn\'t in front'**
  String get trayDesktopNotificationsUnfocused;

  /// No description provided for @paneSplitRight.
  ///
  /// In en, this message translates to:
  /// **'Split right'**
  String get paneSplitRight;

  /// No description provided for @paneSplitDown.
  ///
  /// In en, this message translates to:
  /// **'Split down'**
  String get paneSplitDown;

  /// No description provided for @paneZoom.
  ///
  /// In en, this message translates to:
  /// **'Zoom pane'**
  String get paneZoom;

  /// No description provided for @paneUnzoom.
  ///
  /// In en, this message translates to:
  /// **'Unzoom pane'**
  String get paneUnzoom;

  /// No description provided for @paneEqualize.
  ///
  /// In en, this message translates to:
  /// **'Equalize panes'**
  String get paneEqualize;

  /// No description provided for @paneClose.
  ///
  /// In en, this message translates to:
  /// **'Close pane'**
  String get paneClose;

  /// No description provided for @paneCloseTooltip.
  ///
  /// In en, this message translates to:
  /// **'Close pane  {shortcut}'**
  String paneCloseTooltip(String shortcut);

  /// No description provided for @paneZoomedIndicator.
  ///
  /// In en, this message translates to:
  /// **'Zoomed · {index}/{count}'**
  String paneZoomedIndicator(int index, int count);

  /// No description provided for @paneRegionLabel.
  ///
  /// In en, this message translates to:
  /// **'Pane {index} of {count} — {title}'**
  String paneRegionLabel(int index, int count, String title);

  /// No description provided for @paneRegionUnreadLabel.
  ///
  /// In en, this message translates to:
  /// **'Pane {index} of {count} — {title}, has unread notifications'**
  String paneRegionUnreadLabel(int index, int count, String title);

  /// No description provided for @paneDividerLabel.
  ///
  /// In en, this message translates to:
  /// **'Pane divider'**
  String get paneDividerLabel;

  /// No description provided for @paneSplitNoRoom.
  ///
  /// In en, this message translates to:
  /// **'Not enough room to split this pane'**
  String get paneSplitNoRoom;

  /// No description provided for @paneAnnounceSplit.
  ///
  /// In en, this message translates to:
  /// **'Split, pane {index} of {count}'**
  String paneAnnounceSplit(int index, int count);

  /// No description provided for @paneAnnounceClosed.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Pane closed, 1 left} other{Pane closed, {count} left}}'**
  String paneAnnounceClosed(int count);

  /// No description provided for @paneAnnounceZoomed.
  ///
  /// In en, this message translates to:
  /// **'Pane zoomed'**
  String get paneAnnounceZoomed;

  /// No description provided for @paneAnnounceUnzoomed.
  ///
  /// In en, this message translates to:
  /// **'Pane unzoomed'**
  String get paneAnnounceUnzoomed;

  /// No description provided for @sidebarPaneCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 pane} other{{count} panes}}'**
  String sidebarPaneCount(int count);

  /// No description provided for @terminalCloseTabAllPanes.
  ///
  /// In en, this message translates to:
  /// **'Close tab (all panes)'**
  String get terminalCloseTabAllPanes;

  /// No description provided for @confirmCloseRunningPaneBody.
  ///
  /// In en, this message translates to:
  /// **'The command running in this pane will be stopped.'**
  String get confirmCloseRunningPaneBody;

  /// No description provided for @confirmCloseRunningPaneAction.
  ///
  /// In en, this message translates to:
  /// **'Close pane'**
  String get confirmCloseRunningPaneAction;

  /// No description provided for @confirmCloseRunningPanesBody.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{The command running in 1 pane will be stopped.} other{The commands running in {count} panes will be stopped.}}'**
  String confirmCloseRunningPanesBody(int count);

  /// A9 D20 confirm-close-surface = always, idle one-pane tab
  ///
  /// In en, this message translates to:
  /// **'The shell in this tab will close.'**
  String get confirmCloseAlwaysBody;

  /// A9 D20, idle split tab
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 pane in this tab will close.} other{{count} panes in this tab will close.}}'**
  String confirmCloseAlwaysPanesBody(int count);

  /// A9 D20, idle pane
  ///
  /// In en, this message translates to:
  /// **'The shell in this pane will close.'**
  String get confirmClosePaneAlwaysBody;

  /// No description provided for @terminalRestoredDivider.
  ///
  /// In en, this message translates to:
  /// **'— Session restored · {time} —'**
  String terminalRestoredDivider(String time);

  /// No description provided for @restoreTimeYesterday.
  ///
  /// In en, this message translates to:
  /// **'yesterday {time}'**
  String restoreTimeYesterday(String time);

  /// No description provided for @trayTerminal.
  ///
  /// In en, this message translates to:
  /// **'Terminal'**
  String get trayTerminal;

  /// No description provided for @trayRestoreScrollback.
  ///
  /// In en, this message translates to:
  /// **'Save terminal contents on quit'**
  String get trayRestoreScrollback;

  /// No description provided for @trayClearSavedScrollback.
  ///
  /// In en, this message translates to:
  /// **'Clear saved contents'**
  String get trayClearSavedScrollback;

  /// No description provided for @restoreAbnormalStrip.
  ///
  /// In en, this message translates to:
  /// **'ShellX didn\'t close normally last time. Reopened {count, plural, =1{1 tab} other{{count} tabs}}; contents as of {time}.'**
  String restoreAbnormalStrip(int count, String time);

  /// No description provided for @restoreAbnormalNoText.
  ///
  /// In en, this message translates to:
  /// **'ShellX didn\'t close normally last time. Reopened {count, plural, =1{1 tab} other{{count} tabs}}.'**
  String restoreAbnormalNoText(int count);

  /// No description provided for @restoreStripCloseLabel.
  ///
  /// In en, this message translates to:
  /// **'Dismiss restore notice'**
  String get restoreStripCloseLabel;

  /// No description provided for @restorePanesFailed.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Couldn\'t reopen 1 pane} other{Couldn\'t reopen {count} panes}}'**
  String restorePanesFailed(int count);

  /// A7 D23: label of a notification sent by `shellx notify` from outside a ShellX pane
  ///
  /// In en, this message translates to:
  /// **'Command line'**
  String get cliNoticeSource;

  /// A7 D26: tray submenu, right after Notifications
  ///
  /// In en, this message translates to:
  /// **'Command line'**
  String get trayCommandLine;

  /// No description provided for @trayCliControl.
  ///
  /// In en, this message translates to:
  /// **'Allow controlling ShellX from the command line'**
  String get trayCliControl;

  /// A7 amendment: lets terminals ShellX did not open use the shellx command
  ///
  /// In en, this message translates to:
  /// **'Allow other terminals'**
  String get trayCliAllowExternal;

  /// No description provided for @trayCliInstallPath.
  ///
  /// In en, this message translates to:
  /// **'Install the shellx command for all terminals…'**
  String get trayCliInstallPath;

  /// No description provided for @trayCliRemovePath.
  ///
  /// In en, this message translates to:
  /// **'Remove the shellx command from other terminals'**
  String get trayCliRemovePath;

  /// No description provided for @trayCliCopySkills.
  ///
  /// In en, this message translates to:
  /// **'Copy the agent skill install command'**
  String get trayCliCopySkills;

  /// No description provided for @cliSkillsCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied “shellx skills install” — paste it in a terminal'**
  String get cliSkillsCopied;

  /// A7 D8 + amendment: toast after the PATH install; the two settings stay independent
  ///
  /// In en, this message translates to:
  /// **'Installed the shellx command. To let other terminals control ShellX, also tick “Allow other terminals” in the tray’s Command line menu.'**
  String get cliPathInstalled;

  /// No description provided for @cliPathFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t install the shellx command. Add {path} to your PATH.'**
  String cliPathFailed(String path);

  /// No description provided for @cliPathRemoveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t remove the shellx command. Remove {path} yourself.'**
  String cliPathRemoveFailed(String path);

  /// No description provided for @agentChip.
  ///
  /// In en, this message translates to:
  /// **'Agent'**
  String get agentChip;

  /// No description provided for @agentChipTooltip.
  ///
  /// In en, this message translates to:
  /// **'A program is controlling this tab through the ShellX command line'**
  String get agentChipTooltip;

  /// No description provided for @cliAnnounceAgent.
  ///
  /// In en, this message translates to:
  /// **'An agent is controlling {tab}'**
  String cliAnnounceAgent(String tab);

  /// A7 ruling M10: after a macOS install, /usr/local/bin is missing from the login shell's PATH
  ///
  /// In en, this message translates to:
  /// **'Installed the shellx command in /usr/local/bin, but your shell doesn’t look there. Add this line to {file}: {line}'**
  String cliPathNotOnPath(String file, String line);

  /// UI-A9 §7.1
  ///
  /// In en, this message translates to:
  /// **'There\'s no terminal to run this in'**
  String get userCommandNoTerminal;

  /// UI-A9 §7.1
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open {path}'**
  String configOpenFailed(String path);

  /// UI-A9 §5
  ///
  /// In en, this message translates to:
  /// **'{shortcut} …'**
  String sequencePending(String shortcut);

  /// UI-A9 §8
  ///
  /// In en, this message translates to:
  /// **'{shortcut} pressed, waiting for the next key'**
  String sequencePendingAnnounce(String shortcut);

  /// UI-A9 §3.1
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 problem in the configuration} other{{count} problems in the configuration}}'**
  String configProblemsToast(int count);

  /// UI-A9 §3.1 toast button
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get configProblemsShow;

  /// UI-A9 §3.1
  ///
  /// In en, this message translates to:
  /// **'Configuration reloaded'**
  String get configReloaded;

  /// A9 D4, shown once
  ///
  /// In en, this message translates to:
  /// **'Using fonts and colours from your Ghostty config (turn off with ghostty-config = false)'**
  String get configGhosttyNotice;

  /// UI-A9 §3.2
  ///
  /// In en, this message translates to:
  /// **'Configuration problems'**
  String get configProblemsTitle;

  /// UI-A9 §3.2
  ///
  /// In en, this message translates to:
  /// **'No problems in the configuration.'**
  String get configProblemsNone;

  /// UI-A9 §3.2
  ///
  /// In en, this message translates to:
  /// **'{file}, line {line}'**
  String configProblemWhere(String file, int line);

  /// A9 T10: a problem whose file path is unknown
  ///
  /// In en, this message translates to:
  /// **'line {line}'**
  String configProblemLine(int line);

  /// UI-A9 §3.2
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get configSeverityError;

  /// UI-A9 §3.2
  ///
  /// In en, this message translates to:
  /// **'Warning'**
  String get configSeverityWarning;

  /// UI-A9 §3.2
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get configSeverityInfo;

  /// UI-A9 §3.2
  ///
  /// In en, this message translates to:
  /// **'Open configuration file'**
  String get configOpenFile;

  /// UI-A9 §3.2
  ///
  /// In en, this message translates to:
  /// **'Reload configuration'**
  String get configReload;

  /// No description provided for @configProblemSyntax.
  ///
  /// In en, this message translates to:
  /// **'Line has no “=” (expected key = value)'**
  String get configProblemSyntax;

  /// No description provided for @configProblemBadKey.
  ///
  /// In en, this message translates to:
  /// **'“{key}” is not a valid key name'**
  String configProblemBadKey(String key);

  /// No description provided for @configProblemUnknownKey.
  ///
  /// In en, this message translates to:
  /// **'ShellX has no key “{key}”'**
  String configProblemUnknownKey(String key);

  /// No description provided for @configProblemBadValue.
  ///
  /// In en, this message translates to:
  /// **'{key}: “{value}” is not valid (expected {hint})'**
  String configProblemBadValue(String key, String value, String hint);

  /// No description provided for @configProblemOutOfRange.
  ///
  /// In en, this message translates to:
  /// **'{key}: {value} is outside {hint}, using {detail}'**
  String configProblemOutOfRange(
    String key,
    String value,
    String hint,
    String detail,
  );

  /// No description provided for @configProblemDuplicate.
  ///
  /// In en, this message translates to:
  /// **'{key}: replaces line {detail}'**
  String configProblemDuplicate(String key, String detail);

  /// No description provided for @configProblemIncludeMissing.
  ///
  /// In en, this message translates to:
  /// **'File “{value}” not found'**
  String configProblemIncludeMissing(String value);

  /// No description provided for @configProblemIncludeCycle.
  ///
  /// In en, this message translates to:
  /// **'“{value}” is already loaded (config-file loop)'**
  String configProblemIncludeCycle(String value);

  /// No description provided for @configProblemIncludeDepth.
  ///
  /// In en, this message translates to:
  /// **'config-file is nested more than 4 levels'**
  String get configProblemIncludeDepth;

  /// No description provided for @configProblemIncludeLimit.
  ///
  /// In en, this message translates to:
  /// **'More than 64 config files — the rest are ignored'**
  String get configProblemIncludeLimit;

  /// No description provided for @configProblemUnreadable.
  ///
  /// In en, this message translates to:
  /// **'Can\'t read the file — keeping the previous configuration'**
  String get configProblemUnreadable;

  /// No description provided for @configProblemNotUtf8.
  ///
  /// In en, this message translates to:
  /// **'The file isn\'t UTF-8 — keeping the previous configuration'**
  String get configProblemNotUtf8;

  /// No description provided for @configProblemTooLarge.
  ///
  /// In en, this message translates to:
  /// **'The file is larger than 256 KiB — keeping the previous configuration'**
  String get configProblemTooLarge;

  /// No description provided for @configProblemThemeNotFound.
  ///
  /// In en, this message translates to:
  /// **'Theme “{value}” not found'**
  String configProblemThemeNotFound(String value);

  /// No description provided for @configProblemFontNotFound.
  ///
  /// In en, this message translates to:
  /// **'Font “{value}” not found — using JetBrains Mono'**
  String configProblemFontNotFound(String value);

  /// No description provided for @configProblemFontNotMonospace.
  ///
  /// In en, this message translates to:
  /// **'Font “{value}” isn\'t monospaced — columns may not line up'**
  String configProblemFontNotMonospace(String value);

  /// No description provided for @configProblemLowContrast.
  ///
  /// In en, this message translates to:
  /// **'Low text/background contrast ({detail}:1, aim for 4.5:1)'**
  String configProblemLowContrast(String detail);

  /// No description provided for @configProblemUnsupportedValue.
  ///
  /// In en, this message translates to:
  /// **'{key} = {value} isn\'t supported (using {hint})'**
  String configProblemUnsupportedValue(String key, String value, String hint);

  /// No description provided for @configProblemNotOnThisPlatform.
  ///
  /// In en, this message translates to:
  /// **'{key} only has an effect on macOS'**
  String configProblemNotOnThisPlatform(String key);

  /// No description provided for @configProblemBadTrigger.
  ///
  /// In en, this message translates to:
  /// **'“{value}” is not a valid key combination'**
  String configProblemBadTrigger(String value);

  /// No description provided for @configProblemUnknownAction.
  ///
  /// In en, this message translates to:
  /// **'There\'s no action “{value}”'**
  String configProblemUnknownAction(String value);

  /// No description provided for @configProblemBadActionParam.
  ///
  /// In en, this message translates to:
  /// **'“{value}” is not valid (expected {hint})'**
  String configProblemBadActionParam(String value, String hint);

  /// No description provided for @configProblemReservedTrigger.
  ///
  /// In en, this message translates to:
  /// **'{value} is reserved by the system'**
  String configProblemReservedTrigger(String value);

  /// No description provided for @configProblemPlainKeyTrigger.
  ///
  /// In en, this message translates to:
  /// **'{value} is for typing — add Ctrl, Alt or ⌘'**
  String configProblemPlainKeyTrigger(String value);

  /// No description provided for @configProblemRegionTrigger.
  ///
  /// In en, this message translates to:
  /// **'F6 and Shift+F6 always move between regions'**
  String get configProblemRegionTrigger;

  /// No description provided for @configProblemShellKeyTrigger.
  ///
  /// In en, this message translates to:
  /// **'{value} will no longer reach the shell'**
  String configProblemShellKeyTrigger(String value);

  /// No description provided for @configProblemOptionKeyTrigger.
  ///
  /// In en, this message translates to:
  /// **'{value} will no longer type its Option character'**
  String configProblemOptionKeyTrigger(String value);

  /// No description provided for @configProblemAltGrTrigger.
  ///
  /// In en, this message translates to:
  /// **'{value} works with the left Alt only; AltGr still types characters'**
  String configProblemAltGrTrigger(String value);

  /// No description provided for @configProblemMissionControlTrigger.
  ///
  /// In en, this message translates to:
  /// **'Mission Control may take {value}'**
  String configProblemMissionControlTrigger(String value);

  /// No description provided for @configProblemUnsupportedPrefix.
  ///
  /// In en, this message translates to:
  /// **'The “{value}” prefix isn\'t supported'**
  String configProblemUnsupportedPrefix(String value);

  /// No description provided for @configProblemSequenceTooLong.
  ///
  /// In en, this message translates to:
  /// **'Key sequences have at most 2 steps'**
  String get configProblemSequenceTooLong;

  /// No description provided for @configProblemSequencePrefixShadows.
  ///
  /// In en, this message translates to:
  /// **'{value} starts a key sequence, so it no longer works on its own'**
  String configProblemSequencePrefixShadows(String value);

  /// No description provided for @configProblemSequenceRepeatsPrefix.
  ///
  /// In en, this message translates to:
  /// **'This sequence can\'t fire: pressing {value} twice sends it'**
  String configProblemSequenceRepeatsPrefix(String value);

  /// No description provided for @configProblemUnknownCommand.
  ///
  /// In en, this message translates to:
  /// **'There\'s no command “{value}”'**
  String configProblemUnknownCommand(String value);

  /// No description provided for @configProblemCommandLimit.
  ///
  /// In en, this message translates to:
  /// **'More than 200 commands — the rest are ignored'**
  String get configProblemCommandLimit;

  /// No description provided for @configProblemLimit.
  ///
  /// In en, this message translates to:
  /// **'{detail} problems — showing the first 100'**
  String configProblemLimit(String detail);

  /// No description provided for @configProblemInternal.
  ///
  /// In en, this message translates to:
  /// **'Unexpected error — keeping the previous configuration'**
  String get configProblemInternal;

  /// UI-A9 §6
  ///
  /// In en, this message translates to:
  /// **'Configuration'**
  String get trayConfig;

  /// UI-A9 §6
  ///
  /// In en, this message translates to:
  /// **'Open configuration file'**
  String get trayConfigOpen;

  /// UI-A9 §6
  ///
  /// In en, this message translates to:
  /// **'Reload configuration'**
  String get trayConfigReload;

  /// UI-A9 §6
  ///
  /// In en, this message translates to:
  /// **'Keyboard shortcuts…'**
  String get trayConfigShortcuts;

  /// UI-A9 §6
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{⚠ 1 configuration problem…} other{⚠ {count} configuration problems…}}'**
  String trayConfigProblems(int count);

  /// UI-A9 §2
  ///
  /// In en, this message translates to:
  /// **'Command palette'**
  String get paletteTitle;

  /// UI-A9 §2
  ///
  /// In en, this message translates to:
  /// **'Search commands'**
  String get paletteSearchLabel;

  /// UI-A9 §2
  ///
  /// In en, this message translates to:
  /// **'Type a command…'**
  String get paletteSearchHint;

  /// UI-A9 §2
  ///
  /// In en, this message translates to:
  /// **'No matching commands'**
  String get paletteNoResults;

  /// UI-A9 §8
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 command} other{{count} commands}}'**
  String paletteResultCount(int count);

  /// UI-A9 §2
  ///
  /// In en, this message translates to:
  /// **'Your command'**
  String get paletteKindUserCommand;

  /// UI-A9 §2
  ///
  /// In en, this message translates to:
  /// **'Snippet'**
  String get paletteKindSnippet;

  /// UI-A9 §2
  ///
  /// In en, this message translates to:
  /// **'Configuration'**
  String get paletteKindConfig;

  /// UI-A9 §7.3
  ///
  /// In en, this message translates to:
  /// **'New tab'**
  String get actionNewTab;

  /// UI-A9 §7.3
  ///
  /// In en, this message translates to:
  /// **'Close pane or tab'**
  String get actionCloseSurface;

  /// UI-A9 §7.3
  ///
  /// In en, this message translates to:
  /// **'Close whole tab'**
  String get actionCloseTab;

  /// UI-A9 §7.3
  ///
  /// In en, this message translates to:
  /// **'New workspace'**
  String get actionNewWorkspace;

  /// UI-A9 §7.3
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get actionToggleNotifications;

  /// UI-A9 §7.3
  ///
  /// In en, this message translates to:
  /// **'Jump to unread'**
  String get actionJumpToUnread;

  /// UI-A9 §7.3
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get actionCopy;

  /// UI-A9 §7.3
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get actionPaste;

  /// UI-A9 §7.3
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get actionSelectAll;

  /// UI-A9 §7.3
  ///
  /// In en, this message translates to:
  /// **'Go to tab {n}'**
  String actionGotoTab(String n);

  /// UI-A9 §7.3
  ///
  /// In en, this message translates to:
  /// **'Next tab'**
  String get actionNextTab;

  /// UI-A9 §7.3
  ///
  /// In en, this message translates to:
  /// **'Previous tab'**
  String get actionPreviousTab;

  /// UI-A9 §7.3
  ///
  /// In en, this message translates to:
  /// **'Split right'**
  String get actionSplitRight;

  /// UI-A9 §7.3
  ///
  /// In en, this message translates to:
  /// **'Split down'**
  String get actionSplitDown;

  /// UI-A9 §7.3
  ///
  /// In en, this message translates to:
  /// **'{direction, select, left{Focus pane on the left} right{Focus pane on the right} up{Focus pane above} other{Focus pane below}}'**
  String actionFocusPane(String direction);

  /// UI-A9 §7.3
  ///
  /// In en, this message translates to:
  /// **'{direction, select, left{Move divider left} right{Move divider right} up{Move divider up} other{Move divider down}}'**
  String actionResizePane(String direction);

  /// UI-A9 §7.3
  ///
  /// In en, this message translates to:
  /// **'Zoom or unzoom pane'**
  String get actionToggleZoom;

  /// UI-A9 §7.3
  ///
  /// In en, this message translates to:
  /// **'Equalize panes'**
  String get actionEqualize;

  /// UI-A9 §7.3
  ///
  /// In en, this message translates to:
  /// **'Bigger text'**
  String get actionFontBigger;

  /// UI-A9 §7.3
  ///
  /// In en, this message translates to:
  /// **'Smaller text'**
  String get actionFontSmaller;

  /// UI-A9 §7.3
  ///
  /// In en, this message translates to:
  /// **'Default text size'**
  String get actionFontReset;

  /// UI-A9 §7.3
  ///
  /// In en, this message translates to:
  /// **'Next region'**
  String get actionNextRegion;

  /// UI-A9 §7.3
  ///
  /// In en, this message translates to:
  /// **'Previous region'**
  String get actionPreviousRegion;

  /// UI-A9 §7.3
  ///
  /// In en, this message translates to:
  /// **'Reload configuration'**
  String get actionReloadConfig;

  /// UI-A9 §7.3
  ///
  /// In en, this message translates to:
  /// **'Open configuration file'**
  String get actionOpenConfig;

  /// UI-A9 §7.3
  ///
  /// In en, this message translates to:
  /// **'Command palette'**
  String get actionCommandPalette;

  /// UI-A9 §7.3
  ///
  /// In en, this message translates to:
  /// **'Keyboard shortcuts…'**
  String get actionShowShortcuts;

  /// UI-A9 §7.3
  ///
  /// In en, this message translates to:
  /// **'Show configuration problems'**
  String get actionShowConfigProblems;

  /// UI-A9 §7.3
  ///
  /// In en, this message translates to:
  /// **'Run “{name}”'**
  String actionRunCommand(String name);

  /// UI-A9 §7.3
  ///
  /// In en, this message translates to:
  /// **'Send text to the terminal'**
  String get actionSendText;

  /// UI-A9 §7.3
  ///
  /// In en, this message translates to:
  /// **'Ignore key'**
  String get actionIgnore;

  /// UI-A9 §4
  ///
  /// In en, this message translates to:
  /// **'Keyboard shortcuts'**
  String get shortcutsTitle;

  /// UI-A9 §4
  ///
  /// In en, this message translates to:
  /// **'Search shortcuts'**
  String get shortcutsSearchLabel;

  /// UI-A9 §4.1
  ///
  /// In en, this message translates to:
  /// **'{group, select, tabs{Tabs} panes{Panes} notifications{Notifications} editing{Editing} font{Text size} browser{Browser} window{Window} config{Configuration} other{Your commands}}'**
  String shortcutsGroup(String group);

  /// UI-A9 §4.1
  ///
  /// In en, this message translates to:
  /// **'Add shortcut'**
  String get shortcutsAdd;

  /// UI-A9 §8
  ///
  /// In en, this message translates to:
  /// **'Add a shortcut for “{action}”'**
  String shortcutsAddFor(String action);

  /// UI-A9 §4.1
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get shortcutsReset;

  /// UI-A9 §8
  ///
  /// In en, this message translates to:
  /// **'Reset “{action}”'**
  String shortcutsResetFor(String action);

  /// UI-A9 §8
  ///
  /// In en, this message translates to:
  /// **'Remove {shortcut}'**
  String shortcutsRemove(String shortcut);

  /// UI-A9 §4.1
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get shortcutsNone;

  /// UI-A9 §4.1
  ///
  /// In en, this message translates to:
  /// **'Press a key combination… (Esc to cancel)'**
  String get shortcutsRecording;

  /// UI-A9 §4.1: the modifiers held so far while recording
  ///
  /// In en, this message translates to:
  /// **'{keys}…'**
  String shortcutsHeld(String keys);

  /// UI-A9 §4.1
  ///
  /// In en, this message translates to:
  /// **'{shortcut} is used by “{action}”.'**
  String shortcutsConflict(String shortcut, String action);

  /// UI-A9 §4.1
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get shortcutsReplace;

  /// UI-A9 §4.1
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get shortcutsCancel;

  /// UI-A9 §4.1
  ///
  /// In en, this message translates to:
  /// **'A later line in {file}:{line} overrides this'**
  String shortcutsOverridden(String file, int line);

  /// UI-A9 §4.1
  ///
  /// In en, this message translates to:
  /// **'Set in the configuration file, line {line}'**
  String shortcutsFromFile(int line);

  /// UI-A9 §8
  ///
  /// In en, this message translates to:
  /// **'{shortcut} now runs “{action}”'**
  String shortcutsAssigned(String shortcut, String action);

  /// UI-A9 §8
  ///
  /// In en, this message translates to:
  /// **'Removed {shortcut}'**
  String shortcutsRemoved(String shortcut);

  /// UI-A9 §8
  ///
  /// In en, this message translates to:
  /// **'“{action}” reset'**
  String shortcutsResetDone(String action);

  /// UI-A9 §4.1
  ///
  /// In en, this message translates to:
  /// **'Shortcuts written in the file are kept.'**
  String get shortcutsFooter;

  /// UI-A9 §7.1
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save the shortcut to {path}'**
  String configWriteFailed(String path);

  /// No description provided for @sshConnectMenu.
  ///
  /// In en, this message translates to:
  /// **'Connect over SSH…'**
  String get sshConnectMenu;

  /// No description provided for @tmuxAttachMenu.
  ///
  /// In en, this message translates to:
  /// **'Attach tmux session…'**
  String get tmuxAttachMenu;

  /// No description provided for @sshDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Connect to a server'**
  String get sshDialogTitle;

  /// No description provided for @sshDialogTabSsh.
  ///
  /// In en, this message translates to:
  /// **'SSH'**
  String get sshDialogTabSsh;

  /// No description provided for @sshDialogTabTmux.
  ///
  /// In en, this message translates to:
  /// **'tmux'**
  String get sshDialogTabTmux;

  /// No description provided for @sshHostLabel.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get sshHostLabel;

  /// No description provided for @sshHostHint.
  ///
  /// In en, this message translates to:
  /// **'devbox or user@host:2222'**
  String get sshHostHint;

  /// No description provided for @sshHostInvalid.
  ///
  /// In en, this message translates to:
  /// **'Not a valid server name'**
  String get sshHostInvalid;

  /// No description provided for @sshSuggestionsConfig.
  ///
  /// In en, this message translates to:
  /// **'In ~/.ssh/config'**
  String get sshSuggestionsConfig;

  /// No description provided for @sshSuggestionsRecent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get sshSuggestionsRecent;

  /// No description provided for @sshSuggestionsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 suggestion} other{{count} suggestions}}'**
  String sshSuggestionsCount(int count);

  /// No description provided for @sshRemoteDirLabel.
  ///
  /// In en, this message translates to:
  /// **'Folder on the server (optional)'**
  String get sshRemoteDirLabel;

  /// No description provided for @sshRemoteDirInvalid.
  ///
  /// In en, this message translates to:
  /// **'The path must start with / or ~'**
  String get sshRemoteDirInvalid;

  /// No description provided for @sshNoHookLabel.
  ///
  /// In en, this message translates to:
  /// **'Don’t install the ShellX hook on this server'**
  String get sshNoHookLabel;

  /// No description provided for @sshNoHookHelp.
  ///
  /// In en, this message translates to:
  /// **'The hook tells ShellX the folder, branch and ports on the server. Turn it off for servers that aren’t Unix.'**
  String get sshNoHookHelp;

  /// No description provided for @sshConnectAction.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get sshConnectAction;

  /// No description provided for @sshUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Can’t find the ssh command on this computer'**
  String get sshUnavailable;

  /// No description provided for @sshUnavailableWindows.
  ///
  /// In en, this message translates to:
  /// **'Can’t find ssh. Turn on “OpenSSH Client” in Settings → Apps → Optional features.'**
  String get sshUnavailableWindows;

  /// No description provided for @tmuxSourceLabel.
  ///
  /// In en, this message translates to:
  /// **'tmux sessions on'**
  String get tmuxSourceLabel;

  /// No description provided for @tmuxSourceLocal.
  ///
  /// In en, this message translates to:
  /// **'This computer'**
  String get tmuxSourceLocal;

  /// No description provided for @tmuxLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading sessions…'**
  String get tmuxLoading;

  /// No description provided for @tmuxEmpty.
  ///
  /// In en, this message translates to:
  /// **'No tmux sessions yet'**
  String get tmuxEmpty;

  /// No description provided for @tmuxUnavailable.
  ///
  /// In en, this message translates to:
  /// **'tmux isn’t installed on {where}'**
  String tmuxUnavailable(String where);

  /// No description provided for @tmuxListFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t list sessions on {where}. Connect to it over SSH once (so no password is needed), then try again.'**
  String tmuxListFailed(String where);

  /// No description provided for @tmuxRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tmuxRetry;

  /// No description provided for @tmuxWindows.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 window} other{{count} windows}}'**
  String tmuxWindows(int count);

  /// No description provided for @tmuxAttachedElsewhere.
  ///
  /// In en, this message translates to:
  /// **'attached elsewhere'**
  String get tmuxAttachedElsewhere;

  /// No description provided for @tmuxLastActive.
  ///
  /// In en, this message translates to:
  /// **'active {time}'**
  String tmuxLastActive(String time);

  /// No description provided for @tmuxAttachAction.
  ///
  /// In en, this message translates to:
  /// **'Attach'**
  String get tmuxAttachAction;

  /// No description provided for @tmuxNewLabel.
  ///
  /// In en, this message translates to:
  /// **'New session name'**
  String get tmuxNewLabel;

  /// No description provided for @tmuxNameInvalid.
  ///
  /// In en, this message translates to:
  /// **'Use up to 64 characters, without “:” or “.”'**
  String get tmuxNameInvalid;

  /// No description provided for @tmuxCreateAction.
  ///
  /// In en, this message translates to:
  /// **'Create and attach'**
  String get tmuxCreateAction;

  /// No description provided for @sidebarRemoteMark.
  ///
  /// In en, this message translates to:
  /// **'SSH: {host}'**
  String sidebarRemoteMark(String host);

  /// No description provided for @sidebarTmuxMark.
  ///
  /// In en, this message translates to:
  /// **'tmux: {name}'**
  String sidebarTmuxMark(String name);

  /// No description provided for @sidebarTmuxRemoteMark.
  ///
  /// In en, this message translates to:
  /// **'tmux: {name} · {host}'**
  String sidebarTmuxRemoteMark(String name, String host);

  /// No description provided for @sshStateConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting to {host}'**
  String sshStateConnecting(String host);

  /// No description provided for @sshStateDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Lost connection to {host}'**
  String sshStateDisconnected(String host);

  /// No description provided for @sshStateFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t connect to {host}'**
  String sshStateFailed(String host);

  /// No description provided for @sshRetryIn.
  ///
  /// In en, this message translates to:
  /// **'{seconds, plural, =1{Retrying in 1 second} other{Retrying in {seconds} seconds}}'**
  String sshRetryIn(int seconds);

  /// No description provided for @sshRetrying.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting…'**
  String get sshRetrying;

  /// No description provided for @sshAutoRetryStopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped retrying'**
  String get sshAutoRetryStopped;

  /// No description provided for @sshFailedHookHint.
  ///
  /// In en, this message translates to:
  /// **'The server may not support the ShellX hook'**
  String get sshFailedHookHint;

  /// No description provided for @sshReconnectAction.
  ///
  /// In en, this message translates to:
  /// **'Reconnect'**
  String get sshReconnectAction;

  /// No description provided for @sshRetryAction.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get sshRetryAction;

  /// No description provided for @sshRetryPlainAction.
  ///
  /// In en, this message translates to:
  /// **'Try without the hook'**
  String get sshRetryPlainAction;

  /// No description provided for @sshClosePaneAction.
  ///
  /// In en, this message translates to:
  /// **'Close pane'**
  String get sshClosePaneAction;

  /// No description provided for @sshTmuxHint.
  ///
  /// In en, this message translates to:
  /// **'Run inside tmux to keep programs running when the connection drops'**
  String get sshTmuxHint;

  /// No description provided for @sshDisconnectedLine.
  ///
  /// In en, this message translates to:
  /// **'[Lost connection to {host}] — press Enter to reconnect'**
  String sshDisconnectedLine(String host);

  /// No description provided for @sshFailedLine.
  ///
  /// In en, this message translates to:
  /// **'[Couldn’t connect to {host}] — press Enter to try again'**
  String sshFailedLine(String host);

  /// No description provided for @sshReconnectedDivider.
  ///
  /// In en, this message translates to:
  /// **'— Reconnected · {time} —'**
  String sshReconnectedDivider(String time);

  /// No description provided for @workspaceNewRemoteTab.
  ///
  /// In en, this message translates to:
  /// **'New SSH tab on {host}'**
  String workspaceNewRemoteTab(String host);

  /// No description provided for @workspaceNewLocalTab.
  ///
  /// In en, this message translates to:
  /// **'New local tab'**
  String get workspaceNewLocalTab;

  /// No description provided for @workspaceReconnectAll.
  ///
  /// In en, this message translates to:
  /// **'Reconnect all panes'**
  String get workspaceReconnectAll;

  /// No description provided for @workspaceRemoteLabel.
  ///
  /// In en, this message translates to:
  /// **'SSH workspace {host}'**
  String workspaceRemoteLabel(String host);

  /// No description provided for @rowReconnect.
  ///
  /// In en, this message translates to:
  /// **'Reconnect'**
  String get rowReconnect;

  /// No description provided for @paneSplitLocalRight.
  ///
  /// In en, this message translates to:
  /// **'Split right on this computer'**
  String get paneSplitLocalRight;

  /// No description provided for @remotePortTooltip.
  ///
  /// In en, this message translates to:
  /// **'Open port {port} on {host} (forwarded over SSH)'**
  String remotePortTooltip(int port, String host);

  /// No description provided for @remotePortForwarded.
  ///
  /// In en, this message translates to:
  /// **'localhost:{local} → {host}:{port}'**
  String remotePortForwarded(int local, String host, int port);

  /// No description provided for @remotePortForwardFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t forward port {port}'**
  String remotePortForwardFailed(int port);

  /// No description provided for @sshTrayMenu.
  ///
  /// In en, this message translates to:
  /// **'SSH'**
  String get sshTrayMenu;

  /// No description provided for @sshTrayHook.
  ///
  /// In en, this message translates to:
  /// **'Install the ShellX hook on servers (folder, branch, ports)'**
  String get sshTrayHook;

  /// No description provided for @sshTrayClearRecent.
  ///
  /// In en, this message translates to:
  /// **'Clear recent servers'**
  String get sshTrayClearRecent;

  /// No description provided for @sshRecentCleared.
  ///
  /// In en, this message translates to:
  /// **'Recent servers cleared'**
  String get sshRecentCleared;

  /// No description provided for @sshAnnounceConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected to {host}'**
  String sshAnnounceConnected(String host);

  /// No description provided for @sshAnnounceDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Lost connection to {host}'**
  String sshAnnounceDisconnected(String host);

  /// No description provided for @sshAnnounceReconnected.
  ///
  /// In en, this message translates to:
  /// **'Reconnected to {host}'**
  String sshAnnounceReconnected(String host);

  /// No description provided for @paneRemoteSuffix.
  ///
  /// In en, this message translates to:
  /// **', on {host}'**
  String paneRemoteSuffix(String host);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'vi'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'vi':
      return AppLocalizationsVi();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
