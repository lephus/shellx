import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/platform/pty/process_table.dart';
import 'package:shellx_desktop/src/platform/pty/process_tree_killer.dart';

final class _FakeTable implements ProcessTable {
  _FakeTable(this.snapshots);
  final List<List<ProcessEntry>> snapshots;
  int calls = 0;

  @override
  Future<List<ProcessEntry>> snapshot() async =>
      snapshots[calls < snapshots.length ? calls++ : snapshots.length - 1];
}

ProcessEntry _p(int pid, int ppid, [String name = 'x']) =>
    ProcessEntry(pid: pid, parentPid: ppid, name: name);

void main() {
  group('parsePsOutput', () {
    test('parses padded columns and names containing spaces', () {
      const output =
          '    1     0 /sbin/launchd\n'
          '  812     1 /Applications/Visual Studio Code.app/Contents/MacOS/Electron\n'
          'garbage line\n'
          ' 9001   812 -zsh\n';
      final entries = parsePsOutput(output);
      expect(entries.map((e) => e.pid), [1, 812, 9001]);
      expect(
        entries[1].name,
        '/Applications/Visual Studio Code.app/Contents/MacOS/Electron',
      );
      expect(entries[2].parentPid, 812);
    });
  });

  group('descendantsOf', () {
    test('returns the whole subtree and nothing else', () {
      final table = [
        _p(1, 0),
        _p(100, 1),
        _p(101, 100),
        _p(102, 101),
        _p(103, 100),
        _p(200, 1),
        _p(201, 200),
      ];
      expect(descendantsOf(100, table)..sort(), [101, 102, 103]);
      expect(descendantsOf(999, table), isEmpty);
    });

    test('survives self-parented entries and cycles', () {
      final table = [_p(0, 0), _p(5, 6), _p(6, 5)];
      expect(descendantsOf(5, table), [6]);
    });
  });

  group('PosixProcessTreeKiller', () {
    test(
      'SIGHUPs the tree, then SIGKILLs survivors and late children',
      () async {
        final sent = <(int, ProcessSignal)>[];
        final table = _FakeTable([
          [_p(1, 0), _p(100, 1), _p(101, 100), _p(102, 101), _p(200, 1)],
          [_p(1, 0), _p(101, 1), _p(100, 1), _p(105, 100), _p(200, 1)],
        ]);
        final killer = PosixProcessTreeKiller(
          table: table,
          signal: (pid, signal) {
            sent.add((pid, signal));
            return true;
          },
          grace: Duration.zero,
          ownPid: 4242,
        );

        await killer.killTree(100);

        final hups = sent
            .where((s) => s.$2 == ProcessSignal.sighup)
            .map((s) => s.$1)
            .toSet();
        final kills = sent
            .where((s) => s.$2 == ProcessSignal.sigkill)
            .map((s) => s.$1)
            .toSet();
        expect(hups, {100, 101, 102});
        expect(kills, {100, 101, 105});
        expect(sent.map((s) => s.$1), isNot(contains(200)));
      },
    );

    test('never signals itself, launchd or pid 0', () async {
      final sent = <int>[];
      final killer = PosixProcessTreeKiller(
        table: _FakeTable([
          [_p(50, 1), _p(4242, 50), _p(1, 50)],
        ]),
        signal: (pid, _) {
          sent.add(pid);
          return true;
        },
        grace: Duration.zero,
        ownPid: 4242,
      );
      await killer.killTree(50);
      expect(sent.toSet(), {50});
      sent.clear();
      await killer.killTree(4242);
      await killer.killTree(1);
      expect(sent, isEmpty);
    });
  });

  test(
    'WindowsProcessTreeKiller runs taskkill /T /F on the shell pid',
    () async {
      final calls = <List<String>>[];
      final killer = WindowsProcessTreeKiller(
        run: (exe, args) async {
          calls.add([exe, ...args]);
          return ProcessResult(0, 0, '', '');
        },
      );
      await killer.killTree(777);
      expect(calls, [
        ['taskkill', '/PID', '777', '/T', '/F'],
      ]);
    },
  );
}
