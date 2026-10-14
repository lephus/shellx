import 'dart:convert';

import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:test/test.dart';

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

PermissionRequest perm(String toolCallId) => PermissionRequest.fromJson({
  'sessionId': 's',
  'toolCall': {'toolCallId': toolCallId, 'title': 'Edit main.ts'},
  'options': [
    {'optionId': 'allow', 'name': 'Yes', 'kind': 'allow_once'},
    {
      'optionId': 'always',
      'name': 'Yes, allow all edits',
      'kind': 'allow_always',
    },
    {'optionId': 'reject', 'name': 'No', 'kind': 'reject_once'},
  ],
});

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

/// A finished tool call [i] (`t$i`) with about 1 KB of output.
void heavyTool(AiSessionState s, int i) => tool(s, 't$i', {
  'title': 'Run $i',
  'kind': 'execute',
  'status': 'completed',
  'content': [
    {
      'type': 'content',
      'content': {'type': 'text', 'text': 'line of call $i\n' * 60},
    },
  ],
});

/// Every body [sub] has to send, fed to [mirror] and acknowledged as the
/// phone does, until nothing is left to send.
List<AiOutgoing> drain(AiSubscription sub, AiMirror mirror) {
  final sent = <AiOutgoing>[];
  for (var round = 0; sub.dirty && round < 100; round++) {
    final out = sub.delta();
    expect(feed(mirror, out), isTrue);
    for (final o in out) {
      sub.ack(o.seq);
    }
    sent.addAll(out);
  }
  expect(sub.dirty, isFalse);
  return sent;
}

int bytesOf(List<AiOutgoing> out) => out.fold(0, (n, o) => n + o.body.length);

/// Item records in [out].
int recordsIn(List<AiOutgoing> out) =>
    out.fold(0, (n, o) => n + (decodeBody(o.body)!['items'] as List).length);

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
  group('subscription and mirror (D5)', () {
    test('attach, stream, permission: the mirror follows exactly', () {
      final s = fresh()..setPhase(AgentPhase.ready);
      s.beginTurn(const [TextBlock('Thêm nút đăng xuất')], t0);
      final sub = AiSubscription(s, generation: 7);
      final mirror = AiMirror();
      final first = sub.attach(null);
      expect(first.first.snapshot, isTrue);
      expect(feed(mirror, first), isTrue);
      expectSame(mirror, s);
      expect(mirror.head!.turn!.index, 1);

      say(s, 'Mình sẽ ');
      say(s, 'thêm nút.');
      final d = sub.delta();
      expect(d, hasLength(1));
      final record =
          (decodeBody(d.single.body)!['items'] as List).single as Map;
      expect((record['at'], record['add']), (0, 'Mình sẽ thêm nút.'));
      expect(feed(mirror, d), isTrue);
      say(s, ' Xong.');
      final d2 = sub.delta();
      final r2 = (decodeBody(d2.single.body)!['items'] as List).single as Map;
      expect((r2['at'], r2['add']), ('Mình sẽ thêm nút.'.length, ' Xong.'));
      feed(mirror, d2);
      expectSame(mirror, s);

      tool(s, 'c1', {
        'title': 'Edit main.ts',
        'kind': 'edit',
        'status': 'pending',
      });
      s.addPermission(perm('c1'), t0);
      feed(mirror, sub.delta());
      final p = mirror.head!.permission!;
      expect((p.title, p.item), ('Edit main.ts', 2));
      expect(p.options.map((o) => o.kind), [
        PermissionKind.allowOnce,
        PermissionKind.allowAlways,
        PermissionKind.rejectOnce,
      ]);
      expect(
        (mirror.at(2)! as MirrorTool).permission,
        MirrorPermissionState.waiting,
      );
      expect(sub.delta(), isEmpty); // nothing changed
    });

    test('a re-attach with what the phone holds brings only what changed', () {
      final s = fresh()..beginTurn(const [TextBlock('go')], t0);
      for (var i = 0; i < 10; i++) {
        tool(s, 'c$i', {'title': 'Read f$i', 'kind': 'read'});
      }
      final sub = AiSubscription(s, generation: 1);
      final mirror = AiMirror();
      feed(mirror, sub.attach(null));
      final have = AiHave.fromJson(
        jsonDecode(jsonEncode(mirror.have.toJson())) as Map<String, Object?>,
      );
      update(s, {
        'sessionUpdate': 'tool_call_update',
        'toolCallId': 'c3',
        'status': 'completed',
      });
      say(s, 'done');
      final again = sub.attach(have);
      final body = decodeBody(again.single.body)!;
      expect(body['reset'], isFalse);
      expect((body['items'] as List).map((r) => (r as Map)['i']), [4, 11]);
      expect(feed(mirror, again), isTrue);
      expectSame(mirror, s);
    });

    test('another generation, or too much new, starts over', () {
      final s = fresh()..beginTurn(const [TextBlock('go')], t0);
      final sub = AiSubscription(s, generation: 2);
      final mirror = AiMirror();
      feed(mirror, sub.attach(null));
      final stale = AiHave(generation: 1, from: 0, revs: mirror.have.revs);
      final again = decodeBody(sub.attach(stale).first.body)!;
      expect(again['reset'], isTrue);
      for (var i = 0; i < 200; i++) {
        tool(s, 'c$i', {'title': 'Read $i', 'kind': 'read'});
      }
      final far = decodeBody(sub.attach(mirror.have).first.body)!;
      expect((far['reset'], far['from']), (true, 201 - kAiAttachItems));
    });

    test('a 200 KB answer goes in pieces within the window; acks open it', () {
      final s = fresh()..beginTurn(const [TextBlock('write')], t0);
      final sub = AiSubscription(s, generation: 1, windowBytes: 64 * 1024);
      final mirror = AiMirror();
      feed(mirror, sub.attach(null));
      sub.ack(1);
      final para = 'Dòng tiếng Việt có dấu, "trích dẫn" và \\ gạch.\n';
      say(s, para * 4000);
      var rounds = 0;
      while (sub.dirty && rounds < 100) {
        final out = sub.delta();
        expect(sub.unackedBytes, lessThanOrEqualTo(64 * 1024 + kAiBodyBytes));
        expect(feed(mirror, out), isTrue);
        for (final o in out) {
          sub.ack(o.seq);
        }
        rounds++;
      }
      expect(rounds, greaterThan(3));
      expectSame(mirror, s);
    });

    test('load earlier: pages of whole items, continuing downwards', () {
      final s = fresh()..beginTurn(const [TextBlock('go')], t0);
      for (var i = 0; i < 150; i++) {
        tool(s, 'c$i', {'title': 'Read $i', 'kind': 'read'});
      }
      final sub = AiSubscription(s, generation: 1);
      final mirror = AiMirror();
      feed(mirror, sub.attach(null));
      expect((mirror.from, mirror.hasEarlier), (151 - kAiAttachItems, true));
      expect(feed(mirror, sub.earlier(mirror.from)), isTrue);
      expect(mirror.from, 151 - 2 * kAiAttachItems);
      expect(feed(mirror, sub.earlier(mirror.from)), isTrue);
      expect((mirror.from, mirror.hasEarlier), (0, false));
      expectSame(mirror, s);
      expect(sub.earlier(0), isEmpty);
    });

    test('a missing body is found: apply answers false', () {
      final s = fresh()..beginTurn(const [TextBlock('go')], t0);
      final sub = AiSubscription(s, generation: 1);
      final mirror = AiMirror();
      feed(mirror, sub.attach(null));
      say(s, 'one');
      sub.delta(); // lost on the way
      say(s, ' two');
      expect(feed(mirror, sub.delta()), isFalse);
    });

    test('a phone far behind starts over from the last 60: one reset '
        'snapshot, not the whole history (D5)', () {
      final s = fresh()..setPhase(AgentPhase.ready);
      final sub = AiSubscription(s, generation: 1);
      final mirror = AiMirror();
      expect(feed(mirror, sub.attach(null)), isTrue); // nothing yet
      for (var i = 0; i < 400; i++) {
        heavyTool(s, i);
      }
      final sent = drain(sub, mirror);
      expect((mirror.from, mirror.items.length), (400 - kAiAttachItems, 60));
      expect(mirror.hasEarlier, isTrue);
      expectSame(mirror, s);
      expect(sent.where((o) => o.snapshot), hasLength(1));
      expect(recordsIn(sent), kAiAttachItems);
      // About 1 KB per card: 60 of them, not 400.
      expect(bytesOf(sent), lessThan(100 * 1024));

      // What comes next is an update again, after the 60.
      heavyTool(s, 400);
      final next = drain(sub, mirror);
      expect(next.map((o) => o.snapshot), everyElement(isFalse));
      expect((mirror.from, mirror.end), (400 - kAiAttachItems, 401));
      expectSame(mirror, s);
    });

    test('up to twice 60 items behind, the items come as updates', () {
      final s = fresh()..setPhase(AgentPhase.ready);
      final sub = AiSubscription(s, generation: 1);
      final mirror = AiMirror();
      feed(mirror, sub.attach(null));
      for (var i = 0; i < 2 * kAiAttachItems; i++) {
        heavyTool(s, i);
      }
      final sent = drain(sub, mirror);
      expect(sent.map((o) => o.snapshot), everyElement(isFalse));
      expect((mirror.from, mirror.end), (0, 2 * kAiAttachItems));
      // One more than that starts over.
      for (var i = 0; i <= 2 * kAiAttachItems; i++) {
        heavyTool(s, 1000 + i);
      }
      final over = drain(sub, mirror);
      expect(over.first.snapshot, isTrue);
      expect(decodeBody(over.first.body)!['reset'], isTrue);
      expect(mirror.from, s.timeline.items.length - kAiAttachItems);
      expectSame(mirror, s);
    });

    test('while the agent starts, new items wait: a history replayed then '
        'comes as its last 60, however slowly it came (D15)', () {
      final s = fresh()..setPhase(AgentPhase.starting);
      final sub = AiSubscription(s, generation: 1);
      final mirror = AiMirror();
      feed(mirror, sub.attach(null));
      for (var round = 0; round < 10; round++) {
        // 40 at a time: never twice 60 behind at one flush.
        for (var i = 0; i < 40; i++) {
          heavyTool(s, round * 40 + i);
        }
        drain(sub, mirror);
        expect(mirror.items, isEmpty);
      }
      expect(mirror.head!.phase, 'starting');
      s.setPhase(AgentPhase.ready);
      final sent = drain(sub, mirror);
      expect(mirror.head!.phase, 'ready');
      expect((mirror.from, mirror.items.length), (400 - kAiAttachItems, 60));
      expect(mirror.hasEarlier, isTrue);
      expect(recordsIn(sent), kAiAttachItems);
      expectSame(mirror, s);
    });

    test('a session that restarts keeps what the phone holds, and what '
        'changes in it still goes while the agent starts', () {
      final s = fresh()..setPhase(AgentPhase.ready);
      for (var i = 0; i < 10; i++) {
        heavyTool(s, i);
      }
      final sub = AiSubscription(s, generation: 1);
      final mirror = AiMirror();
      feed(mirror, sub.attach(null));
      s.setPhase(AgentPhase.starting); // "Khởi động lại"
      update(s, {
        'sessionUpdate': 'tool_call_update',
        'toolCallId': 't3',
        'status': 'failed',
      });
      heavyTool(s, 10); // new: it waits
      drain(sub, mirror);
      expect(mirror.end, 10);
      expect(mirror.at(3)!.rev, s.timeline.items[3].rev);
      s.setPhase(AgentPhase.ready);
      drain(sub, mirror);
      expect((mirror.from, mirror.end), (0, 11));
      expectSame(mirror, s);
    });

    test('toString of every remote type is …', () {
      final s = fresh()..beginTurn(const [TextBlock('secret')], t0);
      final sub = AiSubscription(s, generation: 1);
      final mirror = AiMirror();
      final out = sub.attach(null);
      feed(mirror, out);
      expect(
        {
          sub,
          mirror,
          out.first,
          mirror.head,
          mirror.at(0),
          mirror.have,
        }.map((o) => '$o').toSet(),
        {'…'},
      );
    });
  });
}
