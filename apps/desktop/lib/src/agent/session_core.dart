import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';

import 'agent_runtime.dart';

/// What lives for the whole process (A1 D7): the one [SessionManager], the
/// id allocator it shares with each runtime's desktop terminals, and the
/// push notifications of every session. Built once in `main.dart`; every
/// [CoreAgentRuntime] borrows it.
final class SessionCore {
  SessionCore._(this.ids, this.notifications, this.sessions);

  /// [api] is the app's shared [ShellxApi]: notifications are sent with
  /// whatever token it holds and fail locally (nothing leaves the
  /// computer) while signed out.
  factory SessionCore({
    required PtyFactory ptyFactory,
    required ShellResolver shellResolver,
    required String homeDirectory,
    required Map<String, String> baseEnvironment,
    required ShellxApi api,
    PushNotificationsSetup? notifications,
    DateTime Function()? now,
    int Function()? sessionIds,
    GitBranchLookup? gitHeads,
    PortProbe? portProbe,
  }) {
    final ids = sessionIds ?? sessionIdAllocator();
    // One AgentNotifications for both kinds of session: the 6-per-minute
    // limit is per machine (push spec N10).
    final agentNotifications = notifications == null
        ? null
        : AgentNotifications(
            NotificationsConfig(
              api: api,
              threshold: notifications.threshold,
              machineName: notifications.machineName,
              locale: notifications.locale,
            ),
            now: now,
          );
    final hooks = notifications?.hooksDirectory;
    final sessions = SessionManager(
      ptyFactory: ptyFactory,
      shellResolver: shellResolver,
      homeDirectory: homeDirectory,
      baseEnvironment: baseEnvironment,
      nextId: ids,
      notifications: agentNotifications,
      shellIntegration: hooks == null
          ? null
          : ShellIntegration(directory: hooks),
      clock: now,
      commandNoticeThreshold: notifications?.threshold,
      gitHeads: gitHeads,
      portProbe: portProbe,
      windowsPaths: Platform.isWindows,
      localHostName: Platform.localHostname,
      log: (message) => debugPrint('ShellX sessions: $message'),
    );
    return SessionCore._(ids, agentNotifications, sessions);
  }

  final int Function() ids;
  final AgentNotifications? notifications;
  final SessionManager sessions;
}
