// Pins what the brief's runtime tests leave open: the dispatch decisions
// (settle before a turn ends, a smooth start), the lifecycle edges (dispose,
// restart, sign-in, failed starts), the status stream, the settings and
// session calls, and the undo calls. Each test names the break it catches.
import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_ai/testing.dart';
import 'package:test/test.dart';

import '../support/runtime_rig.dart';

const _form = {
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
};

void main() {
  group('a turn never ends while it still waits for an answer', () {
    test(
      'the agent exits while a permission is open: the card is cancelled first',
      () async {
        final r = RuntimeRig(
          first: FakeScenario(
            turns: [
              [FakeSteps.permission('e1', 'Edit a.txt')],
            ],
          ),
        );
        addTearDown(r.dispose);
        await r.runtime.start();
        final watch = SettleWatch(r.state);
        await r.runtime.send(hi);
        await r.until(() => r.state.currentPermission != null);
        final card = r.state.currentPermission!.item;
        await r.launcher.channels.single.kill();
        await r.until(() => r.state.phase == AgentPhase.failed);
        expect(card.permissionCancelled, isTrue);
        expect(r.state.permissions, isEmpty);
        expect(r.state.needsInput, isFalse);
        expect(r.turnEnds.single.outcome, TurnOutcome.interrupted);
        expect(r.statuses, [
          AiStatus.running,
          AiStatus.needsInput,
          AiStatus.ended,
        ]);
        expect(watch.checks, greaterThan(0));
        expect(
          watch.violations,
          0,
          reason: 'no view saw a finished turn waiting',
        );
      },
    );

    test('the agent exits while a question is open', () async {
      final r = RuntimeRig(
        first: FakeScenario(
          turns: [
            [FakeSteps.ask(_form)],
          ],
        ),
      );
      addTearDown(r.dispose);
      await r.runtime.start();
      final watch = SettleWatch(r.state);
      await r.runtime.send(hi);
      await r.until(() => r.state.currentAsk != null);
      final card = r.state.currentAsk!.item;
      await r.launcher.channels.single.kill();
      await r.until(() => r.state.phase == AgentPhase.failed);
      expect(card.response, isA<ElicitCancel>());
      expect(r.state.asks, isEmpty);
      expect(r.state.needsInput, isFalse);
      expect(watch.violations, 0);
    });

    test(
      'the turn ends with a permission still open: answered cancelled at once, before the undo data is read',
      () async {
        final gate = Completer<void>();
        final ck = RecordingCheckpoints()..treeGate = gate.future;
        final r = RuntimeRig(
          first: FakeScenario(
            turns: [
              [FakeSteps.permission('e1', 'Edit a.txt')],
            ],
          ),
          checkpoints: () async => (ck, null),
        );
        addTearDown(() {
          if (!gate.isCompleted) gate.complete();
          return r.dispose();
        });
        await r.runtime.start();
        final watch = SettleWatch(r.state);
        await r.runtime.send(hi);
        await r.until(() => r.state.currentPermission != null);
        // A second ask the agent does not wait for; the first one's answer
        // lets the agent finish its turn while this one is still open.
        final late = askPermission(r.agent(), 'late', 'Edit b.txt');
        await r.until(() => r.state.permissions.length == 2);
        final card = r.state.permissions.last.item;
        r.runtime.answerPermission(r.state.currentPermission!.id, 'allow-once');
        // The turn is over; its tree is still being read (the gate is shut).
        expect(
          await late.timeout(const Duration(seconds: 2)),
          {
            'outcome': {'outcome': 'cancelled'},
          },
          reason: 'the agent is not kept waiting for the undo data',
        );
        expect(gate.isCompleted, isFalse);
        expect(ck.calls, contains('tree'));
        gate.complete();
        await r.runtime.whenIdle();
        expect(card.permissionCancelled, isTrue);
        expect(r.state.needsInput, isFalse);
        expect(r.statuses, [
          AiStatus.running,
          AiStatus.needsInput,
          AiStatus.idle,
        ]);
        expect(watch.violations, 0);
      },
    );

    test('dispose while a permission is open', () async {
      final r = RuntimeRig(
        first: FakeScenario(
          turns: [
            [FakeSteps.permission('e1', 'Edit a.txt')],
          ],
        ),
      );
      addTearDown(r.dispose);
      await r.runtime.start();
      final watch = SettleWatch(r.state);
      await r.runtime.send(hi);
      await r.until(() => r.state.currentPermission != null);
      final card = r.state.currentPermission!.item;
      await r.runtime.dispose();
      expect(card.permissionCancelled, isTrue);
      expect(r.state.needsInput, isFalse);
      expect(r.turnEnds.single.outcome, TurnOutcome.cancelled);
      expect(r.statuses.last, AiStatus.ended);
      expect(watch.violations, 0);
    });

    test('Force stop while a permission is open', () async {
      final r = RuntimeRig(
        first: FakeScenario(
          turns: [
            [FakeSteps.permission('e1', 'Edit a.txt')],
          ],
        ),
      );
      addTearDown(r.dispose);
      await r.runtime.start();
      final watch = SettleWatch(r.state);
      await r.runtime.send(hi);
      await r.until(() => r.state.currentPermission != null);
      final card = r.state.currentPermission!.item;
      await r.runtime.forceStop();
      await r.until(() => r.state.phase == AgentPhase.stopped);
      expect(card.permissionCancelled, isTrue);
      expect(r.state.needsInput, isFalse);
      expect(r.turnEnds.single.outcome, TurnOutcome.cancelled);
      expect(watch.violations, 0);
    });

    test(
      'a question that comes in while the turn is wrapped up is settled too',
      () async {
        final gate = Completer<void>();
        final ck = RecordingCheckpoints()..treeGate = gate.future;
        final r = RuntimeRig(
          first: FakeScenario(
            turns: [
              [FakeSteps.text('ok')],
            ],
          ),
          checkpoints: () async => (ck, null),
        );
        addTearDown(() {
          if (!gate.isCompleted) gate.complete();
          return r.dispose();
        });
        await r.runtime.start();
        final watch = SettleWatch(r.state);
        await r.runtime.send(hi);
        // The agent has answered; the turn waits for the tree of the project.
        await r.until(() => ck.calls.contains('tree'));
        final answer = askPermission(r.agent(), 'late', 'Edit b.txt');
        await r.until(() => r.state.currentPermission != null);
        gate.complete();
        await r.runtime.whenIdle();
        expect(await answer, {
          'outcome': {'outcome': 'cancelled'},
        });
        expect(r.state.needsInput, isFalse);
        expect(watch.violations, 0);
        expect(r.statuses, [
          AiStatus.running,
          AiStatus.needsInput,
          AiStatus.idle,
        ]);
      },
    );
  });

  group('questions (spec D10, D22)', () {
    test(
      'a URL question waits for the user; "done" from the agent marks the card',
      () async {
        final r = RuntimeRig(
          first: FakeScenario(
            turns: [
              [
                FakeSteps.ask({
                  'mode': 'url',
                  'message': 'Sign in',
                  'elicitationId': 'el-1',
                  'url': 'https://example.com/login',
                }),
                FakeSteps.completeAsk('el-1'),
              ],
            ],
          ),
        );
        addTearDown(r.dispose);
        await r.runtime.start();
        await r.runtime.send(hi);
        await r.until(() => r.state.currentAsk != null);
        final card = r.state.currentAsk!.item;
        expect(card.request, isA<ElicitationUrl>());
        expect(r.statuses, [AiStatus.running, AiStatus.needsInput]);
        r.runtime.answerAsk(r.state.currentAsk!.id, const ElicitAccept());
        await r.runtime.whenIdle();
        expect(r.agent().received, contains('ask:accept'));
        expect(card.completed, isTrue);
      },
    );

    test(
      'a kind of question ShellX does not know is declined at once, unseen by the status',
      () async {
        final r = RuntimeRig(
          first: FakeScenario(
            turns: [
              [
                FakeSteps.ask({'mode': 'weird', 'message': 'Hm?'}),
              ],
            ],
          ),
        );
        addTearDown(r.dispose);
        await r.runtime.start();
        await r.runtime.send(hi);
        await r.runtime.whenIdle();
        expect(r.agent().received, contains('ask:decline'));
        expect(
          r.state.timeline.items.whereType<AskItem>().single.autoDeclined,
          isTrue,
        );
        expect(r.statuses, [AiStatus.running, AiStatus.idle]);
      },
    );

    test('Stop answers an open question cancelled', () async {
      final r = RuntimeRig(
        first: FakeScenario(
          turns: [
            [FakeSteps.ask(_form)],
          ],
        ),
      );
      addTearDown(r.dispose);
      await r.runtime.start();
      await r.runtime.send(hi);
      await r.until(() => r.state.currentAsk != null);
      final card = r.state.currentAsk!.item;
      r.runtime.cancel();
      await r.runtime.whenIdle();
      expect(
        r.agent().received,
        containsAllInOrder(['session/cancel', 'ask:cancel']),
      );
      expect(card.response, isA<ElicitCancel>());
      expect(r.state.needsInput, isFalse);
      expect(r.turnEnds.single.outcome, TurnOutcome.cancelled);
    });

    test(
      'after Stop, new questions are answered cancelled at once and draw no card',
      () async {
        final r = RuntimeRig(
          first: FakeScenario(
            turns: [
              [FakeSteps.hang()],
            ],
          ),
        );
        addTearDown(r.dispose);
        await r.runtime.start();
        await r.runtime.send(hi);
        r.runtime.cancel();
        expect(await askPermission(r.agent(), 'x', 'Edit a.txt'), {
          'outcome': {'outcome': 'cancelled'},
        });
        expect(await askQuestion(r.agent(), _form), {'action': 'cancel'});
        expect(r.state.permissions, isEmpty);
        expect(r.state.asks, isEmpty);
        expect(r.state.timeline.items.whereType<AskItem>(), isEmpty);
        expect(r.statuses, [AiStatus.running], reason: 'it never needed input');
      },
    );
  });

  group('start', () {
    test(
      'the phase is starting at once; the folder check does not block',
      () async {
        final r = RuntimeRig();
        addTearDown(r.dispose);
        Directory(r.project).deleteSync();
        final started = r.runtime.start();
        expect(
          r.state.phase,
          AgentPhase.starting,
          reason: 'the folder is checked without blocking the isolate',
        );
        await started;
        expect(r.state.phase, AgentPhase.failed);
        expect(r.notices.single, isA<FolderMissing>());
      },
    );

    test('two start calls are one start', () async {
      final r = RuntimeRig();
      addTearDown(r.dispose);
      await Future.wait([r.runtime.start(), r.runtime.start()]);
      expect(r.launcher.channels, hasLength(1));
      expect(r.state.phase, AgentPhase.ready);
      await r.runtime.start();
      expect(r.launcher.channels, hasLength(1), reason: 'a ready agent stays');
    });

    test(
      'a resolver that throws is a failed start, never a stuck one',
      () async {
        final r = RuntimeRig(
          resolve: () async => throw StateError('probe broke'),
        );
        addTearDown(r.dispose);
        await expectLater(r.runtime.start(), completes);
        expect(r.state.phase, AgentPhase.failed);
        expect(
          r.notices.single,
          isA<StartFailed>().having(
            (n) => n.reason,
            'reason',
            StartFailure.spawn,
          ),
        );
        expect(r.launcher.channels, isEmpty);
      },
    );

    test('a process that cannot be started: StartFailed(spawn)', () async {
      final r = RuntimeRig(
        launch: (command, {required cwd}) async =>
            throw const ProcessException('fake-agent', []),
      );
      addTearDown(r.dispose);
      await r.runtime.start();
      expect(r.state.phase, AgentPhase.failed);
      expect(
        r.notices.single,
        isA<StartFailed>().having(
          (n) => n.reason,
          'reason',
          StartFailure.spawn,
        ),
      );
    });

    test(
      'an agent that never answers initialize: StartFailed(timeout), stopped',
      () async {
        final silent = SilentChannel();
        final r = RuntimeRig(
          launch: (command, {required cwd}) async => silent,
          initializeTimeout: const Duration(milliseconds: 50),
        );
        addTearDown(r.dispose);
        await r.runtime.start();
        expect(r.state.phase, AgentPhase.failed);
        expect(
          r.notices.single,
          isA<StartFailed>().having(
            (n) => n.reason,
            'reason',
            StartFailure.timeout,
          ),
        );
        expect(silent.stopCalls, 1);
        expect(silent.exited, isTrue);
      },
    );

    test(
      'another protocol version: StartFailed(protocol), the agent is stopped',
      () async {
        final r = RuntimeRig(first: const FakeScenario(protocolVersion: 2));
        addTearDown(r.dispose);
        await r.runtime.start();
        expect(r.state.phase, AgentPhase.failed);
        expect(
          r.notices.single,
          isA<StartFailed>().having(
            (n) => n.reason,
            'reason',
            StartFailure.protocol,
          ),
        );
        expect(r.launcher.channels.single.exited, isTrue);
      },
    );

    test(
      'session/new that fails: StartFailed(session), the agent is stopped',
      () async {
        final r = RuntimeRig(
          first: const FakeScenario(
            newSessionError: {'code': -32603, 'message': 'boom'},
          ),
        );
        addTearDown(r.dispose);
        await r.runtime.start();
        expect(r.state.phase, AgentPhase.failed);
        expect(
          r.notices.single,
          isA<StartFailed>().having(
            (n) => n.reason,
            'reason',
            StartFailure.session,
          ),
        );
        expect(r.launcher.channels.single.exited, isTrue);
      },
    );

    test('a session with no id: StartFailed(protocol)', () async {
      final r = RuntimeRig(first: const FakeScenario(sessionId: ''));
      addTearDown(r.dispose);
      await r.runtime.start();
      expect(
        r.notices.single,
        isA<StartFailed>().having(
          (n) => n.reason,
          'reason',
          StartFailure.protocol,
        ),
      );
      expect(r.launcher.channels.single.exited, isTrue);
    });

    test(
      'retry after a failed start starts again and folds the old card',
      () async {
        final r = RuntimeRig(
          first: const FakeScenario(
            newSessionError: {'code': -32603, 'message': 'boom'},
          ),
          later: [const FakeScenario()],
        );
        addTearDown(r.dispose);
        await r.runtime.start();
        expect(r.state.phase, AgentPhase.failed);
        await r.runtime.retry();
        expect(r.state.phase, AgentPhase.ready);
        expect(r.launcher.channels, hasLength(2));
        expect(r.cards.single.resolved, isTrue);
      },
    );

    test('a restart folds the crash card but keeps the undo note', () async {
      final r = RuntimeRig(
        first: FakeScenario(
          turns: [
            [FakeSteps.exit(2)],
          ],
        ),
        later: [const FakeScenario()],
        checkpoints: () async => (null, UndoOff.noGit),
      );
      addTearDown(r.dispose);
      await r.runtime.start();
      await r.runtime.send(hi);
      await r.until(() => r.state.phase == AgentPhase.failed);
      await r.runtime.restart();
      expect(r.state.phase, AgentPhase.ready);
      final byKind = {
        for (final c in r.cards) c.notice.runtimeType: c.resolved,
      };
      expect(byKind[AgentExited], isTrue);
      expect(byKind[UndoUnavailable], isFalse);
    });
  });

  group('dispose', () {
    test('right after start: nothing is even looked up', () async {
      var looked = 0;
      final r = RuntimeRig(
        resolve: () async {
          looked++;
          return const AgentReady(fakeCommand);
        },
      );
      addTearDown(r.dispose);
      final started = r.runtime.start();
      await r.runtime.dispose();
      await started;
      expect(looked, 0);
      expect(r.launcher.channels, isEmpty);
      expect(r.state.phase, AgentPhase.stopped);
    });

    test('while the agent is still being found: nothing is launched', () async {
      final resolving = Completer<void>();
      final gate = Completer<void>();
      final r = RuntimeRig(
        resolve: () async {
          resolving.complete();
          await gate.future;
          return const AgentReady(fakeCommand);
        },
      );
      addTearDown(r.dispose);
      final started = r.runtime.start();
      await resolving.future;
      await r.runtime.dispose();
      gate.complete();
      await started;
      expect(r.launcher.channels, isEmpty);
      expect(r.state.phase, AgentPhase.stopped);
    });

    test('a start that never finishes does not keep waiters waiting', () async {
      final resolving = Completer<void>();
      final r = RuntimeRig(
        resolve: () {
          resolving.complete();
          return Completer<AgentReadiness>().future; // the probe hangs
        },
      );
      addTearDown(r.dispose);
      unawaited(r.runtime.start());
      final idle = r.runtime.whenIdle();
      await resolving.future;
      await r.runtime.dispose();
      await idle.timeout(const Duration(seconds: 1));
    });

    test(
      'while the process is being launched: the late process is stopped unasked',
      () async {
        final launching = Completer<void>();
        final gate = Completer<void>();
        final inner = FakeLauncher(const FakeScenario());
        final r = RuntimeRig(
          launch: (command, {required cwd}) async {
            launching.complete();
            await gate.future;
            return inner.call(command, cwd: cwd);
          },
        );
        addTearDown(r.dispose);
        final started = r.runtime.start();
        await launching.future;
        await r.runtime.dispose();
        gate.complete();
        await started;
        final channel = inner.channels.single;
        expect(channel.exited, isTrue, reason: 'no agent outlives its tab');
        expect(
          channel.agent.received,
          isEmpty,
          reason: 'it was not even asked',
        );
        expect(r.state.phase, AgentPhase.stopped);
      },
    );

    test(
      'while a turn runs: the turn ends cancelled and idle waiters wake',
      () async {
        final r = RuntimeRig(
          first: FakeScenario(
            turns: [
              [FakeSteps.hang()],
            ],
          ),
        );
        addTearDown(r.dispose);
        await r.runtime.start();
        await r.runtime.send(hi);
        final idle = r.runtime.whenIdle();
        await r.runtime.dispose();
        await idle.timeout(const Duration(seconds: 2));
        expect(r.turnEnds.single.outcome, TurnOutcome.cancelled);
        expect(r.state.phase, AgentPhase.stopped);
      },
    );

    test('twice is one stop', () async {
      final r = RuntimeRig();
      addTearDown(r.dispose);
      await r.runtime.start();
      await Future.wait([r.runtime.dispose(), r.runtime.dispose()]);
      await r.runtime.dispose();
      expect(r.launcher.channels.single.stopCalls, 1);
    });

    test('afterwards nothing is taken and nothing starts', () async {
      final r = RuntimeRig();
      addTearDown(r.dispose);
      await r.runtime.start();
      await r.runtime.dispose();
      expect(await r.runtime.send(hi), isFalse);
      expect(r.state.queue, isEmpty);
      await r.runtime.start();
      await r.runtime.restart();
      await r.runtime.retry();
      expect(r.launcher.channels, hasLength(1));
    });
  });

  group('restart', () {
    test(
      'while the agent hangs at initialize: the hung process goes, a new one starts',
      () async {
        // Its pipe closes a little after the exit is reported, as a real one does.
        final silent = SilentChannel(
          eofDelay: const Duration(milliseconds: 30),
        );
        final fresh = FakeLauncher(const FakeScenario());
        var launches = 0;
        final r = RuntimeRig(
          launch: (command, {required cwd}) async {
            if (launches++ == 0) return silent;
            return fresh.call(command, cwd: cwd);
          },
        );
        addTearDown(r.dispose);
        unawaited(r.runtime.start());
        await r.until(() => silent.written > 0); // initialize is out; no answer
        await r.runtime.restart();
        expect(silent.stopCalls, 1);
        expect(r.state.phase, AgentPhase.ready);
        expect(fresh.channels, hasLength(1));
        expect(fresh.channels.single.agent.received, contains('session/new'));
      },
    );

    test(
      'while the agent is still being found: the start finishes, its agent is replaced',
      () async {
        final gate = Completer<void>();
        final r = RuntimeRig(
          resolve: () async {
            await gate.future;
            return const AgentReady(fakeCommand);
          },
        );
        addTearDown(r.dispose);
        unawaited(r.runtime.start());
        final restarting = r.runtime.restart();
        gate.complete();
        await restarting;
        expect(r.state.phase, AgentPhase.ready);
        expect(r.launcher.channels, hasLength(2));
        expect(
          r.launcher.channels.first.exited,
          isTrue,
          reason: 'no stray agent',
        );
        expect(r.launcher.channels.last.exited, isFalse);
      },
    );

    test(
      'while a turn runs: the turn ends cancelled, the new agent loads the session',
      () async {
        final r = RuntimeRig(
          first: FakeScenario(
            turns: [
              [FakeSteps.text('working'), FakeSteps.hang()],
            ],
          ),
          later: [const FakeScenario()],
        );
        addTearDown(r.dispose);
        await r.runtime.start();
        await r.runtime.send(hi);
        await r.until(
          () => r.state.timeline.items.whereType<AgentTextItem>().isNotEmpty,
        );
        await r.runtime.restart();
        expect(r.state.phase, AgentPhase.ready);
        expect(r.turnEnds.single.outcome, TurnOutcome.cancelled);
        expect(r.launcher.channels.first.exited, isTrue);
        expect(r.agent(1).received, contains('session/load:sess-1'));
        expect(r.statuses, [AiStatus.running, AiStatus.ended]);
      },
    );
  });

  group('sign in (spec D8)', () {
    test(
      'an agent-type method: authenticate, then the session opens',
      () async {
        final r = RuntimeRig(
          first: const FakeScenario(
            requireAuth: true,
            authMethods: [
              {'id': 'a1', 'name': 'Agent login', 'type': 'agent'},
            ],
          ),
        );
        addTearDown(r.dispose);
        await r.runtime.start();
        expect(r.state.phase, AgentPhase.needsAuth);
        expect(await r.runtime.authenticate('a1'), isTrue);
        expect(r.state.phase, AgentPhase.ready);
        expect(r.agent().received, [
          'initialize',
          'session/new',
          'authenticate:a1',
          'session/new',
        ]);
        expect(r.cards.single.resolved, isTrue);
      },
    );

    test(
      'authenticate outside the sign-in state is refused and opens no second session',
      () async {
        final r = RuntimeRig();
        addTearDown(r.dispose);
        expect(
          await r.runtime.authenticate('a1'),
          isFalse,
          reason: 'no agent yet',
        );
        await r.runtime.start();
        expect(await r.runtime.authenticate('a1'), isFalse, reason: 'ready');
        expect(
          r.agent().received.where((e) => e.startsWith('authenticate')),
          isEmpty,
        );
        expect(
          r.agent().received.where((e) => e == 'session/new'),
          hasLength(1),
        );
      },
    );

    test('two authenticate calls at once open one session', () async {
      final r = RuntimeRig(
        first: const FakeScenario(
          requireAuth: true,
          authMethods: [
            {'id': 'a1', 'name': 'Agent login', 'type': 'agent'},
          ],
        ),
      );
      addTearDown(r.dispose);
      await r.runtime.start();
      final both = await Future.wait([
        r.runtime.authenticate('a1'),
        r.runtime.authenticate('a1'),
      ]);
      expect(both.first, isTrue);
      expect(r.state.phase, AgentPhase.ready);
      expect(
        r.agent().received.where((e) => e == 'session/new'),
        hasLength(2),
        reason: 'the failed one and the one after the sign-in',
      );
    });

    test('retry while still signed out keeps one open card', () async {
      final r = RuntimeRig(
        first: const FakeScenario(
          requireAuth: true,
          authMethods: [
            {'id': 'login', 'name': 'Log in', 'type': 'terminal'},
          ],
        ),
      );
      addTearDown(r.dispose);
      await r.runtime.start();
      await r.runtime.retry(); // the login did not take
      expect(r.state.phase, AgentPhase.needsAuth);
      final cards = r.cards.where((c) => c.notice is LoginNeeded).toList();
      expect(cards.where((c) => !c.resolved), hasLength(1));
    });

    test(
      'the "cannot resume" note is given once, even with a sign-in in between',
      () async {
        final dir = Directory.systemTemp.createTempSync('auth');
        addTearDown(() => dir.deleteSync(recursive: true));
        final marker = p.join(dir.path, 'signed-in');
        final r = RuntimeRig(
          first: FakeScenario(
            loadSession: false,
            requireAuth: true,
            authFile: marker,
            authMethods: const [
              {'id': 'login', 'name': 'Log in', 'type': 'terminal'},
            ],
          ),
          resume: 'old-1',
        );
        addTearDown(r.dispose);
        await r.runtime.start();
        expect(r.state.phase, AgentPhase.needsAuth);
        File(marker).writeAsStringSync('');
        await r.runtime.retry();
        expect(r.state.phase, AgentPhase.ready);
        expect(r.notices.whereType<CannotResume>(), hasLength(1));
      },
    );

    test('the login command exists only after the agent was found', () async {
      final r = RuntimeRig();
      addTearDown(r.dispose);
      const method = AuthMethodTerminal(id: 'login', name: 'Log in');
      expect(r.runtime.loginCommand(method), isNull);
      await r.runtime.start();
      expect(r.runtime.loginCommand(method)!.args, ['--acp']);
    });
  });

  group('a resumed tab keeps its replay after a card (spec D14, D15)', () {
    const history = [
      {
        'sessionUpdate': 'user_message_chunk',
        'content': {'type': 'text', 'text': 'q1'},
      },
      {
        'sessionUpdate': 'agent_message_chunk',
        'content': {'type': 'text', 'text': 'a1'},
      },
    ];

    void expectReplayed(RuntimeRig r) {
      final items = r.state.timeline.items;
      expect(items.whereType<UserItem>().map((u) => u.text), ['q1']);
      expect(items.whereType<AgentTextItem>().map((t) => t.text), ['a1']);
      expect(r.state.label, 'q1');
    }

    test('a sign-in card, then the login, then retry', () async {
      final dir = Directory.systemTemp.createTempSync('auth');
      addTearDown(() => dir.deleteSync(recursive: true));
      final marker = p.join(dir.path, 'signed-in');
      final r = RuntimeRig(
        first: FakeScenario(
          requireAuth: true,
          authFile: marker,
          authMethods: const [
            {'id': 'login', 'name': 'Log in', 'type': 'terminal'},
          ],
          history: history,
        ),
        resume: 'old-1',
      );
      addTearDown(r.dispose);
      await r.runtime.start();
      expect(r.state.phase, AgentPhase.needsAuth);
      File(marker).writeAsStringSync('');
      await r.runtime.retry();
      expect(r.state.phase, AgentPhase.ready);
      expect(r.state.sessionId, 'old-1');
      expectReplayed(r);
    });

    test(
      'a "Node missing" card, then the setup is fixed, then retry',
      () async {
        var fixed = false;
        final r = RuntimeRig(
          first: const FakeScenario(history: history),
          resolve: () async => fixed
              ? const AgentReady(fakeCommand)
              : const AgentNeedsNode(required: 22, found: 'v20.1.0'),
          resume: 'old-1',
        );
        addTearDown(r.dispose);
        await r.runtime.start();
        expect(r.state.phase, AgentPhase.failed);
        expect(r.notices.single, isA<NodeMissing>());
        fixed = true;
        await r.runtime.retry();
        expect(r.state.phase, AgentPhase.ready);
        expect(r.state.sessionId, 'old-1');
        expectReplayed(r);
      },
    );

    test('a failed first start, then restart', () async {
      final r = RuntimeRig(
        first: const FakeScenario(
          loadSessionError: {'code': -32603, 'message': 'boom'},
          history: history,
        ),
        later: const [FakeScenario(history: history)],
        resume: 'old-1',
      );
      addTearDown(r.dispose);
      await r.runtime.start();
      expect(r.state.phase, AgentPhase.failed);
      expect(
        r.notices.single,
        isA<StartFailed>().having(
          (n) => n.reason,
          'reason',
          StartFailure.session,
        ),
      );
      await r.runtime.restart();
      expect(r.state.phase, AgentPhase.ready);
      expectReplayed(r);
    });

    test(
      'a restart of a tab that shows the conversation still does not draw it twice',
      () async {
        final r = RuntimeRig(
          first: const FakeScenario(history: history),
          later: const [FakeScenario(history: history)],
          resume: 'old-1',
        );
        addTearDown(r.dispose);
        await r.runtime.start();
        expectReplayed(r);
        await r.runtime.restart();
        expect(r.state.phase, AgentPhase.ready);
        expect(r.agent(1).received, contains('session/load:old-1'));
        expectReplayed(r);
      },
    );
  });

  group('a session that cannot be reopened (final review I-6)', () {
    const history = [
      {
        'sessionUpdate': 'user_message_chunk',
        'content': {'type': 'text', 'text': 'q1'},
      },
      {
        'sessionUpdate': 'agent_message_chunk',
        'content': {'type': 'text', 'text': 'a1'},
      },
    ];
    const boom = {'code': -32603, 'message': 'boom'};

    List<String> loads(FakeAgent a) =>
        a.received.where((e) => e.startsWith('session/load')).toList();

    test('"Start a new session" drops the old id, opens a new session and '
        'says so once', () async {
      final r = RuntimeRig(
        first: const FakeScenario(loadSessionError: boom, history: history),
        later: const [FakeScenario()],
        resume: 'old-1',
      );
      addTearDown(r.dispose);
      await r.runtime.start();
      expect(r.state.phase, AgentPhase.failed);
      expect(r.notices.single, isA<StartFailed>());
      expect(r.runtime.resumesSession, isTrue);

      await r.runtime.retry(newSession: true);

      expect(r.state.phase, AgentPhase.ready);
      expect(r.agent(1).received, contains('session/new'));
      expect(loads(r.agent(1)), isEmpty, reason: 'the old one is let go');
      expect(r.state.sessionId, 'sess-1');
      expect(r.notices.whereType<CannotResume>(), hasLength(1));
      expect(
        r.cards.firstWhere((c) => c.notice is StartFailed).resolved,
        isTrue,
        reason: 'the failure card folds',
      );
    });

    test(
      'a plain retry repeats the same load (that is what is stuck)',
      () async {
        final r = RuntimeRig(
          first: const FakeScenario(loadSessionError: boom, history: history),
          later: const [FakeScenario(loadSessionError: boom)],
          resume: 'old-1',
        );
        addTearDown(r.dispose);
        await r.runtime.start();
        await r.runtime.retry();
        expect(r.state.phase, AgentPhase.failed);
        expect(loads(r.agent(1)), ['session/load:old-1']);
      },
    );

    test('later restarts reopen the new session, not the old one', () async {
      final r = RuntimeRig(
        first: const FakeScenario(loadSessionError: boom),
        later: const [FakeScenario()],
        resume: 'old-1',
      );
      addTearDown(r.dispose);
      await r.runtime.start();
      await r.runtime.retry(newSession: true);
      await r.runtime.restart();
      expect(r.state.phase, AgentPhase.ready);
      expect(loads(r.agent(2)), ['session/load:sess-1']);
      expect(r.notices.whereType<CannotResume>(), hasLength(1));
    });

    test(
      'a tab that resumes nothing says so, and the call is a plain retry',
      () async {
        var fixed = false;
        final r = RuntimeRig(
          resolve: () async => fixed
              ? const AgentReady(fakeCommand)
              : const AgentNeedsNode(required: 22, found: 'v20.1.0'),
        );
        addTearDown(r.dispose);
        await r.runtime.start();
        expect(r.runtime.resumesSession, isFalse);
        fixed = true;
        await r.runtime.retry(newSession: true);
        expect(r.state.phase, AgentPhase.ready);
        expect(
          r.notices.whereType<CannotResume>(),
          isEmpty,
          reason: 'there was nothing to let go',
        );
      },
    );

    test(
      'a second ask while the first is under way does not say it twice',
      () async {
        final r = RuntimeRig(
          first: const FakeScenario(loadSessionError: boom),
          later: const [FakeScenario()],
          resume: 'old-1',
        );
        addTearDown(r.dispose);
        await r.runtime.start();
        await Future.wait([
          r.runtime.retry(newSession: true),
          r.runtime.retry(newSession: true),
        ]);
        expect(r.state.phase, AgentPhase.ready);
        expect(r.notices.whereType<CannotResume>(), hasLength(1));
        expect(r.launcher.channels, hasLength(2), reason: 'one new agent');
      },
    );

    test(
      'a tab waiting for a sign-in can start a new session as well',
      () async {
        final r = RuntimeRig(
          first: const FakeScenario(
            requireAuth: true,
            authMethods: [
              {'id': 'login', 'name': 'Log in', 'type': 'terminal'},
            ],
          ),
          resume: 'old-1',
        );
        addTearDown(r.dispose);
        await r.runtime.start();
        expect(r.state.phase, AgentPhase.needsAuth);
        await r.runtime.retry(newSession: true);
        expect(r.state.phase, AgentPhase.needsAuth, reason: 'still signed out');
        expect(r.runtime.resumesSession, isFalse);
        expect(r.notices.whereType<CannotResume>(), hasLength(1));
      },
    );
  });

  group('status (spec D13)', () {
    test(
      'Stop with a question open: running again at once, even if the agent hangs',
      () async {
        final r = RuntimeRig(
          first: FakeScenario(
            turns: [
              [FakeSteps.hang()],
            ],
          ),
        );
        addTearDown(r.dispose);
        await r.runtime.start();
        await r.runtime.send(hi);
        final answer = askPermission(r.agent(), 'x', 'Edit a.txt');
        await r.until(() => r.state.currentPermission != null);
        expect(r.statuses, [AiStatus.running, AiStatus.needsInput]);
        r.runtime.cancel();
        expect(r.statuses, [
          AiStatus.running,
          AiStatus.needsInput,
          AiStatus.running,
        ], reason: 'nothing waits for the user any more');
        expect(await answer, {
          'outcome': {'outcome': 'cancelled'},
        });
        expect(
          r.state.turn,
          isNotNull,
          reason: 'the agent has not answered yet',
        );
        expect(r.statuses.last, AiStatus.running);
      },
    );

    test(
      'Stop with a question open and an agent that ends its turn: running, then idle',
      () async {
        final r = RuntimeRig(
          first: FakeScenario(
            turns: [
              [FakeSteps.ask(_form)],
            ],
          ),
        );
        addTearDown(r.dispose);
        await r.runtime.start();
        await r.runtime.send(hi);
        await r.until(() => r.state.currentAsk != null);
        r.runtime.cancel();
        await r.runtime.whenIdle();
        expect(r.statuses, [
          AiStatus.running,
          AiStatus.needsInput,
          AiStatus.running,
          AiStatus.idle,
        ]);
      },
    );

    test(
      'a question outside any turn needs input; the answer returns the tab to idle',
      () async {
        final r = RuntimeRig();
        addTearDown(r.dispose);
        await r.runtime.start();
        final answer = askPermission(r.agent(), 'bg', 'Run npm run dev');
        await r.until(() => r.state.currentPermission != null);
        expect(r.statuses, [AiStatus.needsInput]);
        r.runtime.answerPermission(r.state.currentPermission!.id, 'allow-once');
        expect(await answer, {
          'outcome': {'outcome': 'selected', 'optionId': 'allow-once'},
        });
        expect(r.statuses, [AiStatus.needsInput, AiStatus.idle]);
      },
    );

    test(
      'with two questions open the tab needs input until the last is answered',
      () async {
        final r = RuntimeRig(
          first: FakeScenario(
            turns: [
              [
                FakeSteps.permission('e1', 'Edit a.txt'),
                FakeSteps.text('done'),
              ],
            ],
          ),
        );
        addTearDown(r.dispose);
        await r.runtime.start();
        await r.runtime.send(hi);
        await r.until(() => r.state.currentPermission != null);
        final second = askPermission(r.agent(), 'e2', 'Edit b.txt');
        await r.until(() => r.state.permissions.length == 2);
        expect(
          r.state.currentPermission!.title,
          'Edit a.txt',
          reason: 'in order',
        );
        r.runtime.answerPermission(r.state.currentPermission!.id, 'allow-once');
        expect(r.state.currentPermission!.title, 'Edit b.txt');
        expect(r.statuses, [AiStatus.running, AiStatus.needsInput]);
        r.runtime.answerPermission(r.state.currentPermission!.id, null);
        expect(r.statuses, [
          AiStatus.running,
          AiStatus.needsInput,
          AiStatus.running,
        ]);
        expect(await second, {
          'outcome': {'outcome': 'cancelled'},
        });
        await r.runtime.whenIdle();
        expect(r.statuses.last, AiStatus.idle);
      },
    );

    test('an unknown id is ignored', () async {
      final r = RuntimeRig(
        first: FakeScenario(
          turns: [
            [FakeSteps.permission('e1', 'Edit a.txt')],
          ],
        ),
      );
      addTearDown(r.dispose);
      await r.runtime.start();
      await r.runtime.send(hi);
      await r.until(() => r.state.currentPermission != null);
      r.runtime.answerPermission(999, 'allow-once');
      r.runtime.answerAsk(999, const ElicitDecline());
      expect(r.state.currentPermission, isNotNull);
      expect(r.statuses, [AiStatus.running, AiStatus.needsInput]);
    });

    test(
      'queued prompts run back to back without an idle in between',
      () async {
        final r = RuntimeRig(
          first: FakeScenario(
            turns: [
              [FakeSteps.sleep(10), FakeSteps.text('ok')],
            ],
          ),
        );
        addTearDown(r.dispose);
        await r.runtime.start();
        await r.runtime.send(const [TextBlock('a')]);
        await r.runtime.send(const [TextBlock('b')]);
        await r.until(() => r.turnEnds.length == 2);
        await r.runtime.whenIdle();
        expect(r.statuses, [AiStatus.running, AiStatus.idle]);
      },
    );
  });

  group('how a turn ends (spec §4.2)', () {
    test(
      'the agent answers the prompt with an error: failed, and the tab takes the next prompt',
      () async {
        final r = RuntimeRig(
          first: FakeScenario(
            turns: [
              [FakeSteps.error(-32603, 'model overloaded')],
              [FakeSteps.text('fine')],
            ],
          ),
        );
        addTearDown(r.dispose);
        await r.runtime.start();
        await r.runtime.send(hi);
        await r.runtime.whenIdle();
        final end = r.turnEnds.single;
        expect(end.outcome, TurnOutcome.failed);
        expect(end.error, 'model overloaded');
        expect(end.stopReason, isNull);
        expect(r.state.phase, AgentPhase.ready);
        expect(r.statuses, [AiStatus.running, AiStatus.idle]);
        expect(await r.runtime.send(const [TextBlock('again')]), isTrue);
        await r.runtime.whenIdle();
        expect(r.turnEnds.last.outcome, TurnOutcome.finished);
      },
    );

    test(
      'a stop reason other than end_turn is kept; only cancelled is a cancelled turn',
      () async {
        final r = RuntimeRig(
          first: FakeScenario(
            turns: [
              [FakeSteps.stop('refusal')],
              [FakeSteps.stop('max_tokens')],
              [FakeSteps.stop('cancelled')],
            ],
          ),
        );
        addTearDown(r.dispose);
        await r.runtime.start();
        for (final t in ['a', 'b', 'c']) {
          await r.runtime.send([TextBlock(t)]);
          await r.runtime.whenIdle();
        }
        expect(
          [for (final e in r.turnEnds) (e.outcome, e.stopReason)],
          [
            (TurnOutcome.finished, StopReason.refusal),
            (TurnOutcome.finished, StopReason.maxTokens),
            (TurnOutcome.cancelled, StopReason.cancelled),
          ],
        );
      },
    );
  });

  group('an agent that misbehaves (spec §6)', () {
    test(
      'garbled output from an agent that ignores EOF: it is killed',
      () async {
        final inner = FakeAgentChannel(
          FakeScenario(
            turns: [
              [
                FakeSteps.text('ok'),
                for (var i = 0; i < 21; i++) FakeSteps.raw('banner $i'),
                FakeSteps.hang(),
              ],
            ],
          ),
        );
        final r = RuntimeRig(
          launch: (command, {required cwd}) async => StubbornChannel(inner),
        );
        addTearDown(r.dispose);
        await r.runtime.start();
        await r.runtime.send(hi);
        await r.until(() => r.state.phase == AgentPhase.failed);
        expect(inner.killCalls, 1, reason: 'closing its stdin was not enough');
        expect(r.notices.single, isA<AgentOutputInvalid>());
        expect(r.turnEnds.single.outcome, TurnOutcome.interrupted);
      },
    );
  });

  group('send and wait', () {
    test('a failed agent and a signed-out agent take nothing', () async {
      final failing = RuntimeRig(
        first: const FakeScenario(
          newSessionError: {'code': -32603, 'message': 'boom'},
        ),
      );
      addTearDown(failing.dispose);
      await failing.runtime.start();
      expect(await failing.runtime.send(hi), isFalse);
      expect(failing.state.queue, isEmpty);
      final signedOut = RuntimeRig(
        first: const FakeScenario(
          requireAuth: true,
          authMethods: [
            {'id': 'login', 'name': 'Log in', 'type': 'terminal'},
          ],
        ),
      );
      addTearDown(signedOut.dispose);
      await signedOut.runtime.start();
      expect(await signedOut.runtime.send(hi), isFalse);
      expect(signedOut.state.queue, isEmpty);
    });

    test(
      'a prompt sent while the agent starts waits and goes out when it is ready',
      () async {
        final r = RuntimeRig();
        addTearDown(r.dispose);
        final started = r.runtime.start();
        expect(r.state.phase, AgentPhase.starting);
        expect(await r.runtime.send(hi), isTrue);
        expect(r.state.queue, hasLength(1));
        await started;
        await r.runtime.whenIdle();
        expect(r.agent().received, contains('session/prompt:hi'));
        expect(r.state.queue, isEmpty);
      },
    );

    test(
      'whenIdle called while the agent starts returns when it is ready',
      () async {
        final r = RuntimeRig();
        addTearDown(r.dispose);
        final started = r.runtime.start();
        final idle = r.runtime.whenIdle();
        await started;
        await idle.timeout(const Duration(seconds: 1));
        expect(r.state.phase, AgentPhase.ready);
      },
    );

    test(
      'whenIdle called while the agent starts returns when the start fails',
      () async {
        final r = RuntimeRig(
          resolve: () async => const AgentNotFound('fake-agent'),
        );
        addTearDown(r.dispose);
        final started = r.runtime.start();
        final idle = r.runtime.whenIdle();
        await started;
        await idle.timeout(const Duration(seconds: 1));
        expect(r.state.phase, AgentPhase.failed);
      },
    );

    test(
      'whenIdle called while the agent starts returns when it asks for a sign-in',
      () async {
        final r = RuntimeRig(
          first: const FakeScenario(
            requireAuth: true,
            authMethods: [
              {'id': 'login', 'name': 'Log in', 'type': 'terminal'},
            ],
          ),
        );
        addTearDown(r.dispose);
        final started = r.runtime.start();
        final idle = r.runtime.whenIdle();
        await started;
        await idle.timeout(const Duration(seconds: 1));
        expect(r.state.phase, AgentPhase.needsAuth);
      },
    );

    test(
      'whenIdle returns when the agent died with prompts still waiting',
      () async {
        final r = RuntimeRig(
          first: FakeScenario(
            turns: [
              [FakeSteps.hang()],
            ],
          ),
        );
        addTearDown(r.dispose);
        await r.runtime.start();
        await r.runtime.send(const [TextBlock('a')]);
        await r.runtime.send(const [TextBlock('b')]);
        await r.launcher.channels.single.kill();
        await r.until(() => r.state.phase == AgentPhase.failed);
        expect(r.state.queue, hasLength(1));
        await r.runtime.whenIdle().timeout(const Duration(seconds: 1));
      },
    );

    test(
      'whenIdle returns when the agent waits for a sign-in with prompts waiting',
      () async {
        final r = RuntimeRig(
          first: const FakeScenario(
            requireAuth: true,
            authMethods: [
              {'id': 'login', 'name': 'Log in', 'type': 'terminal'},
            ],
          ),
        );
        addTearDown(r.dispose);
        final started = r.runtime.start();
        expect(await r.runtime.send(hi), isTrue);
        await started;
        expect(r.state.phase, AgentPhase.needsAuth);
        expect(r.state.queue, hasLength(1));
        await r.runtime.whenIdle().timeout(const Duration(seconds: 1));
      },
    );
  });

  group('stop (spec §1.4)', () {
    test('Force stop is offered only after the grace', () async {
      final r = RuntimeRig(
        first: FakeScenario(
          turns: [
            [FakeSteps.hang()],
          ],
        ),
        cancelGrace: const Duration(milliseconds: 400),
      );
      addTearDown(r.dispose);
      await r.runtime.start();
      await r.runtime.send(hi);
      r.runtime.cancel();
      expect(r.state.turn!.cancelRequested, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(r.state.turn!.canForceStop, isFalse, reason: 'inside the grace');
      await r.until(() => r.state.turn?.canForceStop ?? false);
    });

    test('Stop twice sends one session/cancel', () async {
      final r = RuntimeRig(
        first: FakeScenario(
          turns: [
            [FakeSteps.hang()],
          ],
        ),
      );
      addTearDown(r.dispose);
      await r.runtime.start();
      await r.runtime.send(hi);
      r.runtime.cancel();
      r.runtime.cancel();
      await r.until(() => r.agent().received.contains('session/cancel'));
      expect(
        r.agent().received.where((e) => e == 'session/cancel'),
        hasLength(1),
      );
    });

    test('Stop and Force stop with nothing running do nothing', () async {
      final r = RuntimeRig();
      addTearDown(r.dispose);
      r.runtime.cancel();
      await r.runtime.forceStop();
      await r.runtime.start();
      r.runtime.cancel();
      expect(r.state.phase, AgentPhase.ready);
      expect(r.agent().received, isNot(contains('session/cancel')));
    });
  });

  group('settings and sessions (spec D11, D15)', () {
    const options = [
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
        'id': 'effort',
        'name': 'Effort',
        'type': 'select',
        'currentValue': 'high',
        'options': [
          {'value': 'high', 'name': 'High'},
          {'value': 'low', 'name': 'Low'},
        ],
      },
      {
        'id': 'think',
        'name': 'Think',
        'type': 'boolean',
        'currentValue': false,
      },
    ];

    test(
      'a remembered Bypass is never applied, whichever way the mode is named',
      () async {
        const modeChoices = [
          {'value': 'default', 'name': 'Manual'},
          {'value': 'bypassPermissions', 'name': 'Bypass permissions'},
        ];
        final r = RuntimeRig(
          first: const FakeScenario(
            configOptions: [
              {
                'id': 'permissions',
                'name': 'Permissions',
                'category': 'mode',
                'type': 'select',
                'currentValue': 'default',
                'options': modeChoices,
              },
              {
                'id': 'mode',
                'name': 'Mode',
                'type': 'select',
                'currentValue': 'default',
                'options': modeChoices,
              },
            ],
          ),
          preferred: {
            'permissions': 'bypassPermissions',
            'mode': 'bypassPermissions',
          },
        );
        addTearDown(r.dispose);
        await r.runtime.start();
        expect(
          r.agent().received.where(
            (e) => e.startsWith('session/set_config_option'),
          ),
          isEmpty,
        );
      },
    );

    test(
      'remembered choices: valid ones are applied, the rest are skipped',
      () async {
        final r = RuntimeRig(
          first: const FakeScenario(configOptions: options),
          preferred: {
            'think': true, // a boolean the agent offers
            'model': 'zzz', // not a choice
            'effort': 'high', // already so
            'think2': true, // not offered
          },
        );
        addTearDown(r.dispose);
        await r.runtime.start();
        final sent = r.agent().received.where(
          (e) => e.startsWith('session/set_config_option'),
        );
        expect(sent, ['session/set_config_option:think=true']);
        expect(
          r.agent().params['session/set_config_option']!['type'],
          'boolean',
        );
        expect(
          r.state.configOptions!
              .firstWhere((o) => o.id == 'think')
              .currentValue,
          true,
        );
      },
    );

    test('setConfig sends the choice and the state follows', () async {
      final r = RuntimeRig(first: const FakeScenario(configOptions: options));
      addTearDown(r.dispose);
      await r.runtime.start();
      await r.runtime.setConfig('model', 'b');
      expect(r.agent().received, contains('session/set_config_option:model=b'));
      expect(
        r.state.configOptions!.firstWhere((o) => o.id == 'model').currentValue,
        'b',
      );
    });

    test(
      'setMode (an agent with legacy modes only) changes the current mode',
      () async {
        final r = RuntimeRig(
          first: const FakeScenario(
            modes: {
              'currentModeId': 'ask',
              'availableModes': [
                {'id': 'ask', 'name': 'Ask'},
                {'id': 'code', 'name': 'Code'},
              ],
            },
          ),
        );
        addTearDown(r.dispose);
        await r.runtime.start();
        expect(r.state.modes!.currentModeId, 'ask');
        await r.runtime.setMode('code');
        expect(r.agent().received, contains('session/set_mode:code'));
        expect(r.state.modes!.currentModeId, 'code');
      },
    );

    test(
      'setMode changes the current mode even when the agent says nothing about it',
      () async {
        final inner = FakeAgentChannel(
          const FakeScenario(
            modes: {
              'currentModeId': 'ask',
              'availableModes': [
                {'id': 'ask', 'name': 'Ask'},
                {'id': 'code', 'name': 'Code'},
              ],
            },
          ),
        );
        final r = RuntimeRig(
          launch: (command, {required cwd}) async =>
              SilentAbout(inner, 'current_mode_update'),
        );
        addTearDown(r.dispose);
        await r.runtime.start();
        await r.runtime.setMode('code');
        expect(inner.agent.received, contains('session/set_mode:code'));
        expect(r.state.modes!.currentModeId, 'code');
      },
    );

    test('settings before the agent runs are ignored', () async {
      final r = RuntimeRig();
      addTearDown(r.dispose);
      await r.runtime.setConfig('model', 'b');
      await r.runtime.setMode('code');
      expect(await r.runtime.listSessions(), isNull);
      expect(r.launcher.channels, isEmpty);
    });

    test(
      'listSessions asks for this folder and passes the cursor on',
      () async {
        final r = RuntimeRig(
          first: const FakeScenario(
            sessions: [
              {'sessionId': 's-9', 'cwd': '/x', 'title': 'Old chat'},
            ],
          ),
        );
        addTearDown(r.dispose);
        await r.runtime.start();
        final result = await r.runtime.listSessions(cursor: 'c1');
        expect(result!.sessions.single.sessionId, 's-9');
        expect(r.agent().params['session/list'], {
          'cwd': r.project,
          'cursor': 'c1',
        });
      },
    );

    test(
      'listSessions is null, and asks nothing, when the agent does not offer it',
      () async {
        final r = RuntimeRig(first: const FakeScenario(listSessions: false));
        addTearDown(r.dispose);
        await r.runtime.start();
        expect(await r.runtime.listSessions(), isNull);
        expect(r.agent().received, isNot(contains('session/list')));
      },
    );

    test(
      'updates of another session are dropped; those of this one land',
      () async {
        final r = RuntimeRig();
        addTearDown(r.dispose);
        await r.runtime.start();
        r.agent().connection
          ..notify('session/update', {
            'sessionId': 'other',
            'update': {
              'sessionUpdate': 'agent_message_chunk',
              'content': {'type': 'text', 'text': 'stray'},
            },
          })
          ..notify('session/update', {
            'sessionId': 'sess-1',
            'update': {
              'sessionUpdate': 'session_info_update',
              'title': 'My chat',
            },
          });
        await r.until(() => r.state.title == 'My chat');
        expect(r.state.timeline.items, isEmpty);
        expect(r.state.label, 'My chat');
      },
    );
  });

  group('the agent log (spec D20)', () {
    test(
      'stderrTail follows the agent and is still there after it exits',
      () async {
        final r = RuntimeRig(
          first: FakeScenario(
            turns: [
              [FakeSteps.stderr('boom: the details'), FakeSteps.exit(3)],
            ],
          ),
        );
        addTearDown(r.dispose);
        expect(r.runtime.stderrTail, isEmpty, reason: 'before any agent');
        await r.runtime.start();
        expect(r.runtime.stderrTail, contains('RECV initialize'));
        await r.runtime.send(hi);
        await r.until(() => r.state.phase == AgentPhase.failed);
        expect(
          r.runtime.stderrTail,
          contains('boom: the details'),
          reason: '"Xem log" is offered on the crash card',
        );
      },
    );
  });

  group('undo that was off for a transient cause (spec D12)', () {
    final turn = FakeScenario(
      turns: [
        [FakeSteps.text('ok')],
      ],
    );

    List<NoticeItem> undoNotes(RuntimeRig r) => [
      for (final c in r.cards)
        if (c.notice is UndoUnavailable) c,
    ];

    test('no git at first, git later: the next ready probes again', () async {
      var asked = 0;
      final ck = RecordingCheckpoints();
      final r = RuntimeRig(
        first: turn,
        later: [turn],
        checkpoints: () async =>
            ++asked == 1 ? (null, UndoOff.noGit) : (ck, null),
      );
      addTearDown(r.dispose);
      await r.runtime.start();
      await r.until(() => undoNotes(r).isNotEmpty);
      expect(
        undoNotes(r).single.notice,
        isA<UndoUnavailable>().having((n) => n.reason, 'reason', UndoOff.noGit),
      );
      await r.runtime.restart();
      await r.runtime.send(hi);
      await r.runtime.whenIdle();
      expect(asked, 2);
      expect(
        r.turnEnds.single.checkpoint,
        isNotNull,
        reason: 'the turn has undo',
      );
      expect(r.runtime.checkpointOf(1)!.commit, 'c-k1/1');
      expect(ck.calls.where((c) => c.startsWith('snapshot')), [
        'snapshot:k1/0',
        'snapshot:k1/1',
      ]);
      expect(
        undoNotes(r).single.resolved,
        isTrue,
        reason: 'undo is not off any more',
      );
    });

    test('a source that threw at first answers later', () async {
      var asked = 0;
      final ck = RecordingCheckpoints();
      final r = RuntimeRig(
        first: turn,
        later: [turn],
        checkpoints: () async {
          if (++asked == 1) throw StateError('git probe');
          return (ck, null);
        },
      );
      addTearDown(r.dispose);
      await r.runtime.start();
      await r.until(() => undoNotes(r).isNotEmpty);
      await r.runtime.restart();
      await r.runtime.send(hi);
      await r.runtime.whenIdle();
      expect(r.turnEnds.single.checkpoint, isNotNull);
      expect(undoNotes(r).single.resolved, isTrue);
    });

    test('a retry after the agent died probes again too', () async {
      var asked = 0;
      final ck = RecordingCheckpoints();
      final r = RuntimeRig(
        first: FakeScenario(
          turns: [
            [FakeSteps.exit(3)],
          ],
        ),
        later: [turn],
        checkpoints: () async =>
            ++asked == 1 ? (null, UndoOff.noGit) : (ck, null),
      );
      addTearDown(r.dispose);
      await r.runtime.start();
      await r.runtime.send(hi);
      await r.until(() => r.state.phase == AgentPhase.failed);
      await r.runtime.retry();
      await r.runtime.send(const [TextBlock('again')]);
      await r.runtime.whenIdle();
      expect(asked, 2);
      expect(r.turnEnds.last.checkpoint, isNotNull);
    });

    test('still off: one note, however often the agent restarts', () async {
      final r = RuntimeRig(
        first: turn,
        later: [turn],
        checkpoints: () async => (null, UndoOff.noGit),
      );
      addTearDown(r.dispose);
      await r.runtime.start();
      for (var i = 0; i < 2; i++) {
        await r.runtime.restart();
        await r.runtime.send(hi);
        await r.runtime.whenIdle();
      }
      expect(undoNotes(r), hasLength(1));
      expect(undoNotes(r).single.resolved, isFalse);
    });

    test('a source that keeps throwing: one note', () async {
      final r = RuntimeRig(
        first: turn,
        later: [turn],
        checkpoints: () async => throw StateError('git probe'),
      );
      addTearDown(r.dispose);
      await r.runtime.start();
      for (var i = 0; i < 2; i++) {
        await r.runtime.restart();
        await r.runtime.send(hi);
        await r.runtime.whenIdle();
      }
      expect(undoNotes(r), hasLength(1));
      expect(
        (undoNotes(r).single.notice as UndoUnavailable).reason,
        UndoOff.failed,
      );
    });

    test('another reason replaces the note', () async {
      var asked = 0;
      final ck = RecordingCheckpoints()..off = UndoOff.tooManyFiles;
      final r = RuntimeRig(
        first: turn,
        later: [turn],
        checkpoints: () async =>
            ++asked == 1 ? (null, UndoOff.noGit) : (ck, null),
      );
      addTearDown(r.dispose);
      await r.runtime.start();
      await r.until(() => undoNotes(r).isNotEmpty);
      await r.runtime.restart();
      await r.runtime.send(hi);
      await r.runtime.whenIdle();
      expect(
        [
          for (final c in undoNotes(r))
            ((c.notice as UndoUnavailable).reason, c.resolved),
        ],
        [(UndoOff.noGit, true), (UndoOff.tooManyFiles, false)],
      );
    });

    test('a probe still under way is not started twice', () async {
      final gate = Completer<void>();
      var asked = 0;
      final ck = RecordingCheckpoints();
      final r = RuntimeRig(
        first: turn,
        later: [turn],
        checkpoints: () async {
          asked++;
          await gate.future;
          return (ck, null);
        },
      );
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
        return r.dispose();
      });
      await r.runtime.start();
      await r.runtime.restart(); // ready again while the first probe waits
      expect(asked, 1);
      gate.complete();
      await r.runtime.send(hi);
      await r.runtime.whenIdle();
      expect(asked, 1);
      expect(r.turnEnds.single.checkpoint, isNotNull);
    });

    test(
      'a store that exists but is off for the project is not asked again',
      () async {
        var asked = 0;
        final ck = RecordingCheckpoints()..off = UndoOff.tooManyFiles;
        final r = RuntimeRig(
          first: turn,
          later: [turn],
          checkpoints: () async {
            asked++;
            return (ck, null);
          },
        );
        addTearDown(r.dispose);
        await r.runtime.start();
        await r.runtime.restart();
        await r.runtime.send(hi);
        await r.runtime.whenIdle();
        expect(asked, 1);
        expect(undoNotes(r), hasLength(1));
        expect(
          (undoNotes(r).single.notice as UndoUnavailable).reason,
          UndoOff.tooManyFiles,
        );
      },
    );
  });

  group('undo (spec D12)', () {
    test('without checkpoints every undo call says there is none', () async {
      final r = RuntimeRig();
      addTearDown(r.dispose);
      await r.runtime.start();
      expect(r.runtime.checkpointOf(1), isNull);
      expect(await r.runtime.changesSince(1), isNull);
      expect(await r.runtime.sessionChanges(), isNull);
      expect(await r.runtime.changedAfterTurn(1), isNull);
      expect(await r.runtime.fileBefore(1, 'a.txt'), isNull);
      expect(await r.runtime.revert(1, ['a.txt']), isFalse);
      expect(await r.runtime.revertSession(['a.txt']), isFalse);
    });

    test(
      'each question goes to the checkpoint of its turn; the session to the first',
      () async {
        final ck = RecordingCheckpoints();
        final r = RuntimeRig(
          first: FakeScenario(
            turns: [
              [FakeSteps.text('one')],
              [FakeSteps.text('two')],
            ],
          ),
          checkpoints: () async => (ck, null),
        );
        addTearDown(r.dispose);
        await r.runtime.start();
        await r.runtime.send(const [TextBlock('a')]);
        await r.runtime.whenIdle();
        await r.runtime.send(const [TextBlock('b')]);
        await r.runtime.whenIdle();
        expect(r.runtime.checkpointOf(2)!.commit, 'c-k1/2');
        expect(r.runtime.checkpointOf(3), isNull);

        ck.calls.clear();
        expect((await r.runtime.changesSince(2))!.single.path, 'a.txt');
        expect(await r.runtime.sessionChanges(), isNotEmpty);
        expect(await r.runtime.changedAfterTurn(2), {'a.txt'});
        expect(await r.runtime.fileBefore(2, 'a.txt'), [1, 2, 3]);
        expect(await r.runtime.revert(2, ['a.txt']), isTrue);
        expect(await r.runtime.revertSession(['a.txt', 'b.txt']), isTrue);
        expect(ck.calls, [
          'changes:t-k1/2..now',
          'changes:t-k1/1..now',
          'changedSince:after-2',
          'fileAt:t-k1/2:a.txt',
          'restore:c-k1/2:a.txt',
          'restore:c-k1/1:a.txt,b.txt',
        ]);
      },
    );

    test('revert is refused while a turn runs and touches nothing', () async {
      final ck = RecordingCheckpoints();
      final r = RuntimeRig(
        first: FakeScenario(
          turns: [
            [FakeSteps.text('one')],
            [FakeSteps.hang()],
          ],
        ),
        checkpoints: () async => (ck, null),
      );
      addTearDown(r.dispose);
      await r.runtime.start();
      await r.runtime.send(const [TextBlock('a')]);
      await r.runtime.whenIdle();
      await r.runtime.send(const [TextBlock('b')]);
      expect(r.state.turn, isNotNull);
      expect(await r.runtime.revert(1, ['a.txt']), isFalse);
      expect(await r.runtime.revertSession(['a.txt']), isFalse);
      expect(ck.calls.where((c) => c.startsWith('restore')), isEmpty);
    });

    test('a failing restore reaches the caller', () async {
      final ck = RecordingCheckpoints()..failRestore = true;
      final r = RuntimeRig(
        first: FakeScenario(
          turns: [
            [FakeSteps.text('one')],
          ],
        ),
        checkpoints: () async => (ck, null),
      );
      addTearDown(r.dispose);
      await r.runtime.start();
      await r.runtime.send(hi);
      await r.runtime.whenIdle();
      await expectLater(
        r.runtime.revert(1, ['a.txt']),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('questions the store cannot answer are null, not errors', () async {
      final ck = RecordingCheckpoints();
      final r = RuntimeRig(
        first: FakeScenario(
          turns: [
            [FakeSteps.text('one')],
          ],
        ),
        checkpoints: () async => (ck, null),
      );
      addTearDown(r.dispose);
      await r.runtime.start();
      await r.runtime.send(hi);
      await r.runtime.whenIdle();
      ck.failQueries = true;
      expect(await r.runtime.changesSince(1), isNull);
      expect(await r.runtime.sessionChanges(), isNull);
      expect(await r.runtime.changedAfterTurn(1), isNull);
      expect(await r.runtime.fileBefore(1, 'a.txt'), isNull);
    });

    test(
      'a checkpoint source that throws: a card says undo failed, turns still run',
      () async {
        final r = RuntimeRig(
          first: FakeScenario(
            turns: [
              [FakeSteps.text('ok')],
            ],
          ),
          checkpoints: () async => throw StateError('git probe'),
        );
        addTearDown(r.dispose);
        await r.runtime.start();
        await r.runtime.send(hi);
        await r.runtime.whenIdle();
        expect(
          r.notices.single,
          isA<UndoUnavailable>()
              .having((n) => n.reason, 'reason', UndoOff.failed)
              .having((n) => n.turnOnly, 'turnOnly', isFalse),
        );
        expect(r.turnEnds.single.outcome, TurnOutcome.finished);
        expect(r.turnEnds.single.checkpoint, isNull);
      },
    );

    test('a snapshot that throws costs the turn its undo only', () async {
      final ck = RecordingCheckpoints()..failSnapshot = (ref) => ref == 'k1/1';
      final r = RuntimeRig(
        first: FakeScenario(
          turns: [
            [FakeSteps.text('ok')],
            [FakeSteps.text('ok again')],
          ],
        ),
        checkpoints: () async => (ck, null),
      );
      addTearDown(r.dispose);
      await r.runtime.start();
      await r.runtime.send(hi);
      await r.runtime.whenIdle();
      expect(
        r.notices.single,
        isA<UndoUnavailable>().having((n) => n.turnOnly, 'turnOnly', isTrue),
      );
      expect(r.agent().received, contains('session/prompt:hi'));
      expect(r.turnEnds.single.checkpoint, isNull);
      await r.runtime.send(const [TextBlock('again')]);
      await r.runtime.whenIdle();
      expect(
        r.turnEnds.last.checkpoint,
        isNotNull,
        reason: 'the next turn has undo',
      );
      expect(r.runtime.checkpointOf(1), isNull);
      expect(r.runtime.checkpointOf(2), isNotNull);
    });

    test(
      'a store that cannot read the tree after a turn does not hold the turn up',
      () async {
        final ck = RecordingCheckpoints()..failTree = true;
        final r = RuntimeRig(
          first: FakeScenario(
            turns: [
              [FakeSteps.text('ok')],
            ],
          ),
          checkpoints: () async => (ck, null),
        );
        addTearDown(r.dispose);
        await r.runtime.start();
        await r.runtime.send(hi);
        await r.runtime.whenIdle().timeout(const Duration(seconds: 2));
        final end = r.turnEnds.single;
        expect(end.outcome, TurnOutcome.finished);
        expect(end.checkpoint, isNotNull);
        expect(end.changes, isNull);
        expect(r.statuses, [AiStatus.running, AiStatus.idle]);
      },
    );

    test(
      'a store that cannot diff after a turn does not hold the turn up either',
      () async {
        final ck = RecordingCheckpoints()..failQueries = true;
        final r = RuntimeRig(
          first: FakeScenario(
            turns: [
              [FakeSteps.text('ok')],
            ],
          ),
          checkpoints: () async => (ck, null),
        );
        addTearDown(r.dispose);
        await r.runtime.start();
        await r.runtime.send(hi);
        await r.runtime.whenIdle().timeout(const Duration(seconds: 2));
        final end = r.turnEnds.single;
        expect(end.outcome, TurnOutcome.finished);
        expect(end.afterTree, 'after-1');
        expect(end.changes, isEmpty);
      },
    );

    test(
      'two turns against a real repository: the session spans both, a turn only its own',
      () async {
        final r = RuntimeRig(
          first: FakeScenario(
            turns: [
              [FakeSteps.write('a.txt', 'a1')],
              [FakeSteps.write('b.txt', 'b1')],
            ],
          ),
          realCheckpoints: true,
        );
        addTearDown(r.dispose);
        await r.runtime.start();
        await r.runtime.send(hi);
        await r.runtime.whenIdle();
        await r.runtime.send(const [TextBlock('again')]);
        await r.runtime.whenIdle();
        expect(
          {for (final c in (await r.runtime.sessionChanges())!) c.path},
          {'a.txt', 'b.txt'},
        );
        expect(
          {for (final c in (await r.runtime.changesSince(2))!) c.path},
          {'b.txt'},
        );
        expect(await r.runtime.fileBefore(2, 'a.txt'), 'a1'.codeUnits);
        expect(await r.runtime.revertSession(['a.txt', 'b.txt']), isTrue);
        expect(File(p.join(r.project, 'a.txt')).existsSync(), isFalse);
        expect(File(p.join(r.project, 'b.txt')).existsSync(), isFalse);
      },
    );
  });
}
