// The final review's first "fix now" (V2-1b, spec Review Focus 5): an agent
// that leaves when stdin closes leaves its children running (a dev server
// holding a port, a test run). `AgentProcess.stop` reads the process table
// while the agent is still their parent, closes stdin, and after the exit (or
// the grace) kills what is left of them: only what it started, and only what
// is still the same process.
import 'dart:async';
import 'dart:io';

import 'package:shellx_ai/host.dart';
import 'package:test/test.dart';

import '../support/processes.dart';
import '../support/scripts.dart';

/// Says it is up (a file), then leaves when stdin closes, saying so (a
/// file). Its arguments are the two files.
const _upThenExitOnEof = '''
import 'dart:io';
void main(List<String> args) {
  File(args[0]).writeAsStringSync('up');
  stdin.listen((_) {}, onDone: () { File(args[1]).writeAsStringSync('eof'); exit(0); });
}
''';

/// A pid no system hands out (macOS stops at 99998, Linux at 4194304): a test
/// that names it can never signal a stranger by mistake.
const _nowhere = 5000000;

bool _alive(int pid) => Process.runSync('kill', ['-0', '$pid']).exitCode == 0;

void main() {
  late Directory tmp;
  final started = <AgentProcess>[];
  final strangers = <int>[];
  setUp(() => tmp = Directory.systemTemp.createTempSync('agent_leftovers'));
  tearDown(() async {
    for (final p in started) {
      await killIfRunning(p);
    }
    started.clear();
    // A test that failed midway must not leave processes behind. These pids
    // are the ones the test itself started.
    for (final pid in strangers) {
      if (!Platform.isWindows && _alive(pid)) {
        Process.killPid(pid, ProcessSignal.sigkill);
      }
    }
    strangers.clear();
    tmp.deleteSync(recursive: true);
  });

  AgentProcess track(AgentProcess p) {
    started.add(p);
    return p;
  }

  group('with a process table that is scripted', () {
    final t0 = DateTime.utc(2026, 10, 14, 9);
    ProcessRow row(
      int pid,
      int parent, {
      DateTime? at,
      String command = 'node',
    }) => ProcessRow(
      pid: pid,
      parentPid: parent,
      command: command,
      startedAt: at ?? t0,
    );

    /// The agent and what it started, as the table shows them while it runs.
    List<ProcessRow> tree(int agent, {int agentParent = -1}) => [
      row(agent, agentParent == -1 ? pid : agentParent),
      row(_nowhere + 1, agent), // a dev server
      row(_nowhere + 2, _nowhere + 1), // its worker
      row(_nowhere + 3, agent), // a test run
      row(_nowhere + 5, 1), // somebody else's
    ];

    /// What is left once the agent has gone: its children belong to pid 1.
    List<ProcessRow> afterwards({bool worker = true, bool testRun = true}) => [
      row(_nowhere + 1, 1),
      if (worker) row(_nowhere + 2, _nowhere + 1),
      if (testRun) row(_nowhere + 3, 1),
      row(_nowhere + 5, 1),
    ];

    /// The agent is a Dart process that leaves when stdin closes (or one that
    /// ignores it). [tables] are the answers to the 1st, 2nd… read of the
    /// process table, the last one repeating; each is given the agent's pid.
    /// [windows] runs the strategy of Windows (a pid at a time, no tree is
    /// walked) on any machine. [killed] are the processes the tree killer was
    /// asked for (elsewhere), [pidKills] those killed one by one (Windows).
    Future<
      ({
        AgentProcess agent,
        List<int> killed,
        List<int> pidKills,
        List<String> log,
        List<Duration?> limits,
        List<Duration?> afters,
      })
    >
    run(
      List<FutureOr<List<ProcessRow>?> Function(int agent)> tables, {
      bool ignoresStdin = false,
      String? source,
      Duration grace = const Duration(seconds: 2),
      Duration? firstReadLimit,
      Set<int> failing = const {},
      bool windows = false,
    }) async {
      final killed = <int>[];
      final pidKills = <int>[];
      final log = <String>[];
      final limits = <Duration?>[];
      final afters = <Duration?>[];
      var reads = 0;
      late final AgentProcess agent;
      agent = track(
        await AgentProcess.start(
          AgentCommand(
            executable: Platform.resolvedExecutable,
            args: source != null
                ? dartScript(tmp, 'custom', source)
                : ignoresStdin
                ? dartScript(tmp, 'ignore', ignoreStdin)
                : [
                    ...dartScript(tmp, 'eof', _upThenExitOnEof),
                    '${tmp.path}/up',
                    '${tmp.path}/eof',
                  ],
            environment: Platform.environment,
          ),
          cwd: tmp.path,
          grace: grace,
          firstReadLimit: firstReadLimit,
          isWindows: windows,
          processTable: ({limit, after}) async {
            log.add('table');
            limits.add(limit);
            afters.add(after);
            final answer =
                tables[reads < tables.length ? reads : tables.length - 1];
            reads++;
            return answer(agent.pid);
          },
          killPid: (pid) async {
            log.add('pid $pid');
            pidKills.add(pid);
            // Only the agent is a real process here, and it is never named.
            if (failing.contains(pid)) throw StateError('cannot kill');
          },
          killTree: (proc) async {
            log.add('kill ${proc.pid == agent.pid ? 'agent' : proc.pid}');
            killed.add(proc.pid);
            // Only the agent is a real process here.
            if (proc.pid == agent.pid) proc.kill(ProcessSignal.sigkill);
            if (failing.contains(proc.pid)) throw StateError('cannot kill');
          },
        ),
      );
      return (
        agent: agent,
        killed: killed,
        pidKills: pidKills,
        log: log,
        limits: limits,
        afters: afters,
      );
    }

    test('the table is read before stdin closes: the agent is still their '
        'parent', () async {
      final up = File('${tmp.path}/up');
      final eof = File('${tmp.path}/eof');
      var told = true;
      final p = track(
        await AgentProcess.start(
          AgentCommand(
            executable: Platform.resolvedExecutable,
            args: [
              ...dartScript(tmp, 'eof', _upThenExitOnEof),
              up.path,
              eof.path,
            ],
            environment: Platform.environment,
          ),
          cwd: tmp.path,
          // Not the 1.5 s of Windows: a cold runner may need longer to start
          // the agent, and the wait for the table would end before it.
          firstReadLimit: const Duration(seconds: 30),
          isWindows: false,
          processTable: ({limit, after}) async {
            // Once the agent is up: a stdin closed before that would be seen
            // the moment it listens.
            for (var i = 0; i < 400 && !up.existsSync(); i++) {
              await Future<void>.delayed(const Duration(milliseconds: 25));
            }
            await Future<void>.delayed(const Duration(milliseconds: 250));
            told = eof.existsSync();
            return null;
          },
        ),
      );
      await p.stop();
      expect(await p.exitCode.timeout(const Duration(seconds: 10)), 0);
      expect(told, isFalse, reason: 'stdin was still open when it was read');
      expect(eof.existsSync(), isTrue, reason: 'and was closed after');
    });

    test('what it started and left running is killed after it has gone: '
        'its processes, still the same ones, and nothing else', () async {
      final r = await run([
        tree,
        (agent) => [
          ...afterwards().take(2),
          // The pid of the test run was reused, an hour later.
          row(_nowhere + 3, 1, at: t0.add(const Duration(hours: 1))),
          row(_nowhere + 5, 1),
          // Started after the table was read: not the agent's.
          row(_nowhere + 9, 1),
        ],
        (agent) => [row(_nowhere + 2, _nowhere + 1), row(_nowhere + 5, 1)],
      ]);
      await r.agent.stop();
      expect(await r.agent.exitCode, 0);
      expect(r.killed, [_nowhere + 1, _nowhere + 2]);
      expect(r.log, [
        'table', // the agent is the parent of all
        'table', // after the exit
        'kill ${_nowhere + 1}', // the top of what is left…
        'table', // …and what its kill did not take
        'kill ${_nowhere + 2}',
      ]);
    });

    test('the kill of the top took the rest: nothing more is killed', () async {
      final r = await run([
        tree,
        (agent) => afterwards(testRun: false),
        (agent) => [row(_nowhere + 5, 1)],
      ]);
      await r.agent.stop();
      expect(r.killed, [_nowhere + 1]);
      expect(r.log.last, 'table');
    });

    test('children of the agent are each a top; one that fails to die '
        'fails nobody', () async {
      final r = await run(
        [tree, (agent) => afterwards(worker: false)],
        failing: {_nowhere + 1},
      );
      await r.agent.stop();
      expect(r.killed, unorderedEquals([_nowhere + 1, _nowhere + 3]));
      expect(await r.agent.exitCode, 0);
    });

    test('nothing left: no kill', () async {
      final r = await run([
        tree,
        (agent) => [row(_nowhere + 5, 1)],
      ]);
      await r.agent.stop();
      expect(r.killed, isEmpty);
      expect(r.log, ['table', 'table']);
    });

    test('an agent that started nothing: one read, no kill', () async {
      final r = await run([
        (agent) => [row(agent, pid), row(_nowhere + 5, 1)],
      ]);
      await r.agent.stop();
      expect(await r.agent.exitCode, 0);
      expect(r.killed, isEmpty);
      expect(r.log, ['table']);
    });

    test(
      'a table that cannot be read before: it stops as it always did',
      () async {
        for (final table in <List<ProcessRow>? Function(int)>[
          (agent) => null,
          (agent) => throw StateError('ps broke'),
          (agent) => <ProcessRow>[],
          // The agent is not in it, or is not this process\'s child.
          (agent) => tree(agent).skip(1).toList(),
          (agent) => tree(agent, agentParent: 1),
        ]) {
          final r = await run([table]);
          await r.agent.stop();
          expect(await r.agent.exitCode, 0);
          expect(r.killed, isEmpty);
          expect(r.log, ['table'], reason: 'no second read without a first');
        }
      },
    );

    test(
      'a table that cannot be read after: nothing is killed on a guess',
      () async {
        for (final second in <List<ProcessRow>? Function(int)>[
          (agent) => null,
          (agent) => throw StateError('ps broke'),
        ]) {
          final r = await run([tree, second]);
          await r.agent.stop();
          expect(r.killed, isEmpty);
          expect(r.log, ['table', 'table']);
        }
      },
    );

    test(
      'an agent that ignores stdin is killed first, then what it left',
      () async {
        final r = await run(
          [tree, (agent) => afterwards(testRun: false)],
          ignoresStdin: true,
          grace: const Duration(milliseconds: 300),
        );
        await r.agent.stop();
        await r.agent.exitCode.timeout(const Duration(seconds: 10));
        expect(r.killed, [r.agent.pid, _nowhere + 1, _nowhere + 2]);
        expect(r.log.first, 'table');
        expect(r.log[1], 'kill agent');
      },
    );

    test('an agent that has left already: no table, no kill', () async {
      final r = await run([tree], source: 'void main() {}');
      await r.agent.exitCode;
      await r.agent.stop();
      expect(r.log, isEmpty);
      expect(r.killed, isEmpty);
    });

    test('asked twice at once, it is one stop', () async {
      final r = await run([tree, (agent) => afterwards()]);
      await Future.wait([r.agent.stop(), r.agent.stop()]);
      expect(
        r.log.where((e) => e == 'table'),
        hasLength(greaterThanOrEqualTo(2)),
      );
      expect(
        r.killed.toSet(),
        hasLength(r.killed.length),
        reason: 'no pid twice',
      );
    });

    test('kill() takes the agent\'s tree and reads no table', () async {
      final r = await run([tree], ignoresStdin: true);
      await r.agent.kill();
      await r.agent.exitCode.timeout(const Duration(seconds: 10));
      expect(r.log, ['kill agent']);
    });

    // A table can say what cannot be: Windows keeps a parent id after the
    // parent has left, and that pid may be the agent's now, so a process that
    // began within the slack of the agent seems to be its child. Whatever the
    // table says, ShellX and what is above it are never killed (the desktop's
    // killProcessTree ends with an unconditional killPid), nor pid 0 and 1,
    // nor anything that is only under them. What the agent really left is
    // still killed. Both ways of killing: a tree at a time, and (Windows) a
    // pid at a time.
    for (final windows in [false, true]) {
      group(
        'never this process, what is above it, or pid 0 and 1 '
        '(${windows ? 'a pid at a time, as on Windows' : 'with the tree killer'})',
        () {
          /// The dev server the agent really left, and its worker.
          List<ProcessRow> left(int agent) => [
            row(_nowhere + 1, agent),
            row(_nowhere + 2, _nowhere + 1),
          ];

          Future<void> expectOnlyTheLeftovers(
            List<ProcessRow> Function(int agent) table,
          ) async {
            final r = await run([table], windows: windows);
            await r.agent.stop();
            expect(await r.agent.exitCode, 0);
            final named = windows ? r.pidKills : r.killed;
            expect(
              named,
              unorderedEquals([_nowhere + 1, _nowhere + 2]),
              reason: 'what the agent left, and nothing else',
            );
            expect(windows ? r.killed : r.pidKills, isEmpty);
          }

          test('this process listed as a child of the agent: neither it nor '
              'what is under it', () async {
            await expectOnlyTheLeftovers(
              (agent) => [
                row(agent, pid), // the agent, a child of this process
                row(pid, agent), // this process, "a child of the agent"
                row(_nowhere + 20, pid), // a shell this process started
                row(_nowhere + 21, _nowhere + 20), // its child
                ...left(agent),
              ],
            );
          });

          test('an ancestor listed as a child of the agent: neither it nor '
              'what is under it', () async {
            const parent = _nowhere + 30;
            const grandparent = _nowhere + 31;
            await expectOnlyTheLeftovers(
              (agent) => [
                row(agent, pid),
                row(pid, parent), // this process, started by `parent`…
                row(parent, grandparent), // …which `grandparent` started…
                row(grandparent, agent), // …and that is "a child of the agent"
                row(_nowhere + 32, grandparent), // under an ancestor
                row(_nowhere + 33, parent), // under another
                ...left(agent),
              ],
            );
          });

          test('pid 1 and pid 0 listed as children of the agent: neither them '
              'nor what is under them', () async {
            await expectOnlyTheLeftovers(
              (agent) => [
                row(agent, pid),
                row(1, agent, command: 'launchd'),
                row(0, agent, command: 'kernel_task'),
                row(_nowhere + 40, 1), // anything the system started
                row(_nowhere + 41, 0),
                ...left(agent),
              ],
            );
          });

          test('the same in the table read after the exit', () async {
            // The first table is right; the second lists this process under the
            // agent. Only what was in the first can be killed anyway.
            final r = await run([
              (agent) => [row(agent, pid), ...left(agent)],
              (agent) => [row(pid, agent), ...left(agent)],
            ], windows: windows);
            await r.agent.stop();
            expect(
              windows ? r.pidKills : r.killed,
              unorderedEquals([_nowhere + 1, _nowhere + 2]),
            );
          });
        },
      );
    }

    // Windows keeps the parent id of a process whose parent has left, and
    // reuses a pid at once, so a tree walked when the kill is made (taskkill
    // /T, the tree killer) can take a process that is not the agent's: ShellX
    // itself, or what is above it. There nothing is killed by walking: the
    // agent (its own Process, whose handle is ours), and the processes the
    // table showed it had started, each on its own, after the check that it
    // is still the same process.
    group('on Windows no tree is walked', () {
      test('what the agent left is killed one by one, each as the table '
          'showed it, and the tree killer is not asked', () async {
        final r = await run([tree, (agent) => afterwards()], windows: true);
        await r.agent.stop();
        expect(await r.agent.exitCode, 0);
        expect(
          r.pidKills,
          unorderedEquals([_nowhere + 1, _nowhere + 2, _nowhere + 3]),
          reason: 'the worker too: it is on the list, not found by a walk',
        );
        expect(r.killed, isEmpty, reason: 'no taskkill /T, no tree killer');
        expect(
          r.log.where((e) => e == 'table'),
          hasLength(2),
          reason: 'one read before, one after: nothing is left to a third',
        );
      });

      test('only what is still the same process: not a reused pid, not what '
          'came after the table', () async {
        final r = await run([
          tree,
          (agent) => [
            row(_nowhere + 1, 1),
            row(_nowhere + 2, _nowhere + 1),
            // The pid of the test run was reused, an hour later.
            row(_nowhere + 3, 1, at: t0.add(const Duration(hours: 1))),
            row(_nowhere + 5, 1),
            row(_nowhere + 9, 1), // started after the table was read
          ],
        ], windows: true);
        await r.agent.stop();
        expect(r.pidKills, unorderedEquals([_nowhere + 1, _nowhere + 2]));
        expect(r.killed, isEmpty);
      });

      test('an agent that ignores stdin is killed on its own, then the '
          'processes the table showed', () async {
        final r = await run(
          [tree, (agent) => afterwards(testRun: false)],
          ignoresStdin: true,
          grace: const Duration(milliseconds: 300),
          windows: true,
        );
        await r.agent.stop();
        expect(
          await r.agent.exitCode.timeout(const Duration(seconds: 10)),
          isNot(0),
          reason: 'the agent was killed (by its own handle)',
        );
        expect(r.killed, isEmpty, reason: 'its tree is not walked');
        expect(r.pidKills, unorderedEquals([_nowhere + 1, _nowhere + 2]));
        expect(r.pidKills, isNot(contains(r.agent.pid)));
      });

      test(
        'with no table the agent is killed and nothing is guessed',
        () async {
          final r = await run(
            [(agent) => null],
            ignoresStdin: true,
            grace: const Duration(milliseconds: 300),
            windows: true,
          );
          await r.agent.stop();
          await r.agent.exitCode.timeout(const Duration(seconds: 10));
          expect(r.killed, isEmpty);
          expect(r.pidKills, isEmpty);
        },
      );

      test('a pid that cannot be killed fails nobody else', () async {
        final r = await run(
          [tree, (agent) => afterwards()],
          failing: {_nowhere + 1},
          windows: true,
        );
        await r.agent.stop();
        expect(
          r.pidKills,
          unorderedEquals([_nowhere + 1, _nowhere + 2, _nowhere + 3]),
        );
        expect(await r.agent.exitCode, 0);
      });

      test(
        'kill() reads the table, then kills the agent, and each process '
        'the table showed under it that is still there, one by one',
        () async {
          final r = await run(
            [tree, (agent) => afterwards()],
            ignoresStdin: true,
            windows: true,
          );
          await r.agent.kill();
          expect(
            await r.agent.exitCode.timeout(const Duration(seconds: 10)),
            isNot(0),
          );
          expect(
            r.pidKills,
            unorderedEquals([_nowhere + 1, _nowhere + 2, _nowhere + 3]),
          );
          expect(r.killed, isEmpty, reason: 'no tree is walked');
          expect(
            r.log.take(2),
            ['table', 'table'],
            reason: 'the table, the agent still there; then the check again',
          );
        },
      );

      test('kill() checks again that each is still the same process, as the '
          'stop does: not a pid that was reused, not what left', () async {
        final r = await run(
          [
            tree,
            (agent) => [
              row(_nowhere + 1, 1),
              // _nowhere + 2 has left.
              // The pid of the test run was reused, an hour later.
              row(_nowhere + 3, 1, at: t0.add(const Duration(hours: 1))),
              row(_nowhere + 5, 1),
              row(_nowhere + 9, 1), // came after the table was read
            ],
          ],
          ignoresStdin: true,
          windows: true,
        );
        await r.agent.kill();
        await r.agent.exitCode.timeout(const Duration(seconds: 10));
        expect(r.pidKills, [_nowhere + 1]);
        expect(r.killed, isEmpty);
      });

      test('kill() with a table that cannot be read the second time kills '
          'the agent and guesses nothing', () async {
        for (final second in <List<ProcessRow>? Function(int)>[
          (agent) => null,
          (agent) => throw StateError('ps broke'),
        ]) {
          final r = await run(
            [tree, second],
            ignoresStdin: true,
            windows: true,
          );
          await r.agent.kill();
          await r.agent.exitCode.timeout(const Duration(seconds: 10));
          expect(r.pidKills, isEmpty);
          expect(r.log, ['table', 'table']);
        }
      });

      test('kill() never names this process or what is above it', () async {
        final r = await run(
          [
            (agent) => [
              row(agent, pid),
              row(pid, agent),
              row(_nowhere + 20, pid),
              row(1, agent),
              row(_nowhere + 1, agent),
            ],
          ],
          ignoresStdin: true,
          windows: true,
        );
        await r.agent.kill();
        await r.agent.exitCode.timeout(const Duration(seconds: 10));
        expect(r.pidKills, [_nowhere + 1]);
      });

      test('kill() with no table kills the agent and nothing else', () async {
        final r = await run(
          [(agent) => null],
          ignoresStdin: true,
          windows: true,
        );
        await r.agent.kill();
        await r.agent.exitCode.timeout(const Duration(seconds: 10));
        expect(r.pidKills, isEmpty);
        expect(r.killed, isEmpty);
      });

      test('kill() of an agent that has left reads no table', () async {
        final r = await run([tree], source: 'void main() {}', windows: true);
        await r.agent.exitCode;
        await r.agent.kill();
        expect(r.log, isEmpty);
      });
    });

    // The table a stop is given must not be older than the agent: a shared
    // read (SharedProcessTable) that began before it was spawned shows the
    // pid it got as the process that had it then. Both ways of killing, the
    // platform pinned in each: what is killed is the same.
    for (final windows in [false, true]) {
      group(
        'a table is never older than the agent '
        '(${windows ? 'a pid at a time, as on Windows' : 'with the tree killer'})',
        () {
          /// An agent that leaves when stdin closes, reading [table] and
          /// killing (either way) into [killed].
          Future<AgentProcess> start(
            ProcessTableReader table,
            List<int> killed,
          ) async => track(
            await AgentProcess.start(
              AgentCommand(
                executable: Platform.resolvedExecutable,
                args: [
                  ...dartScript(tmp, 'eof', _upThenExitOnEof),
                  '${tmp.path}/up',
                  '${tmp.path}/eof',
                ],
                environment: Platform.environment,
              ),
              cwd: tmp.path,
              // Not the 1.5 s of Windows: a cold runner starts the VM slowly.
              firstReadLimit: const Duration(seconds: 30),
              isWindows: windows,
              processTable: table,
              killTree: (proc) async => killed.add(proc.pid),
              killPid: (pid) async => killed.add(pid),
            ),
          );

          test('every request says when the agent was spawned', () async {
            final before = processClock();
            final r = await run([
              tree,
              (agent) => afterwards(),
            ], windows: windows);
            final spawned = processClock();
            await r.agent.stop();
            expect(r.afters, isNotEmpty);
            for (final after in r.afters) {
              expect(after, isNotNull);
              expect(after! >= before && after <= spawned, isTrue);
            }
            expect(r.afters.toSet(), hasLength(1), reason: 'the same moment');
          });

          test('a reader that always answers with a list works with a limit '
              '(its future cannot give null on a timeout, and must not need '
              'to)', () async {
            late final AgentProcess agent;
            var reads = 0;
            final killed = <int>[];
            agent = await start(
              // Written the plain way: the future is a Future<List<ProcessRow>>,
              // never a Future<List<ProcessRow>?>, whatever the type says.
              ({limit, after}) async => reads++ == 0
                  ? [row(agent.pid, pid), row(_nowhere + 1, agent.pid)]
                  : [row(_nowhere + 1, 1)],
              killed,
            );
            await agent.stop();
            expect(killed, [_nowhere + 1], reason: 'the snapshot was taken');
          });

          test('a read that began before the agent existed is not joined: its '
              'pid was another process\'s in that table, and that one\'s '
              'surviving children are not the agent\'s', () async {
            late int agentPid;
            var reads = 0;
            final shared = SharedProcessTable(({limit, after}) async {
              final call = reads++;
              if (call == 0) {
                // The table of a moment ago, slow to come: the pid the agent
                // has now was a child of this process that has left since, and
                // its child stays.
                await Future<void>.delayed(const Duration(milliseconds: 600));
                return [
                  row(agentPid, pid, command: 'old-child'),
                  row(_nowhere + 1, agentPid),
                  row(_nowhere + 2, _nowhere + 1),
                ];
              }
              // The table of now: the agent has started nothing; the old
              // child's children are there still, under init.
              return [
                row(agentPid, pid),
                row(_nowhere + 1, 1),
                row(_nowhere + 2, _nowhere + 1),
              ];
            });
            final someoneElses = shared(); // under way before the agent exists
            await Future<void>.delayed(const Duration(milliseconds: 20));
            final killed = <int>[];
            final agent = await start(shared.call, killed);
            agentPid = agent.pid;
            await agent.stop();
            expect(await agent.exitCode, 0);
            expect(
              killed,
              isEmpty,
              reason: 'nothing the agent started is left',
            );
            expect(
              reads,
              greaterThanOrEqualTo(2),
              reason: 'it read for itself',
            );
            await someoneElses;
          });

          test('a read that began after the agent was spawned is joined, as '
              'before', () async {
            var reads = 0;
            final shared = SharedProcessTable(({limit, after}) async {
              reads++;
              await Future<void>.delayed(const Duration(milliseconds: 200));
              return null;
            });
            final agent = await start(shared.call, []);
            await Future.wait([shared(), agent.stop()]);
            expect(reads, 1, reason: 'one read, started after the spawn');
          });
        },
      );
    }

    // On Windows every read of the table is a PowerShell, a second or two:
    // the stop waits for the first only a little, and the agents that stop
    // together (quit) share it (see SharedProcessTable).
    group('what a stop waits for', () {
      test('the read before stdin closes has the short limit; the ones after '
          'the reader\'s own', () async {
        final r = await run([
          tree,
          (agent) => afterwards(),
          (agent) => afterwards(worker: false),
        ], firstReadLimit: const Duration(milliseconds: 1500));
        await r.agent.stop();
        expect(r.limits.length, greaterThanOrEqualTo(2));
        expect(r.limits.first, const Duration(milliseconds: 1500));
        expect(r.limits.skip(1), everyElement(isNull));
      });

      test('with no limit given, the first read has the platform\'s', () async {
        final r = await run([tree, (agent) => afterwards()]);
        await r.agent.stop();
        expect(r.limits.first, firstTableReadLimit());
        expect(r.limits.skip(1), everyElement(isNull));
      });

      test('a table that does not answer holds the stop for the limit and '
          'no longer', () async {
        final r = await run([
          (agent) => Completer<List<ProcessRow>?>().future,
        ], firstReadLimit: const Duration(milliseconds: 300));
        final clock = Stopwatch()..start();
        await r.agent.stop();
        expect(await r.agent.exitCode, 0);
        expect(
          clock.elapsed,
          lessThan(const Duration(seconds: 5)),
          reason: 'it was not held for the table, it went when stdin closed',
        );
        expect(r.log, ['table'], reason: 'no snapshot, so no read after');
        expect(r.killed, isEmpty);
      }, timeout: const Timeout(Duration(seconds: 20)));

      test('a table that answers in time is used', () async {
        final r = await run([
          (agent) async {
            await Future<void>.delayed(const Duration(milliseconds: 50));
            return tree(agent);
          },
          (agent) => afterwards(testRun: false),
          (agent) => [row(_nowhere + 5, 1)],
        ], firstReadLimit: const Duration(seconds: 5));
        await r.agent.stop();
        expect(r.killed, [_nowhere + 1]);
      });
    });
  });

  // Real processes, both ways of killing what the agent left: a tree at a
  // time (macOS, Linux) and a pid at a time (Windows, run here as well).
  for (final windows in [false, true]) {
    group(
      'with real processes (${windows ? 'a pid at a time, as on Windows' : 'with the tree killer'})',
      () {
        final noSh = Platform.isWindows
            ? 'the fake agent is a shell script'
            : null;

        Future<int> pidIn(File file) async {
          for (var i = 0; i < 200 && !file.existsSync(); i++) {
            await Future<void>.delayed(const Duration(milliseconds: 25));
          }
          // The shell wrote the line as it started the child: a beat for it to be
          // complete.
          await Future<void>.delayed(const Duration(milliseconds: 100));
          final pid = int.parse(file.readAsStringSync().trim());
          strangers.add(pid);
          return pid;
        }

        Future<bool> goneSoon(int pid) async {
          for (var i = 0; i < 60; i++) {
            if (!_alive(pid)) return true;
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
          return false;
        }

        AgentCommand shell(String script) => AgentCommand(
          executable: '/bin/sh',
          args: ['-c', script],
          environment: const {'PATH': '/usr/bin:/bin'},
        );

        test(
          'an agent that exits when stdin closes leaves no child behind',
          () async {
            final pidFile = File('${tmp.path}/child.pid');
            final p = track(
              await AgentProcess.start(
                shell(
                  'sleep 60 & echo \$! > "${pidFile.path}"; cat > /dev/null; exit 0',
                ),
                cwd: tmp.path,
                isWindows: windows,
              ),
            );
            final child = await pidIn(pidFile);
            expect(_alive(child), isTrue);
            await p.stop();
            expect(await p.exitCode, 0, reason: 'it left by itself, in time');
            expect(
              await goneSoon(child),
              isTrue,
              reason: 'its child went with it',
            );
          },
          skip: noSh,
        );

        test(
          'a child with a child of its own: the whole of what it left',
          () async {
            final middleFile = File('${tmp.path}/middle.pid');
            final workerFile = File('${tmp.path}/worker.pid');
            final p = track(
              await AgentProcess.start(
                shell(
                  'sh -c \'sleep 60 & echo \$! > "${workerFile.path}"; wait\' & '
                  'echo \$! > "${middleFile.path}"; cat > /dev/null; exit 0',
                ),
                cwd: tmp.path,
                isWindows: windows,
              ),
            );
            final middle = await pidIn(middleFile);
            final worker = await pidIn(workerFile);
            await p.stop();
            expect(await goneSoon(middle), isTrue);
            expect(await goneSoon(worker), isTrue);
          },
          skip: noSh,
        );

        test('what the agent did not start is left alone', () async {
          final pidFile = File('${tmp.path}/child.pid');
          final bystander = await Process.start('/bin/sleep', ['60']);
          strangers.add(bystander.pid);
          final p = track(
            await AgentProcess.start(
              shell(
                'sleep 60 & echo \$! > "${pidFile.path}"; cat > /dev/null; exit 0',
              ),
              cwd: tmp.path,
              isWindows: windows,
            ),
          );
          final child = await pidIn(pidFile);
          await p.stop();
          expect(await goneSoon(child), isTrue);
          expect(
            _alive(bystander.pid),
            isTrue,
            reason: 'not the agent\'s child',
          );
        }, skip: noSh);

        test('an agent that has to be killed takes its children too', () async {
          final pidFile = File('${tmp.path}/child.pid');
          final p = track(
            await AgentProcess.start(
              shell('sleep 60 & echo \$! > "${pidFile.path}"; exec sleep 300'),
              cwd: tmp.path,
              isWindows: windows,
              grace: const Duration(milliseconds: 400),
            ),
          );
          final child = await pidIn(pidFile);
          await p.stop();
          await p.exitCode.timeout(const Duration(seconds: 10));
          expect(await goneSoon(child), isTrue);
        }, skip: noSh);

        if (windows) {
          test(
            'kill() takes the agent and what it started, one by one',
            () async {
              final pidFile = File('${tmp.path}/child.pid');
              final bystander = await Process.start('/bin/sleep', ['60']);
              strangers.add(bystander.pid);
              final p = track(
                await AgentProcess.start(
                  shell(
                    'sleep 60 & echo \$! > "${pidFile.path}"; exec sleep 300',
                  ),
                  cwd: tmp.path,
                  isWindows: true,
                ),
              );
              final child = await pidIn(pidFile);
              await p.kill();
              await p.exitCode.timeout(const Duration(seconds: 10));
              expect(await goneSoon(child), isTrue);
              expect(
                _alive(bystander.pid),
                isTrue,
                reason: 'not the agent\'s child',
              );
            },
            skip: noSh,
          );
        }
      },
    );
  }
}
