import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_acp/testing.dart';
import 'package:test/test.dart';

// What the client sends and what a scenario makes the scripted agent do, where
// acp_client_test.dart and fake_agent_process_test.dart say nothing: every
// later task builds its tests on these.

/// A client wired to an in-process fake agent.
(AcpClient, FakeAgent) connect(
  FakeScenario scenario, {
  String? cwd,
  void Function(String line)? stderr,
}) {
  final toAgent = StreamController<List<int>>();
  final toClient = StreamController<List<int>>();
  final agent = FakeAgent(
    scenario,
    input: toAgent.stream,
    output: toClient.sink,
    cwd: cwd,
    stderr: stderr,
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

/// The updates [client] is given, in order.
List<SessionUpdate> collect(AcpClient client) {
  final got = <SessionUpdate>[];
  client.onUpdate = (_, u) => got.add(u);
  return got;
}

Matcher failsWith(int code) =>
    throwsA(isA<JsonRpcError>().having((e) => e.code, 'code', code));

String textOf(SessionUpdate u) =>
    ((u as AgentMessageChunk).content as TextBlock).text;

void main() {
  group('what the agent receives', () {
    test('every request carries the arguments the client was given', () async {
      final (client, agent) = connect(const FakeScenario());
      const mcp = [
        McpServerStdio(name: 'm', command: 'c', args: ['--x'], env: {'K': 'V'}),
      ];
      const hi = [TextBlock('hi')];
      await client.initialize(clientVersion: '2.0.0');
      await client.newSession(cwd: '/p', mcpServers: mcp);
      expect(
        agent.params['session/new'],
        newSessionParams(cwd: '/p', mcpServers: mcp),
      );
      await client.loadSession(sessionId: 's9', cwd: '/q', mcpServers: mcp);
      expect(
        agent.params['session/load'],
        loadSessionParams(sessionId: 's9', cwd: '/q', mcpServers: mcp),
      );
      await client.listSessions(cwd: '/p', cursor: 'c1');
      expect(
        agent.params['session/list'],
        listSessionsParams(cwd: '/p', cursor: 'c1'),
      );
      await client.prompt('s9', hi);
      expect(agent.params['session/prompt'], promptParams('s9', hi));
      client.cancel('s9');
      await pumpEventQueue();
      expect(agent.params['session/cancel'], cancelParams('s9'));
      await client.setConfigOption('s9', 'model', 'b');
      expect(
        agent.params['session/set_config_option'],
        setConfigOptionParams('s9', 'model', 'b'),
      );
      await client.setMode('s9', 'plan');
      expect(agent.params['session/set_mode'], setModeParams('s9', 'plan'));
      await client.authenticate('m1');
      expect(agent.params['authenticate'], authenticateParams('m1'));
    });

    test('setConfigOption is null when the agent sends no options', () async {
      final (client, agent) = connect(const FakeScenario());
      agent.connection.onRequest(
        'session/set_config_option',
        (_) => <String, Object?>{},
      );
      await client.initialize(clientVersion: '2.0.0');
      expect(await client.setConfigOption('sess-1', 'model', 'b'), isNull);
    });

    test('stderr gets every RECV line and the stderr step, in order', () async {
      final lines = <String>[];
      final (client, _) = connect(
        FakeScenario(
          turns: [
            [FakeSteps.stderr('note'), FakeSteps.permission('t1', 'Edit')],
          ],
        ),
        stderr: lines.add,
      );
      client.onPermission = (_) async => const PermissionSelected('reject');
      final sid = await start(client);
      await client.prompt(sid, const [TextBlock('go')]);
      expect(lines, [
        'RECV initialize',
        'RECV session/new',
        'RECV session/prompt:go',
        'note',
        'RECV permission:reject',
      ]);
    });
  });

  group('scenario', () {
    test('every field survives the scenario file; absent ones default', () {
      final dir = Directory.systemTemp.createTempSync('fake_scenario');
      addTearDown(() => dir.deleteSync(recursive: true));
      List<Object?> fields(FakeScenario s) => [
        s.protocolVersion,
        s.loadSession,
        s.listSessions,
        s.image,
        s.authMethods,
        s.requireAuth,
        s.authFile,
        s.sessionId,
        s.configOptions,
        s.modes,
        s.turns,
        s.history,
        s.sessions,
        s.newSessionError,
        s.loadSessionError,
      ];
      final scenario = FakeScenario(
        protocolVersion: 2,
        loadSession: false,
        listSessions: false,
        image: false,
        authMethods: const [
          {'id': 'a', 'name': 'A', 'type': 'terminal'},
        ],
        requireAuth: true,
        authFile: '/x/signed-in',
        sessionId: 'sid',
        configOptions: const [
          {'id': 'm', 'name': 'M', 'type': 'boolean', 'currentValue': false},
        ],
        modes: const {
          'currentModeId': 'd',
          'availableModes': [
            {'id': 'd', 'name': 'D'},
          ],
        },
        turns: [
          [FakeSteps.text('a'), FakeSteps.stop('refusal')],
          [FakeSteps.exit(2)],
        ],
        history: const [
          {'sessionUpdate': 'plan', 'entries': []},
        ],
        sessions: const [
          {'sessionId': 's', 'cwd': '/p'},
        ],
        newSessionError: const {'code': 1, 'message': 'n'},
        loadSessionError: const {'code': 2, 'message': 'l'},
      );
      final file = writeScenario(scenario, dir);
      final back = FakeScenario.fromJson(
        jsonDecode(File(file).readAsStringSync()) as JsonMap,
      );
      expect(fields(back), fields(scenario));
      expect(
        fields(FakeScenario.fromJson(<String, Object?>{})),
        fields(const FakeScenario()),
      );
    });

    test(
      'the scenario sets protocol version, capabilities and session id',
      () async {
        final (client, _) = connect(
          const FakeScenario(
            protocolVersion: 2,
            loadSession: false,
            listSessions: false,
            image: false,
            sessionId: 'abc-9',
          ),
        );
        final r = await client.initialize(clientVersion: '2.0.0');
        expect(r.protocolVersion, 2);
        expect(r.capabilities.loadSession, isFalse);
        expect(r.capabilities.listSessions, isFalse);
        expect(r.capabilities.prompt.image, isFalse);
        expect((await client.newSession(cwd: '/p')).sessionId, 'abc-9');
      },
    );

    test('session/new and session/load fail as the scenario says', () async {
      final (a, _) = connect(
        const FakeScenario(
          newSessionError: {'code': -32603, 'message': 'boom'},
        ),
      );
      await expectLater(a.newSession(cwd: '/p'), failsWith(-32603));

      final (b, _) = connect(
        const FakeScenario(
          loadSessionError: {'code': -32002, 'message': 'gone'},
          history: [
            {
              'sessionUpdate': 'agent_message_chunk',
              'content': {'type': 'text', 'text': 'old'},
            },
          ],
        ),
      );
      final replayed = collect(b);
      await expectLater(
        b.loadSession(sessionId: 'x', cwd: '/p'),
        failsWith(JsonRpcError.resourceNotFound),
      );
      expect(replayed, isEmpty, reason: 'a failed load replays nothing');

      final (c, _) = connect(const FakeScenario(loadSession: false));
      await expectLater(
        c.loadSession(sessionId: 'x', cwd: '/p'),
        failsWith(JsonRpcError.methodNotFound),
      );

      final (d, _) = connect(const FakeScenario(requireAuth: true));
      await expectLater(
        d.loadSession(sessionId: 'x', cwd: '/p'),
        failsWith(JsonRpcError.authRequired),
      );
    });
  });

  group('steps', () {
    test('update steps arrive as the types the session model reads', () async {
      final (client, _) = connect(
        FakeScenario(
          turns: [
            [
              FakeSteps.thought('hmm'),
              FakeSteps.tool(
                't1',
                'Edit a.txt',
                kind: 'edit',
                status: 'in_progress',
                content: [FakeSteps.diff('/p/a.txt', null, 'new')],
                locations: [
                  {'path': '/p/a.txt', 'line': 3},
                ],
                rawInput: {'file_path': '/p/a.txt'},
              ),
              FakeSteps.toolUpdate(
                't1',
                status: 'completed',
                content: [FakeSteps.output('done')],
                title: 'Edited a.txt',
              ),
              FakeSteps.plan([('Do x', 'in_progress'), ('Do y', 'pending')]),
              FakeSteps.update({
                'sessionUpdate': 'usage_update',
                'used': 5,
                'size': 100,
              }),
              FakeSteps.text('hello', messageId: 'm1'),
              FakeSteps.tool('t2', 'Run ls'),
            ],
          ],
        ),
      );
      final got = collect(client);
      final sid = await start(client);
      expect(
        await client.prompt(sid, const [TextBlock('go')]),
        StopReason.endTurn,
      );
      expect(got, hasLength(7));

      expect(((got[0] as AgentThoughtChunk).content as TextBlock).text, 'hmm');

      final started = got[1] as ToolCallStarted;
      expect(started.toolCallId, 't1');
      expect(started.fields.title, 'Edit a.txt');
      expect(started.fields.kind, ToolKind.edit);
      expect(started.fields.status, ToolCallStatus.inProgress);
      final diff = started.fields.content!.single as ToolDiff;
      expect(
        (diff.path, diff.oldText, diff.newText),
        ('/p/a.txt', null, 'new'),
      );
      final where = started.fields.locations!.single;
      expect((where.path, where.line), ('/p/a.txt', 3));
      expect(started.fields.rawInput, {'file_path': '/p/a.txt'});

      final updated = got[2] as ToolCallUpdated;
      expect(updated.toolCallId, 't1');
      expect(updated.fields.status, ToolCallStatus.completed);
      expect(updated.fields.title, 'Edited a.txt');
      expect(updated.fields.kind, isNull);
      final output = updated.fields.content!.single as ToolContentBlock;
      expect((output.block as TextBlock).text, 'done');

      final plan = got[3] as PlanUpdated;
      expect(plan.entries.map((e) => (e.content, e.status)), [
        ('Do x', PlanStatus.inProgress),
        ('Do y', PlanStatus.pending),
      ]);
      expect((got[4] as UsageUpdated).usage.percent, 5);
      expect((got[5] as AgentMessageChunk).messageId, 'm1');

      final bare = (got[6] as ToolCallStarted).fields;
      expect(bare.kind, ToolKind.other);
      expect(bare.status, ToolCallStatus.pending);
      expect(
        [bare.content, bare.locations, bare.rawInput],
        everyElement(isNull),
        reason: 'optional fields are left out unless given',
      );
    });

    test(
      'each prompt runs the next turn, the last repeats, stop ends a turn',
      () async {
        final (client, _) = connect(
          FakeScenario(
            turns: [
              [
                FakeSteps.text('one'),
                FakeSteps.stop('max_tokens'),
                FakeSteps.text('skipped'),
              ],
              [FakeSteps.text('two')],
            ],
          ),
        );
        final got = collect(client);
        final sid = await start(client);
        final reasons = [
          for (var i = 0; i < 3; i++)
            await client.prompt(sid, const [TextBlock('go')]),
        ];
        expect(reasons, [
          StopReason.maxTokens,
          StopReason.endTurn,
          StopReason.endTurn,
        ]);
        expect(got.map(textOf), ['one', 'two', 'two']);
      },
    );

    test(
      'a client that hangs up with a question open leaves no error behind',
      () async {
        final JsonMap form = {
          'mode': 'form',
          'message': 'Pick',
          'requestedSchema': {
            'type': 'object',
            'properties': <String, Object?>{},
          },
        };
        final uncaught = <String, List<Object>>{};
        final outcomes = <String, Object?>{};
        for (final (kind, step) in [
          ('permission', FakeSteps.permission('t1', 'Edit a.txt')),
          ('ask', FakeSteps.ask(form)),
        ]) {
          final errors = <Object>[];
          outcomes[kind] = await runZonedGuarded<Future<Object?>>(() async {
            final (client, _) = connect(
              FakeScenario(
                turns: [
                  [step],
                ],
              ),
            );
            final asked = Completer<void>();
            client.onPermission = (_) {
              asked.complete();
              return Completer<PermissionOutcome>().future; // never answered
            };
            client.onElicitation = (_) {
              asked.complete();
              return Completer<ElicitationResponse>().future; // never answered
            };
            final sid = await start(client);
            final turn = client
                .prompt(sid, const [TextBlock('go')])
                .then<Object?>((_) => 'answered', onError: (Object e) => e);
            await asked.future;
            await client.close(); // hangs up with the question still open
            final outcome = await turn;
            await pumpEventQueue(); // let the agent side see the hang-up
            return outcome;
          }, (e, _) => errors.add(e));
          if (errors.isNotEmpty) uncaught[kind] = errors;
        }
        expect(uncaught, isEmpty, reason: 'errors the fake left unhandled');
        expect(outcomes.values, everyElement(isA<ConnectionClosed>()));
      },
    );

    test('a cancel does not leak into the next turn', () async {
      final (client, _) = connect(
        FakeScenario(
          turns: [
            [FakeSteps.waitCancel()],
            [FakeSteps.text('again')],
          ],
        ),
      );
      final got = collect(client);
      final sid = await start(client);
      final first = client.prompt(sid, const [TextBlock('a')]);
      await pumpEventQueue();
      client.cancel(sid);
      expect(await first, StopReason.cancelled);
      expect(
        await client.prompt(sid, const [TextBlock('b')]),
        StopReason.endTurn,
      );
      expect(got.map(textOf), ['again']);
    });

    test('cancel cuts a sleep short, but a hang never answers', () async {
      final (client, agent) = connect(
        FakeScenario(
          turns: [
            [FakeSteps.sleep(600000), FakeSteps.text('never')],
            [FakeSteps.hang()],
          ],
        ),
      );
      final got = collect(client);
      final sid = await start(client);
      final sleeping = client.prompt(sid, const [TextBlock('a')]);
      await pumpEventQueue();
      client.cancel(sid);
      expect(await sleeping, StopReason.cancelled);
      expect(got, isEmpty);

      var answered = false;
      unawaited(
        client
            .prompt(sid, const [TextBlock('b')])
            .then<void>(
              (_) => answered = true,
              onError: (Object _) => answered = true,
            ),
      );
      await pumpEventQueue();
      client.cancel(sid);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(agent.received.where((e) => e == 'session/cancel'), hasLength(2));
      expect(answered, isFalse);
    });

    test(
      'write makes folders under the agent cwd; delete removes a file',
      () async {
        final dir = Directory.systemTemp.createTempSync('fake_files');
        addTearDown(() => dir.deleteSync(recursive: true));
        final (client, _) = connect(
          FakeScenario(
            turns: [
              [FakeSteps.write('sub/dir/f.txt', 'abc')],
              [
                FakeSteps.delete('sub/dir/f.txt'),
                FakeSteps.delete('missing.txt'),
              ],
            ],
          ),
          cwd: dir.path,
        );
        final sid = await start(client);
        await client.prompt(sid, const [TextBlock('a')]);
        expect(File('${dir.path}/sub/dir/f.txt').readAsStringSync(), 'abc');
        expect(
          await client.prompt(sid, const [TextBlock('b')]),
          StopReason.endTurn,
        );
        expect(File('${dir.path}/sub/dir/f.txt').existsSync(), isFalse);
      },
    );

    test(
      'raw lines are not JSON-RPC: 20 are skipped, a 21st closes the connection',
      () async {
        final (client, _) = connect(
          FakeScenario(
            turns: [
              [
                for (var i = 0; i < 20; i++) FakeSteps.raw('banner $i'),
                FakeSteps.text('still here'),
              ],
              [
                for (var i = 0; i < 21; i++) FakeSteps.raw('banner $i'),
                FakeSteps.text('too late'),
              ],
            ],
          ),
        );
        final got = collect(client);
        final sid = await start(client);
        expect(
          await client.prompt(sid, const [TextBlock('a')]),
          StopReason.endTurn,
        );
        expect(got.map(textOf), ['still here']);
        await expectLater(
          client.prompt(sid, const [TextBlock('b')]),
          throwsA(
            isA<ConnectionClosed>().having(
              (e) => e.reason,
              'reason',
              ConnectionCloseReason.tooManyBadLines,
            ),
          ),
        );
      },
    );
  });
}
