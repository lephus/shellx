import 'package:flutter/foundation.dart';

import 'agent_status.dart';

/// A12 D10: at most one hook notification per pane in this time.
const Duration kAgentNoticeGap = Duration(seconds: 5);

/// A12 D10: an OSC / bell notice this soon after a hook event of the same
/// pane is the same news (merged).
const Duration kAgentOscMerge = Duration(seconds: 3);

/// The words of a notification.
enum AgentNoticeText {
  /// The agent's message when it sent one, else "{agent} needs your input".
  needsInput,

  /// "{agent} finished".
  done,

  /// Only the agent's message.
  message,
}

/// What to tell the user about an event; [none] says nothing.
@immutable
final class AgentNotifyDecision {
  const AgentNotifyDecision._(this.text, this.message);
  static const AgentNotifyDecision none = AgentNotifyDecision._(null, null);

  /// Null: nothing to tell.
  final AgentNoticeText? text;

  /// The cleaned message of the event, when it had one.
  final String? message;

  bool get notify => text != null;

  @override
  String toString() => '…';
}

/// A12 D10: which events become a notification. Pure; the notification
/// itself goes through `LocalSessions.notify`, the path of `shellx notify`.
abstract final class AgentNotifyPolicy {
  /// [prev] is the record before [e]; [threshold] is the A4 long-command
  /// threshold (null = the user turned those off); [lastNoticeAt] is when
  /// a hook notification of this pane was last made (by event time).
  static AgentNotifyDecision decide(
    AgentEvent e,
    AgentPane? prev, {
    required bool paneVisible,
    required Duration? threshold,
    required DateTime? lastNoticeAt,
  }) {
    if (lastNoticeAt != null &&
        e.at.difference(lastNoticeAt) < kAgentNoticeGap) {
      return AgentNotifyDecision.none;
    }
    switch (e.kind) {
      case AgentEventKind.needsInput:
        return AgentNotifyDecision._(AgentNoticeText.needsInput, e.message);
      case AgentEventKind.idle:
        final since = prev?.runningSince;
        if (threshold == null ||
            paneVisible ||
            prev?.state != AgentState.running ||
            since == null ||
            e.at.difference(since) < threshold) {
          return AgentNotifyDecision.none;
        }
        return const AgentNotifyDecision._(AgentNoticeText.done, null);
      case AgentEventKind.notice:
        final m = e.message;
        return m == null
            ? AgentNotifyDecision.none
            : AgentNotifyDecision._(AgentNoticeText.message, m);
      case AgentEventKind.start:
      case AgentEventKind.running:
      case AgentEventKind.end:
        return AgentNotifyDecision.none;
    }
  }
}
