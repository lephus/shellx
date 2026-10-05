import 'dart:async';

import 'package:shellx_mobile/features/notifications/domain/push_messaging.dart';
import 'package:shellx_mobile/features/notifications/presentation/notification_opener.dart';

/// A scripted push service: the permission the user would give, the token, and streams a test
/// drives by hand (synchronous).
class FakePushMessaging implements PushMessaging {
  FakePushMessaging({this.available = true});

  @override
  final bool available;

  /// What [permission] reports.
  PushPermission current = PushPermission.notDetermined;

  /// What the user answers to [requestPermission].
  PushPermission answer = PushPermission.granted;
  int requests = 0;
  String? tokenValue = 'fcm-1';
  Object? tokenError;
  int deletes = 0;
  PushMessage? initial;

  final StreamController<String> refreshes = StreamController<String>.broadcast(sync: true);
  final StreamController<PushMessage> foreground = StreamController<PushMessage>.broadcast(sync: true);
  final StreamController<PushMessage> opened = StreamController<PushMessage>.broadcast(sync: true);

  @override
  Future<PushPermission> permission() async => current;

  @override
  Future<PushPermission> requestPermission() async {
    requests++;
    return current = answer;
  }

  @override
  Future<String?> token() async {
    final error = tokenError;
    if (error != null) throw error;
    return tokenValue;
  }

  @override
  Stream<String> get tokenRefreshes => refreshes.stream;

  @override
  Stream<PushMessage> get foregroundMessages => foreground.stream;

  @override
  Stream<PushMessage> get openedMessages => opened.stream;

  @override
  Future<PushMessage?> initialMessage() async => initial;

  /// Runs inside [deleteToken].
  void Function()? onDelete;

  @override
  Future<void> deleteToken() async {
    deletes++;
    onDelete?.call();
  }
}

/// Records what the opener asked the router for.
class FakeMachineNavigator implements MachineNavigator {
  String? showing;
  final List<(String, String)> shown = [];

  @override
  bool isShowing(String agentId) => showing == agentId;

  @override
  void show(String agentId, String machineName) {
    shown.add((agentId, machineName));
    showing = agentId;
  }
}

/// Records what [NotificationOpener.open] was given.
class RecordingOpener implements NotificationOpener {
  final List<PushMessage> opened = [];

  @override
  Future<void> open(PushMessage message) async => opened.add(message);
}
