import 'dart:async';
import 'dart:io';

import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_acp/testing.dart';
import 'package:test/test.dart';

/// A client wired to an in-process fake agent.
(AcpClient, FakeAgent) connect(FakeScenario scenario, {String? cwd}) {
  final toAgent = StreamController<List<int>>();
  final toClient = StreamController<List<int>>();
  final agent = FakeAgent(
    scenario,
    input: toAgent.stream,
    output: toClient.sink,
    cwd: cwd,
    onExit: (_) => toClient.close(),
  );
  final client = AcpClient(
    JsonRpcConnection(input: toClient.stream, output: toAgent.sink),
  );
  return (client, agent);
}

Future<String> start(AcpClient client) async {
  await client.initialize(clientVersion: '2.0.0');
  return (await client.newSession(cwd: '/p')).sessionId;
}

void main() {
  test('initialize sends the D1 capabilities and reads the agent', () async {
    final (client, agent) = connect(
      const FakeScenario(
        authMethods: [
          {
            'id': 'login',
            'name': 'Log in',
            'type': 'terminal',
            'args': ['--login'],
          },
        ],
      ),
    );
    final r = await client.initialize(clientVersion: '2.0.0');
    expect(
      agent.params['initialize'],
      initializeParams(clientVersion: '2.0.0'),
    );
    expect(r.protocolVersion, 1);
    expect(r.capabilities.loadSession, isTrue);
    expect(r.authMethods.single, isA<AuthMethodTerminal>());
    expect(r.agentInfo!.name, 'fake-agent');
  });

  test('every update of a turn arrives before stopReason', () async {
    final (client, _) = connect(
      FakeScenario(
        turns: [
          [
            FakeSteps.text('Hel'),
            FakeSteps.text('lo'),
            FakeSteps.tool(
              't1',
              'Read a.txt',
              kind: 'read',
              status: 'in_progress',
            ),
            FakeSteps.toolUpdate('t1', status: 'completed'),
          ],
        ],
      ),
    );
    final got = <SessionUpdate>[];
    client.onUpdate = (_, u) => got.add(u);
    final sid = await start(client);
    expect(
      await client.prompt(sid, const [TextBlock('hi')]),
      StopReason.endTurn,
    );
    expect(got.map((u) => u.runtimeType.toString()), [
      'AgentMessageChunk',
      'AgentMessageChunk',
      'ToolCallStarted',
      'ToolCallUpdated',
    ]);
  });

  test('the permission handler answers the agent', () async {
    final (client, agent) = connect(
      FakeScenario(
        turns: [
          [FakeSteps.permission('t1', 'Edit a.txt')],
        ],
      ),
    );
    PermissionRequest? asked;
    client.onPermission = (r) async {
      asked = r;
      return PermissionSelected(r.options.first.optionId);
    };
    final sid = await start(client);
    expect(
      await client.prompt(sid, const [TextBlock('go')]),
      StopReason.endTurn,
    );
    expect(asked!.toolCall.title, 'Edit a.txt');
    expect(asked!.options.map((o) => o.optionId), [
      'allow-once',
      'allow-with-updates',
      'reject',
    ]);
    expect(agent.received, contains('permission:allow-once'));
  });

  test(
    'without handlers: permission is cancelled, a question declined',
    () async {
      final (client, agent) = connect(
        FakeScenario(
          turns: [
            [
              FakeSteps.ask({
                'mode': 'form',
                'message': 'Pick',
                'requestedSchema': {'type': 'object', 'properties': {}},
              }),
              FakeSteps.permission('t1', 'Run rm -rf build', kind: 'execute'),
            ],
          ],
        ),
      );
      final sid = await start(client);
      expect(
        await client.prompt(sid, const [TextBlock('go')]),
        StopReason.cancelled,
      );
      expect(
        agent.received,
        containsAllInOrder(['ask:decline', 'permission:cancelled']),
      );
    },
  );

  test(
    'a form answer reaches the agent; elicitation/complete is reported',
    () async {
      final (client, agent) = connect(
        FakeScenario(
          turns: [
            [
              FakeSteps.ask({
                'mode': 'form',
                'message': 'Approach?',
                'requestedSchema': {
                  'type': 'object',
                  'properties': {
                    'a': {
                      'type': 'string',
                      'enum': ['x', 'y'],
                    },
                  },
                },
              }),
              FakeSteps.completeAsk('e1'),
            ],
          ],
        ),
      );
      final completed = <String>[];
      // Two statements: after `=>` a second cascade section would belong to the
      // `ElicitAccept`, not to `client`.
      client.onElicitation = (r) async => const ElicitAccept({'a': 'y'});
      client.onElicitationComplete = completed.add;
      final sid = await start(client);
      await client.prompt(sid, const [TextBlock('go')]);
      expect(agent.received, contains('ask:accept={"a":"y"}'));
      expect(completed, ['e1']);
    },
  );

  test('cancel: the turn ends with cancelled', () async {
    final (client, agent) = connect(
      FakeScenario(
        turns: [
          [FakeSteps.text('working'), FakeSteps.waitCancel()],
        ],
      ),
    );
    final sid = await start(client);
    final turn = client.prompt(sid, const [TextBlock('go')]);
    await pumpEventQueue();
    client.cancel(sid);
    expect(await turn, StopReason.cancelled);
    expect(agent.received, contains('session/cancel'));
  });

  test('auth required: -32000 until authenticate', () async {
    final (client, agent) = connect(
      const FakeScenario(
        requireAuth: true,
        authMethods: [
          {'id': 'agent-login', 'name': 'Log in'},
        ],
      ),
    );
    await client.initialize(clientVersion: '2.0.0');
    await expectLater(
      client.newSession(cwd: '/p'),
      throwsA(
        isA<JsonRpcError>().having(
          (e) => e.code,
          'code',
          JsonRpcError.authRequired,
        ),
      ),
    );
    await client.authenticate('agent-login');
    expect((await client.newSession(cwd: '/p')).sessionId, 'sess-1');
    expect(
      agent.received,
      containsAllInOrder([
        'session/new',
        'authenticate:agent-login',
        'session/new',
      ]),
    );
  });

  test('a terminal login is seen through the auth file', () async {
    final dir = Directory.systemTemp.createTempSync('acp_auth');
    addTearDown(() => dir.deleteSync(recursive: true));
    final marker = '${dir.path}/signed-in';
    final (client, _) = connect(
      FakeScenario(requireAuth: true, authFile: marker),
    );
    await client.initialize(clientVersion: '2.0.0');
    await expectLater(
      client.newSession(cwd: '/p'),
      throwsA(isA<JsonRpcError>()),
    );
    File(marker).writeAsStringSync('');
    expect((await client.newSession(cwd: '/p')).sessionId, 'sess-1');
  });

  test('loadSession replays history before it returns', () async {
    final (client, agent) = connect(
      FakeScenario(
        history: [
          {
            'sessionUpdate': 'user_message_chunk',
            'content': {'type': 'text', 'text': 'old question'},
          },
          {
            'sessionUpdate': 'agent_message_chunk',
            'content': {'type': 'text', 'text': 'old answer'},
          },
        ],
      ),
    );
    final got = <SessionUpdate>[];
    client.onUpdate = (sid, u) {
      expect(sid, 'old-1');
      got.add(u);
    };
    await client.initialize(clientVersion: '2.0.0');
    await client.loadSession(sessionId: 'old-1', cwd: '/p');
    expect(got, hasLength(2));
    expect(agent.received.last, 'session/load:old-1');
  });

  test('config options and modes', () async {
    final (client, agent) = connect(
      const FakeScenario(
        configOptions: [
          {
            'id': 'model',
            'name': 'Model',
            'type': 'select',
            'currentValue': 'a',
            'options': [
              {'value': 'a', 'name': 'A'},
              {'value': 'b', 'name': 'B'},
            ],
          },
          {
            'id': 'fast',
            'name': 'Fast',
            'type': 'boolean',
            'currentValue': false,
          },
        ],
        modes: {
          'currentModeId': 'default',
          'availableModes': [
            {'id': 'default', 'name': 'Manual'},
            {'id': 'plan', 'name': 'Plan'},
          ],
        },
      ),
    );
    final modes = <String>[];
    client.onUpdate = (_, u) {
      if (u is ModeUpdated) modes.add(u.currentModeId);
    };
    await client.initialize(clientVersion: '2.0.0');
    final s = await client.newSession(cwd: '/p');
    expect(s.configOptions!.first.currentValue, 'a');
    final after = await client.setConfigOption(s.sessionId, 'model', 'b');
    expect(after!.first.currentValue, 'b');
    expect(
      (await client.setConfigOption(
        s.sessionId,
        'fast',
        true,
      ))![1].currentValue,
      true,
    );
    expect(agent.params['session/set_config_option']!['type'], 'boolean');
    await client.setMode(s.sessionId, 'plan');
    await pumpEventQueue();
    expect(modes, ['plan']);
  });

  test('listSessions', () async {
    final (client, _) = connect(
      const FakeScenario(
        sessions: [
          {'sessionId': 'a', 'cwd': '/p', 'title': 'Fix cart'},
        ],
      ),
    );
    await client.initialize(clientVersion: '2.0.0');
    expect(
      (await client.listSessions(cwd: '/p')).sessions.single.title,
      'Fix cart',
    );
  });

  test(
    'the agent exits mid-turn: prompt fails with ConnectionClosed',
    () async {
      final (client, _) = connect(
        FakeScenario(
          turns: [
            [FakeSteps.text('bye'), FakeSteps.exit(3)],
          ],
        ),
      );
      final sid = await start(client);
      await expectLater(
        client.prompt(sid, const [TextBlock('go')]),
        throwsA(isA<ConnectionClosed>()),
      );
    },
  );

  test('a prompt error keeps its code', () async {
    final (client, _) = connect(
      FakeScenario(
        turns: [
          [FakeSteps.error(-32603, 'model overloaded')],
        ],
      ),
    );
    final sid = await start(client);
    await expectLater(
      client.prompt(sid, const [TextBlock('go')]),
      throwsA(
        isA<JsonRpcError>().having(
          (e) => e.message,
          'message',
          'model overloaded',
        ),
      ),
    );
  });

  test('toString is redacted', () {
    final (client, _) = connect(const FakeScenario());
    expect(client.toString(), '…');
  });
}
