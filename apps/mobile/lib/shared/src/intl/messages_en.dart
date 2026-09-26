// DO NOT EDIT. This is code generated via package:intl/generate_localized.dart
// This is a library that provides messages for a en locale. All the
// messages from the main program should be duplicated here with the same
// function name.

// Ignore issues from commonly used lints in this file.
// ignore_for_file:unnecessary_brace_in_string_interps, unnecessary_new
// ignore_for_file:prefer_single_quotes,comment_references, directives_ordering
// ignore_for_file:annotate_overrides,prefer_generic_function_type_aliases
// ignore_for_file:unused_import, file_names, avoid_escaping_inner_quotes
// ignore_for_file:unnecessary_string_interpolations, unnecessary_string_escapes

import 'package:intl/intl.dart';
import 'package:intl/message_lookup_by_library.dart';

final messages = new MessageLookup();

typedef String MessageIfAbsent(String messageStr, List<dynamic> args);

class MessageLookup extends MessageLookupByLibrary {
  String get localeName => 'en';

  static String m0(email) =>
      "Deletes the account ${email} with all its devices and pairings.";

  static String m1(site) =>
      "Install ShellX on your computer (macOS or Windows) from ${site}.";

  static String m2(menu) =>
      "Click the ShellX icon → ${menu}, then scan the code.";

  static String m3(reason) => "Couldn\'t start the shell: ${reason}";

  static String m4(code) => "Something went wrong (${code}).";

  static String m5(day, month, time) => "${month}/${day}, ${time}";

  static String m6(count) =>
      "${Intl.plural(count, one: '1 minute ago', other: '${count} minutes ago')}";

  static String m7(time) => "today, ${time}";

  static String m8(time) => "yesterday, ${time}";

  static String m9(method) => "Unlock with ${method}";

  static String m10(when) => "Last online: ${when}";

  static String m11(count) =>
      "${Intl.plural(count, one: '1 tab', other: '${count} tabs')}";

  static String m12(name) =>
      "${name} now trusts this phone. From now on, just tap the computer to open a terminal.";

  static String m13(count) =>
      "${Intl.plural(count, one: '1 more character needed.', other: '${count} more characters needed.')}";

  static String m14(count) =>
      "${Intl.plural(count, one: '1 character too many.', other: '${count} characters too many.')}";

  static String m15(when) => "opened ${when}";

  static String m16(count) =>
      "${Intl.plural(count, one: 'This computer has 1 session', other: 'This computer has ${count} sessions')}";

  static String m17(menu) =>
      "macOS: click the ShellX icon in the menu bar. Windows: click the icon in the system tray. Choose ${menu}";

  static String m18(code) =>
      "The last command exited with code ${code}. The output above can still be read and copied.";

  static String m19(method) => "Lock with ${method}";

  static String m20(name) =>
      "Unpair ${name}? You\'ll need to scan a QR code again to use this computer.";

  static String m21(version, build) => "ShellX ${version} (${build})";

  static String m22(terms, privacy) =>
      "By creating an account you agree to the ${terms} and the ${privacy}.";

  static String m23(length) => "Password must be at least ${length} characters";

  static String m24(length) => "Must be at most ${length} characters";

  static String m25(length) => "Must be at least ${length} characters";

  final messages = _notInlinedMessages(_notInlinedMessages);
  static Map<String, Function> _notInlinedMessages(_) => <String, Function>{
    "actionCancel": MessageLookupByLibrary.simpleMessage("Cancel"),
    "actionClose": MessageLookupByLibrary.simpleMessage("Close"),
    "actionLater": MessageLookupByLibrary.simpleMessage("Later"),
    "actionScanCode": MessageLookupByLibrary.simpleMessage("Scan code"),
    "appTitle": MessageLookupByLibrary.simpleMessage("ShellX"),
    "backToMachines": MessageLookupByLibrary.simpleMessage("Back to computers"),
    "bannerReconnectButton": MessageLookupByLibrary.simpleMessage("Reconnect"),
    "bannerReconnecting": MessageLookupByLibrary.simpleMessage(
      "Connection lost, retrying…",
    ),
    "bannerReplaced": MessageLookupByLibrary.simpleMessage(
      "Another instance of the app has connected.",
    ),
    "biometricFaceId": MessageLookupByLibrary.simpleMessage("Face ID"),
    "biometricFingerprint": MessageLookupByLibrary.simpleMessage("fingerprint"),
    "biometricGeneric": MessageLookupByLibrary.simpleMessage("biometrics"),
    "biometricPasscode": MessageLookupByLibrary.simpleMessage(
      "device passcode",
    ),
    "biometricTouchId": MessageLookupByLibrary.simpleMessage("Touch ID"),
    "closeTab": MessageLookupByLibrary.simpleMessage("Close tab"),
    "copied": MessageLookupByLibrary.simpleMessage("Copied"),
    "copyAction": MessageLookupByLibrary.simpleMessage("Copy"),
    "createAccountLink": MessageLookupByLibrary.simpleMessage("Create one"),
    "deleteAccountButton": MessageLookupByLibrary.simpleMessage(
      "Delete permanently",
    ),
    "deleteAccountLoseAccount": m0,
    "deleteAccountLoseComputers": MessageLookupByLibrary.simpleMessage(
      "Every computer signed in to it is signed out.",
    ),
    "deleteAccountLoseSessions": MessageLookupByLibrary.simpleMessage(
      "Open terminal sessions are closed.",
    ),
    "deleteAccountPasswordLabel": MessageLookupByLibrary.simpleMessage(
      "Enter your password to confirm",
    ),
    "deleteAccountTitle": MessageLookupByLibrary.simpleMessage(
      "Delete account",
    ),
    "deleteAccountWarningTitle": MessageLookupByLibrary.simpleMessage(
      "This can\'t be undone",
    ),
    "emailHint": MessageLookupByLibrary.simpleMessage("email@example.com"),
    "emailLabel": MessageLookupByLibrary.simpleMessage("Email"),
    "emptyStep1": m1,
    "emptyStep2": MessageLookupByLibrary.simpleMessage(
      "Sign in with this same account.",
    ),
    "emptyStep3": m2,
    "emptyTitle": MessageLookupByLibrary.simpleMessage("No computers yet"),
    "errorAgentOffline": MessageLookupByLibrary.simpleMessage(
      "The computer is offline. Open ShellX on the computer and try again.",
    ),
    "errorDisposableEmail": MessageLookupByLibrary.simpleMessage(
      "Disposable email addresses can\'t be used. Please use a real email.",
    ),
    "errorEmailTaken": MessageLookupByLibrary.simpleMessage(
      "This email is already registered.",
    ),
    "errorInvalidCredentials": MessageLookupByLibrary.simpleMessage(
      "Incorrect email or password.",
    ),
    "errorInvalidEmail": MessageLookupByLibrary.simpleMessage(
      "Invalid email address.",
    ),
    "errorNetwork": MessageLookupByLibrary.simpleMessage(
      "Can\'t reach the server. Check your connection and try again.",
    ),
    "errorNotInAccount": MessageLookupByLibrary.simpleMessage(
      "This computer doesn\'t belong to your account. Sign in with the same account on the computer.",
    ),
    "errorQrInvalid": MessageLookupByLibrary.simpleMessage(
      "The QR code is invalid or has expired. Create a new code on your computer.",
    ),
    "errorRateLimited": MessageLookupByLibrary.simpleMessage(
      "Try again in a few minutes.",
    ),
    "errorSessionLimit": MessageLookupByLibrary.simpleMessage(
      "This computer already has the maximum of 10 sessions open. Close some sessions first.",
    ),
    "errorSpawnFailed": m3,
    "errorTimeout": MessageLookupByLibrary.simpleMessage(
      "The computer didn\'t respond. Please try again.",
    ),
    "errorUnknown": m4,
    "errorUntrusted": MessageLookupByLibrary.simpleMessage(
      "This computer no longer trusts this phone. Please pair again.",
    ),
    "errorWeakPassword": MessageLookupByLibrary.simpleMessage(
      "Password must be 8–128 characters.",
    ),
    "errorWrongPassword": MessageLookupByLibrary.simpleMessage(
      "Incorrect password.",
    ),
    "fontSizeTooltip": MessageLookupByLibrary.simpleMessage("Font size"),
    "forbiddenTitle": MessageLookupByLibrary.simpleMessage(
      "You don\'t have permission to access this feature",
    ),
    "forgotPasswordHint": MessageLookupByLibrary.simpleMessage(
      "Forgot your password? Change it in ShellX on a computer that is signed in.",
    ),
    "keyArrowDown": MessageLookupByLibrary.simpleMessage("Down arrow"),
    "keyArrowLeft": MessageLookupByLibrary.simpleMessage("Left arrow"),
    "keyArrowRight": MessageLookupByLibrary.simpleMessage("Right arrow"),
    "keyArrowUp": MessageLookupByLibrary.simpleMessage("Up arrow"),
    "keyMinus": MessageLookupByLibrary.simpleMessage("Hyphen"),
    "keyPaste": MessageLookupByLibrary.simpleMessage("Paste"),
    "keyPipe": MessageLookupByLibrary.simpleMessage("Vertical bar"),
    "keySlash": MessageLookupByLibrary.simpleMessage("Slash"),
    "keyTilde": MessageLookupByLibrary.simpleMessage("Tilde"),
    "keyboardTooltip": MessageLookupByLibrary.simpleMessage("Keyboard"),
    "lastSeenDate": m5,
    "lastSeenJustNow": MessageLookupByLibrary.simpleMessage("just now"),
    "lastSeenMinutes": m6,
    "lastSeenToday": m7,
    "lastSeenUnknown": MessageLookupByLibrary.simpleMessage("unknown"),
    "lastSeenYesterday": m8,
    "loadMoreFailPleaseTryAgain": MessageLookupByLibrary.simpleMessage(
      "Load more failed\nPlease try again",
    ),
    "lockReason": MessageLookupByLibrary.simpleMessage("Unlock ShellX"),
    "lockSubtitle": MessageLookupByLibrary.simpleMessage(
      "Unlock to see your computers and terminal sessions.",
    ),
    "lockTitle": MessageLookupByLibrary.simpleMessage("ShellX is locked"),
    "lockUnlockWith": m9,
    "loginButton": MessageLookupByLibrary.simpleMessage("Sign in"),
    "loginSubtitle": MessageLookupByLibrary.simpleMessage(
      "Use the same account as ShellX on your computer.",
    ),
    "loginTitle": MessageLookupByLibrary.simpleMessage("Sign in"),
    "machineLastOnline": m10,
    "machineNotPaired": MessageLookupByLibrary.simpleMessage("Not paired"),
    "machineOffline": MessageLookupByLibrary.simpleMessage(
      "This computer is offline.",
    ),
    "machineOnline": MessageLookupByLibrary.simpleMessage("Online"),
    "machineTabs": m11,
    "machineWaiting": MessageLookupByLibrary.simpleMessage(
      "Waiting for connection",
    ),
    "machinesOfflineHeader": MessageLookupByLibrary.simpleMessage("Offline"),
    "machinesTitle": MessageLookupByLibrary.simpleMessage("Your computers"),
    "networkError": MessageLookupByLibrary.simpleMessage("Network Error"),
    "noAccountPrompt": MessageLookupByLibrary.simpleMessage("No account yet?"),
    "notFound": MessageLookupByLibrary.simpleMessage("Not Found"),
    "openAppStore": MessageLookupByLibrary.simpleMessage("Open the App Store"),
    "openPlayStore": MessageLookupByLibrary.simpleMessage("Open Google Play"),
    "openSettings": MessageLookupByLibrary.simpleMessage("Open Settings"),
    "openTerminal": MessageLookupByLibrary.simpleMessage("Open terminal"),
    "pairNewMachine": MessageLookupByLibrary.simpleMessage(
      "Pair a new computer",
    ),
    "pairPhoneMenuItem": MessageLookupByLibrary.simpleMessage("Pair phone…"),
    "pairingFailedTitle": MessageLookupByLibrary.simpleMessage(
      "Couldn\'t pair",
    ),
    "pairingSucceeded": MessageLookupByLibrary.simpleMessage("Paired"),
    "pairingSucceededBody": m12,
    "passwordHide": MessageLookupByLibrary.simpleMessage("Hide password"),
    "passwordHint": MessageLookupByLibrary.simpleMessage("Password"),
    "passwordLabel": MessageLookupByLibrary.simpleMessage("Password"),
    "passwordMissing": m13,
    "passwordRule": MessageLookupByLibrary.simpleMessage(
      "8 to 128 characters.",
    ),
    "passwordShow": MessageLookupByLibrary.simpleMessage("Show password"),
    "passwordTooLong": m14,
    "pickerAttachedElsewhere": MessageLookupByLibrary.simpleMessage(
      "open on another device",
    ),
    "pickerOpen": MessageLookupByLibrary.simpleMessage("Open"),
    "pickerStarted": m15,
    "pickerSubtitle": MessageLookupByLibrary.simpleMessage(
      "Reopen a session to continue where you left off, or start a new one.",
    ),
    "pickerTitle": m16,
    "privacyLink": MessageLookupByLibrary.simpleMessage("Privacy Policy"),
    "registerButton": MessageLookupByLibrary.simpleMessage("Create account"),
    "registerSubtitle": MessageLookupByLibrary.simpleMessage(
      "One account for your phone and all your computers.",
    ),
    "registerTitle": MessageLookupByLibrary.simpleMessage("Create account"),
    "retry": MessageLookupByLibrary.simpleMessage("Retry"),
    "scanAgain": MessageLookupByLibrary.simpleMessage("Scan again"),
    "scanQrButton": MessageLookupByLibrary.simpleMessage("Scan QR code"),
    "scannerCameraDenied": MessageLookupByLibrary.simpleMessage(
      "Camera access is needed to scan the QR code. Allow it in your phone\'s Settings.",
    ),
    "scannerCameraError": MessageLookupByLibrary.simpleMessage(
      "Couldn\'t start the camera.",
    ),
    "scannerCardBody": m17,
    "scannerCardTitle": MessageLookupByLibrary.simpleMessage(
      "The code is on your computer",
    ),
    "scannerPairing": MessageLookupByLibrary.simpleMessage("Pairing…"),
    "scannerTitle": MessageLookupByLibrary.simpleMessage("Scan pairing code"),
    "sessionEnded": MessageLookupByLibrary.simpleMessage("Session ended"),
    "sessionExitedBody": m18,
    "sessionGoneBody": MessageLookupByLibrary.simpleMessage(
      "The computer no longer has this session. The output above can still be read and copied.",
    ),
    "sessionsLoading": MessageLookupByLibrary.simpleMessage(
      "Getting the session list…",
    ),
    "settingsAccountGroup": MessageLookupByLibrary.simpleMessage("Account"),
    "settingsBiometricUnavailable": MessageLookupByLibrary.simpleMessage(
      "No passcode or biometrics are set up on this device",
    ),
    "settingsDeleteAccount": MessageLookupByLibrary.simpleMessage(
      "Delete account",
    ),
    "settingsEmail": MessageLookupByLibrary.simpleMessage("Email"),
    "settingsFontSize": MessageLookupByLibrary.simpleMessage(
      "Default font size",
    ),
    "settingsLockFootnote": MessageLookupByLibrary.simpleMessage(
      "Asked when the app opens and when you come back after more than 5 minutes.",
    ),
    "settingsLockWith": m19,
    "settingsLogout": MessageLookupByLibrary.simpleMessage("Sign out"),
    "settingsLogoutConfirm": MessageLookupByLibrary.simpleMessage(
      "Sign out of ShellX? Paired computers are kept for your next sign-in.",
    ),
    "settingsNoPairedMachines": MessageLookupByLibrary.simpleMessage(
      "No paired computers.",
    ),
    "settingsPairedMachines": MessageLookupByLibrary.simpleMessage(
      "Paired computers",
    ),
    "settingsSecurityGroup": MessageLookupByLibrary.simpleMessage("Security"),
    "settingsTerminalGroup": MessageLookupByLibrary.simpleMessage("Terminal"),
    "settingsTitle": MessageLookupByLibrary.simpleMessage("Settings"),
    "settingsTooltip": MessageLookupByLibrary.simpleMessage("Settings"),
    "settingsUnpair": MessageLookupByLibrary.simpleMessage("Unpair"),
    "settingsUnpairConfirm": m20,
    "settingsUnpairFailed": MessageLookupByLibrary.simpleMessage(
      "Couldn\'t unpair yet.",
    ),
    "settingsVersion": m21,
    "signedOutAccountDeleted": MessageLookupByLibrary.simpleMessage(
      "Your account has been deleted.",
    ),
    "signedOutExpired": MessageLookupByLibrary.simpleMessage(
      "Your sign-in has expired. Please sign in again.",
    ),
    "somethingWentWrong": MessageLookupByLibrary.simpleMessage(
      "Something went wrong",
    ),
    "somethingWentWrongPleaseTryAgain": MessageLookupByLibrary.simpleMessage(
      "Something went wrong, please try again",
    ),
    "tabClosedByHost": MessageLookupByLibrary.simpleMessage(
      "The session was closed on the computer.",
    ),
    "tabReattach": MessageLookupByLibrary.simpleMessage("Reattach"),
    "tabTakenOver": MessageLookupByLibrary.simpleMessage(
      "This session was opened on another device.",
    ),
    "terminalCloseConfirm": MessageLookupByLibrary.simpleMessage(
      "Close this session? Programs running in it will be stopped.",
    ),
    "terminalCloseTab": MessageLookupByLibrary.simpleMessage("Close session"),
    "terminalConnected": MessageLookupByLibrary.simpleMessage(
      "Connected · end-to-end encrypted",
    ),
    "terminalConnecting": MessageLookupByLibrary.simpleMessage("Connecting…"),
    "terminalNoTabs": MessageLookupByLibrary.simpleMessage("No open sessions."),
    "terminalOpenNew": MessageLookupByLibrary.simpleMessage(
      "Open a new session",
    ),
    "termsLink": MessageLookupByLibrary.simpleMessage("Terms"),
    "termsNotice": m22,
    "unauthorized": MessageLookupByLibrary.simpleMessage("Unauthorized"),
    "unknownError": MessageLookupByLibrary.simpleMessage("Unknown Error"),
    "unknownMachine": MessageLookupByLibrary.simpleMessage("Unknown computer"),
    "untrustedTitle": MessageLookupByLibrary.simpleMessage("Pair again"),
    "updateRequiredBody": MessageLookupByLibrary.simpleMessage(
      "This version can no longer connect to your computers. Update to keep using ShellX.",
    ),
    "updateRequiredTitle": MessageLookupByLibrary.simpleMessage(
      "App update required",
    ),
    "validationEmailInvalid": MessageLookupByLibrary.simpleMessage(
      "Please enter a valid email address",
    ),
    "validationEmailRequired": MessageLookupByLibrary.simpleMessage(
      "Email is required",
    ),
    "validationPasswordConfirmRequired": MessageLookupByLibrary.simpleMessage(
      "Please confirm your password",
    ),
    "validationPasswordDigit": MessageLookupByLibrary.simpleMessage(
      "Password must contain at least one number",
    ),
    "validationPasswordLowercase": MessageLookupByLibrary.simpleMessage(
      "Password must contain at least one lowercase letter",
    ),
    "validationPasswordMinLength": m23,
    "validationPasswordNotMatch": MessageLookupByLibrary.simpleMessage(
      "Passwords do not match",
    ),
    "validationPasswordRequired": MessageLookupByLibrary.simpleMessage(
      "Password is required",
    ),
    "validationPasswordSpecialChar": MessageLookupByLibrary.simpleMessage(
      "Password must contain at least one special character",
    ),
    "validationPasswordUppercase": MessageLookupByLibrary.simpleMessage(
      "Password must contain at least one uppercase letter",
    ),
    "validationPhoneInvalid": MessageLookupByLibrary.simpleMessage(
      "Please enter a valid phone number",
    ),
    "validationPhoneRequired": MessageLookupByLibrary.simpleMessage(
      "Phone number is required",
    ),
    "validationTextMaxLength": m24,
    "validationTextMinLength": m25,
    "validationTextRequired": MessageLookupByLibrary.simpleMessage(
      "This field is required",
    ),
  };
}
