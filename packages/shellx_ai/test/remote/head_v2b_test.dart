import 'dart:convert';

import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:test/test.dart';

final _at = DateTime.utc(2026, 10, 15, 9);

AiSessionState _state() =>
    AiSessionState(agentId: 'claude', agentName: 'Claude', cwd: '/p')
      ..setPhase(AgentPhase.ready);

ConfigOption _model(String current, {String name = 'Opus'}) => ConfigOption(
  id: 'model',
  name: 'Model',
  kind: ConfigKind.select,
  category: 'model',
  currentValue: current,
  choices: [
    const ConfigChoice(value: 'default', name: 'Default'),
    ConfigChoice(value: 'opus', name: name),
  ],
);

Map<String, Object?> _head(AiSessionState s) => encodeHead(s, (_) => -1);

/// What a phone reads of [s]'s header (through JSON, as on the wire).
MirrorHead _phone(AiSessionState s) => MirrorHead.fromJson(
  jsonDecode(jsonEncode(_head(s))) as Map<String, Object?>,
);

/// V2-2b §4.2: the header keys a phone needs for B11, B17, B19 and B22.
void main() {
  test('acp, model, hist and undo, as the phone reads them', () {
    final s = _state()
      ..setAgent(
        InitializeResult.fromJson({
          'protocolVersion': 1,
          'agentCapabilities': {
            'sessionCapabilities': {'list': <String, Object?>{}},
          },
        }),
      )
      ..setSession('sess-1', configOptions: [_model('opus')]);
    expect(_head(s), containsPair('acp', 'sess-1'));
    expect(_head(s)['model'], {'id': 'opus', 'name': 'Opus'});
    expect(_head(s)['hist'], isTrue);
    expect(_head(s)['undo'], 'on');
    final head = _phone(s);
    expect(
      (head.acp, head.modelId, head.modelName, head.history, head.undoOff),
      ('sess-1', 'opus', 'Opus', true, false),
    );
  });

  test('none of them without a session, a model option or session/list', () {
    final head = _head(_state());
    expect(head.containsKey('acp'), isFalse);
    expect(head.containsKey('model'), isFalse);
    expect(head.containsKey('hist'), isFalse);
  });

  test('an older computer\'s header has none of them: nothing is known', () {
    final head = MirrorHead.fromJson(const {
      'phase': 'ready',
      'agent': 'claude',
      'name': 'Claude',
    });
    expect(
      (head.acp, head.modelId, head.history, head.undo, head.undoOff),
      (null, null, false, null, false),
    );
  });

  test('undo is off while no turn has a restore point and the conversation '
      'says why; a turn with one, or the card folded, turns it on', () {
    final s = _state();
    final card = s.addNotice(const UndoUnavailable(UndoOff.noGit));
    expect(_head(s)['undo'], 'off');
    expect(_phone(s).undoOff, isTrue);
    s.resolveNotices((n) => n is UndoUnavailable);
    expect(card.resolved, isTrue);
    expect(_head(s)['undo'], 'on');
    s.addNotice(const UndoUnavailable(UndoOff.failed, turnOnly: true));
    s.beginTurn(const [TextBlock('go')], _at);
    s.turn!.checkpoint = const Checkpoint(commit: 'c1', tree: 't1');
    s.endTurn(outcome: TurnOutcome.finished, at: _at);
    expect(aiTurnsOf(s).last, 1);
    expect(_head(s)['undo'], 'on');
  });

  test(
    'the agent\'s ids and names are cut like the listing\'s (200 bytes)',
    () {
      final s = _state()
        ..setSession(
          's' * 1000,
          configOptions: [_model('opus', name: 'n' * 1000)],
        );
      final head = _head(s);
      expect(
        utf8.encode(head['acp']! as String).length,
        lessThanOrEqualTo(200),
      );
      final model = head['model']! as Map<String, Object?>;
      expect(
        utf8.encode(model['name']! as String).length,
        lessThanOrEqualTo(200),
      );
    },
  );

  test('a header too big for one body loses the model with the plan; the '
      'request it asks stays', () {
    final s = _state()
      ..setSession('sess-1', configOptions: [_model('opus')])
      ..plan = [
        for (var i = 0; i < 30; i++)
          PlanEntry(content: 'p' * 600, status: PlanStatus.pending),
      ];
    s.addPermission(
      PermissionRequest.fromJson({
        'sessionId': 's',
        'toolCall': {'toolCallId': 'c1', 'title': 'Edit a.ts'},
        'options': [
          for (var i = 0; i < 200; i++)
            {'optionId': 'o$i', 'name': 'x' * 300, 'kind': 'allow_once'},
        ],
      }),
      _at,
    );
    final sub = AiSubscription(s, generation: 1);
    final body = decodeBody(sub.attach(null).first.body)!;
    final head = body['head']! as Map<String, Object?>;
    expect(head.containsKey('model'), isFalse);
    expect(head.containsKey('plan'), isFalse);
    expect((head['perm']! as Map<String, Object?>)['title'], 'Edit a.ts');
  });

  group('the turns undo knows (moved from the desktop Changes panel)', () {
    test('only turns with a restore point count; the running one too', () {
      final s = _state();
      expect(aiTurnsOf(s), (
        first: null,
        last: null,
        lastFinished: null,
        running: false,
      ));
      s.beginTurn(const [TextBlock('a')], _at);
      s.endTurn(outcome: TurnOutcome.finished, at: _at); // no restore point
      s.beginTurn(const [TextBlock('b')], _at);
      s.turn!.checkpoint = const Checkpoint(commit: 'c2', tree: 't2');
      expect(aiTurnsOf(s), (
        first: 2,
        last: 2,
        lastFinished: null,
        running: true,
      ));
    });

    test('why undo is off: the latest card still open', () {
      final s = _state();
      expect(aiUndoOffOf(s), isNull);
      s.addNotice(const UndoUnavailable(UndoOff.noGit));
      s.addNotice(const UndoUnavailable(UndoOff.tooSlow));
      expect(aiUndoOffOf(s)!.reason, UndoOff.tooSlow);
    });
  });
}
