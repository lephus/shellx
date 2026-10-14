import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_ai/testing.dart';
import 'package:test/test.dart';

/// A runtime on in-process fake agents, in a temp project.
final class Rig {
  Rig(
    FakeScenario first, {
    List<FakeScenario> later = const [],
    Future<AgentReadiness> Function()? resolve,
    Future<(Checkpoints?, UndoOff?)> Function()? checkpoints,
    bool realCheckpoints = false,
    String? resume,
    Map<String, Object> preferred = const {},
    Duration cancelGrace = const Duration(seconds: 10),
  }) : tmp = Directory.systemTemp.createTempSync('runtime') {
    Directory(project).createSync();
    launcher = FakeLauncher(first, later);
    final stores = CheckpointStores(
      root: p.join(tmp.path, 'support', 'ai', 'checkpoints'),
    );
    runtime = AiRuntime(
      state: AiSessionState(agentId: 'fake', agentName: 'Fake', cwd: project),
      resolve:
          resolve ??
          () async => const AgentReady(
            AgentCommand(executable: 'fake-agent', args: ['--acp']),
          ),
      launch: launcher.call,
      clientVersion: '2.0.0',
      checkpoints:
          checkpoints ??
          (realCheckpoints
              ? () async => stores.forProject(
                  project,
                  LoginEnv(
                    Platform.environment,
                    source: LoginEnvSource.process,
                  ),
                )
              : null),
      resumeSessionId: resume,
      preferredConfig: preferred,
      cancelGrace: cancelGrace,
      sessionKey: 'k1',
    )..onStatus = statuses.add;
  }

  final Directory tmp;
  late final FakeLauncher launcher;
  late final AiRuntime runtime;
  final statuses = <AiStatus>[];

  String get project => p.join(tmp.path, 'project');
  AiSessionState get state => runtime.state;
  FakeAgent agent([int i = -1]) =>
      (i < 0 ? launcher.channels.last : launcher.channels[i]).agent;

  Future<void> until(bool Function() test) async {
    for (var i = 0; i < 400 && !test(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(test(), isTrue, reason: 'condition not reached');
  }

  Future<void> dispose() async {
    await runtime.dispose();
    tmp.deleteSync(recursive: true);
  }
}

const hi = [TextBlock('hi')];

void main() {
  test(
    'start: D1 initialize, new session, preferred config — never Bypass (R6)',
    () async {
      final r = Rig(
        const FakeScenario(
          configOptions: [
            {
              'id': 'mode',
              'name': 'Mode',
              'category': 'mode',
              'type': 'select',
              'currentValue': 'default',
              'options': [
                {'value': 'default', 'name': 'Manual'},
                {'value': 'bypassPermissions', 'name': 'Bypass permissions'},
              ],
            },
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
          ],
        ),
        preferred: {'model': 'b', 'mode': 'bypassPermissions', 'gone': 'x'},
      );
      addTearDown(r.dispose);
      await r.runtime.start();
      expect(r.state.phase, AgentPhase.ready);
      expect(r.state.sessionId, 'sess-1');
      expect(
        r.agent().params['initialize'],
        initializeParams(clientVersion: '2.0.0'),
      );
      expect(r.agent().received, contains('session/set_config_option:model=b'));
      expect(
        r.agent().received.where((e) => e.contains('bypassPermissions')),
        isEmpty,
      );
      expect(
        r.state.configOptions!.firstWhere((o) => o.id == 'model').currentValue,
        'b',
      );
      expect(r.launcher.commands.single.args, ['--acp']);
    },
  );

  test(
    'a turn: prompt, merged text, a finished card, the summary; running → idle',
    () async {
      final r = Rig(
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
      addTearDown(r.dispose);
      await r.runtime.start();
      expect(await r.runtime.send(hi), isTrue);
      await r.runtime.whenIdle();
      final items = r.state.timeline.items;
      expect((items[0] as UserItem).text, 'hi');
      expect((items[1] as AgentTextItem).text, 'Hello');
      expect((items[2] as ToolItem).end, ToolEnd.completed);
      expect((items[3] as TurnEndItem).outcome, TurnOutcome.finished);
      expect((items[3] as TurnEndItem).stopReason, StopReason.endTurn);
      expect(r.statuses, [AiStatus.running, AiStatus.idle]);
      expect(r.state.label, 'hi');
    },
  );

  test('permission: needs input, the answer reaches the agent', () async {
    final r = Rig(
      FakeScenario(
        turns: [
          [FakeSteps.permission('e1', 'Edit a.txt'), FakeSteps.text('done')],
        ],
      ),
    );
    addTearDown(r.dispose);
    await r.runtime.start();
    await r.runtime.send(hi);
    await r.until(() => r.state.currentPermission != null);
    expect(r.statuses, [AiStatus.running, AiStatus.needsInput]);
    final p = r.state.currentPermission!;
    expect(p.title, 'Edit a.txt');
    r.runtime.answerPermission(p.id, 'allow-once');
    await r.runtime.whenIdle();
    expect(r.agent().received, contains('permission:allow-once'));
    expect(r.statuses, [
      AiStatus.running,
      AiStatus.needsInput,
      AiStatus.running,
      AiStatus.idle,
    ]);
  });

  test(
    'cancel answers open questions cancelled; the turn ends cancelled',
    () async {
      final r = Rig(
        FakeScenario(
          turns: [
            [FakeSteps.permission('x', 'Run rm -rf build', kind: 'execute')],
          ],
        ),
      );
      addTearDown(r.dispose);
      await r.runtime.start();
      await r.runtime.send(hi);
      await r.until(() => r.state.currentPermission != null);
      final card = r.state.currentPermission!.item;
      r.runtime.cancel();
      await r.runtime.whenIdle();
      expect(
        r.agent().received,
        containsAllInOrder(['session/cancel', 'permission:cancelled']),
      );
      expect(card.permissionCancelled, isTrue);
      expect(
        r.state.timeline.items.whereType<TurnEndItem>().single.outcome,
        TurnOutcome.cancelled,
      );
      expect(r.state.needsInput, isFalse);
    },
  );

  test(
    'a hung agent: Force stop after the grace; the next prompt restarts and loads (spec §1.4)',
    () async {
      final r = Rig(
        FakeScenario(
          turns: [
            [FakeSteps.text('working'), FakeSteps.hang()],
          ],
        ),
        later: [
          FakeScenario(
            history: [
              {
                'sessionUpdate': 'user_message_chunk',
                'content': {'type': 'text', 'text': 'hi'},
              },
            ],
            turns: [
              [FakeSteps.text('after restart')],
            ],
          ),
        ],
        cancelGrace: const Duration(milliseconds: 50),
      );
      addTearDown(r.dispose);
      await r.runtime.start();
      await r.runtime.send(hi);
      await r.until(
        () => r.state.timeline.items.whereType<AgentTextItem>().isNotEmpty,
      );
      r.runtime.cancel();
      await r.until(() => r.state.turn?.canForceStop ?? false);
      await r.runtime.forceStop();
      await r.runtime.whenIdle();
      expect(r.launcher.channels.first.killCalls, 1);
      expect(r.state.phase, AgentPhase.stopped);
      expect(
        r.state.timeline.items.whereType<TurnEndItem>().single.outcome,
        TurnOutcome.cancelled,
      );

      expect(await r.runtime.send(const [TextBlock('again')]), isTrue);
      await r.until(
        () => r.state.timeline.items.whereType<TurnEndItem>().length == 2,
      );
      expect(r.launcher.channels, hasLength(2));
      expect(
        r.agent(1).received,
        containsAllInOrder(['session/load:sess-1', 'session/prompt:again']),
      );
      expect(
        r.state.timeline.items.whereType<UserItem>().map((u) => u.text),
        ['hi', 'again'],
        reason: 'the replay is not drawn twice',
      );
      expect(
        r.state.timeline.items.whereType<AgentTextItem>().last.text,
        'after restart',
      );
    },
  );

  test(
    'the agent dies mid-turn: interrupted, cards stopped, "dừng bất ngờ"; restart loads',
    () async {
      final r = Rig(
        FakeScenario(
          turns: [
            [
              FakeSteps.tool(
                't1',
                'npm test',
                kind: 'execute',
                status: 'in_progress',
              ),
              FakeSteps.exit(3),
            ],
          ],
        ),
        later: [const FakeScenario()],
      );
      addTearDown(r.dispose);
      await r.runtime.start();
      await r.runtime.send(hi);
      await r.until(() => r.state.phase == AgentPhase.failed);
      expect(
        r.state.timeline.items.whereType<TurnEndItem>().single.outcome,
        TurnOutcome.interrupted,
      );
      expect(r.state.timeline.tool('t1')!.end, ToolEnd.stopped);
      expect(
        r.state.timeline.items.whereType<NoticeItem>().map((n) => n.notice),
        contains(isA<AgentExited>().having((n) => n.exitCode, 'code', 3)),
      );
      expect(r.statuses.last, AiStatus.ended);
      await r.runtime.restart();
      expect(r.state.phase, AgentPhase.ready);
      expect(r.agent(1).received, contains('session/load:sess-1'));
    },
  );

  test(
    'output ShellX cannot read stops the agent and says so (spec §6)',
    () async {
      final r = Rig(
        FakeScenario(
          turns: [
            [
              FakeSteps.text('ok'),
              for (var i = 0; i < 21; i++)
                FakeSteps.raw('Welcome to my noisy profile $i'),
              FakeSteps.hang(),
            ],
          ],
        ),
      );
      addTearDown(r.dispose);
      await r.runtime.start();
      await r.runtime.send(hi);
      await r.until(() => r.state.phase == AgentPhase.failed);
      expect(
        r.state.timeline.items.whereType<TurnEndItem>().single.outcome,
        TurnOutcome.interrupted,
      );
      expect(
        r.state.timeline.items.whereType<NoticeItem>().single.notice,
        isA<AgentOutputInvalid>().having(
          (n) => n.reason,
          'reason',
          ConnectionCloseReason.tooManyBadLines,
        ),
      );
      expect(r.launcher.channels.single.exited, isTrue);
    },
  );

  test(
    'sign in: LoginNeeded, the terminal login command, retry after exit 0 (spec D8)',
    () async {
      final dir = Directory.systemTemp.createTempSync('auth');
      addTearDown(() => dir.deleteSync(recursive: true));
      final marker = p.join(dir.path, 'signed-in');
      final r = Rig(
        FakeScenario(
          requireAuth: true,
          authFile: marker,
          authMethods: const [
            {
              'id': 'login',
              'name': 'Log in',
              'type': 'terminal',
              'args': ['--login'],
              'env': {'MODE': 'x'},
            },
          ],
        ),
      );
      addTearDown(r.dispose);
      await r.runtime.start();
      expect(r.state.phase, AgentPhase.needsAuth);
      final notice = r.state.timeline.items.whereType<NoticeItem>().single;
      final method =
          (notice.notice as LoginNeeded).methods.single as AuthMethodTerminal;
      final login = r.runtime.loginCommand(method)!;
      expect(
        [login.executable, ...login.args],
        ['fake-agent', '--acp', '--login'],
      );
      expect(login.environment['MODE'], 'x');
      File(
        marker,
      ).writeAsStringSync(''); // what the run sheet's login leaves behind
      await r.runtime.retry();
      expect(r.state.phase, AgentPhase.ready);
      expect(notice.resolved, isTrue);
    },
  );

  group('setup problems are cards, and nothing starts (spec §4.5)', () {
    Future<AiNotice> failWith(AgentReadiness readiness) async {
      final r = Rig(const FakeScenario(), resolve: () async => readiness);
      addTearDown(r.dispose);
      await r.runtime.start();
      expect(r.state.phase, AgentPhase.failed);
      expect(r.launcher.channels, isEmpty);
      return r.state.timeline.items.whereType<NoticeItem>().single.notice;
    }

    test('node', () async {
      expect(
        await failWith(const AgentNeedsNode(required: 22, found: 'v20.1.0')),
        isA<NodeMissing>().having((n) => n.found, 'found', 'v20.1.0'),
      );
    });
    test('install', () async {
      expect(
        await failWith(const AgentNeedsInstall(null)),
        isA<AgentNotInstalled>().having((n) => n.canInstall, 'can', isFalse),
      );
    });
    test('missing command', () async {
      expect(
        await failWith(const AgentNotFound('opencode', shimOnly: true)),
        isA<AgentMissing>().having((n) => n.shimOnly, 'shim', isTrue),
      );
    });
    test('missing folder', () async {
      final r = Rig(const FakeScenario());
      addTearDown(r.dispose);
      Directory(r.project).deleteSync();
      await r.runtime.start();
      expect(
        r.state.timeline.items.whereType<NoticeItem>().single.notice,
        isA<FolderMissing>(),
      );
    });
  });

  group('resume (spec D14)', () {
    test('session/load replays the old conversation', () async {
      final r = Rig(
        const FakeScenario(
          history: [
            {
              'sessionUpdate': 'user_message_chunk',
              'content': {'type': 'text', 'text': 'q1'},
            },
            {
              'sessionUpdate': 'agent_message_chunk',
              'content': {'type': 'text', 'text': 'a1'},
            },
          ],
        ),
        resume: 'old-1',
      );
      addTearDown(r.dispose);
      await r.runtime.start();
      expect(r.state.sessionId, 'old-1');
      expect(r.state.timeline.items.map((i) => i.runtimeType.toString()), [
        'UserItem',
        'AgentTextItem',
      ]);
      expect(r.state.label, 'q1');
    });

    test('an agent without loadSession: a new session and a note', () async {
      final r = Rig(const FakeScenario(loadSession: false), resume: 'old-1');
      addTearDown(r.dispose);
      await r.runtime.start();
      expect(r.agent().received, contains('session/new'));
      expect(
        r.state.timeline.items.whereType<NoticeItem>().single.notice,
        isA<CannotResume>(),
      );
    });

    test(
      'the agent forgot the session (-32002): a new session and a note',
      () async {
        final r = Rig(
          const FakeScenario(
            loadSessionError: {'code': -32002, 'message': 'not found'},
          ),
          resume: 'old-1',
        );
        addTearDown(r.dispose);
        await r.runtime.start();
        expect(r.state.phase, AgentPhase.ready);
        expect(
          r.agent().received,
          containsAllInOrder(['session/load:old-1', 'session/new']),
        );
        expect(
          r.state.timeline.items.whereType<NoticeItem>().single.notice,
          isA<CannotResume>(),
        );
      },
    );
  });

  test(
    'queue: prompts sent during a turn go out in order; at most 5 (spec D16)',
    () async {
      final r = Rig(
        FakeScenario(
          turns: [
            [FakeSteps.sleep(30), FakeSteps.text('ok')],
          ],
        ),
      );
      addTearDown(r.dispose);
      await r.runtime.start();
      expect(await r.runtime.send(const [TextBlock('a')]), isTrue);
      for (final t in ['b', 'c', 'd', 'e', 'f']) {
        expect(await r.runtime.send([TextBlock(t)]), isTrue);
      }
      expect(
        await r.runtime.send(const [TextBlock('g')]),
        isFalse,
        reason: 'five already wait',
      );
      await r.until(
        () => r.state.timeline.items.whereType<TurnEndItem>().length == 6,
      );
      expect(
        r.agent().received.where((e) => e.startsWith('session/prompt:')),
        ['a', 'b', 'c', 'd', 'e', 'f'].map((t) => 'session/prompt:$t'),
      );
    },
  );

  test(
    'questions: a form answer; an unsupported form is declined by itself (spec D22)',
    () async {
      final r = Rig(
        FakeScenario(
          turns: [
            [
              FakeSteps.ask({
                'mode': 'form',
                'message': 'Approach?',
                'requestedSchema': {
                  'type': 'object',
                  'properties': {
                    'approach': {
                      'type': 'string',
                      'enum': ['a', 'b'],
                    },
                  },
                },
              }),
              FakeSteps.ask({
                'mode': 'form',
                'message': 'File?',
                'requestedSchema': {
                  'type': 'object',
                  'properties': {
                    'f': {'type': 'blob'},
                  },
                },
              }),
            ],
          ],
        ),
      );
      addTearDown(r.dispose);
      await r.runtime.start();
      await r.runtime.send(hi);
      await r.until(() => r.state.currentAsk != null);
      r.runtime.answerAsk(
        r.state.currentAsk!.id,
        const ElicitAccept({'approach': 'a'}),
      );
      await r.runtime.whenIdle();
      expect(
        r.agent().received,
        containsAllInOrder(['ask:accept={"approach":"a"}', 'ask:decline']),
      );
      expect(
        r.state.timeline.items.whereType<AskItem>().last.autoDeclined,
        isTrue,
      );
    },
  );

  test('an update after stopReason lands on the finished turn', () async {
    final r = Rig(
      FakeScenario(
        turns: [
          [
            FakeSteps.tool(
              'bg',
              'npm run dev',
              kind: 'execute',
              status: 'in_progress',
            ),
          ],
        ],
      ),
    );
    addTearDown(r.dispose);
    await r.runtime.start();
    await r.runtime.send(hi);
    await r.runtime.whenIdle();
    r.agent().connection.notify('session/update', {
      'sessionId': 'sess-1',
      'update': {
        'sessionUpdate': 'tool_call_update',
        'toolCallId': 'bg',
        'status': 'completed',
      },
    });
    await r.until(() => r.state.timeline.tool('bg')!.end == ToolEnd.completed);
    expect(r.state.timeline.tool('bg')!.turn, 1);
  });

  group('checkpoints (spec D12, Review Focus 5)', () {
    test('a turn that writes files is listed and can be undone', () async {
      final r = Rig(
        FakeScenario(
          turns: [
            [
              FakeSteps.write('a.txt', 'after'),
              FakeSteps.write('new/n.txt', 'n'),
            ],
          ],
        ),
        realCheckpoints: true,
      );
      addTearDown(r.dispose);
      File(p.join(r.project, 'a.txt')).writeAsStringSync('before');
      await r.runtime.start();
      await r.runtime.send(hi);
      await r.runtime.whenIdle();
      final end = r.state.timeline.items.whereType<TurnEndItem>().single;
      expect(
        {for (final c in end.changes!) c.path: c.kind},
        {'a.txt': ChangeKind.modified, 'new/n.txt': ChangeKind.added},
      );
      expect(
        (await r.runtime.changesSince(1))!.map((c) => c.path),
        unorderedEquals(['a.txt', 'new/n.txt']),
      );
      File(
        p.join(r.project, 'a.txt'),
      ).writeAsStringSync('edited by the user later');
      expect(await r.runtime.changedAfterTurn(1), {'a.txt'});
      expect(await r.runtime.revert(1, ['a.txt', 'new/n.txt']), isTrue);
      expect(File(p.join(r.project, 'a.txt')).readAsStringSync(), 'before');
      expect(File(p.join(r.project, 'new', 'n.txt')).existsSync(), isFalse);
    });

    test(
      'send waits for the first snapshot; the turn checkpoint is taken before the prompt',
      () async {
        final first = Completer<void>();
        final fake = FakeCheckpoints(warmupGate: first.future);
        final r = Rig(
          FakeScenario(
            turns: [
              [FakeSteps.text('ok')],
            ],
          ),
          checkpoints: () async => (fake, null),
        );
        addTearDown(r.dispose);
        await r.runtime.start();
        await r.runtime.send(hi);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(
          r.agent().received.where((e) => e.startsWith('session/prompt')),
          isEmpty,
          reason: 'still snapshotting',
        );
        first.complete();
        await r.runtime.whenIdle();
        expect(fake.refs, ['k1/0', 'k1/1']);
        expect(r.runtime.checkpointOf(1)!.commit, 'c-k1/1');
      },
    );

    test('Stop while the snapshot runs: the prompt never goes out', () async {
      final gate = Completer<void>();
      final fake = FakeCheckpoints(turnGate: gate.future);
      final r = Rig(
        FakeScenario(
          turns: [
            [FakeSteps.text('ok')],
          ],
        ),
        checkpoints: () async => (fake, null),
      );
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
        return r.dispose();
      });
      await r.runtime.start();
      await r.runtime.send(hi);
      await r.until(() => fake.refs.contains('k1/1'));
      r.runtime.cancel();
      await r.runtime.whenIdle().timeout(const Duration(seconds: 2));
      expect(
        r.state.timeline.items.whereType<TurnEndItem>().single.outcome,
        TurnOutcome.cancelled,
      );
      expect(
        r.agent().received.where((e) => e.startsWith('session/prompt')),
        isEmpty,
      );
    });

    test('undo off: a card says why; turns still run', () async {
      final r = Rig(
        FakeScenario(
          turns: [
            [FakeSteps.text('ok')],
          ],
        ),
        checkpoints: () async => (null, UndoOff.noCommandLineTools),
      );
      addTearDown(r.dispose);
      await r.runtime.start();
      await r.runtime.send(hi);
      await r.runtime.whenIdle();
      expect(
        r.state.timeline.items.whereType<NoticeItem>().single.notice,
        isA<UndoUnavailable>().having(
          (n) => n.reason,
          'reason',
          UndoOff.noCommandLineTools,
        ),
      );
      expect(
        r.state.timeline.items.whereType<TurnEndItem>().single.checkpoint,
        isNull,
      );
    });
  });

  test('dispose stops the agent', () async {
    final r = Rig(const FakeScenario());
    await r.runtime.start();
    await r.dispose();
    expect(r.launcher.channels.single.stopCalls, 1);
    expect(r.launcher.channels.single.exited, isTrue);
    expect(r.statuses.last, AiStatus.ended);
  });

  test('toString is redacted', () {
    final r = Rig(const FakeScenario());
    addTearDown(r.dispose);
    expect(r.runtime.toString(), '…');
  });
}

/// Checkpoints without git: records refs; gates let a test hold a snapshot.
final class FakeCheckpoints implements Checkpoints {
  FakeCheckpoints({this.warmupGate, this.turnGate});

  final Future<void>? warmupGate;
  final Future<void>? turnGate;
  final refs = <String>[];

  @override
  UndoOff? get off => null;

  @override
  Future<Checkpoint?> snapshot(String ref) async {
    refs.add(ref);
    final gate = ref.endsWith('/0') ? warmupGate : turnGate;
    if (gate != null) await gate;
    return Checkpoint(commit: 'c-$ref', tree: 't-$ref');
  }

  @override
  Future<String?> currentTree() async => 'after';

  @override
  Future<List<FileChange>> changes(String fromTree, [String? toTree]) async =>
      const [];

  @override
  Future<Set<String>> changedSince(String tree) async => const {};

  @override
  Future<List<int>?> fileAt(String treeish, String path) async => null;

  @override
  Future<void> restore(String treeish, Iterable<String> paths) async {}
}
