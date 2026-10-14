// Pins what the brief's process test files leave open: redacted toString,
// the default tree killer, the stderr ring and the working folder of a real
// process, no shell, and the shapes the crash registry reads and writes.
import 'dart:convert';
import 'dart:io';

import 'package:shellx_ai/host.dart';
import 'package:test/test.dart';

import '../support/processes.dart';
import '../support/scripts.dart';

void main() {
  late Directory tmp;
  final started = <AgentProcess>[];
  setUp(() => tmp = Directory.systemTemp.createTempSync('process_contract'));
  tearDown(() async {
    for (final p in started) {
      await killIfRunning(p);
    }
    started.clear();
    tmp.deleteSync(recursive: true);
  });

  group('AgentProcess', () {
    Future<AgentProcess> launch(
      String source, {
      List<String> scriptArgs = const [],
      KillTree killTree = killOnly,
      Duration grace = const Duration(seconds: 2),
    }) async {
      final p = await AgentProcess.start(
        AgentCommand(
          executable: Platform.resolvedExecutable,
          args: [
            ...dartScript(tmp, 'script${started.length}', source),
            ...scriptArgs,
          ],
          environment: Platform.environment,
        ),
        cwd: tmp.path,
        killTree: killTree,
        isWindows: false, // the tree killer is what these tests ask about
        grace: grace,
      );
      started.add(p);
      return p;
    }

    Future<String> output(AgentProcess p) => p.stdout
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 10));

    test('toString shows nothing of the process', () async {
      final p = await launch(printEnv);
      expect(p.toString(), '…');
      await p.exitCode.timeout(const Duration(seconds: 10));
    });

    test('kill() ends it at once; by default only the process', () async {
      final p = await launch(ignoreStdin);
      await p.kill();
      expect(await p.exitCode.timeout(const Duration(seconds: 10)), isNot(0));
    });

    test('kill() goes through the given tree killer', () async {
      final trees = <int>[];
      final p = await launch(
        ignoreStdin,
        killTree: (proc) async {
          trees.add(proc.pid);
          proc.kill(ProcessSignal.sigkill);
        },
      );
      await p.kill();
      await p.exitCode.timeout(const Duration(seconds: 10));
      expect(trees, [p.pid]);
    });

    test('stop() asked twice at once is one stop and one kill', () async {
      final killed = <int>[];
      final p = await launch(
        ignoreStdin,
        grace: const Duration(milliseconds: 300),
        killTree: (proc) async {
          killed.add(proc.pid);
          proc.kill(ProcessSignal.sigkill);
        },
      );
      await Future.wait([p.stop(), p.stop()]);
      await p.exitCode.timeout(const Duration(seconds: 10));
      expect(killed, [p.pid]);
    });

    test('stop() on a process that has left kills nothing', () async {
      final killed = <int>[];
      final p = await launch(
        printEnv,
        killTree: (proc) async => killed.add(proc.pid),
      );
      await p.exitCode.timeout(const Duration(seconds: 10));
      await p.stop();
      expect(killed, isEmpty);
    });

    test('stderrTail keeps the last 256 KiB of a noisy process', () async {
      final p = await launch(noisyStderr);
      await p.exitCode.timeout(const Duration(seconds: 10));
      // The pipe may still hold the last bytes when the exit is reported.
      for (var i = 0; i < 100 && !p.stderrTail.endsWith('last line\n'); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      final tail = p.stderrTail;
      expect(tail, endsWith('last line\n'));
      expect(utf8.encode(tail), hasLength(256 * 1024));
    });

    test('runs in the folder it is given', () async {
      final p = await launch(printCwd);
      expect(
        Directory(await output(p)).resolveSymbolicLinksSync(),
        tmp.resolveSymbolicLinksSync(),
      );
    });

    test('no shell: arguments arrive exactly as given', () async {
      final args = [
        'a b',
        r'$HOME',
        '*',
        '; echo hi',
        "it's",
        // Windows command lines have their own rule for an empty argument.
        if (!Platform.isWindows) '',
      ];
      final p = await launch(printArgs, scriptArgs: args);
      expect(jsonDecode(await output(p)), args);
    });
  });

  group('RunningAgents', () {
    late File file;
    final t0 = DateTime.utc(2026, 10, 14, 9);
    setUp(() => file = File('${tmp.path}/ai/running.json'));

    test('RunningRecord shows nothing in toString', () {
      final r = RunningRecord(pid: 7, command: '/secret/agent', startedAt: t0);
      expect(r.toString(), '…');
    });

    test(
      'the file is {v, agents} with epoch milliseconds, no temp left',
      () async {
        final r = RunningAgents(file);
        await r.add(
          RunningRecord(pid: 7, command: '/usr/bin/node', startedAt: t0),
        );
        expect(jsonDecode(file.readAsStringSync()), {
          'v': 1,
          'agents': [
            {
              'pid': 7,
              'command': '/usr/bin/node',
              'startedAt': t0.millisecondsSinceEpoch,
            },
          ],
        });
        expect(File('${file.path}.tmp').existsSync(), isFalse);
        final back = RunningAgents(file).read().single;
        expect(
          (back.pid, back.command, back.startedAt),
          (7, '/usr/bin/node', t0),
        );
      },
    );

    test('adding a pid again replaces its record', () async {
      final r = RunningAgents(file);
      await r.add(RunningRecord(pid: 7, command: 'node', startedAt: t0));
      await r.add(
        RunningRecord(
          pid: 7,
          command: 'python3',
          startedAt: t0.add(const Duration(minutes: 1)),
        ),
      );
      final records = r.read();
      expect(records, hasLength(1));
      expect(records.single.command, 'python3');
    });

    test('removing an unknown pid changes nothing', () async {
      final r = RunningAgents(file);
      await r.add(RunningRecord(pid: 1, command: 'node', startedAt: t0));
      await r.remove(2);
      expect(r.read().map((e) => e.pid), [1]);
    });

    test('a missing file is empty', () async {
      final r = RunningAgents(file, info: (_) async => fail('nothing'));
      expect(r.read(), isEmpty);
      expect(await r.sweep(), 0);
    });

    test('entries it cannot understand are skipped, the rest kept', () {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        jsonEncode({
          'v': 1,
          'agents': [
            {'pid': 1, 'command': 'node', 'startedAt': 1000},
            {'pid': '2', 'command': 'node', 'startedAt': 1000},
            {'pid': 3, 'startedAt': 1000},
            {'pid': 4, 'command': 'node'},
            {'pid': 5, 'command': 5, 'startedAt': 1000},
            'garbage',
            5,
            null,
            {'pid': 6, 'command': 'node', 'startedAt': 2000},
          ],
        }),
      );
      expect(RunningAgents(file).read().map((e) => e.pid), [1, 6]);
    });

    test('a file of another shape is empty', () {
      file.parent.createSync(recursive: true);
      for (final text in ['', '[]', '5', 'null', '{}', '{"agents": 5}']) {
        file.writeAsStringSync(text);
        expect(RunningAgents(file).read(), isEmpty, reason: text);
      }
    });

    test('sweep matches the start time within the tolerance', () async {
      const tolerance = Duration(seconds: 2);
      const ms = Duration(milliseconds: 1);
      final killed = <int>[];
      final now = {
        1: (command: 'node', startedAt: t0.add(tolerance)),
        2: (command: 'node', startedAt: t0.add(tolerance + ms)),
        3: (command: 'node', startedAt: t0.subtract(tolerance)),
        4: (command: 'node', startedAt: t0.subtract(tolerance + ms)),
      };
      final r = RunningAgents(
        file,
        tolerance: tolerance,
        isWindows: false, // the tree killer is what is asked about
        info: (pid) async => now[pid],
        killPid: (pid) async => killed.add(pid),
      );
      for (final pid in now.keys) {
        await r.add(
          RunningRecord(pid: pid, command: '/usr/bin/node', startedAt: t0),
        );
      }
      expect(await r.sweep(), 2);
      expect(killed, [
        1,
        3,
      ], reason: 'a millisecond further is another process');
    });

    test('sweep compares the program name, not folder, case or .exe', () async {
      final killed = <int>[];
      final now = {
        1: (command: r'C:\Program Files\nodejs\node.exe', startedAt: t0),
        2: (
          command: '/opt/homebrew/Cellar/node/22.1.0/bin/node',
          startedAt: t0,
        ),
        3: (command: '/usr/bin/nodejs', startedAt: t0),
        4: (command: '/usr/bin/NODE', startedAt: t0),
      };
      final r = RunningAgents(
        file,
        isWindows: false, // the tree killer is what is asked about
        info: (pid) async => now[pid],
        killPid: (pid) async => killed.add(pid),
      );
      for (final (pid, cmd) in [
        (1, 'node'),
        (2, r'C:\tools\Node.EXE'),
        (3, 'node'),
        (4, '/usr/local/bin/node'),
      ]) {
        await r.add(RunningRecord(pid: pid, command: cmd, startedAt: t0));
      }
      expect(await r.sweep(), 3);
      expect(killed, [1, 2, 4], reason: '3 is nodejs, another program');
    });

    test('lookupProcess finds nothing for a process that has left', () async {
      final done = await Process.run(
        Platform.resolvedExecutable,
        dartScript(tmp, 'env', printEnv),
      );
      expect(await lookupProcess(done.pid), isNull);
    });
  });
}
