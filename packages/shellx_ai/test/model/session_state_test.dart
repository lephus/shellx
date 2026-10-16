import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:test/test.dart';

final t0 = DateTime.utc(2026, 10, 14, 9);
AiSessionState fresh() =>
    AiSessionState(agentId: 'claude', agentName: 'Claude', cwd: '/p');
PermissionRequest perm(String toolCallId, {String? title}) =>
    PermissionRequest.fromJson({
      'sessionId': 's',
      'toolCall': {'toolCallId': toolCallId, 'title': ?title},
      'options': [
        {'optionId': 'allow-once', 'name': 'Yes', 'kind': 'allow_once'},
        {'optionId': 'reject', 'name': 'No', 'kind': 'reject_once'},
      ],
    });

void main() {
  group('label (spec D2)', () {
    test('the session title wins', () {
      final s = fresh()..beginTurn(const [TextBlock('first prompt')], t0);
      s.applyUpdate(
        SessionUpdate.fromJson({
          'sessionUpdate': 'session_info_update',
          'title': 'Fix cart',
        }),
        t0,
      );
      expect(s.label, 'Fix cart');
    });

    test('else the first prompt, spaces collapsed, cut at 40 characters', () {
      final s = fresh()
        ..beginTurn(const [
          TextBlock('  Fix   the cart total when a second item is added  '),
        ], t0);
      expect(s.label, 'Fix the cart total when a second item is…');
    });

    test('the cut never splits a character', () {
      final s = fresh()..beginTurn([TextBlock('😀' * 50)], t0);
      expect(s.label!.runes.length, 41);
      expect(s.label!.endsWith('😀…'), isTrue);
    });

    test('else null ("Phiên AI mới" in the UI); a null title clears', () {
      final s = fresh();
      expect(s.label, isNull);
      s.applyUpdate(
        SessionUpdate.fromJson({
          'sessionUpdate': 'session_info_update',
          'title': 'T',
        }),
        t0,
      );
      s.applyUpdate(
        SessionUpdate.fromJson({
          'sessionUpdate': 'session_info_update',
          'title': null,
        }),
        t0,
      );
      expect(s.label, isNull);
    });
  });

  test(
    'session-wide updates; each change bumps the version and calls listeners',
    () {
      final s = fresh()
        ..setSession(
          's1',
          modes: const SessionModes(currentModeId: 'default', available: []),
        );
      var calls = 0;
      s.addListener(() => calls++);
      final v = s.version;
      s.applyUpdate(
        SessionUpdate.fromJson({
          'sessionUpdate': 'plan',
          'entries': [
            {'content': 'Read', 'priority': 'high', 'status': 'pending'},
          ],
        }),
        t0,
      );
      s.applyUpdate(
        SessionUpdate.fromJson({
          'sessionUpdate': 'available_commands_update',
          'availableCommands': [
            {'name': 'review', 'description': 'r'},
          ],
        }),
        t0,
      );
      s.applyUpdate(
        SessionUpdate.fromJson({
          'sessionUpdate': 'current_mode_update',
          'currentModeId': 'plan',
        }),
        t0,
      );
      s.applyUpdate(
        SessionUpdate.fromJson({
          'sessionUpdate': 'usage_update',
          'used': 50,
          'size': 100,
        }),
        t0,
      );
      s.applyUpdate(
        SessionUpdate.fromJson({
          'sessionUpdate': 'config_option_update',
          'configOptions': [],
        }),
        t0,
      );
      s.applyUpdate(
        SessionUpdate.fromJson({'sessionUpdate': 'something_new'}),
        t0,
      );
      expect(s.plan.single.content, 'Read');
      expect(s.commands.single.name, 'review');
      expect(s.modes!.currentModeId, 'plan');
      expect(s.usage!.percent, 50);
      expect(s.configOptions, isEmpty);
      expect(s.version, v + 5, reason: 'the unknown update changes nothing');
      expect(calls, 5);
    },
  );

  test(
    'our own prompt is not doubled by a user_message_chunk during the turn',
    () {
      final s = fresh()..beginTurn(const [TextBlock('hi')], t0);
      s.applyUpdate(
        SessionUpdate.fromJson({
          'sessionUpdate': 'user_message_chunk',
          'content': {'type': 'text', 'text': 'hi'},
        }),
        t0,
      );
      expect(s.timeline.items.whereType<UserItem>(), hasLength(1));
    },
  );

  test('timelineToo: false keeps session-wide updates only', () {
    final s = fresh();
    s.applyUpdate(
      SessionUpdate.fromJson({
        'sessionUpdate': 'agent_message_chunk',
        'content': {'type': 'text', 'text': 'x'},
      }),
      t0,
      timelineToo: false,
    );
    s.applyUpdate(
      SessionUpdate.fromJson({
        'sessionUpdate': 'usage_update',
        'used': 1,
        'size': 4,
      }),
      t0,
      timelineToo: false,
    );
    expect(s.timeline.items, isEmpty);
    expect(s.usage!.used, 1);
  });

  group('turns', () {
    test('begin and end: phase, elapsed, checkpoint, outcome', () {
      final s = fresh()..setPhase(AgentPhase.ready);
      final turn = s.beginTurn(const [TextBlock('go')], t0);
      turn.checkpoint = const Checkpoint(commit: 'c1', tree: 'tr1');
      expect(s.phase, AgentPhase.running);
      s.applyUpdate(
        SessionUpdate.fromJson({
          'sessionUpdate': 'tool_call',
          'toolCallId': 'a',
          'title': 'A',
          'status': 'in_progress',
        }),
        t0,
      );
      final end = s.endTurn(
        outcome: TurnOutcome.cancelled,
        at: t0.add(const Duration(seconds: 41)),
        stopReason: StopReason.cancelled,
      )!;
      expect(end.turn, 1);
      expect(end.elapsed, const Duration(seconds: 41));
      expect(end.checkpoint!.commit, 'c1');
      expect(s.timeline.tool('a')!.end, ToolEnd.stopped);
      expect(s.turn, isNull);
      expect(s.phase, AgentPhase.ready);
      expect(s.endTurn(outcome: TurnOutcome.finished, at: t0), isNull);
    });

    test(
      'a finished turn leaves open tools open (background work may update them)',
      () {
        final s = fresh()..beginTurn(const [TextBlock('go')], t0);
        s.applyUpdate(
          SessionUpdate.fromJson({
            'sessionUpdate': 'tool_call',
            'toolCallId': 'bg',
            'title': 'npm run dev',
            'status': 'in_progress',
          }),
          t0,
        );
        s.endTurn(
          outcome: TurnOutcome.finished,
          at: t0,
          stopReason: StopReason.endTurn,
        );
        expect(s.timeline.tool('bg')!.end, isNull);
        s.applyUpdate(
          SessionUpdate.fromJson({
            'sessionUpdate': 'tool_call_update',
            'toolCallId': 'bg',
            'status': 'completed',
          }),
          t0,
        );
        expect(s.timeline.tool('bg')!.end, ToolEnd.completed);
      },
    );
  });

  group('permissions (spec D10)', () {
    test('one at a time, in order; answers land on the card', () {
      final s = fresh()..beginTurn(const [TextBlock('go')], t0);
      s.applyUpdate(
        SessionUpdate.fromJson({
          'sessionUpdate': 'tool_call',
          'toolCallId': 'e1',
          'title': 'Edit a.txt',
          'kind': 'edit',
        }),
        t0,
      );
      final p1 = s.addPermission(perm('e1'), t0);
      final p2 = s.addPermission(perm('x9', title: 'Run rm -rf build'), t0);
      expect(s.needsInput, isTrue);
      expect(s.currentPermission, same(p1));
      expect(p1.title, 'Edit a.txt');
      expect(
        p2.title,
        'Run rm -rf build',
        reason: 'no card yet: the request title (spec §6)',
      );
      expect(s.timeline.tool('x9'), isNotNull);
      expect(p1.item.awaitingPermission, isTrue);
      s.resolvePermission(p1.id, const PermissionSelected('allow-once'));
      expect(p1.item.permissionAnswer!.name, 'Yes');
      expect(p1.item.awaitingPermission, isFalse);
      expect(s.currentPermission, same(p2));
      s.resolvePermission(p2.id, const PermissionCancelled());
      expect(p2.item.permissionCancelled, isTrue);
      expect(s.needsInput, isFalse);
      s.resolvePermission(p2.id, const PermissionCancelled()); // twice: no-op
    });
  });

  group('questions (spec D22)', () {
    test('pending, answered, url completed, auto-declined', () {
      final s = fresh()..beginTurn(const [TextBlock('go')], t0);
      final form = ElicitationRequest.fromJson({
        'mode': 'form',
        'message': 'Pick',
        'requestedSchema': {'type': 'object', 'properties': {}},
      });
      final a = s.addAsk(form)!;
      expect(s.currentAsk, same(a));
      expect(s.needsInput, isTrue);
      s.resolveAsk(a.id, const ElicitAccept({}));
      expect(a.item.response, isA<ElicitAccept>());
      expect(s.needsInput, isFalse);

      final url = s.addAsk(
        ElicitationRequest.fromJson({
          'mode': 'url',
          'message': 'Sign in',
          'elicitationId': 'e1',
          'url': 'https://x.test',
        }),
      )!;
      s.resolveAsk(url.id, const ElicitAccept());
      s.completeUrlAsk('e1');
      expect(url.item.completed, isTrue);

      final odd = ElicitationRequest.fromJson({
        'mode': 'form',
        'message': 'File?',
        'requestedSchema': {
          'type': 'object',
          'properties': {
            'f': {'type': 'blob'},
          },
        },
      });
      expect(s.addAsk(odd, autoDeclined: true), isNull);
      final card = s.timeline.items.whereType<AskItem>().last;
      expect(card.autoDeclined, isTrue);
      expect(card.response, isA<ElicitDecline>());
    });
  });

  test('queue holds at most 5, in order (spec D16)', () {
    final s = fresh();
    final ids = [
      for (var i = 0; i < 5; i++) s.enqueue([TextBlock('q$i')])!.id,
    ];
    expect(s.enqueue(const [TextBlock('q5')]), isNull);
    s.removeQueued(ids[1]);
    expect(s.takeQueued()!.text, 'q0');
    expect(s.takeQueued()!.text, 'q2');
    expect(s.queue.map((q) => q.text), ['q3', 'q4']);
  });

  test('notices are added and folded', () {
    final s = fresh();
    s.addNotice(const LoginNeeded([]));
    s.addNotice(const AgentExited(3));
    s.resolveNotices((n) => n is LoginNeeded);
    final cards = s.timeline.items.whereType<NoticeItem>().toList();
    expect(cards.map((c) => c.resolved), [true, false]);
  });

  test('toString is redacted', () {
    final s = fresh()..beginTurn(const [TextBlock('secret')], t0);
    final p = s.addPermission(perm('a', title: 'secret'), t0);
    expect(
      [
        s,
        s.turn,
        p,
        s.enqueue(const [TextBlock('secret')]),
        const FileChange(path: 'secret', kind: ChangeKind.added),
      ].map((o) => o.toString()).toSet(),
      {'…'},
    );
  });
}
