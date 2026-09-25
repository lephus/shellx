// GENERATED CODE - DO NOT MODIFY BY HAND
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'intl/messages_all.dart';

// **************************************************************************
// Generator: Flutter Intl IDE plugin
// Made by Localizely
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, lines_longer_than_80_chars
// ignore_for_file: join_return_with_assignment, prefer_final_in_for_each
// ignore_for_file: avoid_redundant_argument_values, avoid_escaping_inner_quotes

class S {
  S();

  static S? _current;

  static S get current {
    assert(
      _current != null,
      'No instance of S was loaded. Try to initialize the S delegate before accessing S.current.',
    );
    return _current!;
  }

  static const AppLocalizationDelegate delegate = AppLocalizationDelegate();

  static Future<S> load(Locale locale) {
    final name = (locale.countryCode?.isEmpty ?? false)
        ? locale.languageCode
        : locale.toString();
    final localeName = Intl.canonicalizedLocale(name);
    return initializeMessages(localeName).then((_) {
      Intl.defaultLocale = localeName;
      final instance = S();
      S._current = instance;

      return instance;
    });
  }

  static S of(BuildContext context) {
    final instance = S.maybeOf(context);
    assert(
      instance != null,
      'No instance of S present in the widget tree. Did you add S.delegate in localizationsDelegates?',
    );
    return instance!;
  }

  static S? maybeOf(BuildContext context) {
    return Localizations.of<S>(context, S);
  }

  /// `Something went wrong`
  String get somethingWentWrong {
    return Intl.message(
      'Something went wrong',
      name: 'somethingWentWrong',
      desc: '',
      args: [],
    );
  }

  /// `Load more failed\nPlease try again`
  String get loadMoreFailPleaseTryAgain {
    return Intl.message(
      'Load more failed\nPlease try again',
      name: 'loadMoreFailPleaseTryAgain',
      desc: '',
      args: [],
    );
  }

  /// `Retry`
  String get retry {
    return Intl.message('Retry', name: 'retry', desc: '', args: []);
  }

  /// `Something went wrong, please try again`
  String get somethingWentWrongPleaseTryAgain {
    return Intl.message(
      'Something went wrong, please try again',
      name: 'somethingWentWrongPleaseTryAgain',
      desc: '',
      args: [],
    );
  }

  /// `You don't have permission to access this feature`
  String get forbiddenTitle {
    return Intl.message(
      'You don\'t have permission to access this feature',
      name: 'forbiddenTitle',
      desc: '',
      args: [],
    );
  }

  /// `Network Error`
  String get networkError {
    return Intl.message(
      'Network Error',
      name: 'networkError',
      desc: '',
      args: [],
    );
  }

  /// `Not Found`
  String get notFound {
    return Intl.message('Not Found', name: 'notFound', desc: '', args: []);
  }

  /// `Unauthorized`
  String get unauthorized {
    return Intl.message(
      'Unauthorized',
      name: 'unauthorized',
      desc: '',
      args: [],
    );
  }

  /// `Unknown Error`
  String get unknownError {
    return Intl.message(
      'Unknown Error',
      name: 'unknownError',
      desc: '',
      args: [],
    );
  }

  /// `Email is required`
  String get validationEmailRequired {
    return Intl.message(
      'Email is required',
      name: 'validationEmailRequired',
      desc: '',
      args: [],
    );
  }

  /// `Please enter a valid email address`
  String get validationEmailInvalid {
    return Intl.message(
      'Please enter a valid email address',
      name: 'validationEmailInvalid',
      desc: '',
      args: [],
    );
  }

  /// `Password is required`
  String get validationPasswordRequired {
    return Intl.message(
      'Password is required',
      name: 'validationPasswordRequired',
      desc: '',
      args: [],
    );
  }

  /// `Password must be at least {length} characters`
  String validationPasswordMinLength(int length) {
    return Intl.message(
      'Password must be at least $length characters',
      name: 'validationPasswordMinLength',
      desc: '',
      args: [length],
    );
  }

  /// `Password must contain at least one uppercase letter`
  String get validationPasswordUppercase {
    return Intl.message(
      'Password must contain at least one uppercase letter',
      name: 'validationPasswordUppercase',
      desc: '',
      args: [],
    );
  }

  /// `Password must contain at least one lowercase letter`
  String get validationPasswordLowercase {
    return Intl.message(
      'Password must contain at least one lowercase letter',
      name: 'validationPasswordLowercase',
      desc: '',
      args: [],
    );
  }

  /// `Password must contain at least one number`
  String get validationPasswordDigit {
    return Intl.message(
      'Password must contain at least one number',
      name: 'validationPasswordDigit',
      desc: '',
      args: [],
    );
  }

  /// `Password must contain at least one special character`
  String get validationPasswordSpecialChar {
    return Intl.message(
      'Password must contain at least one special character',
      name: 'validationPasswordSpecialChar',
      desc: '',
      args: [],
    );
  }

  /// `Please confirm your password`
  String get validationPasswordConfirmRequired {
    return Intl.message(
      'Please confirm your password',
      name: 'validationPasswordConfirmRequired',
      desc: '',
      args: [],
    );
  }

  /// `Passwords do not match`
  String get validationPasswordNotMatch {
    return Intl.message(
      'Passwords do not match',
      name: 'validationPasswordNotMatch',
      desc: '',
      args: [],
    );
  }

  /// `This field is required`
  String get validationTextRequired {
    return Intl.message(
      'This field is required',
      name: 'validationTextRequired',
      desc: '',
      args: [],
    );
  }

  /// `Must be at least {length} characters`
  String validationTextMinLength(int length) {
    return Intl.message(
      'Must be at least $length characters',
      name: 'validationTextMinLength',
      desc: '',
      args: [length],
    );
  }

  /// `Must be at most {length} characters`
  String validationTextMaxLength(int length) {
    return Intl.message(
      'Must be at most $length characters',
      name: 'validationTextMaxLength',
      desc: '',
      args: [length],
    );
  }

  /// `Phone number is required`
  String get validationPhoneRequired {
    return Intl.message(
      'Phone number is required',
      name: 'validationPhoneRequired',
      desc: '',
      args: [],
    );
  }

  /// `Please enter a valid phone number`
  String get validationPhoneInvalid {
    return Intl.message(
      'Please enter a valid phone number',
      name: 'validationPhoneInvalid',
      desc: '',
      args: [],
    );
  }

  /// `ShellX`
  String get appTitle {
    return Intl.message('ShellX', name: 'appTitle', desc: '', args: []);
  }

  /// `Cancel`
  String get actionCancel {
    return Intl.message('Cancel', name: 'actionCancel', desc: '', args: []);
  }

  /// `Close`
  String get actionClose {
    return Intl.message('Close', name: 'actionClose', desc: '', args: []);
  }

  /// `Later`
  String get actionLater {
    return Intl.message('Later', name: 'actionLater', desc: '', args: []);
  }

  /// `Sign in`
  String get loginTitle {
    return Intl.message('Sign in', name: 'loginTitle', desc: '', args: []);
  }

  /// `Use the same account as ShellX on your computer.`
  String get loginSubtitle {
    return Intl.message(
      'Use the same account as ShellX on your computer.',
      name: 'loginSubtitle',
      desc: '',
      args: [],
    );
  }

  /// `Email`
  String get emailLabel {
    return Intl.message('Email', name: 'emailLabel', desc: '', args: []);
  }

  /// `email@example.com`
  String get emailHint {
    return Intl.message(
      'email@example.com',
      name: 'emailHint',
      desc: '',
      args: [],
    );
  }

  /// `Password`
  String get passwordLabel {
    return Intl.message('Password', name: 'passwordLabel', desc: '', args: []);
  }

  /// `Password`
  String get passwordHint {
    return Intl.message('Password', name: 'passwordHint', desc: '', args: []);
  }

  /// `Sign in`
  String get loginButton {
    return Intl.message('Sign in', name: 'loginButton', desc: '', args: []);
  }

  /// `Forgot your password? Change it in ShellX on a computer that is signed in.`
  String get forgotPasswordHint {
    return Intl.message(
      'Forgot your password? Change it in ShellX on a computer that is signed in.',
      name: 'forgotPasswordHint',
      desc: '',
      args: [],
    );
  }

  /// `No account yet?`
  String get noAccountPrompt {
    return Intl.message(
      'No account yet?',
      name: 'noAccountPrompt',
      desc: '',
      args: [],
    );
  }

  /// `Create one`
  String get createAccountLink {
    return Intl.message(
      'Create one',
      name: 'createAccountLink',
      desc: '',
      args: [],
    );
  }

  /// `Your sign-in has expired. Please sign in again.`
  String get signedOutExpired {
    return Intl.message(
      'Your sign-in has expired. Please sign in again.',
      name: 'signedOutExpired',
      desc: '',
      args: [],
    );
  }

  /// `Your account has been deleted.`
  String get signedOutAccountDeleted {
    return Intl.message(
      'Your account has been deleted.',
      name: 'signedOutAccountDeleted',
      desc: '',
      args: [],
    );
  }

  /// `Create account`
  String get registerTitle {
    return Intl.message(
      'Create account',
      name: 'registerTitle',
      desc: '',
      args: [],
    );
  }

  /// `One account for your phone and all your computers.`
  String get registerSubtitle {
    return Intl.message(
      'One account for your phone and all your computers.',
      name: 'registerSubtitle',
      desc: '',
      args: [],
    );
  }

  /// `Create account`
  String get registerButton {
    return Intl.message(
      'Create account',
      name: 'registerButton',
      desc: '',
      args: [],
    );
  }

  /// `8 to 128 characters.`
  String get passwordRule {
    return Intl.message(
      '8 to 128 characters.',
      name: 'passwordRule',
      desc: '',
      args: [],
    );
  }

  /// `{count, plural, =1{1 more character needed.} other{{count} more characters needed.}}`
  String passwordMissing(int count) {
    return Intl.plural(
      count,
      one: '1 more character needed.',
      other: '$count more characters needed.',
      name: 'passwordMissing',
      desc: '',
      args: [count],
    );
  }

  /// `{count, plural, =1{1 character too many.} other{{count} characters too many.}}`
  String passwordTooLong(int count) {
    return Intl.plural(
      count,
      one: '1 character too many.',
      other: '$count characters too many.',
      name: 'passwordTooLong',
      desc: '',
      args: [count],
    );
  }

  /// `By creating an account you agree to the {terms} and the {privacy}.`
  String termsNotice(String terms, String privacy) {
    return Intl.message(
      'By creating an account you agree to the $terms and the $privacy.',
      name: 'termsNotice',
      desc: '',
      args: [terms, privacy],
    );
  }

  /// `Terms`
  String get termsLink {
    return Intl.message('Terms', name: 'termsLink', desc: '', args: []);
  }

  /// `Privacy Policy`
  String get privacyLink {
    return Intl.message(
      'Privacy Policy',
      name: 'privacyLink',
      desc: '',
      args: [],
    );
  }

  /// `Invalid email address.`
  String get errorInvalidEmail {
    return Intl.message(
      'Invalid email address.',
      name: 'errorInvalidEmail',
      desc: '',
      args: [],
    );
  }

  /// `Password must be 8–128 characters.`
  String get errorWeakPassword {
    return Intl.message(
      'Password must be 8–128 characters.',
      name: 'errorWeakPassword',
      desc: '',
      args: [],
    );
  }

  /// `Disposable email addresses can't be used. Please use a real email.`
  String get errorDisposableEmail {
    return Intl.message(
      'Disposable email addresses can\'t be used. Please use a real email.',
      name: 'errorDisposableEmail',
      desc: '',
      args: [],
    );
  }

  /// `This email is already registered.`
  String get errorEmailTaken {
    return Intl.message(
      'This email is already registered.',
      name: 'errorEmailTaken',
      desc: '',
      args: [],
    );
  }

  /// `Incorrect email or password.`
  String get errorInvalidCredentials {
    return Intl.message(
      'Incorrect email or password.',
      name: 'errorInvalidCredentials',
      desc: '',
      args: [],
    );
  }

  /// `Incorrect password.`
  String get errorWrongPassword {
    return Intl.message(
      'Incorrect password.',
      name: 'errorWrongPassword',
      desc: '',
      args: [],
    );
  }

  /// `Try again in a few minutes.`
  String get errorRateLimited {
    return Intl.message(
      'Try again in a few minutes.',
      name: 'errorRateLimited',
      desc: '',
      args: [],
    );
  }

  /// `Can't reach the server. Check your connection and try again.`
  String get errorNetwork {
    return Intl.message(
      'Can\'t reach the server. Check your connection and try again.',
      name: 'errorNetwork',
      desc: '',
      args: [],
    );
  }

  /// `Something went wrong ({code}).`
  String errorUnknown(String code) {
    return Intl.message(
      'Something went wrong ($code).',
      name: 'errorUnknown',
      desc: '',
      args: [code],
    );
  }

  /// `This computer doesn't belong to your account. Sign in with the same account on the computer.`
  String get errorNotInAccount {
    return Intl.message(
      'This computer doesn\'t belong to your account. Sign in with the same account on the computer.',
      name: 'errorNotInAccount',
      desc: '',
      args: [],
    );
  }

  /// `The QR code is invalid or has expired. Create a new code on your computer.`
  String get errorQrInvalid {
    return Intl.message(
      'The QR code is invalid or has expired. Create a new code on your computer.',
      name: 'errorQrInvalid',
      desc: '',
      args: [],
    );
  }

  /// `The computer is offline. Open ShellX on the computer and try again.`
  String get errorAgentOffline {
    return Intl.message(
      'The computer is offline. Open ShellX on the computer and try again.',
      name: 'errorAgentOffline',
      desc: '',
      args: [],
    );
  }

  /// `The computer didn't respond. Please try again.`
  String get errorTimeout {
    return Intl.message(
      'The computer didn\'t respond. Please try again.',
      name: 'errorTimeout',
      desc: '',
      args: [],
    );
  }

  /// `This computer no longer trusts this phone. Please pair again.`
  String get errorUntrusted {
    return Intl.message(
      'This computer no longer trusts this phone. Please pair again.',
      name: 'errorUntrusted',
      desc: '',
      args: [],
    );
  }

  /// `This computer already has the maximum of 10 sessions open. Close some sessions first.`
  String get errorSessionLimit {
    return Intl.message(
      'This computer already has the maximum of 10 sessions open. Close some sessions first.',
      name: 'errorSessionLimit',
      desc: '',
      args: [],
    );
  }

  /// `Couldn't start the shell: {reason}`
  String errorSpawnFailed(String reason) {
    return Intl.message(
      'Couldn\'t start the shell: $reason',
      name: 'errorSpawnFailed',
      desc: '',
      args: [reason],
    );
  }

  /// `App update required`
  String get updateRequiredTitle {
    return Intl.message(
      'App update required',
      name: 'updateRequiredTitle',
      desc: '',
      args: [],
    );
  }

  /// `This version can no longer connect to your computers. Update to keep using ShellX.`
  String get updateRequiredBody {
    return Intl.message(
      'This version can no longer connect to your computers. Update to keep using ShellX.',
      name: 'updateRequiredBody',
      desc: '',
      args: [],
    );
  }

  /// `Open the App Store`
  String get openAppStore {
    return Intl.message(
      'Open the App Store',
      name: 'openAppStore',
      desc: '',
      args: [],
    );
  }

  /// `Open Google Play`
  String get openPlayStore {
    return Intl.message(
      'Open Google Play',
      name: 'openPlayStore',
      desc: '',
      args: [],
    );
  }

  /// `ShellX is locked`
  String get lockTitle {
    return Intl.message(
      'ShellX is locked',
      name: 'lockTitle',
      desc: '',
      args: [],
    );
  }

  /// `Unlock to see your computers and terminal sessions.`
  String get lockSubtitle {
    return Intl.message(
      'Unlock to see your computers and terminal sessions.',
      name: 'lockSubtitle',
      desc: '',
      args: [],
    );
  }

  /// `Unlock ShellX`
  String get lockReason {
    return Intl.message(
      'Unlock ShellX',
      name: 'lockReason',
      desc: '',
      args: [],
    );
  }

  /// `Unlock with {method}`
  String lockUnlockWith(String method) {
    return Intl.message(
      'Unlock with $method',
      name: 'lockUnlockWith',
      desc: '',
      args: [method],
    );
  }

  /// `Face ID`
  String get biometricFaceId {
    return Intl.message('Face ID', name: 'biometricFaceId', desc: '', args: []);
  }

  /// `Touch ID`
  String get biometricTouchId {
    return Intl.message(
      'Touch ID',
      name: 'biometricTouchId',
      desc: '',
      args: [],
    );
  }

  /// `fingerprint`
  String get biometricFingerprint {
    return Intl.message(
      'fingerprint',
      name: 'biometricFingerprint',
      desc: '',
      args: [],
    );
  }

  /// `biometrics`
  String get biometricGeneric {
    return Intl.message(
      'biometrics',
      name: 'biometricGeneric',
      desc: '',
      args: [],
    );
  }

  /// `device passcode`
  String get biometricPasscode {
    return Intl.message(
      'device passcode',
      name: 'biometricPasscode',
      desc: '',
      args: [],
    );
  }

  /// `Connection lost, retrying…`
  String get bannerReconnecting {
    return Intl.message(
      'Connection lost, retrying…',
      name: 'bannerReconnecting',
      desc: '',
      args: [],
    );
  }

  /// `Another instance of the app has connected.`
  String get bannerReplaced {
    return Intl.message(
      'Another instance of the app has connected.',
      name: 'bannerReplaced',
      desc: '',
      args: [],
    );
  }

  /// `Reconnect`
  String get bannerReconnectButton {
    return Intl.message(
      'Reconnect',
      name: 'bannerReconnectButton',
      desc: '',
      args: [],
    );
  }

  /// `Your computers`
  String get machinesTitle {
    return Intl.message(
      'Your computers',
      name: 'machinesTitle',
      desc: '',
      args: [],
    );
  }

  /// `Settings`
  String get settingsTooltip {
    return Intl.message(
      'Settings',
      name: 'settingsTooltip',
      desc: '',
      args: [],
    );
  }

  /// `Online`
  String get machineOnline {
    return Intl.message('Online', name: 'machineOnline', desc: '', args: []);
  }

  /// `Offline`
  String get machinesOfflineHeader {
    return Intl.message(
      'Offline',
      name: 'machinesOfflineHeader',
      desc: '',
      args: [],
    );
  }

  /// `This computer is offline.`
  String get machineOffline {
    return Intl.message(
      'This computer is offline.',
      name: 'machineOffline',
      desc: '',
      args: [],
    );
  }

  /// `Waiting for connection`
  String get machineWaiting {
    return Intl.message(
      'Waiting for connection',
      name: 'machineWaiting',
      desc: '',
      args: [],
    );
  }

  /// `Last online: {when}`
  String machineLastOnline(String when) {
    return Intl.message(
      'Last online: $when',
      name: 'machineLastOnline',
      desc: '',
      args: [when],
    );
  }

  /// `Not paired`
  String get machineNotPaired {
    return Intl.message(
      'Not paired',
      name: 'machineNotPaired',
      desc: '',
      args: [],
    );
  }

  /// `{count, plural, =1{1 tab} other{{count} tabs}}`
  String machineTabs(int count) {
    return Intl.plural(
      count,
      one: '1 tab',
      other: '$count tabs',
      name: 'machineTabs',
      desc: '',
      args: [count],
    );
  }

  /// `Pair a new computer`
  String get pairNewMachine {
    return Intl.message(
      'Pair a new computer',
      name: 'pairNewMachine',
      desc: '',
      args: [],
    );
  }

  /// `No computers yet`
  String get emptyTitle {
    return Intl.message(
      'No computers yet',
      name: 'emptyTitle',
      desc: '',
      args: [],
    );
  }

  /// `Install ShellX on your computer (macOS or Windows) from {site}.`
  String emptyStep1(String site) {
    return Intl.message(
      'Install ShellX on your computer (macOS or Windows) from $site.',
      name: 'emptyStep1',
      desc: '',
      args: [site],
    );
  }

  /// `Sign in with this same account.`
  String get emptyStep2 {
    return Intl.message(
      'Sign in with this same account.',
      name: 'emptyStep2',
      desc: '',
      args: [],
    );
  }

  /// `Click the ShellX icon → {menu}, then scan the code.`
  String emptyStep3(String menu) {
    return Intl.message(
      'Click the ShellX icon → $menu, then scan the code.',
      name: 'emptyStep3',
      desc: '',
      args: [menu],
    );
  }

  /// `Pair phone…`
  String get pairPhoneMenuItem {
    return Intl.message(
      'Pair phone…',
      name: 'pairPhoneMenuItem',
      desc: '',
      args: [],
    );
  }

  /// `Scan QR code`
  String get scanQrButton {
    return Intl.message(
      'Scan QR code',
      name: 'scanQrButton',
      desc: '',
      args: [],
    );
  }

  /// `Pair again`
  String get untrustedTitle {
    return Intl.message(
      'Pair again',
      name: 'untrustedTitle',
      desc: '',
      args: [],
    );
  }

  /// `Scan code`
  String get actionScanCode {
    return Intl.message(
      'Scan code',
      name: 'actionScanCode',
      desc: '',
      args: [],
    );
  }

  /// `just now`
  String get lastSeenJustNow {
    return Intl.message(
      'just now',
      name: 'lastSeenJustNow',
      desc: '',
      args: [],
    );
  }

  /// `{count, plural, =1{1 minute ago} other{{count} minutes ago}}`
  String lastSeenMinutes(int count) {
    return Intl.plural(
      count,
      one: '1 minute ago',
      other: '$count minutes ago',
      name: 'lastSeenMinutes',
      desc: '',
      args: [count],
    );
  }

  /// `today, {time}`
  String lastSeenToday(String time) {
    return Intl.message(
      'today, $time',
      name: 'lastSeenToday',
      desc: '',
      args: [time],
    );
  }

  /// `yesterday, {time}`
  String lastSeenYesterday(String time) {
    return Intl.message(
      'yesterday, $time',
      name: 'lastSeenYesterday',
      desc: '',
      args: [time],
    );
  }

  /// `{month}/{day}, {time}`
  String lastSeenDate(int day, int month, String time) {
    return Intl.message(
      '$month/$day, $time',
      name: 'lastSeenDate',
      desc: '',
      args: [day, month, time],
    );
  }

  /// `unknown`
  String get lastSeenUnknown {
    return Intl.message('unknown', name: 'lastSeenUnknown', desc: '', args: []);
  }

  /// `Scan pairing code`
  String get scannerTitle {
    return Intl.message(
      'Scan pairing code',
      name: 'scannerTitle',
      desc: '',
      args: [],
    );
  }

  /// `The code is on your computer`
  String get scannerCardTitle {
    return Intl.message(
      'The code is on your computer',
      name: 'scannerCardTitle',
      desc: '',
      args: [],
    );
  }

  /// `macOS: click the ShellX icon in the menu bar. Windows: click the icon in the system tray. Choose {menu}`
  String scannerCardBody(String menu) {
    return Intl.message(
      'macOS: click the ShellX icon in the menu bar. Windows: click the icon in the system tray. Choose $menu',
      name: 'scannerCardBody',
      desc: '',
      args: [menu],
    );
  }

  /// `Pairing…`
  String get scannerPairing {
    return Intl.message('Pairing…', name: 'scannerPairing', desc: '', args: []);
  }

  /// `Camera access is needed to scan the QR code. Allow it in your phone's Settings.`
  String get scannerCameraDenied {
    return Intl.message(
      'Camera access is needed to scan the QR code. Allow it in your phone\'s Settings.',
      name: 'scannerCameraDenied',
      desc: '',
      args: [],
    );
  }

  /// `Open Settings`
  String get openSettings {
    return Intl.message(
      'Open Settings',
      name: 'openSettings',
      desc: '',
      args: [],
    );
  }

  /// `Couldn't start the camera.`
  String get scannerCameraError {
    return Intl.message(
      'Couldn\'t start the camera.',
      name: 'scannerCameraError',
      desc: '',
      args: [],
    );
  }

  /// `Paired`
  String get pairingSucceeded {
    return Intl.message('Paired', name: 'pairingSucceeded', desc: '', args: []);
  }

  /// `{name} now trusts this phone. From now on, just tap the computer to open a terminal.`
  String pairingSucceededBody(String name) {
    return Intl.message(
      '$name now trusts this phone. From now on, just tap the computer to open a terminal.',
      name: 'pairingSucceededBody',
      desc: '',
      args: [name],
    );
  }

  /// `Open terminal`
  String get openTerminal {
    return Intl.message(
      'Open terminal',
      name: 'openTerminal',
      desc: '',
      args: [],
    );
  }

  /// `Back to computers`
  String get backToMachines {
    return Intl.message(
      'Back to computers',
      name: 'backToMachines',
      desc: '',
      args: [],
    );
  }

  /// `Couldn't pair`
  String get pairingFailedTitle {
    return Intl.message(
      'Couldn\'t pair',
      name: 'pairingFailedTitle',
      desc: '',
      args: [],
    );
  }

  /// `Scan again`
  String get scanAgain {
    return Intl.message('Scan again', name: 'scanAgain', desc: '', args: []);
  }

  /// `Connected · end-to-end encrypted`
  String get terminalConnected {
    return Intl.message(
      'Connected · end-to-end encrypted',
      name: 'terminalConnected',
      desc: '',
      args: [],
    );
  }

  /// `Connecting…`
  String get terminalConnecting {
    return Intl.message(
      'Connecting…',
      name: 'terminalConnecting',
      desc: '',
      args: [],
    );
  }

  /// `Font size`
  String get fontSizeTooltip {
    return Intl.message(
      'Font size',
      name: 'fontSizeTooltip',
      desc: '',
      args: [],
    );
  }

  /// `Keyboard`
  String get keyboardTooltip {
    return Intl.message(
      'Keyboard',
      name: 'keyboardTooltip',
      desc: '',
      args: [],
    );
  }

  /// `Open a new session`
  String get terminalOpenNew {
    return Intl.message(
      'Open a new session',
      name: 'terminalOpenNew',
      desc: '',
      args: [],
    );
  }

  /// `Close session`
  String get terminalCloseTab {
    return Intl.message(
      'Close session',
      name: 'terminalCloseTab',
      desc: '',
      args: [],
    );
  }

  /// `Close this session? Programs running in it will be stopped.`
  String get terminalCloseConfirm {
    return Intl.message(
      'Close this session? Programs running in it will be stopped.',
      name: 'terminalCloseConfirm',
      desc: '',
      args: [],
    );
  }

  /// `No open sessions.`
  String get terminalNoTabs {
    return Intl.message(
      'No open sessions.',
      name: 'terminalNoTabs',
      desc: '',
      args: [],
    );
  }

  /// `Getting the session list…`
  String get sessionsLoading {
    return Intl.message(
      'Getting the session list…',
      name: 'sessionsLoading',
      desc: '',
      args: [],
    );
  }

  /// `{count, plural, =1{This computer has 1 session} other{This computer has {count} sessions}}`
  String pickerTitle(int count) {
    return Intl.plural(
      count,
      one: 'This computer has 1 session',
      other: 'This computer has $count sessions',
      name: 'pickerTitle',
      desc: '',
      args: [count],
    );
  }

  /// `Reopen a session to continue where you left off, or start a new one.`
  String get pickerSubtitle {
    return Intl.message(
      'Reopen a session to continue where you left off, or start a new one.',
      name: 'pickerSubtitle',
      desc: '',
      args: [],
    );
  }

  /// `Open`
  String get pickerOpen {
    return Intl.message('Open', name: 'pickerOpen', desc: '', args: []);
  }

  /// `opened {when}`
  String pickerStarted(String when) {
    return Intl.message(
      'opened $when',
      name: 'pickerStarted',
      desc: '',
      args: [when],
    );
  }

  /// `open on another device`
  String get pickerAttachedElsewhere {
    return Intl.message(
      'open on another device',
      name: 'pickerAttachedElsewhere',
      desc: '',
      args: [],
    );
  }

  /// `Session ended`
  String get sessionEnded {
    return Intl.message(
      'Session ended',
      name: 'sessionEnded',
      desc: '',
      args: [],
    );
  }

  /// `The last command exited with code {code}. The output above can still be read and copied.`
  String sessionExitedBody(int code) {
    return Intl.message(
      'The last command exited with code $code. The output above can still be read and copied.',
      name: 'sessionExitedBody',
      desc: '',
      args: [code],
    );
  }

  /// `The computer no longer has this session. The output above can still be read and copied.`
  String get sessionGoneBody {
    return Intl.message(
      'The computer no longer has this session. The output above can still be read and copied.',
      name: 'sessionGoneBody',
      desc: '',
      args: [],
    );
  }

  /// `This session was opened on another device.`
  String get tabTakenOver {
    return Intl.message(
      'This session was opened on another device.',
      name: 'tabTakenOver',
      desc: '',
      args: [],
    );
  }

  /// `The session was closed on the computer.`
  String get tabClosedByHost {
    return Intl.message(
      'The session was closed on the computer.',
      name: 'tabClosedByHost',
      desc: '',
      args: [],
    );
  }

  /// `Reattach`
  String get tabReattach {
    return Intl.message('Reattach', name: 'tabReattach', desc: '', args: []);
  }

  /// `Close tab`
  String get closeTab {
    return Intl.message('Close tab', name: 'closeTab', desc: '', args: []);
  }

  /// `Copy`
  String get copyAction {
    return Intl.message('Copy', name: 'copyAction', desc: '', args: []);
  }

  /// `Copied`
  String get copied {
    return Intl.message('Copied', name: 'copied', desc: '', args: []);
  }

  /// `Paste`
  String get keyPaste {
    return Intl.message('Paste', name: 'keyPaste', desc: '', args: []);
  }

  /// `Settings`
  String get settingsTitle {
    return Intl.message('Settings', name: 'settingsTitle', desc: '', args: []);
  }

  /// `Terminal`
  String get settingsTerminalGroup {
    return Intl.message(
      'Terminal',
      name: 'settingsTerminalGroup',
      desc: '',
      args: [],
    );
  }

  /// `Default font size`
  String get settingsFontSize {
    return Intl.message(
      'Default font size',
      name: 'settingsFontSize',
      desc: '',
      args: [],
    );
  }

  /// `Security`
  String get settingsSecurityGroup {
    return Intl.message(
      'Security',
      name: 'settingsSecurityGroup',
      desc: '',
      args: [],
    );
  }

  /// `Lock with {method}`
  String settingsLockWith(String method) {
    return Intl.message(
      'Lock with $method',
      name: 'settingsLockWith',
      desc: '',
      args: [method],
    );
  }

  /// `Asked when the app opens and when you come back after more than 5 minutes.`
  String get settingsLockFootnote {
    return Intl.message(
      'Asked when the app opens and when you come back after more than 5 minutes.',
      name: 'settingsLockFootnote',
      desc: '',
      args: [],
    );
  }

  /// `No passcode or biometrics are set up on this device`
  String get settingsBiometricUnavailable {
    return Intl.message(
      'No passcode or biometrics are set up on this device',
      name: 'settingsBiometricUnavailable',
      desc: '',
      args: [],
    );
  }

  /// `Paired computers`
  String get settingsPairedMachines {
    return Intl.message(
      'Paired computers',
      name: 'settingsPairedMachines',
      desc: '',
      args: [],
    );
  }

  /// `No paired computers.`
  String get settingsNoPairedMachines {
    return Intl.message(
      'No paired computers.',
      name: 'settingsNoPairedMachines',
      desc: '',
      args: [],
    );
  }

  /// `Unpair`
  String get settingsUnpair {
    return Intl.message('Unpair', name: 'settingsUnpair', desc: '', args: []);
  }

  /// `Unpair {name}? You'll need to scan a QR code again to use this computer.`
  String settingsUnpairConfirm(String name) {
    return Intl.message(
      'Unpair $name? You\'ll need to scan a QR code again to use this computer.',
      name: 'settingsUnpairConfirm',
      desc: '',
      args: [name],
    );
  }

  /// `Account`
  String get settingsAccountGroup {
    return Intl.message(
      'Account',
      name: 'settingsAccountGroup',
      desc: '',
      args: [],
    );
  }

  /// `Email`
  String get settingsEmail {
    return Intl.message('Email', name: 'settingsEmail', desc: '', args: []);
  }

  /// `Sign out`
  String get settingsLogout {
    return Intl.message('Sign out', name: 'settingsLogout', desc: '', args: []);
  }

  /// `Sign out of ShellX? Paired computers are kept for your next sign-in.`
  String get settingsLogoutConfirm {
    return Intl.message(
      'Sign out of ShellX? Paired computers are kept for your next sign-in.',
      name: 'settingsLogoutConfirm',
      desc: '',
      args: [],
    );
  }

  /// `Delete account`
  String get settingsDeleteAccount {
    return Intl.message(
      'Delete account',
      name: 'settingsDeleteAccount',
      desc: '',
      args: [],
    );
  }

  /// `ShellX {version} ({build})`
  String settingsVersion(String version, String build) {
    return Intl.message(
      'ShellX $version ($build)',
      name: 'settingsVersion',
      desc: '',
      args: [version, build],
    );
  }

  /// `Unknown computer`
  String get unknownMachine {
    return Intl.message(
      'Unknown computer',
      name: 'unknownMachine',
      desc: '',
      args: [],
    );
  }

  /// `Delete account`
  String get deleteAccountTitle {
    return Intl.message(
      'Delete account',
      name: 'deleteAccountTitle',
      desc: '',
      args: [],
    );
  }

  /// `This can't be undone`
  String get deleteAccountWarningTitle {
    return Intl.message(
      'This can\'t be undone',
      name: 'deleteAccountWarningTitle',
      desc: '',
      args: [],
    );
  }

  /// `Deletes the account {email} with all its devices and pairings.`
  String deleteAccountLoseAccount(String email) {
    return Intl.message(
      'Deletes the account $email with all its devices and pairings.',
      name: 'deleteAccountLoseAccount',
      desc: '',
      args: [email],
    );
  }

  /// `Every computer signed in to it is signed out.`
  String get deleteAccountLoseComputers {
    return Intl.message(
      'Every computer signed in to it is signed out.',
      name: 'deleteAccountLoseComputers',
      desc: '',
      args: [],
    );
  }

  /// `Open terminal sessions are closed.`
  String get deleteAccountLoseSessions {
    return Intl.message(
      'Open terminal sessions are closed.',
      name: 'deleteAccountLoseSessions',
      desc: '',
      args: [],
    );
  }

  /// `Enter your password to confirm`
  String get deleteAccountPasswordLabel {
    return Intl.message(
      'Enter your password to confirm',
      name: 'deleteAccountPasswordLabel',
      desc: '',
      args: [],
    );
  }

  /// `Delete permanently`
  String get deleteAccountButton {
    return Intl.message(
      'Delete permanently',
      name: 'deleteAccountButton',
      desc: '',
      args: [],
    );
  }
}

class AppLocalizationDelegate extends LocalizationsDelegate<S> {
  const AppLocalizationDelegate();

  List<Locale> get supportedLocales {
    return const <Locale>[
      Locale.fromSubtags(languageCode: 'en'),
      Locale.fromSubtags(languageCode: 'vi'),
    ];
  }

  @override
  bool isSupported(Locale locale) => _isSupported(locale);
  @override
  Future<S> load(Locale locale) => S.load(locale);
  @override
  bool shouldReload(AppLocalizationDelegate old) => false;

  bool _isSupported(Locale locale) {
    for (var supportedLocale in supportedLocales) {
      if (supportedLocale.languageCode == locale.languageCode) {
        return true;
      }
    }
    return false;
  }
}
