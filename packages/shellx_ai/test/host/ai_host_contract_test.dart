// Pins what the brief's two host tests leave open: a launch waits for the
// startup sweep (Task 9 decision), the sweep runs once, the crash registry is
// best effort and never strands an agent, and a runtime made by the host
// works end to end on a real agent process.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_acp/testing.dart';
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:test/test.dart';

import '../support/processes.dart';
import '../support/runtime_rig.dart' show deleteTree;
import '../support/scripts.dart';

/// Writes the marker file named by its argument, then lives until stdin
/// closes (what `AgentProcess.stop` does).
const _markerThenWait = '''
import 'dart:io';
void main(List<String> args) {
  File(args.single).writeAsStringSync('up');
  stdin.listen((_) {}, onDone: () => exit(0));
}
''';

const _quickExit = 'void main() {}';

/// A file system on which every path is an executable: `git` is found on any
/// PATH, so that asking it for its version is what the test would notice.
final class _AnyExecutable implements FileProbe {
  const _AnyExecutable();

  @override
  bool isExecutable(String path) => true;

  @override
  bool isFile(String path) => true;

  @override
  String? read(String path) => null;
}

/// A temp folder and everything a test started inside it, cleaned up in one
/// step and in the right order: runtimes and processes first, the folder last.
final class _Env {
  _Env() : tmp = Directory.systemTemp.createTempSync('ai_host_contract');

  final Directory tmp;
  final processes = <AgentProcess>[];
  final runtimes = <AiRuntime>[];

  /// A login shell that answers at once, so nothing here runs a real shell.
  final env = LoginShellEnv(
    processEnv: {'PATH': '/usr/bin'},
    run: (s, a, e, t) async => (0, <int>[]),
  );

  File get registry => File(p.join(tmp.path, 'ai', 'running.json'));

  AgentCommand script(
    String name,
    String source, [
    List<String> more = const [],
  ]) => AgentCommand(
    executable: Platform.resolvedExecutable,
    args: [...dartScript(tmp, name, source), ...more],
    environment: Platform.environment,
  );

  Future<AgentProcess> launch(AiHost host, AgentCommand command) async {
    final process = await host.launch(command, cwd: tmp.path) as AgentProcess;
    processes.add(process);
    return process;
  }

  Future<void> until(bool Function() test, {int tries = 1000}) async {
    for (var i = 0; i < tries && !test(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(test(), isTrue, reason: 'condition not reached');
  }

  /// A runtime made by a host of its own on the fake agent as a real process,
  /// in a fresh project folder, without undo.
  AiRuntime fakeRuntime(
    FakeScenario scenario, {
    String? resume,
    Map<String, Object> preferred = const {},
  }) {
    final project = Directory(p.join(tmp.path, 'project'))..createSync();
    final host = AiHost(
      supportDir: p.join(tmp.path, 'support'),
      clientVersion: '2.0.0',
      env: LoginShellEnv(
        processEnv: Platform.environment,
        run: (s, a, c, t) async => (0, <int>[]),
      ),
      // No git: nothing may still be writing under the folder when it goes.
      checkpoints: CheckpointStores(
        root: p.join(tmp.path, 'support', 'ai', 'checkpoints'),
        locator: GitLocator(probe: (exe, args, {environment}) async => null),
      ),
    );
    final spec = AgentSpec(
      id: 'fake',
      name: 'Fake',
      launch: CustomLaunch(
        command: Platform.resolvedExecutable,
        args: fakeAgentArgs(writeScenario(scenario, tmp)),
      ),
    );
    final runtime = host.runtime(
      agent: spec,
      cwd: project.path,
      resumeSessionId: resume,
      preferredConfig: preferred,
    );
    runtimes.add(runtime);
    return runtime;
  }

  Future<void> dispose() async {
    for (final r in runtimes) {
      await r.dispose();
    }
    for (final process in processes) {
      await killIfRunning(process);
    }
    // The registry's last write (the record of a process that just ended) is
    // made within a turn of the event loop; it must not recreate the folder.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await deleteTree(tmp);
  }
}

bool _alive(int pid) => Process.runSync('kill', ['-0', '$pid']).exitCode == 0;

void main() {
  late _Env e;
  setUp(() => e = _Env());
  tearDown(() => e.dispose());

  test('the host and its parts live under the support folder', () {
    final host = AiHost(supportDir: e.tmp.path, clientVersion: '2.0.0');
    expect(host.running.file.path, e.registry.path);
    expect(host.checkpoints.root, p.join(e.tmp.path, 'ai', 'checkpoints'));
    expect(host.resolver.agentsDir, p.join(e.tmp.path, 'ai', 'agents'));
  });

  test('toString is redacted (the host holds paths)', () {
    final host = AiHost(supportDir: e.tmp.path, clientVersion: '2.0.0');
    expect(host.toString(), '…');
  });

  group('the sweep and the first launch (Task 9 decision)', () {
    test(
      'launch waits for a sweep under way, so the sweep never meets the new agent',
      () async {
        final marker = p.join(e.tmp.path, 'started');
        final gate = Completer<void>();
        final looked = <int>[];
        final killed = <int>[];
        final t = DateTime.now();
        late final RunningAgents running;
        running = RunningAgents(
          e.registry,
          info: (pid) async {
            looked.add(pid);
            await gate.future;
            // A process the registry names "matches": the sweep would kill it.
            final record = running
                .read()
                .where((r) => r.pid == pid)
                .firstOrNull;
            return record == null
                ? null
                : (command: record.command, startedAt: record.startedAt);
          },
          killPid: (pid) async => killed.add(pid),
        );
        await running.add(
          RunningRecord(
            pid: 4242,
            command: '/usr/local/bin/node',
            startedAt: t,
          ),
        );
        final host = AiHost(
          supportDir: e.tmp.path,
          clientVersion: '2.0.0',
          running: running,
          env: e.env,
        );
        final sweeping = host.startup();
        await e.until(() => looked.isNotEmpty); // the sweep is inside a lookup
        final launching = host.launch(
          e.script('marker', _markerThenWait, [marker]),
          cwd: e.tmp.path,
        );
        // A Dart process is up and has written its marker well within this.
        await Future<void>.delayed(const Duration(milliseconds: 600));
        expect(
          File(marker).existsSync(),
          isFalse,
          reason: 'no agent starts while the sweep runs',
        );
        gate.complete();
        expect(await sweeping, 1);
        e.processes.add(await launching as AgentProcess);
        await e.until(() => File(marker).existsSync());
        expect(killed, [4242], reason: 'the new agent was left alone');
        expect(looked, [4242]);
        expect(running.read().single.pid, e.processes.single.pid);
      },
    );

    test(
      'startup sweeps once: a second call must not meet the agents of this run',
      () async {
        var lookups = 0;
        final t = DateTime.now();
        final running = RunningAgents(
          e.registry,
          info: (pid) async {
            lookups++;
            return null;
          },
        );
        await running.add(
          RunningRecord(pid: 4242, command: 'node', startedAt: t),
        );
        final host = AiHost(
          supportDir: e.tmp.path,
          clientVersion: '2.0.0',
          running: running,
          env: e.env,
        );
        expect(await host.startup(), 0);
        expect(lookups, 1);
        // An agent this run started and recorded after the sweep.
        await running.add(
          RunningRecord(pid: 5151, command: 'node', startedAt: t),
        );
        expect(await host.startup(), 0);
        expect(lookups, 1, reason: 'no second sweep');
        expect(running.read().single.pid, 5151, reason: 'the record stays');
      },
    );

    test(
      'a startup that comes after a launch leaves the agents of this run alone',
      () async {
        final looked = <int>[];
        final killed = <int>[];
        late final RunningAgents running;
        running = RunningAgents(
          e.registry,
          info: (pid) async {
            looked.add(pid);
            // A process the registry names "matches": a sweep would kill it.
            final record = running
                .read()
                .where((r) => r.pid == pid)
                .firstOrNull;
            return record == null
                ? null
                : (command: record.command, startedAt: record.startedAt);
          },
          killPid: (pid) async => killed.add(pid),
        );
        final host = AiHost(
          supportDir: e.tmp.path,
          clientVersion: '2.0.0',
          running: running,
          env: e.env,
        );
        final process = await e.launch(
          host,
          e.script('marker', _markerThenWait, [p.join(e.tmp.path, 'up')]),
        );
        expect(await host.startup(), 0);
        expect(killed, isEmpty, reason: 'the agent is not a leftover');
        expect(looked, isEmpty);
        expect(running.read().single.pid, process.pid);
        expect(
          await process.exitCode.timeout(Duration.zero, onTimeout: () => -1),
          -1,
          reason: 'still running',
        );
      },
    );

    test(
      'a failing sweep reaches startup and never stops an agent from launching',
      () async {
        final gate = Completer<void>();
        final running = RunningAgents(
          e.registry,
          info: (pid) async {
            await gate.future;
            throw StateError('ps broke');
          },
        );
        await running.add(
          RunningRecord(pid: 4242, command: 'node', startedAt: DateTime.now()),
        );
        final host = AiHost(
          supportDir: e.tmp.path,
          clientVersion: '2.0.0',
          running: running,
          env: e.env,
        );
        final sweeping = host.startup();
        final armed = expectLater(sweeping, throwsA(isA<StateError>()));
        final launching = host.launch(
          e.script('quick', _quickExit),
          cwd: e.tmp.path,
        );
        gate.complete();
        await armed;
        final process = await launching as AgentProcess;
        e.processes.add(process);
        expect(await process.exitCode, 0);
      },
    );

    test('a launch with no startup at all just launches', () async {
      final host = AiHost(
        supportDir: e.tmp.path,
        clientVersion: '2.0.0',
        env: e.env,
      );
      final process = await e.launch(host, e.script('quick', _quickExit));
      expect(await process.exitCode, 0);
    });
  });

  group('what the host passes on', () {
    test(
      'the record names the executable and the time of the host clock',
      () async {
        final clock = DateTime.utc(2026, 10, 14, 12, 30);
        final host = AiHost(
          supportDir: e.tmp.path,
          clientVersion: '2.0.0',
          now: () => clock,
        );
        final process = await e.launch(
          host,
          e.script('marker', _markerThenWait, [p.join(e.tmp.path, 'up')]),
        );
        final record = host.running.read().single;
        expect(record.pid, process.pid);
        expect(record.command, Platform.resolvedExecutable);
        expect(record.startedAt, clock);
      },
    );

    test('agents are killed with the tree killer the host was given', () async {
      final killed = <int>[];
      final host = AiHost(
        supportDir: e.tmp.path,
        clientVersion: '2.0.0',
        killTree: (process) async {
          killed.add(process.pid);
          process.kill(ProcessSignal.sigkill);
        },
      );
      final process = await e.launch(
        host,
        e.script('marker', _markerThenWait, [p.join(e.tmp.path, 'up')]),
      );
      await process.kill();
      await process.exitCode;
      expect(killed, [process.pid]);
    });
  });

  group('the crash registry is best effort', () {
    test('an agent that ends by itself leaves no record', () async {
      final host = AiHost(supportDir: e.tmp.path, clientVersion: '2.0.0');
      final process = await e.launch(host, e.script('quick', _quickExit));
      await process.exitCode;
      await e.until(() => host.running.read().isEmpty);
    });

    test(
      'a registry that cannot be written does not strand the agent it was started for',
      () async {
        final blocker = File(p.join(e.tmp.path, 'blocker'))
          ..writeAsStringSync('');
        final host = AiHost(
          supportDir: e.tmp.path,
          clientVersion: '2.0.0',
          running: RunningAgents(File(p.join(blocker.path, 'running.json'))),
        );
        final process = await e.launch(
          host,
          e.script('marker', _markerThenWait, [p.join(e.tmp.path, 'up')]),
        );
        expect(
          await process.exitCode.timeout(Duration.zero, onTimeout: () => -1),
          -1,
          reason: 'still running',
        );
        await process.stop();
        await process.exitCode;
        // The record cannot be removed either; nobody may hear about it.
        await Future<void>.delayed(const Duration(milliseconds: 100));
      },
    );
  });

  group('what the host passes to the runtime', () {
    test('the folder, the agent and the session to resume', () async {
      final runtime = e.fakeRuntime(
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
      expect(runtime.state.agentId, 'fake');
      expect(runtime.state.agentName, 'Fake');
      expect(runtime.state.cwd, p.join(e.tmp.path, 'project'));
      await runtime.start();
      expect(runtime.state.sessionId, 'old-1');
      expect(
        runtime.state.label,
        'q1',
        reason: 'the old conversation came back',
      );
      await e.until(
        () => runtime.stderrTail.contains('RECV session/load:old-1'),
      );
    });

    test(
      'a tab on the home folder: undo is off for it, git is asked for '
      'nothing and the first message goes out at once (final review I-1)',
      () async {
        final home = Directory(p.join(e.tmp.path, 'home'))..createSync();
        final asked = <String>[];
        final host = AiHost(
          supportDir: p.join(e.tmp.path, 'support'),
          clientVersion: '2.0.0',
          env: LoginShellEnv(
            processEnv: {...Platform.environment, 'HOME': home.path},
            run: (s, a, c, t) async => (0, <int>[]),
          ),
          checkpoints: CheckpointStores(
            root: p.join(e.tmp.path, 'support', 'ai', 'checkpoints'),
            locator: GitLocator(
              files: const _AnyExecutable(),
              probe: (exe, args, {environment}) async {
                asked.add(exe);
                return null;
              },
            ),
          ),
        );
        final spec = AgentSpec(
          id: 'fake',
          name: 'Fake',
          launch: CustomLaunch(
            command: Platform.resolvedExecutable,
            args: fakeAgentArgs(
              writeScenario(
                FakeScenario(
                  turns: [
                    [FakeSteps.text('hello')],
                  ],
                ),
                e.tmp,
              ),
            ),
          ),
        );
        final runtime = host.runtime(agent: spec, cwd: home.path);
        e.runtimes.add(runtime);
        await runtime.start();
        await runtime.send(const [TextBlock('hi')]);
        await runtime.whenIdle();
        final notes = runtime.state.timeline.items
            .whereType<NoticeItem>()
            .map((n) => n.notice)
            .whereType<UndoUnavailable>();
        expect(notes.map((n) => (n.reason, n.turnOnly)), [
          (UndoOff.broadFolder, false),
        ]);
        expect(asked, isEmpty, reason: 'no git work for a folder like that');
        expect(
          runtime.state.timeline.items.whereType<TurnEndItem>().single.outcome,
          TurnOutcome.finished,
        );
        expect(
          Directory(
            p.join(e.tmp.path, 'support', 'ai', 'checkpoints'),
          ).existsSync(),
          isFalse,
          reason: 'no repository was made',
        );
      },
    );

    test('the remembered choices', () async {
      final runtime = e.fakeRuntime(
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
          ],
        ),
        preferred: {'model': 'b'},
      );
      await runtime.start();
      expect(
        runtime.state.configOptions!.single.currentValue,
        'b',
        reason: 'applied to the new session',
      );
    });
  });

  group('startup prunes the checkpoints in the background (spec D12)', () {
    final live = LoginShellEnv(
      processEnv: Platform.environment,
      run: (s, a, c, t) async => (0, <int>[]),
    );

    Directory repoOfGoneProject(String root) {
      final repo = Directory(p.join(root, 'abc123def456'))
        ..createSync(recursive: true);
      File(
        p.join(repo.path, 'shellx.json'),
      ).writeAsStringSync(jsonEncode({'project': p.join(e.tmp.path, 'gone')}));
      return repo;
    }

    test('the repository of a project that is gone is deleted', () async {
      final root = p.join(e.tmp.path, 'ai', 'checkpoints');
      final repo = repoOfGoneProject(root);
      final host = AiHost(
        supportDir: e.tmp.path,
        clientVersion: '2.0.0',
        env: live,
      );
      expect(await host.startup(), 0);
      await e.until(() => !repo.existsSync());
    });

    test('a startup that comes after a launch still prunes', () async {
      final root = p.join(e.tmp.path, 'ai', 'checkpoints');
      final repo = repoOfGoneProject(root);
      final host = AiHost(
        supportDir: e.tmp.path,
        clientVersion: '2.0.0',
        env: live,
      );
      await e.launch(
        host,
        e.script('marker', _markerThenWait, [p.join(e.tmp.path, 'up')]),
      );
      expect(await host.startup(), 0, reason: 'no sweep, the agent is ours');
      await e.until(() => !repo.existsSync());
    });

    test('a prune that fails is nobody\'s business', () async {
      final root = p.join(e.tmp.path, 'ai', 'checkpoints');
      final repo = repoOfGoneProject(root);
      final host = AiHost(
        supportDir: e.tmp.path,
        clientVersion: '2.0.0',
        env: live,
        checkpoints: CheckpointStores(
          root: root,
          locator: GitLocator(
            probe: (exe, args, {environment}) async =>
                throw StateError('probe'),
          ),
        ),
      );
      expect(await host.startup(), 0);
      // The prune ran and failed in the background; no error may escape.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(repo.existsSync(), isTrue);
    });
  });

  test(
    'a runtime made by the host works on a real agent and leaves nothing behind',
    () async {
      final project = Directory(p.join(e.tmp.path, 'project'))..createSync();
      final scenario = writeScenario(
        FakeScenario(
          turns: [
            [FakeSteps.text('hello'), FakeSteps.write('out.txt', 'x')],
          ],
        ),
        e.tmp,
      );
      final host = AiHost(
        supportDir: p.join(e.tmp.path, 'support'),
        clientVersion: '2.0.0',
        env: LoginShellEnv(
          processEnv: Platform.environment,
          run: (s, a, c, t) async => (0, <int>[]),
        ),
      );
      final spec = AgentSpec(
        id: 'fake',
        name: 'Fake',
        launch: CustomLaunch(
          command: Platform.resolvedExecutable,
          args: fakeAgentArgs(scenario),
        ),
      );
      final runtime = host.runtime(agent: spec, cwd: project.path);
      e.runtimes.add(runtime);
      await runtime.start();
      expect(runtime.state.phase, AgentPhase.ready);
      final pid = host.running.read().single.pid;
      await runtime.send(const [TextBlock('hi')]);
      await runtime.whenIdle();
      final items = runtime.state.timeline.items;
      expect(items.whereType<AgentTextItem>().single.text, 'hello');
      final end = items.whereType<TurnEndItem>().single;
      expect(end.outcome, TurnOutcome.finished);
      expect(
        {for (final c in end.changes!) c.path: c.kind},
        {'out.txt': ChangeKind.added},
      );
      await e.until(
        () => runtime.stderrTail.contains('RECV session/prompt:hi'),
      );
      await runtime.dispose();
      expect(runtime.state.phase, AgentPhase.stopped);
      expect(runtime.stderrTail, contains('RECV session/prompt:hi'));
      await e.until(() => host.running.read().isEmpty);
      expect(_alive(pid), isFalse);
    },
    skip: Platform.isWindows ? 'uses kill -0' : false,
  );
}
