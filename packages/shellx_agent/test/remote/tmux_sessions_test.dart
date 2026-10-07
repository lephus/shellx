import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

void main() {
  test('parses tab-separated sessions and skips noise (D25)', () {
    final sessions = parseTmuxSessions(
      'Welcome to the server\n'
      'main\t3\t0\t1759831200\n'
      'my build\t1\t2\t1759744800\n'
      'bad:name\t1\t0\t1\n'
      'short\t1\n',
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
        const CommandResult(0, 'a\t1\t0\t1\n', ''),
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
}
