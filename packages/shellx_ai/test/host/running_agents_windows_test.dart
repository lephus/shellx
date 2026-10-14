// The startup sweep of the agents a crash left behind (spec §6), on Windows
// (V2-1b final review, G3 round 3). `taskkill /T` there follows the
// ParentProcessId of every process, and Windows keeps that id after the
// parent has left, so a process that has nothing to do with the leftover (an
// explorer.exe whose parent id is the pid the leftover got since, a process
// above ShellX) could die at startup. The sweep checks the leftover agent as
// before, then kills it and the processes ONE table read shows under it, each
// on its own: never a tree, never this process or what is above it. The
// strategy is run on any machine here (`isWindows: true`) with a crafted table.
import 'dart:io';

import 'package:shellx_ai/host.dart';
import 'package:test/test.dart';

/// A pid no system hands out (macOS stops at 99998, Linux at 4194304): a test
/// that names it can never signal a stranger by mistake.
const _nowhere = 5000000;

void main() {
  late Directory tmp;
  late File file;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sweep_windows');
    file = File('${tmp.path}/ai/running.json');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  // The leftover started at t0, a crash ago; this ShellX three hours later.
  final t0 = DateTime.utc(2026, 10, 14, 9);
  const node = r'C:\Program Files\nodejs\node.exe';
  const leftover = _nowhere + 1;
  DateTime at(Duration after) => t0.add(after);
  ProcessRow row(
    int pid,
    int parent, {
    Duration after = Duration.zero,
    String command = r'C:\tools\tool.exe',
  }) => ProcessRow(
    pid: pid,
    parentPid: parent,
    command: command,
    startedAt: at(after),
  );

  /// The leftover agent and what it started, in a table of Windows.
  List<ProcessRow> theirs() => [
    row(leftover, _nowhere + 99, command: node), // its parent is gone
    row(_nowhere + 2, leftover, after: const Duration(minutes: 1)),
    row(_nowhere + 3, _nowhere + 2, after: const Duration(minutes: 2)),
    row(_nowhere + 8, 1), // anybody's
  ];

  /// This process, started by a launcher that explorer.exe started.
  const launcher = _nowhere + 50;
  const explorer = _nowhere + 51;
  List<ProcessRow> ours() => [
    row(
      pid,
      launcher,
      after: const Duration(hours: 3),
      command: r'C:\ShellX\ShellX.exe',
    ),
    row(launcher, explorer, after: const Duration(hours: 2, minutes: 59)),
    row(
      explorer,
      _nowhere + 77, // userinit.exe, long gone
      after: -const Duration(hours: 5),
      command: r'C:\Windows\explorer.exe',
    ),
  ];

  Future<
    ({
      int stopped,
      List<int> alone,
      List<int> tree,
      int reads,
      RunningAgents sweeper,
    })
  >
  sweep(
    List<ProcessRow>? Function() table, {
    List<RunningRecord>? records,
    ProcessLookup? info,
    Set<int> failing = const {},
    bool windows = true,
  }) async {
    final alone = <int>[];
    final tree = <int>[];
    var reads = 0;
    final sweeper = RunningAgents(
      file,
      isWindows: windows,
      info:
          info ??
          (pid) async =>
              pid == leftover ? (command: node, startedAt: t0) : null,
      processTable: ({limit, after}) async {
        reads++;
        return table();
      },
      killPid: (pid) async => tree.add(pid),
      killAlone: (pid) async {
        alone.add(pid);
        if (failing.contains(pid)) throw StateError('cannot kill');
      },
    );
    for (final r
        in records ??
            [RunningRecord(pid: leftover, command: node, startedAt: t0)]) {
      await sweeper.add(r);
    }
    final stopped = await sweeper.sweep();
    return (
      stopped: stopped,
      alone: alone,
      tree: tree,
      reads: reads,
      sweeper: sweeper,
    );
  }

  group('on Windows the sweep kills one table read, a pid at a time', () {
    test('the leftover and what the table shows under it, each on its own; '
        'no tree is walked', () async {
      final r = await sweep(() => [...theirs(), ...ours()]);
      expect(r.stopped, 1, reason: 'one agent was left behind');
      expect(
        r.alone,
        unorderedEquals([leftover, _nowhere + 2, _nowhere + 3]),
        reason: 'the agent, its child, and the child\'s own: all on the list',
      );
      expect(r.tree, isEmpty, reason: 'no taskkill /T, no tree killer');
      expect(r.reads, 1, reason: 'one table for it');
      expect(r.sweeper.read(), isEmpty, reason: 'the file is cleared');
    });

    test('the agent first: it cannot start anything more', () async {
      final r = await sweep(() => [...theirs(), ...ours()]);
      expect(r.alone.first, leftover);
    });

    test('explorer.exe whose parent id is the pid the leftover got is not '
        'killed, nor what is under it', () async {
      final r = await sweep(
        () => [
          ...theirs(),
          // userinit.exe died and the leftover got its pid: explorer's
          // parent id now names the leftover, but explorer is much older.
          row(
            _nowhere + 60,
            leftover,
            after: -const Duration(hours: 5),
            command: r'C:\Windows\explorer.exe',
          ),
          row(
            _nowhere + 61,
            _nowhere + 60,
            after: -const Duration(hours: 4),
            command: r'C:\Windows\System32\cmd.exe',
          ),
        ],
      );
      expect(r.alone, unorderedEquals([leftover, _nowhere + 2, _nowhere + 3]));
    });

    test('so too when that explorer.exe is above this process (ShellX was '
        'started from it)', () async {
      final r = await sweep(
        () => [
          ...theirs(),
          ...ours().map(
            // explorer's parent id is the leftover's pid
            (x) => x.pid == explorer
                ? row(
                    explorer,
                    leftover,
                    after: -const Duration(hours: 5),
                    command: r'C:\Windows\explorer.exe',
                  )
                : x,
          ),
        ],
      );
      expect(
        r.alone,
        unorderedEquals([leftover, _nowhere + 2, _nowhere + 3]),
        reason:
            'explorer is older than the leftover, so the id is stale: the '
            'leftover is still swept, and explorer, the launcher and this '
            'process are not',
      );
      expect(r.stopped, 1);
    });

    test('this process listed under the leftover: nothing is killed, the '
        'leftover may be what started it', () async {
      final r = await sweep(
        () => [
          ...theirs(),
          row(pid, leftover, after: const Duration(hours: 3)),
          row(_nowhere + 70, pid, after: const Duration(hours: 3, minutes: 1)),
        ],
      );
      expect(r.alone, isEmpty);
      expect(r.tree, isEmpty);
      expect(r.stopped, 0);
    });

    test(
      'an ancestor of this process listed under the leftover, younger '
      'than it: nothing is killed (the leftover is above this process)',
      () async {
        final r = await sweep(
          () => [
            ...theirs(),
            row(pid, _nowhere + 71, after: const Duration(hours: 3)),
            row(_nowhere + 71, _nowhere + 72, after: const Duration(hours: 2)),
            row(_nowhere + 72, leftover, after: const Duration(hours: 1)),
            row(_nowhere + 73, _nowhere + 72, after: const Duration(hours: 1)),
          ],
        );
        expect(r.alone, isEmpty);
        expect(r.stopped, 0);
      },
    );

    test('an agent that is this process, or above it, or pid 1 or 0, is '
        'never killed, whatever the record says', () async {
      // The table agrees with the record about who it is: it is the refusal
      // that stops the kill, not a difference in the second look.
      final table = [...ours(), row(1, 0), row(0, 0)];
      for (final target in [pid, launcher, explorer, 1, 0]) {
        final named = table.firstWhere((x) => x.pid == target);
        final r = await sweep(
          () => table,
          records: [
            RunningRecord(
              pid: target,
              command: named.command,
              startedAt: named.startedAt,
            ),
          ],
          info: (p) async =>
              (command: named.command, startedAt: named.startedAt),
        );
        expect(r.alone, isEmpty, reason: 'pid $target');
        expect(r.tree, isEmpty);
        expect(r.stopped, 0, reason: 'pid $target');
      }
    });

    test(
      'init and the system listed under the leftover are not killed',
      () async {
        final r = await sweep(
          () => [
            ...theirs(),
            row(1, leftover),
            row(0, leftover),
            row(_nowhere + 40, 1),
            row(_nowhere + 41, 0),
          ],
        );
        expect(
          r.alone,
          unorderedEquals([leftover, _nowhere + 2, _nowhere + 3]),
        );
      },
    );

    test('the second look at the table: another program under that pid, or a '
        'start that does not match, and nothing is killed', () async {
      for (final differing in [
        row(leftover, 1, command: r'C:\Windows\notepad.exe'),
        row(leftover, 1, command: node, after: const Duration(hours: 1)),
      ]) {
        final r = await sweep(() => [differing, row(_nowhere + 2, leftover)]);
        expect(r.alone, isEmpty);
        expect(r.stopped, 0);
      }
    });

    test('the leftover is not in the table (it left in between): nothing is '
        'killed on a guess', () async {
      final r = await sweep(() => [row(_nowhere + 2, leftover), ...ours()]);
      expect(r.alone, isEmpty);
      expect(r.stopped, 0);
    });

    test('a table that cannot be had: the leftover alone, as the check '
        'found it', () async {
      for (final none in <List<ProcessRow>? Function()>[
        () => null,
        () => throw StateError('powershell broke'),
      ]) {
        final r = await sweep(none);
        expect(r.alone, [leftover]);
        expect(r.tree, isEmpty);
        expect(r.stopped, 1);
      }
    });

    test('the identity check comes first: no table is read for what is no '
        'leftover', () async {
      for (final info in <ProcessLookup>[
        (pid) async => null,
        (pid) async => (command: r'C:\Windows\notepad.exe', startedAt: t0),
        (pid) async => (command: node, startedAt: at(const Duration(hours: 1))),
      ]) {
        final r = await sweep(() => theirs(), info: info);
        expect(r.reads, 0);
        expect(r.alone, isEmpty);
        expect(r.stopped, 0);
      }
    });

    test('every leftover is looked at on its own table', () async {
      final r = await sweep(
        () => [
          ...theirs(),
          row(_nowhere + 11, _nowhere + 99, command: node),
          row(_nowhere + 12, _nowhere + 11),
        ],
        records: [
          RunningRecord(pid: leftover, command: node, startedAt: t0),
          RunningRecord(pid: _nowhere + 11, command: node, startedAt: t0),
        ],
        info: (pid) async => (command: node, startedAt: t0),
      );
      expect(r.stopped, 2);
      expect(r.reads, 2);
      expect(
        r.alone,
        unorderedEquals([
          leftover,
          _nowhere + 2,
          _nowhere + 3,
          _nowhere + 11,
          _nowhere + 12,
        ]),
      );
    });

    test('a pid that cannot be killed fails nobody else', () async {
      final r = await sweep(
        () => [...theirs(), ...ours()],
        failing: {leftover, _nowhere + 2},
      );
      expect(r.alone, unorderedEquals([leftover, _nowhere + 2, _nowhere + 3]));
      expect(r.sweeper.read(), isEmpty);
    });
  });

  group('elsewhere the sweep is as it was', () {
    test('the leftover goes through the tree killer, and no table is '
        'read', () async {
      final r = await sweep(() => [...theirs(), ...ours()], windows: false);
      expect(r.tree, [leftover]);
      expect(r.alone, isEmpty);
      expect(r.reads, 0);
      expect(r.stopped, 1);
    });
  });
}
