import 'dart:async';

/// Whether this phone may show ShellX's notifications.
enum PushPermission {
  /// Never asked (iOS); Android 13+ before the prompt reports [denied].
  notDetermined,
  granted,
  denied,
}

/// A push notification as the agent sent it (push spec §4.2): the relay adds `agent_id`, the agent
/// `session_id` and `kind`.
final class PushMessage {
  const PushMessage({this.title, this.body, this.data = const {}, this.action});

  final String? title;
  final String? body;
  final Map<String, String> data;

  /// V2-2b B8, B9: the button of the notification that was tapped (`allow`, `reject`, or the system's own id of a
  /// plain tap); null for a tap on the notification itself, a banner, or a message that was not tapped.
  final String? action;

  /// The computer that sent it; null for a message that did not come through the relay.
  String? get agentId {
    final id = data['agent_id'];
    return id == null || id.isEmpty ? null : id;
  }

  /// The session (tab) it is about, when it names one.
  int? get sessionId => int.tryParse(data['session_id'] ?? '');

  /// V2-2 D11: the AI session it is about (`kind: ai`), when it names one.
  String? get aiSession {
    final sid = data['ai_session'];
    return sid == null || sid.isEmpty ? null : sid;
  }

  /// Never the title or body: they carry command lines (push spec §9).
  @override
  String toString() => 'PushMessage(agentId: $agentId, sessionId: $sessionId)';
}

/// The `data` of a push as strings (FCM hands the values over untyped); null values are left out.
Map<String, String> pushDataOf(Map<String, dynamic> data) => {
  for (final entry in data.entries)
    if (entry.value != null) entry.key: entry.value.toString(),
};

/// The phone's push service (Firebase Cloud Messaging in production). Every method may throw a
/// platform error; callers treat push as best effort.
abstract interface class PushMessaging {
  /// False when Firebase is not configured or failed to start (push spec §6: the app works
  /// without push). Every other member then does nothing.
  bool get available;

  Future<PushPermission> permission();

  /// Shows the system prompt (Android 13+: `POST_NOTIFICATIONS`); returns the answer.
  Future<PushPermission> requestPermission();

  /// This install's FCM token; null when there is none yet (iOS before APNs registered).
  Future<String?> token();

  /// A new token replaced the old one.
  Stream<String> get tokenRefreshes;

  /// Arrived while the app is in the foreground: the system shows nothing.
  Stream<PushMessage> get foregroundMessages;

  /// The user tapped a notification while the app was in the background.
  Stream<PushMessage> get openedMessages;

  /// The notification whose tap launched the app, once; null otherwise.
  Future<PushMessage?> initialMessage();

  /// Invalidates this install's token (sign-out): pushes sent to it stop arriving.
  Future<void> deleteToken();
}

/// [PushMessaging] when Firebase is missing: nothing arrives and nothing is asked.
final class UnavailablePushMessaging implements PushMessaging {
  const UnavailablePushMessaging();

  @override
  bool get available => false;

  @override
  Future<PushPermission> permission() async => PushPermission.denied;

  @override
  Future<PushPermission> requestPermission() async => PushPermission.denied;

  @override
  Future<String?> token() async => null;

  @override
  Stream<String> get tokenRefreshes => const Stream.empty();

  @override
  Stream<PushMessage> get foregroundMessages => const Stream.empty();

  @override
  Stream<PushMessage> get openedMessages => const Stream.empty();

  @override
  Future<PushMessage?> initialMessage() async => null;

  @override
  Future<void> deleteToken() async {}
}
