import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:test/test.dart';

final _at = DateTime.utc(2026, 10, 15, 9);

AiSessionState _state() =>
    AiSessionState(agentId: 'claude', agentName: 'Claude', cwd: '/p');

/// The phone's copy of [s], made the way the hub sends it.
AiMirror _mirror(AiSessionState s) {
  final mirror = AiMirror();
  final sub = AiSubscription(s, generation: 1);
  var out = sub.attach(null);
  for (var round = 0; round < 100; round++) {
    for (final o in out) {
      expect(mirror.apply(decodeBody(o.body)!, snapshot: o.snapshot), isTrue);
      sub.ack(o.seq);
    }
    if (!sub.dirty) break;
    out = sub.delta();
  }
  return mirror;
}

/// V2-2b B24: a phone's prompt is marked `src: phone` on the wire; the
/// computer's carries no key (what an older phone reads stays the same).
void main() {
  test('the record of a phone\'s prompt says src phone; the computer\'s '
      'says nothing', () {
    final s = _state()
      ..beginTurn(const [TextBlock('a')], _at, source: PromptSource.phone)
      ..endTurn(outcome: TurnOutcome.finished, at: _at)
      ..beginTurn(const [TextBlock('b')], _at);
    final users = [
      for (final (i, item) in s.timeline.items.indexed)
        if (item is UserItem) encodeItem(item, i),
    ];
    expect(users.first['src'], 'phone');
    expect(users.last.containsKey('src'), isFalse);
  });

  test('the phone\'s mirror knows which prompts it wrote, also of a long one '
      'that came in pieces', () {
    final s = _state()
      ..beginTurn(
        [TextBlock('x' * (kAiRecordBytes * 2))],
        _at,
        source: PromptSource.phone,
      )
      ..endTurn(outcome: TurnOutcome.finished, at: _at)
      ..beginTurn(const [TextBlock('ở máy tính')], _at);
    final texts = _mirror(s).items.whereType<MirrorText>().toList();
    expect(texts.first.text.length, kAiRecordBytes * 2);
    expect(texts.map((t) => t.fromPhone), [true, false]);
  });
}
