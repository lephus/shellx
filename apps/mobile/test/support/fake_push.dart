import 'dart:async';

import 'package:shellx_mobile/features/notifications/domain/push_answer.dart';
import 'package:shellx_mobile/features/notifications/domain/push_messaging.dart';
import 'package:shellx_mobile/features/notifications/presentation/notification_opener.dart';
import 'package:shellx_mobile/features/notifications/presentation/push_answerer.dart';

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

  /// V2-2: the AI session on top, as `agentId/sid`.
  String? showingAi;
  final List<(String, String, String)> shownAi = [];

  @override
  bool isShowingAi(String agentId, String sid) => showingAi == '$agentId/$sid';

  @override
  void showAi(String agentId, String machineName, String sid) {
    shownAi.add((agentId, machineName, sid));
    showingAi = '$agentId/$sid';
  }
}

/// Records what [NotificationOpener.open] was given.
class RecordingOpener implements NotificationOpener {
  final List<PushMessage> opened = [];

  @override
  Future<void> open(PushMessage message) async => opened.add(message);
}

/// Records the push answers [PushController] hands over (V2-2b B10).
class RecordingAnswerer implements PushAnswerer {
  final List<(PushMessage, PushAnswer)> answered = [];

  @override
  Duration get patience => const Duration(minutes: 2);

  @override
  Duration get relayWait => const Duration(seconds: 10);

  @override
  Future<void> answer(PushMessage message, PushAnswer answer) async => answered.add((message, answer));
}
