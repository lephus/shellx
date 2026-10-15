import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:test/test.dart';

final _at = DateTime.utc(2026, 10, 15, 9);

AiSessionState _state() =>
    AiSessionState(agentId: 'claude', agentName: 'Claude', cwd: '/p');

/// V2-2b B24: a prompt keeps who wrote it, in the timeline and in the queue.
void main() {
  test('a turn begun from the phone says so; one from the computer is the '
      'default', () {
    final s = _state()
      ..beginTurn(const [TextBlock('Sửa lỗi')], _at, source: PromptSource.phone)
      ..endTurn(outcome: TurnOutcome.finished, at: _at)
      ..beginTurn(const [TextBlock('Thêm test')], _at);
    final users = s.timeline.items.whereType<UserItem>().toList();
    expect(users.map((u) => u.source), [
      PromptSource.phone,
      PromptSource.computer,
    ]);
  });

  test('a queued prompt keeps its source until it is taken', () {
    final s = _state()..beginTurn(const [TextBlock('go')], _at);
    s.enqueue(const [TextBlock('from the phone')], source: PromptSource.phone);
    s.enqueue(const [TextBlock('from the computer')]);
    expect(s.takeQueued()!.source, PromptSource.phone);
    expect(s.takeQueued()!.source, PromptSource.computer);
  });

  test('a conversation replayed by session/load reads as the computer\'s '
      '(the agent keeps no source)', () {
    final s = _state()
      ..applyUpdate(
        SessionUpdate.fromJson({
          'sessionUpdate': 'user_message_chunk',
          'content': {'type': 'text', 'text': 'q1'},
        }),
        _at,
        history: true,
      );
    expect(
      s.timeline.items.whereType<UserItem>().single.source,
      PromptSource.computer,
    );
  });
}
