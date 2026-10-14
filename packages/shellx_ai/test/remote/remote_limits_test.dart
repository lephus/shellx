import 'dart:math';

import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:test/test.dart';

// Edges of the sync that the main tests do not reach: a body must never pass
// kAiBodyBytes (one oversize message drops the whole channel, terminals too),
// and a phone must never keep half a text once it asks again.

final t0 = DateTime.utc(2026, 10, 14, 9);

AiSessionState fresh() =>
    AiSessionState(agentId: 'claude', agentName: 'Claude', cwd: '/p');

void update(AiSessionState s, Map<String, Object?> json) =>
    s.applyUpdate(SessionUpdate.fromJson(json), t0);

void say(AiSessionState s, String text) => update(s, {
  'sessionUpdate': 'agent_message_chunk',
  'content': {'type': 'text', 'text': text},
});

void tool(AiSessionState s, String id, Map<String, Object?> fields) =>
    update(s, {'sessionUpdate': 'tool_call', 'toolCallId': id, ...fields});

/// A plan of [steps] lines: a header of more than 1 KiB, which is all a body
/// keeps for its envelope around a record.
void plan(AiSessionState s, int steps) => update(s, {
  'sessionUpdate': 'plan',
  'entries': [
    for (var i = 0; i < steps; i++)
      {
        'content': 'Step $i: ${'update the cart screen and its tests ' * 3}',
        'status': 'pending',
        'priority': 'medium',
      },
  ],
});

/// 32 KiB of text that is mostly newlines: about 47.6 KB once escaped, a
/// record just under [kAiRecordBytes], the largest one sent whole.
final nearMaxText = '\n' * 14800 + 'x' * (32768 - 14800);

/// Feeds every body to [mirror] in order, like the phone does.
bool feed(AiMirror mirror, List<AiOutgoing> out) {
  var ok = true;
  for (final o in out) {
    final body = decodeBody(o.body)!;
    expect(o.body.length, lessThanOrEqualTo(kAiBodyBytes));
    ok = mirror.apply(body, snapshot: o.snapshot) && ok;
  }
  return ok;
}

/// The mirror shows exactly what the desktop's timeline holds from [from].
void expectSame(AiMirror mirror, AiSessionState s) {
  final items = s.timeline.items;
  expect(mirror.end, items.length);
  for (var i = mirror.from; i < items.length; i++) {
    final m = mirror.at(i)!;
    expect(m.rev, items[i].rev, reason: 'rev $i');
    final text = itemText(items[i]);
    if (text != null) expect((m as MirrorText).text, text, reason: 'text $i');
  }
}

void main() {
  group('a body never passes kAiBodyBytes', () {
    test('a header with no room left for the next record goes alone', () {
      final s = fresh()..beginTurn(const [TextBlock('go')], t0);
      final sub = AiSubscription(s, generation: 1);
      final mirror = AiMirror();
      expect(feed(mirror, sub.attach(null)), isTrue);
      say(s, nearMaxText);
      plan(s, 10); // the header changes in the same flush
      final out = sub.delta();
      // The record really is a big one (else this test proves nothing).
      expect(
        out.map((o) => o.body.length).reduce(max),
        greaterThan(kAiBodyBytes - 3 * 1024),
      );
      expect(feed(mirror, out), isTrue);
      expectSame(mirror, s);
      expect(mirror.head!.plan, hasLength(10));
    });

    test('so does a snapshot whose first record is nearly the largest', () {
      final s = fresh();
      plan(s, 10);
      s.beginTurn([TextBlock(nearMaxText)], t0); // a pasted log, item 0
      final sub = AiSubscription(s, generation: 1);
      final out = sub.attach(null);
      expect(out.first.snapshot, isTrue);
      expect(
        out.map((o) => o.body.length).reduce(max),
        greaterThan(kAiBodyBytes - 3 * 1024),
      );
      final mirror = AiMirror();
      expect(feed(mirror, out), isTrue);
      expectSame(mirror, s);
      expect(mirror.head!.plan, hasLength(10));
    });
  });

  group('the phone never keeps half a text', () {
    test('a long text cut off by a lost channel comes whole after attach', () {
      final s = fresh()..beginTurn(const [TextBlock('write')], t0);
      final para = 'Dòng tiếng Việt có dấu, rất dài để thành nhiều mẩu.\n';
      say(s, para * 2500); // about 130 KB: five pieces of 32 KiB
      final sub = AiSubscription(s, generation: 1);
      final mirror = AiMirror();
      feed(mirror, sub.attach(null)); // the first piece; then the channel drops
      expect(
        (mirror.at(1)! as MirrorText).text.length,
        lessThan(para.length * 2500),
      );
      // The phone connects again and says what it holds.
      var out = sub.attach(mirror.have);
      var rounds = 0;
      while (true) {
        expect(feed(mirror, out), isTrue);
        for (final o in out) {
          sub.ack(o.seq);
        }
        if (!sub.dirty || ++rounds > 20) break;
        out = sub.delta();
      }
      // Short message first: a failing text compare prints all 130 KB.
      expect(
        (mirror.at(1)! as MirrorText).text.length,
        (s.timeline.items[1] as AgentTextItem).text.length,
      );
      expectSame(mirror, s);
    });

    test('a page of older items brings the start of a very long text', () {
      final s = fresh()..beginTurn(const [TextBlock('go')], t0);
      say(s, 'x' * 100000); // item 1
      for (var i = 0; i < 80; i++) {
        tool(s, 'c$i', {'title': 'Read $i', 'kind': 'read'});
      }
      final sub = AiSubscription(s, generation: 1);
      final mirror = AiMirror();
      feed(mirror, sub.attach(null));
      expect(mirror.from, 22);
      expect(feed(mirror, sub.earlier(mirror.from)), isTrue);
      expect((mirror.from, mirror.hasEarlier), (0, false));
      final long = mirror.at(1)! as MirrorText;
      expect(long.fullLength, 100000);
      expect(long.text.length, lessThan(100000));
      expect(long.rev, s.timeline.items[1].rev);
      // It is what the phone keeps: a re-attach does not send it again.
      final again = decodeBody(sub.attach(mirror.have).single.body)!;
      expect(again['reset'], isFalse);
      expect(again['items'], isEmpty);
    });
  });
}
