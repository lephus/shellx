import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:test/test.dart';

final t0 = DateTime.utc(2026, 10, 14, 9);
SessionUpdate u(JsonMap j) => SessionUpdate.fromJson(j);
JsonMap text(String s, {String kind = 'agent_message_chunk', String? id}) => {
  'sessionUpdate': kind,
  'messageId': ?id,
  'content': {'type': 'text', 'text': s},
};

void main() {
  late Timeline tl;
  setUp(() => tl = Timeline()..startTurn(const [TextBlock('fix it')]));

  test('message chunks merge; a tool call or a new messageId splits them', () {
    for (final s in ['Hel', 'lo']) {
      tl.apply(u(text(s)), t0);
    }
    tl.apply(
      u({
        'sessionUpdate': 'tool_call',
        'toolCallId': 't1',
        'title': 'Read a',
        'kind': 'read',
      }),
      t0,
    );
    tl.apply(u(text('Done')), t0);
    tl.apply(u(text(' twice', id: 'm2')), t0);
    final texts = tl.items
        .whereType<AgentTextItem>()
        .map((i) => i.text)
        .toList();
    expect(texts, ['Hello', 'Done', ' twice']);
  });

  test('thoughts merge apart from text', () {
    tl.apply(u(text('think ', kind: 'agent_thought_chunk')), t0);
    tl.apply(u(text('more', kind: 'agent_thought_chunk')), t0);
    tl.apply(u(text('answer')), t0);
    expect(tl.items.whereType<ThoughtItem>().single.text, 'think more');
    expect(tl.items.last, isA<AgentTextItem>());
  });

  test(
    'a tool update merges into its card; content is replaced; completed ends it',
    () {
      tl.apply(
        u({
          'sessionUpdate': 'tool_call',
          'toolCallId': 't1',
          'title': 'Edit a.txt',
          'kind': 'edit',
          'status': 'in_progress',
          'content': [
            {
              'type': 'diff',
              'path': '/p/a.txt',
              'oldText': 'a',
              'newText': 'b',
            },
          ],
        }),
        t0,
      );
      final later = t0.add(const Duration(seconds: 2));
      tl.apply(
        u({
          'sessionUpdate': 'tool_call_update',
          'toolCallId': 't1',
          'status': 'completed',
          'content': [],
        }),
        later,
      );
      final card = tl.tool('t1')!;
      expect(tl.items.whereType<ToolItem>(), hasLength(1));
      expect(card.fields.title, 'Edit a.txt');
      expect(card.fields.content, isEmpty);
      expect(card.end, ToolEnd.completed);
      expect(card.endedAt, later);
      expect(card.rev, greaterThan(1));
    },
  );

  test(
    'an update for an unknown id creates the card; a resent tool_call does not duplicate',
    () {
      tl.apply(
        u({
          'sessionUpdate': 'tool_call_update',
          'toolCallId': 'x',
          'status': 'failed',
        }),
        t0,
      );
      tl.apply(
        u({
          'sessionUpdate': 'tool_call',
          'toolCallId': 'x',
          'title': 'Run make',
          'kind': 'execute',
        }),
        t0,
      );
      expect(tl.items.whereType<ToolItem>().single.fields.title, 'Run make');
      expect(tl.tool('x')!.end, ToolEnd.failed);
    },
  );

  test('replayed user messages start turns', () {
    final replay = Timeline();
    replay.apply(u(text('q1', kind: 'user_message_chunk')), t0);
    replay.apply(u(text('a1')), t0);
    replay.apply(u(text('q2', kind: 'user_message_chunk')), t0);
    replay.apply(u(text('a2')), t0);
    expect(replay.items.map((i) => '${i.runtimeType}:${i.turn}'), [
      'UserItem:1',
      'AgentTextItem:1',
      'UserItem:2',
      'AgentTextItem:2',
    ]);
    expect(replay.turn, 2);
  });

  test('stopOpenTools stops only open calls', () {
    tl.apply(
      u({
        'sessionUpdate': 'tool_call',
        'toolCallId': 'a',
        'title': 'A',
        'status': 'completed',
      }),
      t0,
    );
    tl.apply(
      u({
        'sessionUpdate': 'tool_call',
        'toolCallId': 'b',
        'title': 'B',
        'status': 'in_progress',
      }),
      t0,
    );
    tl.stopOpenTools(t0);
    expect(tl.tool('a')!.end, ToolEnd.completed);
    expect(tl.tool('b')!.end, ToolEnd.stopped);
  });

  test(
    'images in agent text are skipped; resource links become markdown links',
    () {
      tl.apply(
        u({
          'sessionUpdate': 'agent_message_chunk',
          'content': {'type': 'image', 'data': '', 'mimeType': 'image/png'},
        }),
        t0,
      );
      expect(tl.items.whereType<AgentTextItem>(), isEmpty);
      tl.apply(
        u({
          'sessionUpdate': 'agent_message_chunk',
          'content': {
            'type': 'resource_link',
            'uri': 'file:///p/a.dart',
            'name': 'a.dart',
          },
        }),
        t0,
      );
      expect(
        tl.items.whereType<AgentTextItem>().single.text,
        '[a.dart](file:///p/a.dart)',
      );
    },
  );

  test('plan and usage are not timeline updates', () {
    expect(tl.apply(u({'sessionUpdate': 'plan', 'entries': []}), t0), isFalse);
    expect(
      tl.apply(u({'sessionUpdate': 'usage_update', 'used': 1, 'size': 2}), t0),
      isFalse,
    );
  });

  test('toString is redacted', () {
    tl.apply(u(text('secret')), t0);
    for (final i in tl.items) {
      expect(i.toString(), '…');
    }
    expect(tl.toString(), '…');
  });
}
