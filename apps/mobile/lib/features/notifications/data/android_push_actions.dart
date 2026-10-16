import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shellx_mobile/features/notifications/domain/push_answer.dart';
import 'package:shellx_mobile/features/notifications/domain/push_messaging.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// The channel FCM draws on (`@string/notification_channel_id`; MainActivity creates it): the notification
/// drawn again with its buttons stays in it, with the user's settings for it.
const String kPushChannelId = 'shellx_notifications';

/// The status-bar icon of the app's notifications (the one FCM uses, `default_notification_icon`).
const String _icon = '@drawable/ic_notification';

/// V2-2b B9 (F47): the ids [aiActionIdOf] gives run from 1 to 2^27 - 1, never FCM's 0. The plugin derives the
/// request codes of a notification's buttons from its id (`id * 16`, `id * 16 + 1`): below 2^27 they fit an int
/// and never meet another id's.
const int _idSpan = (1 << 27) - 1;

/// V2-2b B9 (F47): the id an AI permission push is drawn again under, its own, from FCM's [tag] for it: FNV-1a
/// (32 bits) over the tag's UTF-8 bytes, in 1 ≤ id < 2^27 — the same in any isolate and any run. Two notifications
/// that showed under one id would share the intents of their buttons (the plugin keys them by the id), and a tap
/// on one would answer the other's request.
int aiActionIdOf(String tag) {
  var hash = 0x811c9dc5;
  for (final byte in utf8.encode(tag)) {
    hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
  }
  return 1 + hash % _idSpan;
}

/// V2-2b B9: an AI permission push as Android shows it again, with its two buttons, in place of the one FCM drew
/// (`(tag, 0)`): under its own [id] and without a tag (F47).
final class AiActionNotification {
  const AiActionNotification({required this.tag, required this.payload, this.title, this.body});

  /// The tag FCM drew the push with (`android.notification.tag`, set by the relay since B6): FCM's notification of
  /// the push is `(tag, 0)`.
  final String tag;
  final String? title;
  final String? body;

  /// The push itself ([pushPayloadOf]), for the tap that comes back to the app.
  final String payload;

  /// The id it is drawn under ([aiActionIdOf]).
  int get id => aiActionIdOf(tag);

  /// Never the request.
  @override
  String toString() => 'AiActionNotification(…)';
}

/// V2-2b B9: [data] of a push FCM drew with [tag], as a permission request that gets buttons: exactly the data a
/// button can answer (B10) and a tag of an AI request. Null for any other push — and for one drawn without a tag
/// (an older relay): FCM's notification of it could not be found to be replaced, and two would show.
AiActionNotification? aiActionNotificationOf(
  Map<String, String> data, {
  String? title,
  String? body,
  String? tag,
}) {
  if (tag == null || !tag.startsWith('ai-')) return null;
  final message = PushMessage(title: title, body: body, data: data);
  if (PushAnswer.of(PushMessage(title: title, body: body, data: data, action: 'allow')) == null) return null;
  return AiActionNotification(tag: tag, title: title, body: body, payload: pushPayloadOf(message));
}

/// V2-2b B9 (F47): whether [note] is drawn now, given the notifications of the app that show ([active], as
/// `(id, tag)` pairs, FCM's among them): only in place of FCM's notification of the push, `(tag, 0)`, while it
/// still shows, and only under an id no notification has (this push drawn again already, or another request whose
/// tag gives the same id). Otherwise nothing is drawn and FCM's notification stays as it is: one the user
/// dismissed is never brought back, and no two notifications ever share their buttons.
bool replacesFcmNotification(AiActionNotification note, Iterable<(int?, String?)> active) {
  final id = note.id;
  var fcm = false;
  for (final (shown, tag) in active) {
    if (shown == id) return false;
    if (shown == 0 && tag == note.tag) fcm = true;
  }
  return fcm;
}

/// What an AI permission push is drawn again with: on the app's channel, "Từ chối" then "Cho phép". Without a tag
/// (F47): the plugin cancels a notification by its id alone when one of its buttons is tapped, and a tap on its
/// body cancels it too. Silent: FCM's notification of the push already alerted, and ours is a new one. Both
/// buttons open the app — which needs the phone unlocked — and the answer goes from there, after the app's own
/// lock (B10).
NotificationDetails aiActionDetails({required String allow, required String reject}) => NotificationDetails(
  android: AndroidNotificationDetails(
    kPushChannelId,
    'ShellX',
    icon: _icon,
    importance: Importance.high,
    priority: Priority.high,
    silent: true,
    actions: [
      AndroidNotificationAction('reject', reject, showsUserInterface: true),
      AndroidNotificationAction('allow', allow, showsUserInterface: true),
    ],
  ),
);

/// [message] as the payload of a notification the app draws itself: its title, body and data as JSON.
String pushPayloadOf(PushMessage message) => jsonEncode({
  'title': ?message.title,
  'body': ?message.body,
  'data': message.data,
});

/// The push a payload of [pushPayloadOf] carries, with the button that was tapped ([action]); null when the
/// payload is none of ours.
PushMessage? pushMessageOfPayload(String? payload, {String? action}) {
  if (payload == null) return null;
  try {
    final json = jsonDecode(payload);
    if (json is! Map<String, Object?>) return null;
    final data = json['data'];
    if (data is! Map<String, Object?>) return null;
    final title = json['title'];
    final body = json['body'];
    return PushMessage(
      title: title is String ? title : null,
      body: body is String ? body : null,
      data: {
        for (final MapEntry(:key, :value) in data.entries)
          if (value is String) key: value,
      },
      action: action,
    );
  } on FormatException {
    return null;
  }
}

/// A tap on a notification the app drew: its body (no action) or one of its buttons.
PushMessage? pushMessageOfResponse(NotificationResponse response) => pushMessageOfPayload(
  response.payload,
  action: response.notificationResponseType == NotificationResponseType.selectedNotificationAction
      ? response.actionId
      : null,
);

/// V2-2b B9, Android only: flutter_local_notifications in the app's own isolate. The taps on the notifications the
/// background handler drew again — on their body or on a button — come back as [PushMessage]s ([responses], or
/// [launchMessage] for the one that launched the app). Never made on iOS: there the buttons are the app's own
/// category (B8), and the plugin's initialisation would replace it.
final class AndroidPushActions {
  AndroidPushActions._(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;
  final _responses = StreamController<PushMessage>.broadcast();

  /// Null off Android.
  static Future<AndroidPushActions?> start() async {
    if (!Platform.isAndroid) return null;
    final plugin = FlutterLocalNotificationsPlugin();
    final actions = AndroidPushActions._(plugin);
    await plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings(_icon)),
      onDidReceiveNotificationResponse: actions._onResponse,
    );
    return actions;
  }

  Stream<PushMessage> get responses => _responses.stream;

  /// The notification of ours whose tap launched the app, once; null otherwise.
  Future<PushMessage?> launchMessage() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    final response = details?.notificationResponse;
    if (details == null || !details.didNotificationLaunchApp || response == null) return null;
    return pushMessageOfResponse(response);
  }

  void _onResponse(NotificationResponse response) {
    final message = pushMessageOfResponse(response);
    if (message != null) _responses.add(message);
  }
}

/// V2-2b B9 (F47): draws [note] with its two buttons in place of FCM's notification of the same push, when
/// [replacesFcmNotification] allows it — under its own id, then FCM's is cancelled (ours is silent: the push
/// alerts once). True when drawn; otherwise FCM's notification stays as it is, without buttons.
Future<bool> redrawAiAction(
  FlutterLocalNotificationsPlugin plugin,
  AiActionNotification note, {
  required String allow,
  required String reject,
}) async {
  final active = await plugin.getActiveNotifications();
  if (!replacesFcmNotification(note, [for (final shown in active) (shown.id, shown.tag)])) return false;
  await plugin.show(
    id: note.id,
    title: note.title,
    body: note.body,
    notificationDetails: aiActionDetails(allow: allow, reject: reject),
    payload: note.payload,
  );
  await plugin.cancel(id: 0, tag: note.tag);
  return true;
}

/// V2-2b B9: FCM's background handler (Android; firebase_messaging runs it in an isolate of its own for every
/// push that arrives while the app is not in the foreground). An AI permission push FCM drew with its tag is drawn
/// again in its place with the two buttons ([redrawAiAction]: under its own id, while FCM's still shows, which is
/// then cancelled). Nothing else: no network, no app state, no Firebase service. When this cannot run (the phone
/// keeps the app from running in the background), FCM's notification stays, without buttons.
@pragma('vm:entry-point')
Future<void> shellxBackgroundMessage(RemoteMessage message) async {
  // Registered on Android only, once the app can take the taps (`startPushMessaging`): never draws anything on
  // iOS (B5, B8).
  if (!Platform.isAndroid) return;
  try {
    final note = aiActionNotificationOf(
      pushDataOf(message.data),
      title: message.notification?.title,
      body: message.notification?.body,
      tag: message.notification?.android?.tag,
    );
    if (note == null) return;
    // The phone's language, as iOS names its buttons (B8).
    final words = await S.load(Locale(PlatformDispatcher.instance.locale.languageCode == 'vi' ? 'vi' : 'en'));
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(settings: const InitializationSettings(android: AndroidInitializationSettings(_icon)));
    await redrawAiAction(plugin, note, allow: words.pushActionAllow, reject: words.pushActionReject);
  } catch (error) {
    // FCM's own notification stays (without buttons).
    if (kDebugMode) debugPrint('Push background error: ${error.runtimeType}');
  }
}
