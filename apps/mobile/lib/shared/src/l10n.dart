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
    final name = (locale.countryCode?.isEmpty ?? false) ? locale.languageCode : locale.toString();
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

  /// `Email is required.`
  String get validationEmailRequired {
    return Intl.message(
      'Email is required.',
      name: 'validationEmailRequired',
      desc: '',
      args: [],
    );
  }

  /// `Please enter a valid email address.`
  String get validationEmailInvalid {
    return Intl.message(
      'Please enter a valid email address.',
      name: 'validationEmailInvalid',
      desc: '',
      args: [],
    );
  }

  /// `Password is required.`
  String get validationPasswordRequired {
    return Intl.message(
      'Password is required.',
      name: 'validationPasswordRequired',
      desc: '',
      args: [],
    );
  }

  /// `Password must be at least {length} characters.`
  String validationPasswordMinLength(int length) {
    return Intl.message(
      'Password must be at least $length characters.',
      name: 'validationPasswordMinLength',
      desc: '',
      args: [length],
    );
  }

  /// `Password must contain at least one uppercase letter.`
  String get validationPasswordUppercase {
    return Intl.message(
      'Password must contain at least one uppercase letter.',
      name: 'validationPasswordUppercase',
      desc: '',
      args: [],
    );
  }

  /// `Password must contain at least one lowercase letter.`
  String get validationPasswordLowercase {
    return Intl.message(
      'Password must contain at least one lowercase letter.',
      name: 'validationPasswordLowercase',
      desc: '',
      args: [],
    );
  }

  /// `Password must contain at least one number.`
  String get validationPasswordDigit {
    return Intl.message(
      'Password must contain at least one number.',
      name: 'validationPasswordDigit',
      desc: '',
      args: [],
    );
  }

  /// `Password must contain at least one special character.`
  String get validationPasswordSpecialChar {
    return Intl.message(
      'Password must contain at least one special character.',
      name: 'validationPasswordSpecialChar',
      desc: '',
      args: [],
    );
  }

  /// `Please confirm your password.`
  String get validationPasswordConfirmRequired {
    return Intl.message(
      'Please confirm your password.',
      name: 'validationPasswordConfirmRequired',
      desc: '',
      args: [],
    );
  }

  /// `Passwords do not match.`
  String get validationPasswordNotMatch {
    return Intl.message(
      'Passwords do not match.',
      name: 'validationPasswordNotMatch',
      desc: '',
      args: [],
    );
  }

  /// `This field is required.`
  String get validationTextRequired {
    return Intl.message(
      'This field is required.',
      name: 'validationTextRequired',
      desc: '',
      args: [],
    );
  }

  /// `Must be at least {length} characters.`
  String validationTextMinLength(int length) {
    return Intl.message(
      'Must be at least $length characters.',
      name: 'validationTextMinLength',
      desc: '',
      args: [length],
    );
  }

  /// `Must be at most {length} characters.`
  String validationTextMaxLength(int length) {
    return Intl.message(
      'Must be at most $length characters.',
      name: 'validationTextMaxLength',
      desc: '',
      args: [length],
    );
  }

  /// `Phone number is required.`
  String get validationPhoneRequired {
    return Intl.message(
      'Phone number is required.',
      name: 'validationPhoneRequired',
      desc: '',
      args: [],
    );
  }

  /// `Please enter a valid phone number.`
  String get validationPhoneInvalid {
    return Intl.message(
      'Please enter a valid phone number.',
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

  /// `Show password`
  String get passwordShow {
    return Intl.message(
      'Show password',
      name: 'passwordShow',
      desc: '',
      args: [],
    );
  }

  /// `Hide password`
  String get passwordHide {
    return Intl.message(
      'Hide password',
      name: 'passwordHide',
      desc: '',
      args: [],
    );
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

  /// `Click the ShellX icon, choose {menu}, then scan the code.`
  String emptyStep3(String menu) {
    return Intl.message(
      'Click the ShellX icon, choose $menu, then scan the code.',
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

  /// `shell`
  String get terminalFailedTabTitle {
    return Intl.message(
      'shell',
      name: 'terminalFailedTabTitle',
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

  /// `{name} · running`
  String pickerAgentRunning(String name) {
    return Intl.message(
      '$name · running',
      name: 'pickerAgentRunning',
      desc: '',
      args: [name],
    );
  }

  /// `{name} · needs your answer`
  String pickerAgentNeedsInput(String name) {
    return Intl.message(
      '$name · needs your answer',
      name: 'pickerAgentNeedsInput',
      desc: '',
      args: [name],
    );
  }

  /// `{name} · waiting`
  String pickerAgentIdle(String name) {
    return Intl.message(
      '$name · waiting',
      name: 'pickerAgentIdle',
      desc: '',
      args: [name],
    );
  }

  /// `{name} · done`
  String pickerAgentDone(String name) {
    return Intl.message(
      '$name · done',
      name: 'pickerAgentDone',
      desc: '',
      args: [name],
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

  /// `Terminals on the computer`
  String get pickerDesktopGroup {
    return Intl.message(
      'Terminals on the computer',
      name: 'pickerDesktopGroup',
      desc: '',
      args: [],
    );
  }

  /// `ShellX sessions`
  String get pickerShellxGroup {
    return Intl.message(
      'ShellX sessions',
      name: 'pickerShellxGroup',
      desc: '',
      args: [],
    );
  }

  /// `New session`
  String get pickerNewSession {
    return Intl.message(
      'New session',
      name: 'pickerNewSession',
      desc: '',
      args: [],
    );
  }

  /// `Turn on 'Share terminals with phone' in the ShellX menu on the computer to see its open terminals here.`
  String get pickerHintSharingOff {
    return Intl.message(
      'Turn on \'Share terminals with phone\' in the ShellX menu on the computer to see its open terminals here.',
      name: 'pickerHintSharingOff',
      desc: '',
      args: [],
    );
  }

  /// `Update ShellX on the computer to see its open terminals.`
  String get pickerHintUpdateDesktop {
    return Intl.message(
      'Update ShellX on the computer to see its open terminals.',
      name: 'pickerHintUpdateDesktop',
      desc: '',
      args: [],
    );
  }

  /// `Only terminal windows opened after sharing was turned on show up here. Open a new terminal window on the computer.`
  String get pickerHintOpenNewWindow {
    return Intl.message(
      'Only terminal windows opened after sharing was turned on show up here. Open a new terminal window on the computer.',
      name: 'pickerHintOpenNewWindow',
      desc: '',
      args: [],
    );
  }

  /// `Terminal on the computer`
  String get desktopTerminalLabel {
    return Intl.message(
      'Terminal on the computer',
      name: 'desktopTerminalLabel',
      desc: '',
      args: [],
    );
  }

  /// `The terminal is still running on the computer.`
  String get desktopStillRunning {
    return Intl.message(
      'The terminal is still running on the computer.',
      name: 'desktopStillRunning',
      desc: '',
      args: [],
    );
  }

  /// `The computer is using this terminal`
  String get desktopDriverBanner {
    return Intl.message(
      'The computer is using this terminal',
      name: 'desktopDriverBanner',
      desc: '',
      args: [],
    );
  }

  /// `The terminal window on the computer was closed.`
  String get desktopWindowClosed {
    return Intl.message(
      'The terminal window on the computer was closed.',
      name: 'desktopWindowClosed',
      desc: '',
      args: [],
    );
  }

  /// `Lost the connection to this terminal on the computer.`
  String get desktopTerminalGone {
    return Intl.message(
      'Lost the connection to this terminal on the computer.',
      name: 'desktopTerminalGone',
      desc: '',
      args: [],
    );
  }

  /// `The computer disconnected this phone from this terminal.`
  String get desktopClosedByHost {
    return Intl.message(
      'The computer disconnected this phone from this terminal.',
      name: 'desktopClosedByHost',
      desc: '',
      args: [],
    );
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

  /// `Up arrow`
  String get keyArrowUp {
    return Intl.message('Up arrow', name: 'keyArrowUp', desc: '', args: []);
  }

  /// `Down arrow`
  String get keyArrowDown {
    return Intl.message('Down arrow', name: 'keyArrowDown', desc: '', args: []);
  }

  /// `Left arrow`
  String get keyArrowLeft {
    return Intl.message('Left arrow', name: 'keyArrowLeft', desc: '', args: []);
  }

  /// `Right arrow`
  String get keyArrowRight {
    return Intl.message(
      'Right arrow',
      name: 'keyArrowRight',
      desc: '',
      args: [],
    );
  }

  /// `Vertical bar`
  String get keyPipe {
    return Intl.message('Vertical bar', name: 'keyPipe', desc: '', args: []);
  }

  /// `Tilde`
  String get keyTilde {
    return Intl.message('Tilde', name: 'keyTilde', desc: '', args: []);
  }

  /// `Slash`
  String get keySlash {
    return Intl.message('Slash', name: 'keySlash', desc: '', args: []);
  }

  /// `Hyphen`
  String get keyMinus {
    return Intl.message('Hyphen', name: 'keyMinus', desc: '', args: []);
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

  /// `Notifications`
  String get settingsNotificationsGroup {
    return Intl.message(
      'Notifications',
      name: 'settingsNotificationsGroup',
      desc: '',
      args: [],
    );
  }

  /// `Push notifications`
  String get settingsNotifications {
    return Intl.message(
      'Push notifications',
      name: 'settingsNotifications',
      desc: '',
      args: [],
    );
  }

  /// `On`
  String get settingsNotificationsOn {
    return Intl.message(
      'On',
      name: 'settingsNotificationsOn',
      desc: '',
      args: [],
    );
  }

  /// `Off`
  String get settingsNotificationsOff {
    return Intl.message(
      'Off',
      name: 'settingsNotificationsOff',
      desc: '',
      args: [],
    );
  }

  /// `Turn on notifications`
  String get settingsNotificationsTurnOn {
    return Intl.message(
      'Turn on notifications',
      name: 'settingsNotificationsTurnOn',
      desc: '',
      args: [],
    );
  }

  /// `Open system settings`
  String get settingsNotificationsOpenSystem {
    return Intl.message(
      'Open system settings',
      name: 'settingsNotificationsOpenSystem',
      desc: '',
      args: [],
    );
  }

  /// `Tells you when a long-running command finishes on a computer, or when a program sends a notification. Choose the time threshold in the ShellX menu on the computer.`
  String get settingsNotificationsFootnote {
    return Intl.message(
      'Tells you when a long-running command finishes on a computer, or when a program sends a notification. Choose the time threshold in the ShellX menu on the computer.',
      name: 'settingsNotificationsFootnote',
      desc: '',
      args: [],
    );
  }

  /// `Notifications are off — open the system settings to turn them on.`
  String get settingsNotificationsOffFootnote {
    return Intl.message(
      'Notifications are off — open the system settings to turn them on.',
      name: 'settingsNotificationsOffFootnote',
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

  /// `Couldn't unpair yet.`
  String get settingsUnpairFailed {
    return Intl.message(
      'Couldn\'t unpair yet.',
      name: 'settingsUnpairFailed',
      desc: '',
      args: [],
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

  /// `Speak a command`
  String get voiceMicTooltip {
    return Intl.message(
      'Speak a command',
      name: 'voiceMicTooltip',
      desc: '',
      args: [],
    );
  }

  /// `Stop listening`
  String get voiceStopTooltip {
    return Intl.message(
      'Stop listening',
      name: 'voiceStopTooltip',
      desc: '',
      args: [],
    );
  }

  /// `Speak or type… say “gửi” to send`
  String get voiceHintVi {
    return Intl.message(
      'Speak or type… say “gửi” to send',
      name: 'voiceHintVi',
      desc: '',
      args: [],
    );
  }

  /// `Speak or type… say “send” to send`
  String get voiceHintEn {
    return Intl.message(
      'Speak or type… say “send” to send',
      name: 'voiceHintEn',
      desc: '',
      args: [],
    );
  }

  /// `Send`
  String get voiceSend {
    return Intl.message('Send', name: 'voiceSend', desc: '', args: []);
  }

  /// `Close`
  String get voiceClose {
    return Intl.message('Close', name: 'voiceClose', desc: '', args: []);
  }

  /// `To: {target}`
  String voiceTarget(String target) {
    return Intl.message(
      'To: $target',
      name: 'voiceTarget',
      desc: '',
      args: [target],
    );
  }

  /// `Vietnamese`
  String get voiceLanguageVi {
    return Intl.message(
      'Vietnamese',
      name: 'voiceLanguageVi',
      desc: '',
      args: [],
    );
  }

  /// `English`
  String get voiceLanguageEn {
    return Intl.message('English', name: 'voiceLanguageEn', desc: '', args: []);
  }

  /// `ShellX needs microphone and speech recognition access to take spoken commands`
  String get voiceNoPermission {
    return Intl.message(
      'ShellX needs microphone and speech recognition access to take spoken commands',
      name: 'voiceNoPermission',
      desc: '',
      args: [],
    );
  }

  /// `Speech recognition isn't available on this phone`
  String get voiceUnsupported {
    return Intl.message(
      'Speech recognition isn\'t available on this phone',
      name: 'voiceUnsupported',
      desc: '',
      args: [],
    );
  }

  /// `This phone can't recognize Vietnamese yet — try EN`
  String get voiceLocaleUnavailableVi {
    return Intl.message(
      'This phone can\'t recognize Vietnamese yet — try EN',
      name: 'voiceLocaleUnavailableVi',
      desc: '',
      args: [],
    );
  }

  /// `This phone can't recognize English yet — try VI`
  String get voiceLocaleUnavailableEn {
    return Intl.message(
      'This phone can\'t recognize English yet — try VI',
      name: 'voiceLocaleUnavailableEn',
      desc: '',
      args: [],
    );
  }

  /// `Speech recognition needs a network connection`
  String get voiceNetwork {
    return Intl.message(
      'Speech recognition needs a network connection',
      name: 'voiceNetwork',
      desc: '',
      args: [],
    );
  }

  /// `Couldn't recognize that, try again`
  String get voiceFailed {
    return Intl.message(
      'Couldn\'t recognize that, try again',
      name: 'voiceFailed',
      desc: '',
      args: [],
    );
  }

  /// `The session isn't connected — you can send once it reconnects`
  String get voiceNotLive {
    return Intl.message(
      'The session isn\'t connected — you can send once it reconnects',
      name: 'voiceNotLive',
      desc: '',
      args: [],
    );
  }

  /// `Listening… say “gửi” to send`
  String get voiceListeningVi {
    return Intl.message(
      'Listening… say “gửi” to send',
      name: 'voiceListeningVi',
      desc: '',
      args: [],
    );
  }

  /// `Listening… say “send” to send`
  String get voiceListeningEn {
    return Intl.message(
      'Listening… say “send” to send',
      name: 'voiceListeningEn',
      desc: '',
      args: [],
    );
  }

  /// `Listening`
  String get voiceListeningAnnounce {
    return Intl.message(
      'Listening',
      name: 'voiceListeningAnnounce',
      desc: '',
      args: [],
    );
  }

  /// `Session ended — open a new session to send`
  String get voiceEnded {
    return Intl.message(
      'Session ended — open a new session to send',
      name: 'voiceEnded',
      desc: '',
      args: [],
    );
  }

  /// `This session was disconnected from the phone — reattach to send`
  String get voiceDetached {
    return Intl.message(
      'This session was disconnected from the phone — reattach to send',
      name: 'voiceDetached',
      desc: '',
      args: [],
    );
  }

  /// `Send Enter`
  String get voiceSendEnter {
    return Intl.message(
      'Send Enter',
      name: 'voiceSendEnter',
      desc: '',
      args: [],
    );
  }

  /// `Tap to take over`
  String get desktopDriverTakeOver {
    return Intl.message(
      'Tap to take over',
      name: 'desktopDriverTakeOver',
      desc: '',
      args: [],
    );
  }

  /// `App`
  String get settingsAppGroup {
    return Intl.message('App', name: 'settingsAppGroup', desc: '', args: []);
  }

  /// `Appearance`
  String get settingsTheme {
    return Intl.message(
      'Appearance',
      name: 'settingsTheme',
      desc: '',
      args: [],
    );
  }

  /// `System`
  String get settingsThemeSystem {
    return Intl.message(
      'System',
      name: 'settingsThemeSystem',
      desc: '',
      args: [],
    );
  }

  /// `Light`
  String get settingsThemeLight {
    return Intl.message(
      'Light',
      name: 'settingsThemeLight',
      desc: '',
      args: [],
    );
  }

  /// `Dark`
  String get settingsThemeDark {
    return Intl.message('Dark', name: 'settingsThemeDark', desc: '', args: []);
  }

  /// `Terms of use`
  String get settingsTerms {
    return Intl.message(
      'Terms of use',
      name: 'settingsTerms',
      desc: '',
      args: [],
    );
  }

  /// `Privacy policy`
  String get settingsPrivacy {
    return Intl.message(
      'Privacy policy',
      name: 'settingsPrivacy',
      desc: '',
      args: [],
    );
  }

  /// `Open-source licences`
  String get settingsLicenses {
    return Intl.message(
      'Open-source licences',
      name: 'settingsLicenses',
      desc: '',
      args: [],
    );
  }

  /// `View as text`
  String get viewAsTextTooltip {
    return Intl.message(
      'View as text',
      name: 'viewAsTextTooltip',
      desc: '',
      args: [],
    );
  }

  /// `Terminal text`
  String get viewAsTextTitle {
    return Intl.message(
      'Terminal text',
      name: 'viewAsTextTitle',
      desc: '',
      args: [],
    );
  }

  /// `Copy all`
  String get viewAsTextCopyAll {
    return Intl.message(
      'Copy all',
      name: 'viewAsTextCopyAll',
      desc: '',
      args: [],
    );
  }

  /// `Refresh`
  String get viewAsTextRefresh {
    return Intl.message(
      'Refresh',
      name: 'viewAsTextRefresh',
      desc: '',
      args: [],
    );
  }

  /// `Nothing to show yet`
  String get viewAsTextEmpty {
    return Intl.message(
      'Nothing to show yet',
      name: 'viewAsTextEmpty',
      desc: '',
      args: [],
    );
  }

  /// `Showing the last {lines} lines`
  String viewAsTextTruncated(int lines) {
    return Intl.message(
      'Showing the last $lines lines',
      name: 'viewAsTextTruncated',
      desc: '',
      args: [lines],
    );
  }

  /// `Open link?`
  String get linkSheetTitle {
    return Intl.message(
      'Open link?',
      name: 'linkSheetTitle',
      desc: '',
      args: [],
    );
  }

  /// `Open`
  String get linkSheetOpen {
    return Intl.message('Open', name: 'linkSheetOpen', desc: '', args: []);
  }

  /// `Copy link`
  String get linkSheetCopy {
    return Intl.message('Copy link', name: 'linkSheetCopy', desc: '', args: []);
  }

  /// `Arrow pad. Drag to move the cursor.`
  String get arrowPadLabel {
    return Intl.message(
      'Arrow pad. Drag to move the cursor.',
      name: 'arrowPadLabel',
      desc: '',
      args: [],
    );
  }

  /// `Up`
  String get arrowPadUp {
    return Intl.message('Up', name: 'arrowPadUp', desc: '', args: []);
  }

  /// `Down`
  String get arrowPadDown {
    return Intl.message('Down', name: 'arrowPadDown', desc: '', args: []);
  }

  /// `Left`
  String get arrowPadLeft {
    return Intl.message('Left', name: 'arrowPadLeft', desc: '', args: []);
  }

  /// `Right`
  String get arrowPadRight {
    return Intl.message('Right', name: 'arrowPadRight', desc: '', args: []);
  }

  /// `Last used`
  String get machineLastUsed {
    return Intl.message(
      'Last used',
      name: 'machineLastUsed',
      desc: '',
      args: [],
    );
  }

  /// `{tabs, plural, =1{1 tab} other{{tabs} tabs}} · {unseen} with new output`
  String machineTabsActivity(int tabs, int unseen) {
    return Intl.message(
      '${Intl.plural(tabs, one: '1 tab', other: '$tabs tabs')} · $unseen with new output',
      name: 'machineTabsActivity',
      desc: '',
      args: [tabs, unseen],
    );
  }

  /// `New output`
  String get machineNewOutput {
    return Intl.message(
      'New output',
      name: 'machineNewOutput',
      desc: '',
      args: [],
    );
  }

  /// `Couldn’t load your computers`
  String get machinesErrorTitle {
    return Intl.message(
      'Couldn’t load your computers',
      name: 'machinesErrorTitle',
      desc: '',
      args: [],
    );
  }

  /// `Try again`
  String get machinesRetry {
    return Intl.message('Try again', name: 'machinesRetry', desc: '', args: []);
  }

  /// `Check your internet connection.`
  String get machinesCheckConnection {
    return Intl.message(
      'Check your internet connection.',
      name: 'machinesCheckConnection',
      desc: '',
      args: [],
    );
  }

  /// `Reload`
  String get machinesReload {
    return Intl.message('Reload', name: 'machinesReload', desc: '', args: []);
  }

  /// `Keep terminal size when the keyboard opens`
  String get settingsFixedHeight {
    return Intl.message(
      'Keep terminal size when the keyboard opens',
      name: 'settingsFixedHeight',
      desc: '',
      args: [],
    );
  }

  /// `The keyboard covers the terminal instead of shrinking it.`
  String get settingsFixedHeightHint {
    return Intl.message(
      'The keyboard covers the terminal instead of shrinking it.',
      name: 'settingsFixedHeightHint',
      desc: '',
      args: [],
    );
  }

  /// `Draft saved`
  String get voiceDraftSaved {
    return Intl.message(
      'Draft saved',
      name: 'voiceDraftSaved',
      desc: '',
      args: [],
    );
  }

  /// `Option {number}`
  String replyKeyOption(int number) {
    return Intl.message(
      'Option $number',
      name: 'replyKeyOption',
      desc: '',
      args: [number],
    );
  }

  /// `Yes`
  String get replyKeyYes {
    return Intl.message('Yes', name: 'replyKeyYes', desc: '', args: []);
  }

  /// `No`
  String get replyKeyNo {
    return Intl.message('No', name: 'replyKeyNo', desc: '', args: []);
  }

  /// `Enter`
  String get replyKeyEnter {
    return Intl.message('Enter', name: 'replyKeyEnter', desc: '', args: []);
  }

  /// `Escape`
  String get replyKeyEscape {
    return Intl.message('Escape', name: 'replyKeyEscape', desc: '', args: []);
  }

  /// `Show the extra keys`
  String get replyShowExtraKeys {
    return Intl.message(
      'Show the extra keys',
      name: 'replyShowExtraKeys',
      desc: '',
      args: [],
    );
  }

  /// `Quick replies to the agent`
  String get replyBarLabel {
    return Intl.message(
      'Quick replies to the agent',
      name: 'replyBarLabel',
      desc: '',
      args: [],
    );
  }

  /// `An agent needs your answer`
  String get agentDotNeedsInput {
    return Intl.message(
      'An agent needs your answer',
      name: 'agentDotNeedsInput',
      desc: '',
      args: [],
    );
  }

  /// `An agent is running`
  String get agentDotRunning {
    return Intl.message(
      'An agent is running',
      name: 'agentDotRunning',
      desc: '',
      args: [],
    );
  }

  /// `AI sessions`
  String get aiGroup {
    return Intl.message('AI sessions', name: 'aiGroup', desc: '', args: []);
  }

  /// `New AI session`
  String get aiNewSession {
    return Intl.message(
      'New AI session',
      name: 'aiNewSession',
      desc: '',
      args: [],
    );
  }

  /// `New AI session`
  String get aiUntitled {
    return Intl.message(
      'New AI session',
      name: 'aiUntitled',
      desc: '',
      args: [],
    );
  }

  /// `AI sessions`
  String get aiChromeTooltip {
    return Intl.message(
      'AI sessions',
      name: 'aiChromeTooltip',
      desc: '',
      args: [],
    );
  }

  /// `Running`
  String get aiStateRunning {
    return Intl.message('Running', name: 'aiStateRunning', desc: '', args: []);
  }

  /// `Needs your answer`
  String get aiStateNeedsInput {
    return Intl.message(
      'Needs your answer',
      name: 'aiStateNeedsInput',
      desc: '',
      args: [],
    );
  }

  /// `Waiting`
  String get aiStateIdle {
    return Intl.message('Waiting', name: 'aiStateIdle', desc: '', args: []);
  }

  /// `Starting`
  String get aiStateStarting {
    return Intl.message(
      'Starting',
      name: 'aiStateStarting',
      desc: '',
      args: [],
    );
  }

  /// `Not started`
  String get aiStateStopped {
    return Intl.message(
      'Not started',
      name: 'aiStateStopped',
      desc: '',
      args: [],
    );
  }

  /// `Sign in on the computer`
  String get aiStateNeedsAuth {
    return Intl.message(
      'Sign in on the computer',
      name: 'aiStateNeedsAuth',
      desc: '',
      args: [],
    );
  }

  /// `Error`
  String get aiStateFailed {
    return Intl.message('Error', name: 'aiStateFailed', desc: '', args: []);
  }

  /// `Choose a folder on the computer`
  String get aiStateNoFolder {
    return Intl.message(
      'Choose a folder on the computer',
      name: 'aiStateNoFolder',
      desc: '',
      args: [],
    );
  }

  /// `Agent off on the computer`
  String get aiStateAgentOff {
    return Intl.message(
      'Agent off on the computer',
      name: 'aiStateAgentOff',
      desc: '',
      args: [],
    );
  }

  /// `Closed`
  String get aiStateClosed {
    return Intl.message('Closed', name: 'aiStateClosed', desc: '', args: []);
  }

  /// `{agent} · {state}`
  String aiRowSubtitle(String agent, String state) {
    return Intl.message(
      '$agent · $state',
      name: 'aiRowSubtitle',
      desc: '',
      args: [agent, state],
    );
  }

  /// `Open ShellX on the computer to use AI sessions.`
  String get aiUnavailable {
    return Intl.message(
      'Open ShellX on the computer to use AI sessions.',
      name: 'aiUnavailable',
      desc: '',
      args: [],
    );
  }

  /// `Update ShellX on the computer to use AI sessions from your phone.`
  String get aiUpdateDesktop {
    return Intl.message(
      'Update ShellX on the computer to use AI sessions from your phone.',
      name: 'aiUpdateDesktop',
      desc: '',
      args: [],
    );
  }

  /// `Agent`
  String get aiNewAgent {
    return Intl.message('Agent', name: 'aiNewAgent', desc: '', args: []);
  }

  /// `Folder`
  String get aiNewFolder {
    return Intl.message('Folder', name: 'aiNewFolder', desc: '', args: []);
  }

  /// `Start`
  String get aiNewStart {
    return Intl.message('Start', name: 'aiNewStart', desc: '', args: []);
  }

  /// `Set a folder for a project on the computer first (Settings › Projects).`
  String get aiNewNoFolders {
    return Intl.message(
      'Set a folder for a project on the computer first (Settings › Projects).',
      name: 'aiNewNoFolders',
      desc: '',
      args: [],
    );
  }

  /// `No agent is ready on the computer. Set one up in Settings › Agents.`
  String get aiNewNoAgents {
    return Intl.message(
      'No agent is ready on the computer. Set one up in Settings › Agents.',
      name: 'aiNewNoAgents',
      desc: '',
      args: [],
    );
  }

  /// `set up on the computer`
  String get aiAgentNotReady {
    return Intl.message(
      'set up on the computer',
      name: 'aiAgentNotReady',
      desc: '',
      args: [],
    );
  }

  /// `Message {agent}…`
  String aiComposerHint(String agent) {
    return Intl.message(
      'Message $agent…',
      name: 'aiComposerHint',
      desc: '',
      args: [agent],
    );
  }

  /// `Send`
  String get aiSend {
    return Intl.message('Send', name: 'aiSend', desc: '', args: []);
  }

  /// `Queue`
  String get aiQueue {
    return Intl.message('Queue', name: 'aiQueue', desc: '', args: []);
  }

  /// `Stop`
  String get aiStop {
    return Intl.message('Stop', name: 'aiStop', desc: '', args: []);
  }

  /// `Stopping…`
  String get aiStopping {
    return Intl.message('Stopping…', name: 'aiStopping', desc: '', args: []);
  }

  /// `Force stop`
  String get aiForceStop {
    return Intl.message('Force stop', name: 'aiForceStop', desc: '', args: []);
  }

  /// `Queued`
  String get aiQueued {
    return Intl.message('Queued', name: 'aiQueued', desc: '', args: []);
  }

  /// `Remove from queue`
  String get aiRemoveQueued {
    return Intl.message(
      'Remove from queue',
      name: 'aiRemoveQueued',
      desc: '',
      args: [],
    );
  }

  /// `Load earlier`
  String get aiLoadEarlier {
    return Intl.message(
      'Load earlier',
      name: 'aiLoadEarlier',
      desc: '',
      args: [],
    );
  }

  /// `Latest`
  String get aiJumpLatest {
    return Intl.message('Latest', name: 'aiJumpLatest', desc: '', args: []);
  }

  /// `No messages yet. Write the first one below.`
  String get aiEmpty {
    return Intl.message(
      'No messages yet. Write the first one below.',
      name: 'aiEmpty',
      desc: '',
      args: [],
    );
  }

  /// `Reconnecting… what you see may be behind.`
  String get aiReconnecting {
    return Intl.message(
      'Reconnecting… what you see may be behind.',
      name: 'aiReconnecting',
      desc: '',
      args: [],
    );
  }

  /// `This AI session was closed on the computer.`
  String get aiClosedGone {
    return Intl.message(
      'This AI session was closed on the computer.',
      name: 'aiClosedGone',
      desc: '',
      args: [],
    );
  }

  /// `ShellX was closed on the computer. Open ShellX on the computer, then open the session again.`
  String get aiClosedDesktop {
    return Intl.message(
      'ShellX was closed on the computer. Open ShellX on the computer, then open the session again.',
      name: 'aiClosedDesktop',
      desc: '',
      args: [],
    );
  }

  /// `The phone cannot read this AI session. See it on the computer.`
  String get aiClosedUnreadable {
    return Intl.message(
      'The phone cannot read this AI session. See it on the computer.',
      name: 'aiClosedUnreadable',
      desc: '',
      args: [],
    );
  }

  /// `Too long to send from the phone ({max} KB at most).`
  String aiTooLong(int max) {
    return Intl.message(
      'Too long to send from the phone ($max KB at most).',
      name: 'aiTooLong',
      desc: '',
      args: [max],
    );
  }

  /// `5 messages are already waiting.`
  String get aiQueueFull {
    return Intl.message(
      '5 messages are already waiting.',
      name: 'aiQueueFull',
      desc: '',
      args: [],
    );
  }

  /// `The computer did not take it ({reason}).`
  String aiRequestFailed(String reason) {
    return Intl.message(
      'The computer did not take it ($reason).',
      name: 'aiRequestFailed',
      desc: '',
      args: [reason],
    );
  }

  /// `This may not have been sent — the connection dropped. Check the session before trying again.`
  String get aiOutcomeUnknown {
    return Intl.message(
      'This may not have been sent — the connection dropped. Check the session before trying again.',
      name: 'aiOutcomeUnknown',
      desc: '',
      args: [],
    );
  }

  /// `The new session may not have been created. Check the list before trying again.`
  String get aiOpenOutcomeUnknown {
    return Intl.message(
      'The new session may not have been created. Check the list before trying again.',
      name: 'aiOpenOutcomeUnknown',
      desc: '',
      args: [],
    );
  }

  /// `The computer did not accept this request.`
  String get aiRefused {
    return Intl.message(
      'The computer did not accept this request.',
      name: 'aiRefused',
      desc: '',
      args: [],
    );
  }

  /// `Too many requests at once. Wait a moment, then try again.`
  String get aiBusy {
    return Intl.message(
      'Too many requests at once. Wait a moment, then try again.',
      name: 'aiBusy',
      desc: '',
      args: [],
    );
  }

  /// `Already answered on another device.`
  String get aiAnsweredElsewhere {
    return Intl.message(
      'Already answered on another device.',
      name: 'aiAnsweredElsewhere',
      desc: '',
      args: [],
    );
  }

  /// `Thinking`
  String get aiThought {
    return Intl.message('Thinking', name: 'aiThought', desc: '', args: []);
  }

  /// `Too large for the phone. Open it on the computer.`
  String get aiFromComputerOnly {
    return Intl.message(
      'Too large for the phone. Open it on the computer.',
      name: 'aiFromComputerOnly',
      desc: '',
      args: [],
    );
  }

  /// `This kind of item is not supported on the phone yet. See it on the computer.`
  String get aiItemOnComputer {
    return Intl.message(
      'This kind of item is not supported on the phone yet. See it on the computer.',
      name: 'aiItemOnComputer',
      desc: '',
      args: [],
    );
  }

  /// `{count} lines in all; the middle is on the computer`
  String aiCutLines(int count) {
    return Intl.message(
      '$count lines in all; the middle is on the computer',
      name: 'aiCutLines',
      desc: '',
      args: [count],
    );
  }

  /// `The rest of this message is on the computer.`
  String get aiCutText {
    return Intl.message(
      'The rest of this message is on the computer.',
      name: 'aiCutText',
      desc: '',
      args: [],
    );
  }

  /// `{count, plural, one{+1 more file} other{+{count} more files}}`
  String aiMoreDiffs(int count) {
    return Intl.plural(
      count,
      one: '+1 more file',
      other: '+$count more files',
      name: 'aiMoreDiffs',
      desc: '',
      args: [count],
    );
  }

  /// `new file`
  String get aiCreated {
    return Intl.message('new file', name: 'aiCreated', desc: '', args: []);
  }

  /// `No output`
  String get aiNoOutput {
    return Intl.message('No output', name: 'aiNoOutput', desc: '', args: []);
  }

  /// `Read {target}`
  String aiToolRead(String target) {
    return Intl.message(
      'Read $target',
      name: 'aiToolRead',
      desc: '',
      args: [target],
    );
  }

  /// `Edit {target}`
  String aiToolEdit(String target) {
    return Intl.message(
      'Edit $target',
      name: 'aiToolEdit',
      desc: '',
      args: [target],
    );
  }

  /// `Create {target}`
  String aiToolCreate(String target) {
    return Intl.message(
      'Create $target',
      name: 'aiToolCreate',
      desc: '',
      args: [target],
    );
  }

  /// `Delete {target}`
  String aiToolDelete(String target) {
    return Intl.message(
      'Delete $target',
      name: 'aiToolDelete',
      desc: '',
      args: [target],
    );
  }

  /// `Rename {target}`
  String aiToolMove(String target) {
    return Intl.message(
      'Rename $target',
      name: 'aiToolMove',
      desc: '',
      args: [target],
    );
  }

  /// `Search {target}`
  String aiToolSearch(String target) {
    return Intl.message(
      'Search $target',
      name: 'aiToolSearch',
      desc: '',
      args: [target],
    );
  }

  /// `Fetch {target}`
  String aiToolFetch(String target) {
    return Intl.message(
      'Fetch $target',
      name: 'aiToolFetch',
      desc: '',
      args: [target],
    );
  }

  /// `Run {target}`
  String aiToolExecute(String target) {
    return Intl.message(
      'Run $target',
      name: 'aiToolExecute',
      desc: '',
      args: [target],
    );
  }

  /// `Switch mode`
  String get aiToolSwitchMode {
    return Intl.message(
      'Switch mode',
      name: 'aiToolSwitchMode',
      desc: '',
      args: [],
    );
  }

  /// `waiting`
  String get aiToolPending {
    return Intl.message('waiting', name: 'aiToolPending', desc: '', args: []);
  }

  /// `waiting for you`
  String get aiToolAwaiting {
    return Intl.message(
      'waiting for you',
      name: 'aiToolAwaiting',
      desc: '',
      args: [],
    );
  }

  /// `running · {time}`
  String aiToolRunningFor(String time) {
    return Intl.message(
      'running · $time',
      name: 'aiToolRunningFor',
      desc: '',
      args: [time],
    );
  }

  /// `rejected`
  String get aiToolRejected {
    return Intl.message('rejected', name: 'aiToolRejected', desc: '', args: []);
  }

  /// `stopped`
  String get aiToolStopped {
    return Intl.message('stopped', name: 'aiToolStopped', desc: '', args: []);
  }

  /// `error`
  String get aiToolFailed {
    return Intl.message('error', name: 'aiToolFailed', desc: '', args: []);
  }

  /// `done`
  String get aiToolDone {
    return Intl.message('done', name: 'aiToolDone', desc: '', args: []);
  }

  /// `You chose: {option}`
  String aiYouChose(String option) {
    return Intl.message(
      'You chose: $option',
      name: 'aiYouChose',
      desc: '',
      args: [option],
    );
  }

  /// `{agent} asks:`
  String aiPermTitle(String agent) {
    return Intl.message(
      '$agent asks:',
      name: 'aiPermTitle',
      desc: '',
      args: [agent],
    );
  }

  /// `Allow`
  String get aiPermAllowOnce {
    return Intl.message('Allow', name: 'aiPermAllowOnce', desc: '', args: []);
  }

  /// `Always allow`
  String get aiPermAllowAlways {
    return Intl.message(
      'Always allow',
      name: 'aiPermAllowAlways',
      desc: '',
      args: [],
    );
  }

  /// `Reject`
  String get aiPermRejectOnce {
    return Intl.message('Reject', name: 'aiPermRejectOnce', desc: '', args: []);
  }

  /// `Always reject`
  String get aiPermRejectAlways {
    return Intl.message(
      'Always reject',
      name: 'aiPermRejectAlways',
      desc: '',
      args: [],
    );
  }

  /// `Option`
  String get aiPermOption {
    return Intl.message('Option', name: 'aiPermOption', desc: '', args: []);
  }

  /// `{count} more waiting`
  String aiPermMore(int count) {
    return Intl.message(
      '$count more waiting',
      name: 'aiPermMore',
      desc: '',
      args: [count],
    );
  }

  /// `Details`
  String get aiPermDetails {
    return Intl.message('Details', name: 'aiPermDetails', desc: '', args: []);
  }

  /// `Answer this request on the computer.`
  String get aiPermOnComputer {
    return Intl.message(
      'Answer this request on the computer.',
      name: 'aiPermOnComputer',
      desc: '',
      args: [],
    );
  }

  /// `{agent} asks you`
  String aiAskTitle(String agent) {
    return Intl.message(
      '$agent asks you',
      name: 'aiAskTitle',
      desc: '',
      args: [agent],
    );
  }

  /// `Send answer`
  String get aiAskSubmit {
    return Intl.message('Send answer', name: 'aiAskSubmit', desc: '', args: []);
  }

  /// `Decline`
  String get aiAskDecline {
    return Intl.message('Decline', name: 'aiAskDecline', desc: '', args: []);
  }

  /// `Answer this question on the computer.`
  String get aiAskOnComputer {
    return Intl.message(
      'Answer this question on the computer.',
      name: 'aiAskOnComputer',
      desc: '',
      args: [],
    );
  }

  /// `Answered`
  String get aiAskAnswered {
    return Intl.message('Answered', name: 'aiAskAnswered', desc: '', args: []);
  }

  /// `Declined`
  String get aiAskDeclined {
    return Intl.message('Declined', name: 'aiAskDeclined', desc: '', args: []);
  }

  /// `Cancelled`
  String get aiAskCancelled {
    return Intl.message(
      'Cancelled',
      name: 'aiAskCancelled',
      desc: '',
      args: [],
    );
  }

  /// `This question uses an answer type ShellX does not support yet.`
  String get aiAskUnsupported {
    return Intl.message(
      'This question uses an answer type ShellX does not support yet.',
      name: 'aiAskUnsupported',
      desc: '',
      args: [],
    );
  }

  /// `Waiting for your answer below`
  String get aiAskWaiting {
    return Intl.message(
      'Waiting for your answer below',
      name: 'aiAskWaiting',
      desc: '',
      args: [],
    );
  }

  /// `Turn {n} · {time}`
  String aiTurnSummary(int n, String time) {
    return Intl.message(
      'Turn $n · $time',
      name: 'aiTurnSummary',
      desc: '',
      args: [n, time],
    );
  }

  /// `{count, plural, one{1 file changed} other{{count} files changed}}`
  String aiTurnFiles(int count) {
    return Intl.plural(
      count,
      one: '1 file changed',
      other: '$count files changed',
      name: 'aiTurnFiles',
      desc: '',
      args: [count],
    );
  }

  /// `Stopped turn {n} · {time}`
  String aiTurnStopped(int n, String time) {
    return Intl.message(
      'Stopped turn $n · $time',
      name: 'aiTurnStopped',
      desc: '',
      args: [n, time],
    );
  }

  /// `Turn {n} interrupted`
  String aiTurnInterrupted(int n) {
    return Intl.message(
      'Turn $n interrupted',
      name: 'aiTurnInterrupted',
      desc: '',
      args: [n],
    );
  }

  /// `Turn {n} failed`
  String aiTurnFailed(int n) {
    return Intl.message(
      'Turn $n failed',
      name: 'aiTurnFailed',
      desc: '',
      args: [n],
    );
  }

  /// `{agent} needs you to sign in, on the computer.`
  String aiNoticeLogin(String agent) {
    return Intl.message(
      '$agent needs you to sign in, on the computer.',
      name: 'aiNoticeLogin',
      desc: '',
      args: [agent],
    );
  }

  /// `{agent} needs Node.js {version} or newer on the computer.`
  String aiNoticeNode(String agent, int version) {
    return Intl.message(
      '$agent needs Node.js $version or newer on the computer.',
      name: 'aiNoticeNode',
      desc: '',
      args: [agent, version],
    );
  }

  /// `{agent} is not installed on the computer.`
  String aiNoticeNotInstalled(String agent) {
    return Intl.message(
      '$agent is not installed on the computer.',
      name: 'aiNoticeNotInstalled',
      desc: '',
      args: [agent],
    );
  }

  /// `{agent} was not found on the computer.`
  String aiNoticeMissing(String agent) {
    return Intl.message(
      '$agent was not found on the computer.',
      name: 'aiNoticeMissing',
      desc: '',
      args: [agent],
    );
  }

  /// `{agent} stopped unexpectedly (exit {code}).`
  String aiNoticeExited(String agent, int code) {
    return Intl.message(
      '$agent stopped unexpectedly (exit $code).',
      name: 'aiNoticeExited',
      desc: '',
      args: [agent, code],
    );
  }

  /// `{agent} sent output ShellX cannot read and was stopped.`
  String aiNoticeInvalid(String agent) {
    return Intl.message(
      '$agent sent output ShellX cannot read and was stopped.',
      name: 'aiNoticeInvalid',
      desc: '',
      args: [agent],
    );
  }

  /// `{agent} could not start.`
  String aiNoticeStartFailed(String agent) {
    return Intl.message(
      '$agent could not start.',
      name: 'aiNoticeStartFailed',
      desc: '',
      args: [agent],
    );
  }

  /// `This agent cannot reopen the old session; a new one was started.`
  String get aiNoticeCannotResume {
    return Intl.message(
      'This agent cannot reopen the old session; a new one was started.',
      name: 'aiNoticeCannotResume',
      desc: '',
      args: [],
    );
  }

  /// `The session's folder is gone. Choose one on the computer.`
  String get aiNoticeFolderMissing {
    return Intl.message(
      'The session\'s folder is gone. Choose one on the computer.',
      name: 'aiNoticeFolderMissing',
      desc: '',
      args: [],
    );
  }

  /// `Undo is off for this project.`
  String get aiNoticeUndoOff {
    return Intl.message(
      'Undo is off for this project.',
      name: 'aiNoticeUndoOff',
      desc: '',
      args: [],
    );
  }

  /// `Undo is off for this project ({reason}).`
  String aiNoticeUndoOffReason(String reason) {
    return Intl.message(
      'Undo is off for this project ($reason).',
      name: 'aiNoticeUndoOffReason',
      desc: '',
      args: [reason],
    );
  }

  /// `Undo is off for this turn ({reason}).`
  String aiNoticeUndoOffTurn(String reason) {
    return Intl.message(
      'Undo is off for this turn ($reason).',
      name: 'aiNoticeUndoOffTurn',
      desc: '',
      args: [reason],
    );
  }

  /// `git was not found`
  String get aiUndoNoGit {
    return Intl.message(
      'git was not found',
      name: 'aiUndoNoGit',
      desc: '',
      args: [],
    );
  }

  /// `the Command Line Tools are not installed`
  String get aiUndoNoCommandLineTools {
    return Intl.message(
      'the Command Line Tools are not installed',
      name: 'aiUndoNoCommandLineTools',
      desc: '',
      args: [],
    );
  }

  /// `git is older than 2.26`
  String get aiUndoGitTooOld {
    return Intl.message(
      'git is older than 2.26',
      name: 'aiUndoGitTooOld',
      desc: '',
      args: [],
    );
  }

  /// `more than 200,000 files`
  String get aiUndoTooManyFiles {
    return Intl.message(
      'more than 200,000 files',
      name: 'aiUndoTooManyFiles',
      desc: '',
      args: [],
    );
  }

  /// `the first snapshot took over 30 s`
  String get aiUndoTooSlow {
    return Intl.message(
      'the first snapshot took over 30 s',
      name: 'aiUndoTooSlow',
      desc: '',
      args: [],
    );
  }

  /// `a snapshot failed`
  String get aiUndoFailed {
    return Intl.message(
      'a snapshot failed',
      name: 'aiUndoFailed',
      desc: '',
      args: [],
    );
  }

  /// `this folder is your home folder or a disk root`
  String get aiUndoBroadFolder {
    return Intl.message(
      'this folder is your home folder or a disk root',
      name: 'aiUndoBroadFolder',
      desc: '',
      args: [],
    );
  }

  /// `A notice from the computer.`
  String get aiNoticeOther {
    return Intl.message(
      'A notice from the computer.',
      name: 'aiNoticeOther',
      desc: '',
      args: [],
    );
  }

  /// `Ask first`
  String get aiModeDefault {
    return Intl.message('Ask first', name: 'aiModeDefault', desc: '', args: []);
  }

  /// `Edit files`
  String get aiModeAcceptEdits {
    return Intl.message(
      'Edit files',
      name: 'aiModeAcceptEdits',
      desc: '',
      args: [],
    );
  }

  /// `Plan`
  String get aiModePlan {
    return Intl.message('Plan', name: 'aiModePlan', desc: '', args: []);
  }

  /// `Auto`
  String get aiModeAuto {
    return Intl.message('Auto', name: 'aiModeAuto', desc: '', args: []);
  }

  /// `Bypass permissions`
  String get aiModeBypass {
    return Intl.message(
      'Bypass permissions',
      name: 'aiModeBypass',
      desc: '',
      args: [],
    );
  }

  /// `Context {percent}%`
  String aiContext(int percent) {
    return Intl.message(
      'Context $percent%',
      name: 'aiContext',
      desc: '',
      args: [percent],
    );
  }

  /// `Plan · {done}/{total}`
  String aiPlan(int done, int total) {
    return Intl.message(
      'Plan · $done/$total',
      name: 'aiPlan',
      desc: '',
      args: [done, total],
    );
  }

  /// `from phone`
  String get aiFromPhone {
    return Intl.message('from phone', name: 'aiFromPhone', desc: '', args: []);
  }

  /// `Reconnected after ShellX restarted.`
  String get aiReattached {
    return Intl.message(
      'Reconnected after ShellX restarted.',
      name: 'aiReattached',
      desc: '',
      args: [],
    );
  }

  /// `Open the session list`
  String get aiOpenList {
    return Intl.message(
      'Open the session list',
      name: 'aiOpenList',
      desc: '',
      args: [],
    );
  }

  /// `Mode and model`
  String get aiConfigTitle {
    return Intl.message(
      'Mode and model',
      name: 'aiConfigTitle',
      desc: '',
      args: [],
    );
  }

  /// `Mode`
  String get aiConfigMode {
    return Intl.message('Mode', name: 'aiConfigMode', desc: '', args: []);
  }

  /// `Model`
  String get aiConfigModel {
    return Intl.message('Model', name: 'aiConfigModel', desc: '', args: []);
  }

  /// `Thinking`
  String get aiConfigEffort {
    return Intl.message('Thinking', name: 'aiConfigEffort', desc: '', args: []);
  }

  /// `More choices on the computer.`
  String get aiConfigMore {
    return Intl.message(
      'More choices on the computer.',
      name: 'aiConfigMore',
      desc: '',
      args: [],
    );
  }

  /// `Choose this on the computer.`
  String get aiConfigOnComputer {
    return Intl.message(
      'Choose this on the computer.',
      name: 'aiConfigOnComputer',
      desc: '',
      args: [],
    );
  }

  /// `View all`
  String get aiViewAll {
    return Intl.message('View all', name: 'aiViewAll', desc: '', args: []);
  }

  /// `Loading {part}/{parts}`
  String aiLoadingParts(int part, int parts) {
    return Intl.message(
      'Loading $part/$parts',
      name: 'aiLoadingParts',
      desc: '',
      args: [part, parts],
    );
  }

  /// `It is still changing on the computer. Try again in a moment.`
  String get aiItemChanging {
    return Intl.message(
      'It is still changing on the computer. Try again in a moment.',
      name: 'aiItemChanging',
      desc: '',
      args: [],
    );
  }

  /// `Session history`
  String get aiHistory {
    return Intl.message(
      'Session history',
      name: 'aiHistory',
      desc: '',
      args: [],
    );
  }

  /// `Load more`
  String get aiHistoryMore {
    return Intl.message('Load more', name: 'aiHistoryMore', desc: '', args: []);
  }

  /// `No earlier sessions in this folder.`
  String get aiHistoryEmpty {
    return Intl.message(
      'No earlier sessions in this folder.',
      name: 'aiHistoryEmpty',
      desc: '',
      args: [],
    );
  }

  /// `The history shows once the agent runs.`
  String get aiHistoryNotReady {
    return Intl.message(
      'The history shows once the agent runs.',
      name: 'aiHistoryNotReady',
      desc: '',
      args: [],
    );
  }

  /// `Use this folder`
  String get aiUseFolder {
    return Intl.message(
      'Use this folder',
      name: 'aiUseFolder',
      desc: '',
      args: [],
    );
  }

  /// `Choose a folder for this session`
  String get aiChooseFolder {
    return Intl.message(
      'Choose a folder for this session',
      name: 'aiChooseFolder',
      desc: '',
      args: [],
    );
  }

  /// `Add photos`
  String get aiAttach {
    return Intl.message('Add photos', name: 'aiAttach', desc: '', args: []);
  }

  /// `Photo library`
  String get aiAttachPhoto {
    return Intl.message(
      'Photo library',
      name: 'aiAttachPhoto',
      desc: '',
      args: [],
    );
  }

  /// `Camera`
  String get aiTakePhoto {
    return Intl.message('Camera', name: 'aiTakePhoto', desc: '', args: []);
  }

  /// `{n, plural, one{1 image} other{{n} images}}`
  String aiImagesCount(int n) {
    return Intl.plural(
      n,
      one: '1 image',
      other: '$n images',
      name: 'aiImagesCount',
      desc: '',
      args: [n],
    );
  }

  /// `The image wasn't sent. Retry`
  String get aiImageFailed {
    return Intl.message(
      'The image wasn\'t sent. Retry',
      name: 'aiImageFailed',
      desc: '',
      args: [],
    );
  }

  /// `{agent} doesn't take images.`
  String aiNoImages(String agent) {
    return Intl.message(
      '$agent doesn\'t take images.',
      name: 'aiNoImages',
      desc: '',
      args: [agent],
    );
  }

  /// `Only JPEG, PNG, GIF or WebP images can be sent.`
  String get aiImageType {
    return Intl.message(
      'Only JPEG, PNG, GIF or WebP images can be sent.',
      name: 'aiImageType',
      desc: '',
      args: [],
    );
  }

  /// `This image is over 10 MB.`
  String get aiImageTooBig {
    return Intl.message(
      'This image is over 10 MB.',
      name: 'aiImageTooBig',
      desc: '',
      args: [],
    );
  }

  /// `One message can carry at most 20 MB of images.`
  String get aiImagesTooMuch {
    return Intl.message(
      'One message can carry at most 20 MB of images.',
      name: 'aiImagesTooMuch',
      desc: '',
      args: [],
    );
  }

  /// `Couldn't open the photos. Check ShellX's access in Settings.`
  String get aiPickFailed {
    return Intl.message(
      'Couldn\'t open the photos. Check ShellX\'s access in Settings.',
      name: 'aiPickFailed',
      desc: '',
      args: [],
    );
  }

  /// `Remove image`
  String get aiRemoveImage {
    return Intl.message(
      'Remove image',
      name: 'aiRemoveImage',
      desc: '',
      args: [],
    );
  }

  /// `Sending images…`
  String get aiUploading {
    return Intl.message(
      'Sending images…',
      name: 'aiUploading',
      desc: '',
      args: [],
    );
  }

  /// `Speak a message`
  String get aiMicTooltip {
    return Intl.message(
      'Speak a message',
      name: 'aiMicTooltip',
      desc: '',
      args: [],
    );
  }

  /// `Allow`
  String get pushActionAllow {
    return Intl.message('Allow', name: 'pushActionAllow', desc: '', args: []);
  }

  /// `Deny`
  String get pushActionReject {
    return Intl.message('Deny', name: 'pushActionReject', desc: '', args: []);
  }

  /// `Allowed: {title}`
  String aiPushAllowed(String title) {
    return Intl.message(
      'Allowed: $title',
      name: 'aiPushAllowed',
      desc: '',
      args: [title],
    );
  }

  /// `Denied: {title}`
  String aiPushDenied(String title) {
    return Intl.message(
      'Denied: $title',
      name: 'aiPushDenied',
      desc: '',
      args: [title],
    );
  }

  /// `It may not have been sent. Check the session.`
  String get aiPushMaybeNotSent {
    return Intl.message(
      'It may not have been sent. Check the session.',
      name: 'aiPushMaybeNotSent',
      desc: '',
      args: [],
    );
  }

  /// `This request was already answered elsewhere.`
  String get aiPushAnsweredElsewhere {
    return Intl.message(
      'This request was already answered elsewhere.',
      name: 'aiPushAnsweredElsewhere',
      desc: '',
      args: [],
    );
  }

  /// `✦ {n, plural, =1{1 AI session} other{{n} AI sessions}} · {w} need you`
  String machineAiLine(int n, int w) {
    return Intl.message(
      '✦ ${Intl.plural(n, one: '1 AI session', other: '$n AI sessions')} · $w need you',
      name: 'machineAiLine',
      desc: '',
      args: [n, w],
    );
  }

  /// `✦ {n, plural, =1{1 AI session} other{{n} AI sessions}}`
  String machineAiSessions(int n) {
    return Intl.message(
      '✦ ${Intl.plural(n, one: '1 AI session', other: '$n AI sessions')}',
      name: 'machineAiSessions',
      desc: '',
      args: [n],
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
