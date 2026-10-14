import 'dart:math';

import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:test/test.dart';

// The mirror follows the desktop through any mix of updates, flushes, lost
// channels, re-attaches and "load earlier" (V2-2 review focus: no drift after
// a gap or a reconnect). Seeds are fixed, so a failure repeats: the reason
// names the seed.

final t0 = DateTime.utc(2026, 10, 14, 9);

const _pieces = [
  'hello ', 'world ', 'Mình ', 'sẽ ', 'thêm ', 'nút ', 'đăng ', 'xuất ', //
  '😀', '\n', '\n\n', '"', '\\', '\x01', ' ', '日本語', '    ', '{"a":1}',
];

String _text(Random r, int approx) {
  final b = StringBuffer();
  while (b.length < approx) {
    b.write(_pieces[r.nextInt(_pieces.length)]);
  }
  return b.toString();
}

/// Mostly short, sometimes a few KB, rarely over one 32 KiB piece.
int _size(Random r) {
  final p = r.nextInt(100);
  if (p < 70) return 1 + r.nextInt(60);
  if (p < 93) return 200 + r.nextInt(6000);
  if (p < 98) return 20000 + r.nextInt(40000);
  return 100000 + r.nextInt(120000);
}

/// Delivers [out] in order, acknowledging each; false when the mirror asked
/// to attach again.
bool _deliver(AiMirror mirror, AiSubscription sub, List<AiOutgoing> out) {
  var ok = true;
  for (final o in out) {
    expect(o.body.length, lessThanOrEqualTo(kAiBodyBytes));
    ok = mirror.apply(decodeBody(o.body)!, snapshot: o.snapshot) && ok;
    sub.ack(o.seq);
  }
  return ok;
}

void _session(int seed, {required int steps}) {
  final r = Random(seed);
  final why = 'seed $seed';
  final s = AiSessionState(agentId: 'claude', agentName: 'Claude', cwd: '/p')
    ..setPhase(AgentPhase.ready);
  AiSubscription newSub() =>
      AiSubscription(s, generation: 1, windowBytes: 96 * 1024);
  var sub = newSub();
  final mirror = AiMirror();
  var attached = false;
  var toolId = 0;
  var turnOpen = false;
  final openTools = <String>[];

  void update(Map<String, Object?> json) =>
      s.applyUpdate(SessionUpdate.fromJson(json), t0);

  void attach({bool fresh = false}) {
    if (fresh) sub = newSub();
    final have = attached ? mirror.have : null;
    expect(_deliver(mirror, sub, sub.attach(have)), isTrue, reason: why);
    attached = true;
  }

  void flush({double loss = 0}) {
    if (!attached) return attach();
    final out = sub.delta();
    if (loss > 0 && out.isNotEmpty && r.nextDouble() < loss) {
      // The channel drops after some of the bodies; the hub forgets the
      // phone, which connects again and says what it holds.
      _deliver(mirror, sub, out.take(r.nextInt(out.length + 1)).toList());
      return attach(fresh: true);
    }
    if (!_deliver(mirror, sub, out)) attach(); // a gap: ask again
  }

  Map<String, Object?> textContent(String text) => {
    'type': 'content',
    'content': {'type': 'text', 'text': text},
  };

  for (var step = 0; step < steps; step++) {
    final p = r.nextInt(100);
    if (p < 28) {
      if (!turnOpen) {
        s.beginTurn([TextBlock(_text(r, _size(r)))], t0);
        turnOpen = true;
      } else {
        update({
          'sessionUpdate': 'agent_message_chunk',
          'content': {'type': 'text', 'text': _text(r, _size(r))},
        });
      }
    } else if (p < 33) {
      if (turnOpen) {
        update({
          'sessionUpdate': 'agent_thought_chunk',
          'content': {'type': 'text', 'text': _text(r, _size(r))},
        });
      }
    } else if (p < 48) {
      if (turnOpen) {
        final id = 'c${toolId++}';
        openTools.add(id);
        final big = r.nextInt(6) == 0;
        update({
          'sessionUpdate': 'tool_call',
          'toolCallId': id,
          'title': _text(r, 1 + r.nextInt(80)),
          'kind': ['read', 'edit', 'execute', 'other', 'search'][r.nextInt(5)],
          'status': 'in_progress',
          if (r.nextBool())
            'content': [
              textContent(_text(r, big ? 40000 + r.nextInt(80000) : _size(r))),
              if (r.nextInt(3) == 0)
                for (var d = 0; d < 1 + r.nextInt(5); d++)
                  {
                    'type': 'diff',
                    'path': '/p/f$d.ts',
                    'oldText': r.nextBool() ? null : _text(r, _size(r)),
                    'newText': _text(r, big ? 30000 : _size(r)),
                  },
            ],
          if (r.nextInt(4) == 0) 'rawInput': {'blob': _text(r, _size(r))},
        });
      }
    } else if (p < 58) {
      if (openTools.isNotEmpty) {
        update({
          'sessionUpdate': 'tool_call_update',
          'toolCallId': openTools[r.nextInt(openTools.length)],
          if (r.nextBool()) 'status': 'completed',
          if (r.nextInt(3) == 0) 'content': [textContent(_text(r, _size(r)))],
        });
      }
    } else if (p < 63) {
      if (openTools.isNotEmpty) {
        s.addPermission(
          PermissionRequest.fromJson({
            'sessionId': 's',
            'toolCall': {
              'toolCallId': openTools[r.nextInt(openTools.length)],
              'title': 'Edit ${_text(r, 20)}',
            },
            'options': [
              {'optionId': 'allow', 'name': 'Yes', 'kind': 'allow_once'},
              {'optionId': 'reject', 'name': 'No', 'kind': 'reject_once'},
            ],
          }),
          t0,
        );
      }
    } else if (p < 67) {
      if (s.permissions.isNotEmpty) {
        s.resolvePermission(
          s.permissions[r.nextInt(s.permissions.length)].id,
          r.nextBool()
              ? const PermissionSelected('allow')
              : const PermissionCancelled(),
        );
      }
    } else if (p < 70) {
      if (turnOpen) {
        s.addAsk(
          ElicitationRequest.fromJson({
            'mode': 'form',
            'message': _text(r, 30),
            'requestedSchema': {
              'type': 'object',
              'properties': {
                'a': {'type': 'boolean'},
              },
            },
          }),
        );
      }
    } else if (p < 72) {
      if (s.asks.isNotEmpty) {
        s.resolveAsk(s.asks.first.id, const ElicitDecline());
      }
    } else if (p < 74) {
      s.addNotice(const AgentExited(1));
    } else if (p < 78) {
      update({
        'sessionUpdate': 'plan',
        'entries': [
          for (var i = 0; i < r.nextInt(35); i++)
            {
              'content': _text(r, 1 + r.nextInt(700)),
              'status': 'pending',
              'priority': 'medium',
            },
        ],
      });
    } else if (p < 80) {
      s.enqueue([TextBlock(_text(r, 1 + r.nextInt(500)))]);
    } else if (p < 84) {
      if (turnOpen) {
        s.endTurn(
          outcome: TurnOutcome.finished,
          at: t0.add(Duration(seconds: r.nextInt(100))),
          changes: r.nextBool()
              ? const [
                  FileChange(
                    path: 'a',
                    kind: ChangeKind.modified,
                    added: 3,
                    removed: 1,
                  ),
                ]
              : null,
        );
        turnOpen = false;
        openTools.clear();
      }
    } else if (p < 92) {
      flush(loss: 0.15);
    } else if (p < 95) {
      attach(); // the phone asks again on the same subscription
    } else if (p < 98) {
      if (attached && mirror.hasEarlier) {
        expect(
          _deliver(mirror, sub, sub.earlier(mirror.from)),
          isTrue,
          reason: why,
        );
      }
    } else {
      attach(fresh: true); // a lost channel, nothing acknowledged
    }
  }

  var rounds = 0;
  while ((sub.dirty || !attached) && rounds++ < 500) {
    flush();
  }
  expect(sub.dirty, isFalse, reason: '$why: still sending after $rounds');

  final items = s.timeline.items;
  expect(mirror.end, items.length, reason: why);
  expect(mirror.count, items.length, reason: why);
  for (var i = mirror.from; i < items.length; i++) {
    final m = mirror.at(i)!;
    final item = items[i];
    expect(m.rev, item.rev, reason: '$why item $i rev');
    final text = itemText(item);
    if (text != null) {
      final held = (m as MirrorText).text;
      if (m.fullLength == null) {
        expect(held.length, text.length, reason: '$why item $i text length');
        expect(held == text, isTrue, reason: '$why item $i text');
      } else {
        // An older page brought only the start of a very long text.
        expect(m.fullLength, text.length, reason: '$why item $i clip');
        expect(text.startsWith(held), isTrue, reason: '$why item $i start');
      }
    } else {
      final ok = switch (item) {
        ToolItem() =>
          m is MirrorTool || (m is MirrorUnknown && m.kind == 'big'),
        AskItem() => m is MirrorAsk,
        TurnEndItem() => m is MirrorTurnEnd,
        NoticeItem() => m is MirrorNotice,
        _ => false,
      };
      expect(ok, isTrue, reason: '$why item $i is ${m.runtimeType}');
    }
  }
  final head = mirror.head!;
  expect(head.phase, s.phase.name, reason: why);
  expect(head.plan.length, min(30, s.plan.length), reason: why);
  expect(head.queue.length, s.queue.length, reason: why);
  expect(head.permission?.id, s.currentPermission?.id, reason: why);
  expect(head.ask?.id, s.currentAsk?.id, reason: why);
  expect(head.turn?.index, s.turn?.index, reason: why);
}

void main() {
  test('the mirror equals the desktop after any mix of events', () {
    for (var seed = 1; seed <= 30; seed++) {
      _session(seed, steps: 100);
    }
  });
}
