import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

void main() {
  test('parses tab-separated sessions and skips noise (D25)', () {
    final sessions = parseTmuxSessions(
      'Welcome to the server\n'
      'SXTMUX\tmain\t3\t0\t1759831200\n'
      'SXTMUX\tmy build\t1\t2\t1759744800\n'
      'SXTMUX\tbad:name\t1\t0\t1\n'
      'SXTMUX\tshort\t1\n',
    );
    expect(sessions.map((s) => s.name), ['main', 'my build']);
    expect(sessions.first.windows, 3);
    expect(sessions.first.attachedElsewhere, isFalse);
    expect(sessions.last.attached, 2);
    expect(
      sessions.first.activity,
      DateTime.fromMillisecondsSinceEpoch(1759831200 * 1000),
    );
  });

  test('classifies results', () {
    expect(
      classifyTmuxList(
        const CommandResult(0, 'SXTMUX\ta\t1\t0\t1\n', ''),
        remote: false,
      ),
      isA<TmuxSessions>().having((r) => r.sessions.length, 'n', 1),
    );
    expect(
      classifyTmuxList(
        const CommandResult(
          1,
          '',
          'no server running on /tmp/tmux-501/default',
        ),
        remote: false,
      ),
      isA<TmuxSessions>().having((r) => r.sessions, 'sessions', isEmpty),
    );
    expect(
      classifyTmuxList(
        const CommandResult(
          1,
          '',
          'error connecting to /tmp/tmux-1000/default (No such file or directory)',
        ),
        remote: true,
      ),
      isA<TmuxSessions>(),
    );
    expect(
      classifyTmuxList(
        const CommandResult(127, '', 'sh: tmux: command not found'),
        remote: true,
      ),
      isA<TmuxUnavailable>(),
    );
    expect(
      classifyTmuxList(
        const CommandResult(255, '', 'Permission denied'),
        remote: true,
      ),
      isA<TmuxListFailed>().having(
        (r) => r.reason,
        'reason',
        TmuxListFailure.auth,
      ),
    );
    expect(
      classifyTmuxList(
        const CommandResult(-1, '', '', timedOut: true),
        remote: true,
      ),
      isA<TmuxListFailed>().having(
        (r) => r.reason,
        'reason',
        TmuxListFailure.timeout,
      ),
    );
    expect(
      classifyTmuxList(
        const CommandResult(1, '', 'something else'),
        remote: false,
      ),
      isA<TmuxListFailed>().having(
        (r) => r.reason,
        'reason',
        TmuxListFailure.other,
      ),
    );
  });

  test('rows need the sentinel; a name cannot spoof a row (L5)', () {
    expect(tmuxListFormat, startsWith('SXTMUX\t'));
    final sessions = parseTmuxSessions(
      'main\t1\t0\t1\n'
      'SXTMUX\tok\t1\t0\t1\n',
    );
    expect(sessions.map((s) => s.name), ['ok']);
  });

  test('hostile numbers never throw and are bounded (M2)', () {
    final sessions = parseTmuxSessions(
      'SXTMUX\ta\t1\t0\t99999999999999999\n'
      'SXTMUX\tb\t1\t0\t-5\n'
      'SXTMUX\tc\t-1\t0\t1\n'
      'SXTMUX\td\t1\t100001\t1\n'
      'SXTMUX\te\t99999999999999999999\t0\t1\n'
      'SXTMUX\tf\t2\t1\t253402300799\n',
    );
    expect(sessions.map((s) => s.name), ['a', 'b', 'f']);
    expect(sessions[0].activity, isNull);
    expect(sessions[1].activity, isNull);
    expect(sessions[2].activity, isNotNull);
  });

  test('at most 512 sessions (L4)', () {
    final text = [
      for (var i = 0; i < 600; i++) 'SXTMUX\ts$i\t1\t0\t1',
    ].join('\n');
    expect(parseTmuxSessions(text), hasLength(512));
  });
}
