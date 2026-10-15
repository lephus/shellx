import 'dart:async';
import 'dart:convert';

import 'package:shellx_core/shellx_core.dart';

/// One push notification, as `POST /v1/notifications` takes it.
final class AgentNotification {
  const AgentNotification({
    required this.title,
    required this.body,
    this.data = const {},
    this.category,
    this.tag,
  });
  final String title;
  final String body;
  final Map<String, String> data;

  /// V2-2b B6: the buttons the phone shows (`ai_perm`), and the tag of the
  /// notification (Android) a notification with buttons takes the place of;
  /// null: none. An older relay ignores both.
  final String? category;
  final String? tag;

  @override
  String toString() => 'AgentNotification($title, $body, $data)';
}

/// Sends notifications through the relay (push spec §4.3, N10).
///
/// - At most [maxPerWindow] (6) notifications in any [window] (60 s);
///   beyond that a notification is dropped and counted ([droppedByLimit]).
/// - Fire and forget: [send] returns at once and never throws. A failed
///   request (no network, `404` from an old relay, `503 push_unavailable`,
///   `429`, `401` — the relay connection's own `AgentRevoked` flow handles
///   a revoked agent) drops that notification: no queue, no retry, since a
///   notification minutes late is usually meaningless.
/// - A `202 {sent: 0}` (no paired phone can receive it) pauses sending for
///   [pauseWhenUnheard] (15 min): no notification text leaves the computer
///   while nobody would see it. The pause ends after that time, when a phone
///   connects to the agent ([resume]: it may just have allowed push), or with
///   a new sender (a new runtime); a later `sent > 0` also clears it.
final class NotificationSender {
  NotificationSender({
    required ShellxApi api,
    this.maxPerWindow = 6,
    this.window = const Duration(seconds: 60),
    this.pauseWhenUnheard = const Duration(minutes: 15),
    DateTime Function()? now,
    void Function(String message)? log,
  }) : _api = api,
       _now = now ?? DateTime.now,
       _log = log;

  /// Relay limits (push spec §5).
  static const int maxTitleLength = 200;
  static const int maxBodyLength = 1000;

  /// The relay refuses title + body + data over 3584 bytes of UTF-8; the
  /// body is shortened to stay under this.
  static const int maxPayloadBytes = 3584;

  final ShellxApi _api;
  final int maxPerWindow;
  final Duration window;
  final Duration pauseWhenUnheard;
  final DateTime Function() _now;
  final void Function(String message)? _log;
  final _recent = <DateTime>[];

  int _droppedByLimit = 0;
  int _droppedWhilePaused = 0;
  DateTime? _pausedUntil;
  int _failed = 0;
  int _inFlight = 0;
  Completer<void>? _idle;

  /// Notifications refused by the per-minute limit so far.
  int get droppedByLimit => _droppedByLimit;

  /// Notifications not sent because the last one reached no phone.
  int get droppedWhilePaused => _droppedWhilePaused;

  /// Notifications whose request failed so far.
  int get failed => _failed;

  /// Completes when no request is in flight (tests).
  Future<void> get idle =>
      _inFlight == 0 ? Future.value() : (_idle ??= Completer<void>()).future;

  /// A phone connected to the agent: it may have just allowed notifications,
  /// so the pause after an unheard notification ends now.
  void resume() => _pausedUntil = null;

  /// Returns false when [notification] was dropped by the limit.
  bool send(AgentNotification notification) {
    try {
      final now = _now();
      final pausedUntil = _pausedUntil;
      if (pausedUntil != null) {
        if (now.isBefore(pausedUntil)) {
          _droppedWhilePaused++;
          return false;
        }
        _pausedUntil = null;
      }
      _recent.removeWhere((t) => now.difference(t) >= window);
      if (_recent.length >= maxPerWindow) {
        _droppedByLimit++;
        _log?.call(
          'notification dropped: over $maxPerWindow per ${window.inSeconds} s '
          '($_droppedByLimit dropped so far)',
        );
        return false;
      }
      _recent.add(now);
      _inFlight++;
      unawaited(_deliver(notification));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _deliver(AgentNotification n) async {
    try {
      final title = _clip(n.title, maxTitleLength);
      var dataBytes = 0;
      n.data.forEach((k, v) => dataBytes += _bytes(k) + _bytes(v));
      var body = _clip(n.body, maxBodyLength);
      var max = body.runes.length;
      while (max > 1 &&
          _bytes(title) + _bytes(body) + dataBytes > maxPayloadBytes) {
        max = max * 3 ~/ 4;
        body = _clip(n.body, max);
      }
      final sent = await _api.sendNotification(
        title,
        body,
        data: n.data,
        category: n.category,
        tag: n.tag,
      );
      if (sent == 0) {
        _pausedUntil = _now().add(pauseWhenUnheard);
        _log?.call(
          'no phone received the notification: paused for '
          '${pauseWhenUnheard.inMinutes} min',
        );
      } else {
        _pausedUntil = null;
      }
    } catch (error) {
      _failed++;
      final code = error is ApiException ? error.code : error.runtimeType;
      _log?.call('notification not sent ($code)');
    } finally {
      _inFlight--;
      if (_inFlight == 0) {
        _idle?.complete();
        _idle = null;
      }
    }
  }

  static int _bytes(String text) => utf8.encode(text).length;

  static String _clip(String text, int max) {
    final runes = text.runes;
    return runes.length <= max
        ? text
        : '${String.fromCharCodes(runes.take(max - 1))}…';
  }
}
