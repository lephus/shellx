import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/agent_notify_policy.dart';
import 'package:shellx_desktop/src/terminal/agent_status.dart';

final t0 = DateTime.utc(2026, 10, 7, 12);
const threshold = Duration(seconds: 30);

AgentEvent ev(AgentEventKind k, {int s = 0, String? message}) => AgentEvent(
  pane: 3,
  agent: AgentKind.claude,
  kind: k,
  at: t0.add(Duration(seconds: s)),
  message: message,
);

AgentPane running({int s = 0}) => AgentPane(
  agent: AgentKind.claude,
  state: AgentState.running,
  since: t0.add(Duration(seconds: s)),
  lastEventAt: t0.add(Duration(seconds: s)),
  runningSince: t0.add(Duration(seconds: s)),
);

AgentNotifyDecision decide(
  AgentEvent e, {
  AgentPane? prev,
  bool visible = false,
  Duration? limit = threshold,
  DateTime? last,
}) => AgentNotifyPolicy.decide(
  e,
  prev,
  paneVisible: visible,
  threshold: limit,
  lastNoticeAt: last,
);

void main() {
  test('needs_input always notifies: its message, else the default words', () {
    final withText = decide(
      ev(AgentEventKind.needsInput, message: 'Allow Bash?'),
      visible: true,
    );
    expect(
      (withText.text, withText.message),
      (AgentNoticeText.needsInput, 'Allow Bash?'),
    );
    final bare = decide(ev(AgentEventKind.needsInput));
    expect((bare.text, bare.message), (AgentNoticeText.needsInput, null));
  });

  test('idle: only a turn of the long-command threshold or more, in a pane '
      'nobody is watching', () {
    expect(
      decide(ev(AgentEventKind.idle, s: 2), prev: running()).notify,
      isFalse,
    );
    expect(
      decide(ev(AgentEventKind.idle, s: 29), prev: running()).notify,
      isFalse,
    );
    expect(
      decide(ev(AgentEventKind.idle, s: 30), prev: running()).text,
      AgentNoticeText.done,
    );
    expect(
      decide(ev(AgentEventKind.idle, s: 40), prev: running()).text,
      AgentNoticeText.done,
    );
    // Watched: no.
    expect(
      decide(
        ev(AgentEventKind.idle, s: 40),
        prev: running(),
        visible: true,
      ).notify,
      isFalse,
    );
    // The user turned long-command notices off.
    expect(
      decide(
        ev(AgentEventKind.idle, s: 40),
        prev: running(),
        limit: null,
      ).notify,
      isFalse,
    );
  });

  test('idle without a turn before it says nothing', () {
    expect(decide(ev(AgentEventKind.idle, s: 99)).notify, isFalse);
    final waiting = running().copyWith(state: AgentState.needsInput);
    expect(
      decide(ev(AgentEventKind.idle, s: 99), prev: waiting).notify,
      isFalse,
    );
    final idle = running().copyWith(state: AgentState.idle, runningSince: null);
    expect(decide(ev(AgentEventKind.idle, s: 99), prev: idle).notify, isFalse);
  });

  test('notice: only with a message; it names no state', () {
    expect(decide(ev(AgentEventKind.notice)).notify, isFalse);
    final d = decide(ev(AgentEventKind.notice, message: 'Subagent finished'));
    expect((d.text, d.message), (AgentNoticeText.message, 'Subagent finished'));
  });

  test('start, running and end never notify', () {
    for (final k in [
      AgentEventKind.start,
      AgentEventKind.running,
      AgentEventKind.end,
    ]) {
      expect(decide(ev(k, message: 'x')).notify, isFalse, reason: '$k');
    }
  });

  test('at most one hook notification per pane in 5 s', () {
    final e = ev(AgentEventKind.needsInput, s: 10);
    expect(decide(e, last: t0.add(const Duration(seconds: 6))).notify, isFalse);
    expect(decide(e, last: t0.add(const Duration(seconds: 5))).notify, isTrue);
    expect(decide(e, last: t0).notify, isTrue);
    expect(decide(e, last: null).notify, isTrue);
  });

  test('a decision shows nothing in toString', () {
    expect('${decide(ev(AgentEventKind.needsInput, message: 'secret'))}', '…');
  });
}
