import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/agent_status.dart';

final now = DateTime.utc(2026, 10, 7, 12);
int ms(DateTime t) => t.millisecondsSinceEpoch;

Map<String, Object?> fields([Map<String, Object?> more = const {}]) => {
  'pane': 5,
  'agent': 'claude',
  'event': 'needs_input',
  'at': ms(now),
  ...more,
};

void main() {
  test('a valid map decodes', () {
    final e = decodeAgentEvent(
      fields({'session': 'a1b2', 'message': 'Allow Bash?', 'ok': false}),
      now: now,
    )!;
    expect(e.pane, 5);
    expect(e.agent, AgentKind.claude);
    expect(e.kind, AgentEventKind.needsInput);
    expect(e.at, now);
    expect((e.session, e.message, e.ok), ('a1b2', 'Allow Bash?', false));
  });

  test('every agent and event name decodes', () {
    for (final a in ['claude', 'codex', 'gemini', 'opencode']) {
      for (final k in [
        'start',
        'running',
        'needs_input',
        'idle',
        'end',
        'notice',
      ]) {
        expect(
          decodeAgentEvent(fields({'agent': a, 'event': k}), now: now),
          isNotNull,
          reason: '$a $k',
        );
      }
    }
  });

  test('pane not an int, unknown agent or event ⇒ null (bad_request)', () {
    expect(decodeAgentEvent(fields({'pane': '5'}), now: now), isNull);
    expect(decodeAgentEvent(fields({'pane': null}), now: now), isNull);
    expect(decodeAgentEvent(fields({'pane': 5.5}), now: now), isNull);
    expect(decodeAgentEvent(fields({'agent': 'cursor'}), now: now), isNull);
    expect(decodeAgentEvent(fields({'agent': 3}), now: now), isNull);
    expect(decodeAgentEvent(fields({'event': 'explode'}), now: now), isNull);
    expect(decodeAgentEvent(fields({'event': 'needsInput'}), now: now), isNull);
    expect(decodeAgentEvent({}, now: now), isNull);
  });

  test('a session failing the regex is dropped but the event is kept', () {
    for (final bad in [
      '',
      '-rf',
      'a b',
      'a;rm -rf ~',
      r'$(x)',
      'a\nb',
      'x' * 129,
      '.hidden',
    ]) {
      final e = decodeAgentEvent(fields({'session': bad}), now: now);
      expect(e, isNotNull, reason: bad);
      expect(e!.session, isNull, reason: bad);
    }
    expect(
      decodeAgentEvent(fields({'session': 'x' * 128}), now: now)!.session,
      'x' * 128,
    );
    expect(decodeAgentEvent(fields({'session': 7}), now: now)!.session, isNull);
  });

  test('message: controls become spaces, bidi marks go, 1024 characters', () {
    // RLO, LRI, LS, NEL among ordinary text.
    final dirty =
        'a\u0007b\nc${String.fromCharCodes([0x202e])}d'
        '${String.fromCharCodes([0x2066])}e${String.fromCharCodes([0x2028])}f'
        '${String.fromCharCodes([0x85])}g';
    final e = decodeAgentEvent(fields({'message': dirty}), now: now)!;
    expect(e.message, 'a b cdef g');
    final long = decodeAgentEvent(fields({'message': 'é' * 3000}), now: now)!;
    expect(long.message!.runes.length, 1024);
    expect(
      decodeAgentEvent(fields({'message': ' \n '}), now: now)!.message,
      isNull,
    );
    expect(decodeAgentEvent(fields({'message': 5}), now: now)!.message, isNull);
  });

  test('at outside ±10 min of now is replaced by now', () {
    DateTime at(int deltaSeconds) => decodeAgentEvent(
      fields({'at': ms(now.add(Duration(seconds: deltaSeconds)))}),
      now: now,
    )!.at;
    expect(at(-599), now.subtract(const Duration(seconds: 599)));
    expect(at(599), now.add(const Duration(seconds: 599)));
    expect(at(601), now);
    expect(at(-601), now);
    expect(decodeAgentEvent(fields({'at': 'soon'}), now: now)!.at, now);
    expect(decodeAgentEvent(fields({'at': null}), now: now)!.at, now);
  });

  test('ok is true unless it is false; extra keys are ignored', () {
    expect(decodeAgentEvent(fields({'ok': true}), now: now)!.ok, isTrue);
    expect(decodeAgentEvent(fields({'ok': 'no'}), now: now)!.ok, isTrue);
    expect(decodeAgentEvent(fields({'ok': false}), now: now)!.ok, isFalse);
    expect(decodeAgentEvent(fields({'extra': 1}), now: now), isNotNull);
  });
}
