import 'dart:convert';

import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_ai/src/remote/wire.dart'
    show clipText, headLines, plainText, tailLines, utf8Cut;
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
  group('wire helpers', () {
    test('a UTF-8 cut never splits a character or a surrogate pair', () {
      const s = 'aé😀b';
      expect(utf8Length(s), 1 + 2 + 4 + 1);
      expect(utf8Cut(s, 3), 2); // "aé"
      expect(utf8Cut(s, 6), 2); // the emoji (4 bytes) does not fit
      expect(utf8Cut(s, 7), 4);
      expect(clipText('Sửa lỗi giỏ hàng', 8), 'Sửa…');
    });

    test('head and tail keep whole lines; escapes are stripped', () {
      final text = List.generate(100, (i) => 'line $i').join('\n');
      final head = headLines(text, 30);
      final tail = tailLines(text, 30);
      expect(head.split('\n').every((l) => l.startsWith('line ')), isTrue);
      expect(text.startsWith(head), isTrue);
      expect(text.endsWith(tail), isTrue);
      expect(tail.split('\n').first, startsWith('line '));
      expect(plainText('\x1b[32mok\x1b[0m done\x1b]0;title\x07'), 'ok done');
    });
  });

  group('listing', () {
    test('round-trips; an unknown state reads as idle', () {
      const listing = AiListing(
        sessions: [
          AiSessionInfo(
            sid: 'e.1',
            agentId: 'claude',
            agentName: 'Claude',
            title: 'Nút đăng xuất',
            state: AiRemoteState.needsInput,
            cwd: '/Users/me/shop',
            since: 5,
            waiting: 'Sửa src/main.ts',
            acpSessionId: 'acp-1',
          ),
        ],
        agents: [AiAgentChoice(id: 'claude', name: 'Claude')],
        folders: [
          AiFolderChoice(key: 'ws:a', name: 'shop', path: '/Users/me/shop'),
        ],
        defaultAgent: 'claude',
      );
      final back = AiListing.fromJson(
        jsonDecode(jsonEncode(listing.toJson())) as Map<String, Object?>,
        available: true,
      );
      expect(back.toJson(), listing.toJson());
      expect(back.needsInput, 1);
      final odd = AiSessionInfo.fromJson({'sid': 'e.2', 'state': 'dreaming'})!;
      expect(odd.state, AiRemoteState.idle);
      expect(AiSessionInfo.fromJson({'state': 'idle'}), isNull);
    });

    test('what an agent or a folder name can make long is clipped, whole '
        'characters only', () {
      final long = 'Nút đăng xuất 😀 ' * 8000; // 130 000 characters
      final json = AiListing(
        sessions: [
          AiSessionInfo(
            sid: 'e.1',
            agentId: 'claude',
            agentName: long,
            title: long,
            state: AiRemoteState.needsInput,
            cwd: long,
            waiting: long,
            acpSessionId: long,
          ),
        ],
        agents: [AiAgentChoice(id: 'claude', name: long)],
        folders: [AiFolderChoice(key: 'ws:a', name: long, path: long)],
        defaultAgent: 'claude',
      ).toJson();
      expect(utf8Length(jsonEncode(json)), lessThan(3000));
      final back = AiListing.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, Object?>,
        available: true,
      );
      final s = back.sessions.single;
      final f = back.folders.single;
      final clipped = [
        (s.title, 200),
        (s.acpSessionId!, 200),
        (s.cwd!, 600),
        (s.waiting!, 240),
        (s.agentName, 200),
        (back.agents.single.name, 200),
        (f.name, 200),
        (f.path!, 600),
      ];
      for (final (text, limit) in clipped) {
        expect(utf8Length(text), lessThanOrEqualTo(limit));
        expect(text, endsWith('…'));
        // No half of a surrogate pair: UTF-8 takes the text back unchanged.
        expect(utf8.decode(utf8.encode(text)), text);
      }
      // What is short is left alone; the keys a phone sends back are not cut.
      expect((s.sid, s.state), ('e.1', AiRemoteState.needsInput));
      expect((f.key, back.agents.single.id), ('ws:a', 'claude'));
    });

    test('state of a session: a waiting question wins', () {
      final s = fresh();
      expect(aiRemoteStateOf(s), AiRemoteState.stopped);
      s.setPhase(AgentPhase.ready);
      expect(aiRemoteStateOf(s), AiRemoteState.idle);
      s.beginTurn(const [TextBlock('go')], t0);
      expect(aiRemoteStateOf(s), AiRemoteState.running);
      s.addPermission(perm('c1'), t0);
      expect(aiRemoteStateOf(s), AiRemoteState.needsInput);
      expect(aiWaitingOf(s), 'Edit main.ts');
    });

    test('toString never shows a title', () {
      const info = AiSessionInfo(
        sid: 'e.1',
        agentId: 'claude',
        agentName: 'Claude',
        title: 'secret',
        state: AiRemoteState.idle,
      );
      expect(
        '$info ${const AiListing(sessions: [info])}',
        isNot(contains('secret')),
      );
    });
  });

  group('questions travel in their ACP shape (D7)', () {
    test(
      'every field kind round-trips through ElicitationRequest.fromJson',
      () {
        final request =
            ElicitationRequest.fromJson({
                  'mode': 'form',
                  'message': 'Pick',
                  'requestedSchema': {
                    'type': 'object',
                    'title': 'T',
                    'properties': {
                      'name': {
                        'type': 'string',
                        'minLength': 1,
                        'maxLength': 9,
                        'default': 'a',
                      },
                      'n': {'type': 'integer', 'minimum': 1, 'maximum': 5},
                      'ok': {'type': 'boolean', 'default': true},
                      'one': {
                        'type': 'string',
                        'oneOf': [
                          {'const': 'x', 'title': 'X'},
                          {'const': 'y', 'title': 'Y'},
                        ],
                      },
                      'many': {
                        'type': 'array',
                        'items': {
                          'enum': ['p', 'q'],
                        },
                        'maxItems': 2,
                      },
                      'odd': {'type': 'object'},
                    },
                    'required': ['name', 'one'],
                  },
                })
                as ElicitationForm;
        final back =
            ElicitationRequest.fromJson(elicitationToJson(request))
                as ElicitationForm;
        expect(back.message, 'Pick');
        expect(back.title, 'T');
        expect(
          back.fields.map((f) => (f.key, f.required, f.runtimeType)).toList(),
          request.fields
              .map((f) => (f.key, f.required, f.runtimeType))
              .toList(),
        );
        expect(back.supported, isFalse); // 'odd' stays unsupported
        expect(
          back.accepts({
            'name': 'b',
            'one': 'x',
            'many': ['p'],
          }),
          isTrue,
        );
        expect(back.accepts({'name': 'b', 'one': 'z'}), isFalse);
        final url =
            ElicitationRequest.fromJson(
                  elicitationToJson(
                    const ElicitationUrl(
                      message: 'Sign in',
                      elicitationId: 'e1',
                      url: 'https://example.com',
                    ),
                  ),
                )
                as ElicitationUrl;
        expect((url.elicitationId, url.url), ('e1', 'https://example.com'));
      },
    );
  });

  group('items for the phone (§4.4)', () {
    test('a long tool output keeps its first and last lines, plain', () {
      final s = fresh()..beginTurn(const [TextBlock('run')], t0);
      final out = List.generate(
        5000,
        (i) => '\x1b[2mline $i\x1b[0m',
      ).join('\n');
      tool(s, 'c1', {
        'title': 'npm test',
        'kind': 'execute',
        'status': 'completed',
        'content': [
          {
            'type': 'content',
            'content': {'type': 'text', 'text': out},
          },
        ],
      });
      final r = encodeItem(s.timeline.items[1], 1);
      final o = r['out'] as Map<String, Object?>;
      expect(o['cut'], isTrue);
      expect(o['lines'], 5000);
      expect(o['head'] as String, startsWith('line 0\nline 1\n'));
      expect(o['tail'] as String, endsWith('line 4999'));
      expect('${o['head']}${o['tail']}', isNot(contains('\x1b')));
      expect(r['end'], 'completed');
    });

    test('a diff keeps the changed lines and 3 around them', () {
      final s = fresh()..beginTurn(const [TextBlock('edit')], t0);
      final old = List.generate(50, (i) => 'l$i').join('\n');
      final neu = old.replaceFirst('l20', 'L20').replaceFirst('l21', 'L21');
      tool(s, 'c1', {
        'title': 'Edit a.ts',
        'kind': 'edit',
        'content': [
          {'type': 'diff', 'path': '/p/a.ts', 'oldText': old, 'newText': neu},
          {
            'type': 'diff',
            'path': '/p/new.ts',
            'oldText': null,
            'newText': 'x\ny',
          },
        ],
      });
      final diffs = (encodeItem(s.timeline.items[1], 1)['diffs'] as List)
          .cast<Map<String, Object?>>();
      expect(diffs[0]['old'], 'l17\nl18\nl19\nl20\nl21\nl22\nl23\nl24');
      expect(diffs[0]['new'], 'l17\nl18\nl19\nL20\nL21\nl22\nl23\nl24');
      expect((diffs[0]['plus'], diffs[0]['minus']), (2, 2));
      expect(diffs[1]['created'], isTrue);
      expect((diffs[1]['plus'], diffs[1]['minus']), (2, 0));
    });

    test('a card with huge diffs is cut harder and stays a card', () {
      final s = fresh()..beginTurn(const [TextBlock('edit')], t0);
      tool(s, 'c1', {
        'title': 'x' * 100,
        'kind': 'edit',
        'content': [
          for (var i = 0; i < 3; i++)
            {
              'type': 'diff',
              'path': '/p/$i',
              'oldText': null,
              'newText': '\x01' * 200000,
            },
        ],
      });
      final sub = AiSubscription(s, generation: 1);
      final mirror = AiMirror();
      expect(feed(mirror, sub.attach(null)), isTrue);
      final card = mirror.at(1)! as MirrorTool;
      expect(card.diffs, hasLength(3));
      expect(card.diffs.every((d) => d.cut), isTrue);
    });

    test('a card that no cut can fit becomes a big stub', () {
      final s = fresh()..beginTurn(const [TextBlock('edit')], t0);
      // The call's id is sent whole, whatever the cuts: 100 KB of it passes
      // any record, so only the stub is left.
      tool(s, 'c' * 100000, {'title': 'Edit a.ts', 'kind': 'edit'});
      final sub = AiSubscription(s, generation: 1);
      final mirror = AiMirror();
      expect(feed(mirror, sub.attach(null)), isTrue);
      final card = mirror.at(1)! as MirrorUnknown;
      expect(card.kind, 'big');
      expect((card.index, card.rev), (1, s.timeline.items[1].rev));
    });

    test('turn end, notice and question records', () {
      final s = fresh()..setPhase(AgentPhase.ready);
      final turn = s.beginTurn(const [TextBlock('go')], t0);
      s.addAsk(
        ElicitationRequest.fromJson({
          'mode': 'form',
          'message': 'Which?',
          'requestedSchema': {
            'type': 'object',
            'properties': {
              'a': {'type': 'boolean'},
            },
          },
        }),
      );
      s.addNotice(const AgentExited(3));
      s.endTurn(
        outcome: TurnOutcome.finished,
        at: turn.startedAt.add(const Duration(seconds: 41)),
        changes: const [
          FileChange(
            path: 'a',
            kind: ChangeKind.modified,
            added: 40,
            removed: 5,
          ),
          FileChange(path: 'b', kind: ChangeKind.added, added: 4, removed: 0),
        ],
      );
      final sub = AiSubscription(s, generation: 1);
      final mirror = AiMirror();
      feed(mirror, sub.attach(null));
      final ask = mirror.at(1)! as MirrorAsk;
      expect((ask.status, ask.open), ('open', true));
      expect(ask.request, isA<ElicitationForm>());
      final notice = mirror.at(2)! as MirrorNotice;
      expect((notice.kind, notice.args['code']), ('exited', 3));
      final end = mirror.at(3)! as MirrorTurnEnd;
      expect(
        (end.outcome, end.elapsed.inSeconds, end.files, end.plus, end.minus),
        ('finished', 41, 2, 44, 5),
      );
    });
  });
}
