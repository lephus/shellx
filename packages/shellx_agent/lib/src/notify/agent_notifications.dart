import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';

import '../ai/ai_phone_hub.dart';
import 'command_tracker.dart';
import 'notification_sender.dart';
import 'notification_text.dart';
import 'osc_event_parser.dart';

/// What the desktop app supplies for push notifications (stream N-b). Every
/// getter is read when a notification is built, so a changed setting
/// applies to the next one.
final class NotificationsConfig {
  const NotificationsConfig({
    required this.api,
    required this.threshold,
    required this.machineName,
    required this.locale,
  });

  /// The signed-in agent's API (its token authorizes `POST /v1/notifications`).
  final ShellxApi api;

  /// Long-running command threshold (N6); null = off. Messages from
  /// programs (OSC 9 / 777, `shellx notify`) do not depend on it.
  final Duration? Function() threshold;

  /// The agent's device name, first part of every title.
  final String Function() machineName;

  /// The computer's language, e.g. `vi_VN` or `en-US`.
  final String Function() locale;
}

/// Push notifications of one agent: one [SessionNotifier] per session, all
/// sending through one [NotificationSender] (the 6-per-minute limit is per
/// machine).
final class AgentNotifications {
  AgentNotifications(
    this.config, {
    NotificationSender? sender,
    DateTime Function()? now,
  }) : sender = sender ?? NotificationSender(api: config.api, now: now),
       _now = now;

  final NotificationsConfig config;
  final NotificationSender sender;
  final DateTime Function()? _now;

  /// A phone opened a channel to this agent or paired: lifts the sender's
  /// pause after an unheard notification ([NotificationSender.resume]).
  void phoneConnected() => sender.resume();

  /// V2-2 D11: an AI session needs the user, or finished a long turn
  /// (title `<machine> · <agent>`). The phone opens that session from
  /// `ai_session`; an older phone opens the machine. V2-2b B7: a permission
  /// request with its two answers ([AiPush.answerable]) also carries its id
  /// and the two option ids in `data` (`perm`, `allow`, `reject`), and asks
  /// for the buttons (`category: ai_perm`) and the request's [AiPush.tag]; a
  /// question, a finished turn and any other push have none. Never throws.
  void aiNotice(AiPush push) {
    try {
      NotificationText text;
      try {
        text = NotificationText(config.locale());
      } catch (_) {
        text = NotificationText('en');
      }
      String machine;
      try {
        machine = config.machineName();
      } catch (_) {
        machine = '';
      }
      final body = switch (push.kind) {
        // A question's words never go to the push service (M2).
        AiPushKind.needsInput when push.question => text.aiQuestion(
          push.agentName,
        ),
        AiPushKind.needsInput => text.aiNeedsInput(push.detail),
        AiPushKind.done => text.aiDone(
          push.turn ?? 0,
          push.elapsed ?? Duration.zero,
        ),
      };
      final buttons =
          push.kind == AiPushKind.needsInput &&
          !push.question &&
          push.answerable;
      sender.send(
        AgentNotification(
          title: text.title(machine, push.agentName),
          body: body,
          data: {
            'kind': 'ai',
            'ai_session': push.sid,
            if (buttons) ...{
              'perm': '${push.permission}',
              'allow': push.allow!,
              'reject': push.reject!,
            },
          },
          category: buttons ? kAiPermissionCategory : null,
          tag: buttons ? push.tag : null,
        ),
      );
    } catch (_) {
      // A notification must never break anything.
    }
  }

  /// A ShellX session (title `<machine> · Phiên <index>`).
  SessionNotifier forShell({required int sessionId, required int index}) =>
      SessionNotifier._(this, sessionId, (text) => text.shellSession(index));

  /// A shared desktop terminal (title `<machine> · <app> — <window title>`).
  /// [app] and [title] are read when a notification is built.
  SessionNotifier forDesktop({
    required int sessionId,
    required String Function() app,
    required String Function() title,
  }) => SessionNotifier._(
    this,
    sessionId,
    (text) => text.desktopSession(app(), title()),
  );
}

/// Watches one session's live output for OSC events and sends the
/// resulting notifications. [feed] never throws and never blocks: parsing
/// is a pass over bytes the agent already read, sending is fire and forget.
final class SessionNotifier {
  SessionNotifier._(this._owner, this.sessionId, this._label)
    : _tracker = CommandTracker(
        threshold: _owner.config.threshold,
        now: _owner._now,
      );

  final AgentNotifications _owner;
  final int sessionId;
  final String Function(NotificationText text) _label;
  final _parser = OscEventParser();
  final CommandTracker _tracker;

  /// Live output only — never a replayed snapshot (N11).
  void feed(Uint8List data) {
    try {
      for (final event in _parser.feed(data)) {
        _handle(event);
      }
    } catch (_) {
      // A notification must never break the session.
    }
  }

  /// A new connection starts mid-stream: a half-read sequence is dropped.
  /// A command that started before keeps running.
  void resetParser() => _parser.reset();

  /// A replayed snapshot (never notifies, N11). When the last command event
  /// in it is an end (`133;D`), the command that was running ended while
  /// the link was down: it is forgotten, so a later live `D` does not merge
  /// two commands. A snapshot that ends with a start (or has none) keeps
  /// the running command.
  void snapshot(Uint8List data) {
    try {
      OscEvent? last;
      for (final event in OscEventParser().feed(data)) {
        if (event is CommandStarted || event is CommandFinished) last = event;
      }
      if (last is CommandFinished) _tracker.abandon();
    } catch (_) {
      // Never break the session.
    }
  }

  /// A program's message (OSC 9/777 or `shellx notify`, A7 D23).
  void message({String? title, required String body}) {
    try {
      final text = _text();
      _owner.sender.send(
        AgentNotification(
          title: title ?? _title(text),
          body: body,
          data: _data('message'),
        ),
      );
    } catch (_) {
      // A notification must never break the session.
    }
  }

  void _handle(OscEvent event) {
    if (event is NotifyRequested) {
      message(title: event.title, body: event.body);
      return;
    }
    final completed = _tracker.handle(event);
    if (completed == null) return;
    final text = _text();
    _owner.sender.send(
      AgentNotification(
        title: _title(text),
        body: text.commandBody(completed),
        data: _data('command'),
      ),
    );
  }

  NotificationText _text() {
    try {
      return NotificationText(_owner.config.locale());
    } catch (_) {
      return NotificationText('en');
    }
  }

  String _title(NotificationText text) {
    String machine;
    try {
      machine = _owner.config.machineName();
    } catch (_) {
      machine = '';
    }
    return text.title(machine, _label(text));
  }

  Map<String, String> _data(String kind) => {
    'session_id': '$sessionId',
    'kind': kind,
  };
}
