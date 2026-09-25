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
  /// **'Forgot your password? Open ShellX on a computer that is still signed in and choose “Change password…” from its menu.'**
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
  /// **'{platform, select, macos{ShellX now lives in the menu bar. Choose “Pair phone…” there to connect your phone.} other{ShellX now lives in the system tray. Choose “Pair phone…” there to connect your phone.}}'**
  String onboardingTrayHint(String platform);

  /// No description provided for @onboardingFinish.
  ///
  /// In en, this message translates to:
  /// **'Finish'**
  String get onboardingFinish;

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
  /// **'{count, plural, =1{1 open session will be closed.} other{{count} open sessions will be closed.}}'**
  String confirmRemoteOffBody(int count);

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
  /// **'All sessions will be closed and every paired phone will be removed. After signing in again you must pair your phones again.'**
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
  /// **'This phone loses access to this computer immediately and its sessions are closed. To use it again you must pair it again.'**
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
  /// **'{count, plural, =1{1 open session will be closed. Your phones cannot reach this computer until ShellX runs again.} other{{count} open sessions will be closed. Your phones cannot reach this computer until ShellX runs again.}}'**
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

  /// No description provided for @notifyAlreadyRunningTitle.
  ///
  /// In en, this message translates to:
  /// **'ShellX is already running'**
  String get notifyAlreadyRunningTitle;

  /// No description provided for @notifyAlreadyRunningBody.
  ///
  /// In en, this message translates to:
  /// **'{platform, select, macos{Find it in the menu bar.} other{Find it in the system tray.}}'**
  String notifyAlreadyRunningBody(String platform);

  /// No description provided for @notifyTerminalProblemTitle.
  ///
  /// In en, this message translates to:
  /// **'Processes from a terminal session may still be running'**
  String get notifyTerminalProblemTitle;

  /// No description provided for @windowsVersionUnsupported.
  ///
  /// In en, this message translates to:
  /// **'ShellX requires Windows 10 version 1809 or later.'**
  String get windowsVersionUnsupported;
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
