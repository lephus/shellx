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
    Future<
      ({
        AgentProcess agent,
        List<int> killed,
        List<String> log,
        List<Duration?> limits,
      })
    >
    run(
      List<FutureOr<List<ProcessRow>?> Function(int agent)> tables, {
      bool ignoresStdin = false,
      String? source,
      Duration grace = const Duration(seconds: 2),
      Duration? firstReadLimit,
      Set<int> failing = const {},
    }) async {
      final killed = <int>[];
      final log = <String>[];
      final limits = <Duration?>[];
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
          processTable: ({limit}) async {
            log.add('table');
            limits.add(limit);
            final answer =
                tables[reads < tables.length ? reads : tables.length - 1];
            reads++;
            return answer(agent.pid);
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
      return (agent: agent, killed: killed, log: log, limits: limits);
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
          processTable: ({limit}) async {
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
          tmp.listSync().whereType<File>().forEach((f) => f.deleteSync());
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
          tmp.listSync().whereType<File>().forEach((f) => f.deleteSync());
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
    // still killed.
    group('never this process, what is above it, or pid 0 and 1', () {
      /// The dev server the agent really left, and its worker.
      List<ProcessRow> left(int agent) => [
        row(_nowhere + 1, agent),
        row(_nowhere + 2, _nowhere + 1),
      ];

      Future<void> expectOnlyTheLeftovers(
        List<ProcessRow> Function(int agent) table,
      ) async {
        final r = await run([table]);
        await r.agent.stop();
        expect(await r.agent.exitCode, 0);
        expect(r.killed, [
          _nowhere + 1,
          _nowhere + 2,
        ], reason: 'what the agent left, and nothing else');
      }

      test('this process listed as a child of the agent: neither it nor what '
          'is under it', () async {
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

      test('an ancestor listed as a child of the agent: neither it nor what '
          'is under it', () async {
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
        ]);
        await r.agent.stop();
        expect(r.killed, [_nowhere + 1, _nowhere + 2]);
      });
    });

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

  group('with real processes', () {
    final noSh = Platform.isWindows ? 'the fake agent is a shell script' : null;

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
          ),
        );
        final child = await pidIn(pidFile);
        expect(_alive(child), isTrue);
        await p.stop();
        expect(await p.exitCode, 0, reason: 'it left by itself, in time');
        expect(await goneSoon(child), isTrue, reason: 'its child went with it');
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
        ),
      );
      final child = await pidIn(pidFile);
      await p.stop();
      expect(await goneSoon(child), isTrue);
      expect(_alive(bystander.pid), isTrue, reason: 'not the agent\'s child');
    }, skip: noSh);

    test('an agent that has to be killed takes its children too', () async {
      final pidFile = File('${tmp.path}/child.pid');
      final p = track(
        await AgentProcess.start(
          shell('sleep 60 & echo \$! > "${pidFile.path}"; exec sleep 300'),
          cwd: tmp.path,
          grace: const Duration(milliseconds: 400),
        ),
      );
      final child = await pidIn(pidFile);
      await p.stop();
      await p.exitCode.timeout(const Duration(seconds: 10));
      expect(await goneSoon(child), isTrue);
    }, skip: noSh);
  });
}
