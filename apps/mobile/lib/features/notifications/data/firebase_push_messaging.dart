import 'dart:async';
import 'dart:io';

import 'package:async/async.dart' show StreamGroup;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shellx_mobile/features/notifications/data/android_push_actions.dart';
import 'package:shellx_mobile/features/notifications/domain/push_messaging.dart';
import 'package:shellx_mobile/firebase_options.dart';

/// Starts Firebase for push (push spec §6). Never throws and never blocks the launch for long: a
/// missing configuration, a platform error or a start slower than [timeout] gives
/// [UnavailablePushMessaging], and the app runs without push.
Future<PushMessaging> startPushMessaging({Duration timeout = const Duration(seconds: 5)}) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform).timeout(timeout);
    }
    return FirebasePushMessaging(FirebaseMessaging.instance, actions: await _startAndroidActions(timeout));
  } catch (error) {
    if (kDebugMode) debugPrint('Push unavailable: ${error.runtimeType}');
    return const UnavailablePushMessaging();
  }
}

/// V2-2b B9, Android only: the app's side of the taps on the notifications the background handler draws again with
/// buttons, then that handler. Null elsewhere, or when it cannot start (push still works, without buttons).
Future<AndroidPushActions?> _startAndroidActions(Duration timeout) async {
  if (!Platform.isAndroid) return null;
  try {
    final actions = await AndroidPushActions.start().timeout(timeout);
    // A redraw takes FCM's notification away (F47): only drawn once the app can take its taps.
    if (actions != null) FirebaseMessaging.onBackgroundMessage(shellxBackgroundMessage);
    return actions;
  } catch (error) {
    if (kDebugMode) debugPrint('Push buttons unavailable: ${error.runtimeType}');
    return null;
  }
}

/// [PushMessaging] over `firebase_messaging`. Foreground messages are left to the app (an in-app
/// banner): no system presentation options are set on iOS, and Android never shows them itself. On
/// Android the taps on the notifications the app draws again with buttons ([AndroidPushActions], V2-2b
/// B9) come in with FCM's own.
final class FirebasePushMessaging implements PushMessaging {
  FirebasePushMessaging(this._messaging, {AndroidPushActions? actions}) : _actions = actions;

  final FirebaseMessaging _messaging;
  final AndroidPushActions? _actions;

  /// iOS hands out an FCM token only once APNs has registered the app.
  static const Duration _apnsWait = Duration(milliseconds: 500);
  static const int _apnsAttempts = 6;

  @override
  bool get available => true;

  @override
  Future<PushPermission> permission() async => _map((await _messaging.getNotificationSettings()).authorizationStatus);

  @override
  Future<PushPermission> requestPermission() async =>
      _map((await _messaging.requestPermission(alert: true, badge: false, sound: true)).authorizationStatus);

  @override
  Future<String?> token() async {
    if (Platform.isIOS) {
      var apns = await _messaging.getAPNSToken();
      for (var attempt = 1; apns == null && attempt < _apnsAttempts; attempt++) {
        await Future<void>.delayed(_apnsWait);
        apns = await _messaging.getAPNSToken();
      }
      // onTokenRefresh brings the token once APNs is ready.
      if (apns == null) return null;
    }
    return _messaging.getToken();
  }

  @override
  Stream<String> get tokenRefreshes => _messaging.onTokenRefresh;

  @override
  Stream<PushMessage> get foregroundMessages => FirebaseMessaging.onMessage.map(_message);

  @override
  Stream<PushMessage> get openedMessages {
    final opened = FirebaseMessaging.onMessageOpenedApp.map(_message);
    final actions = _actions;
    return actions == null ? opened : StreamGroup.merge([opened, actions.responses]);
  }

  @override
  Future<PushMessage?> initialMessage() async {
    final message = await _messaging.getInitialMessage();
    if (message != null) return _message(message);
    return _actions?.launchMessage();
  }

  @override
  Future<void> deleteToken() => _messaging.deleteToken();

  /// V2-2b B8: on iOS the button that opened the app comes as `actionIdentifier` (firebase_messaging 16.4.0+).
  static PushMessage _message(RemoteMessage message) => PushMessage(
    title: message.notification?.title,
    body: message.notification?.body,
    data: pushDataOf(message.data),
    action: message.actionIdentifier,
  );

  static PushPermission _map(AuthorizationStatus status) => switch (status) {
    AuthorizationStatus.authorized || AuthorizationStatus.provisional => PushPermission.granted,
    AuthorizationStatus.denied || AuthorizationStatus.deniedPermanently => PushPermission.denied,
    AuthorizationStatus.notDetermined => PushPermission.notDetermined,
  };
}
