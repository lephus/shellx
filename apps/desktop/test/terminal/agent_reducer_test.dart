import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/agent_notify_policy.dart';
import 'package:shellx_desktop/src/terminal/agent_status.dart';

final t0 = DateTime.utc(2026, 10, 7, 12);

AgentEvent ev(AgentEventKind k, {int s = 0, String? session}) => AgentEvent(
  pane: 3,
  agent: AgentKind.claude,
  kind: k,
  at: t0.add(Duration(seconds: s)),
  session: session,
);

/// An event of an AI pane (V2-1 D3: its id is negative).
AgentEvent aiEv(AgentEventKind k, {int s = 0}) => AgentEvent(
  pane: -1,
  agent: AgentKind.claude,
  kind: k,
  at: t0.add(Duration(seconds: s)),
);

AgentPane? reduce(AgentPane? p, AgentEvent e, {bool visible = true}) =>
    reduceAgent(p, e, paneVisible: visible);

void main() {
  test('start → idle with the session id; running → running; end → no '
      'record', () {
    var p = reduce(null, ev(AgentEventKind.start, session: 'abc'))!;
    expect((p.state, p.session), (AgentState.idle, 'abc'));
    p = reduce(p, ev(AgentEventKind.running, s: 1))!;
    expect(
      (p.state, p.runningSince),
      (AgentState.running, t0.add(const Duration(seconds: 1))),
    );
    expect(reduce(p, ev(AgentEventKind.end, s: 2)), isNull);
  });

  test('idle becomes done only when the pane is not being watched', () {
    final r = reduce(null, ev(AgentEventKind.running))!;
    expect(
      reduce(r, ev(AgentEventKind.idle, s: 1), visible: true)!.state,
      AgentState.idle,
    );
    expect(
      reduce(r, ev(AgentEventKind.idle, s: 1), visible: false)!.state,
      AgentState.done,
    );
  });

  test('an older event is ignored (reordered hook processes)', () {
    final r = reduce(null, ev(AgentEventKind.running, s: 5))!;
    final after = reduce(r, ev(AgentEventKind.idle, s: 3))!;
    expect(after.state, AgentState.running);
    expect(after.lastEventAt, t0.add(const Duration(seconds: 5)));
  });

  test('end older than the current record is ignored (a new session already '
      'started)', () {
    final fresh = reduce(null, ev(AgentEventKind.start, s: 10, session: 'b'))!;
    final after = reduce(fresh, ev(AgentEventKind.end, s: 4, session: 'a'));
    expect(after, isNotNull);
    expect(after!.session, 'b');
  });

  test('notice never changes the state, and creates no record', () {
    final r = reduce(null, ev(AgentEventKind.running))!;
    expect(reduce(r, ev(AgentEventKind.notice, s: 1)), same(r));
    expect(reduce(null, ev(AgentEventKind.notice)), isNull);
  });

  test('needs-input survives idle-prompt style noise but not a new prompt', () {
    var p = reduce(null, ev(AgentEventKind.needsInput))!;
    expect(p.state, AgentState.needsInput);
    p = reduce(p, ev(AgentEventKind.idle, s: 60), visible: false)!;
    expect(p.state, AgentState.needsInput); // "waiting for your input"
    p = reduce(p, ev(AgentEventKind.running, s: 61))!;
    expect(p.state, AgentState.running);
  });

  test('a repeated running keeps when the turn began', () {
    final a = reduce(null, ev(AgentEventKind.running))!;
    final b = reduce(a, ev(AgentEventKind.running, s: 9))!;
    expect(b.runningSince, t0);
    expect(b.since, t0);
  });

  test('a turn that waited for the user keeps its start', () {
    var p = reduce(null, ev(AgentEventKind.running))!;
    p = reduce(p, ev(AgentEventKind.needsInput, s: 4))!;
    p = userTyped(p, t0.add(const Duration(seconds: 9)));
    expect((p.state, p.runningSince), (AgentState.running, t0));
    p = reduce(p, ev(AgentEventKind.idle, s: 40), visible: false)!;
    expect((p.state, p.runningSince), (AgentState.done, t0));
  });

  test('an AI pane answered after a question keeps when its turn began '
      '(D13: the runtime reports running, nobody types)', () {
    var p = reduce(null, aiEv(AgentEventKind.start))!;
    p = reduce(p, aiEv(AgentEventKind.running))!;
    p = reduce(p, aiEv(AgentEventKind.needsInput, s: 290))!;
    expect(p.runningSince, t0);
    p = reduce(p, aiEv(AgentEventKind.running, s: 296))!;
    expect(
      (p.state, p.runningSince, p.since),
      (AgentState.running, t0, t0.add(const Duration(seconds: 296))),
      reason: 'a turn of 296 s, not of 0 s',
    );
    // The turn ends unwatched, 4 s after the last answer: finished, and
    // the long-turn notification (30 s by default) is due.
    final end = aiEv(AgentEventKind.idle, s: 300);
    expect(
      AgentNotifyPolicy.decide(
        end,
        p,
        paneVisible: false,
        threshold: const Duration(seconds: 30),
        lastNoticeAt: t0.add(const Duration(seconds: 290)),
      ).text,
      AgentNoticeText.done,
    );
    expect(reduce(p, end, visible: false)!.state, AgentState.done);
  });

  test('a terminal pane told running after a question starts a new turn '
      '(its typing is what answers: userTyped)', () {
    var p = reduce(null, ev(AgentEventKind.running))!;
    p = reduce(p, ev(AgentEventKind.needsInput, s: 290))!;
    p = reduce(p, ev(AgentEventKind.running, s: 296))!;
    expect(p.runningSince, t0.add(const Duration(seconds: 296)));
  });

  test('userTyped: needsInput → running; others unchanged', () {
    final now = t0.add(const Duration(seconds: 7));
    final n = reduce(null, ev(AgentEventKind.needsInput))!;
    final typed = userTyped(n, now);
    expect((typed.state, typed.since), (AgentState.running, now));
    for (final k in [AgentEventKind.running, AgentEventKind.start]) {
      final p = reduce(null, ev(k))!;
      expect(userTyped(p, now), same(p));
    }
  });

  test('paneSeen: done → idle; others unchanged', () {
    final done = reduce(
      reduce(null, ev(AgentEventKind.running))!,
      ev(AgentEventKind.idle, s: 1),
      visible: false,
    )!;
    expect(done.state, AgentState.done);
    expect(paneSeen(done, t0).state, AgentState.idle);
    final r = reduce(null, ev(AgentEventKind.running))!;
    expect(paneSeen(r, t0), same(r));
  });

  test('quietFor: running → idle, needsInput untouched', () {
    final r = reduce(null, ev(AgentEventKind.running))!;
    final q = quietFor(r, t0.add(kAgentQuietDecay));
    expect(q.state, AgentState.idle);
    expect(q.runningSince, isNull);
    final n = reduce(null, ev(AgentEventKind.needsInput))!;
    expect(quietFor(n, t0.add(kAgentQuietDecay)), same(n));
  });

  test(
    'aggregate priority',
    () => expect(
      aggregate([AgentState.idle, AgentState.done, AgentState.needsInput]),
      AgentState.needsInput,
    ),
  );

  test('aggregate: running > done > idle > unknown, empty is unknown', () {
    expect(
      aggregate([AgentState.idle, AgentState.running, AgentState.done]),
      AgentState.running,
    );
    expect(aggregate([AgentState.idle, AgentState.done]), AgentState.done);
    expect(aggregate([AgentState.unknown, AgentState.idle]), AgentState.idle);
    expect(aggregate(const []), AgentState.unknown);
  });

  test('the session id survives events that carry none, and a new id '
      'replaces it', () {
    var p = reduce(null, ev(AgentEventKind.start, session: 'abc'))!;
    p = reduce(p, ev(AgentEventKind.running, s: 1))!;
    expect(p.session, 'abc');
    p = reduce(p, ev(AgentEventKind.idle, s: 2))!;
    expect(p.session, 'abc');
    p = reduce(p, ev(AgentEventKind.running, s: 3, session: 'def'))!;
    expect(p.session, 'def');
  });

  test('toString hides everything', () {
    expect('${ev(AgentEventKind.running, session: 'secret')}', '…');
    expect('${reduce(null, ev(AgentEventKind.start, session: 'secret'))}', '…');
  });
}
