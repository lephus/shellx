import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/platform/pty/process_table.dart';
import 'package:shellx_desktop/src/platform/pty/process_tree_killer.dart';

/// Returns `snapshots[n]` on the n-th call (the last one once exhausted).
final class _FakeTable implements ProcessTable {
  _FakeTable(this.snapshots);
  final List<List<ProcessEntry>> snapshots;
  int calls = 0;

  @override
  Future<List<ProcessEntry>> snapshot() async =>
      snapshots[calls < snapshots.length ? calls++ : snapshots.length - 1];
}

final class _FailingTable implements ProcessTable {
  @override
  Future<List<ProcessEntry>> snapshot() async =>
      throw const ProcessTableException('ps exited with code 1');
}

final class _GrowingTable implements ProcessTable {
  int calls = 0;

  /// A chain 100 -> 101 -> ... that gains one process on every call.
  @override
  Future<List<ProcessEntry>> snapshot() async {
    calls++;
    return [_p(100, 1), for (var i = 1; i <= calls; i++) _p(100 + i, 99 + i)];
  }
}

ProcessEntry _p(int pid, int ppid, [String name = 'x']) =>
    ProcessEntry(pid: pid, parentPid: ppid, name: name);

typedef _Sent = List<(int, ProcessSignal)>;

PosixProcessTreeKiller _killer(
  ProcessTable table,
  _Sent sent, {
  Duration grace = Duration.zero,
  Duration pollInterval = const Duration(milliseconds: 1),
}) {
  return PosixProcessTreeKiller(
    table: table,
    signal: (pid, signal) {
      sent.add((pid, signal));
      return true;
    },
    grace: grace,
    pollInterval: pollInterval,
    ownPid: 4242,
  );
}

Set<int> _pids(_Sent sent, ProcessSignal signal) => {
  for (final (pid, s) in sent)
    if (s == signal) pid,
};

int _first(_Sent sent, int pid, ProcessSignal signal) =>
    sent.indexWhere((s) => s.$1 == pid && s.$2 == signal);

int _last(_Sent sent, ProcessSignal signal) =>
    sent.lastIndexWhere((s) => s.$2 == signal);

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

  group('PsProcessTable', () {
    test('a failing ps is an error, not an empty table', () async {
      final table = PsProcessTable(
        run: (executable, arguments) async =>
            ProcessResult(1, 1, '', 'ps: something went wrong'),
      );
      await expectLater(
        table.snapshot(),
        throwsA(
          isA<ProcessTableException>().having(
            (e) => e.message,
            'message',
            'ps exited with code 1',
          ),
        ),
      );
    });

    test('a ps that cannot start is an error', () async {
      final table = PsProcessTable(
        run: (executable, arguments) async => throw ProcessException(
          executable,
          arguments,
          'No such file or directory',
          2,
        ),
      );
      await expectLater(
        table.snapshot(),
        throwsA(
          isA<ProcessTableException>().having(
            (e) => e.message,
            'message',
            'cannot run ps (OS error 2)',
          ),
        ),
      );
    });

    test('runs /bin/ps and parses its output', () async {
      final calls = <List<String>>[];
      final table = PsProcessTable(
        run: (executable, arguments) async {
          calls.add([executable, ...arguments]);
          return ProcessResult(1, 0, '  100     1 zsh\n', '');
        },
      );
      final entries = await table.snapshot();
      expect(calls, [
        ['/bin/ps', '-A', '-o', 'pid=,ppid=,comm='],
      ]);
      expect(entries.single.pid, 100);
    });
  });

  group('PosixProcessTreeKiller', () {
    test('hangs up the shell first, without stopping it beforehand', () async {
      final sent = <(int, ProcessSignal)>[];
      await _killer(
        _FakeTable([
          [_p(100, 1)],
        ]),
        sent,
      ).killTree(100);
      expect(sent.first, (100, ProcessSignal.sighup));
    });

    test(
      'freezes the tree to a fixpoint, hangs it up, then kills what is left',
      () async {
        final sent = <(int, ProcessSignal)>[];
        final table = _FakeTable([
          [_p(1, 0), _p(100, 1), _p(101, 100), _p(200, 1)],
          // 101 forked 102 before its SIGSTOP landed.
          [_p(1, 0), _p(100, 1), _p(101, 100), _p(102, 101), _p(200, 1)],
        ]);

        await _killer(table, sent).killTree(100);

        expect(_pids(sent, ProcessSignal.sigstop), containsAll([101, 102]));
        expect(_pids(sent, ProcessSignal.sighup), {100, 101, 102});
        expect(_pids(sent, ProcessSignal.sigcont), {100, 101, 102});
        expect(_pids(sent, ProcessSignal.sigkill), {100, 101, 102});
        expect(sent.map((s) => s.$1), isNot(contains(200)));
        expect(sent.map((s) => s.$1), isNot(contains(1)));
        final shellHangUp = _first(sent, 100, ProcessSignal.sighup);
        expect(
          sent.take(shellHangUp).map((s) => s.$1),
          isNot(contains(100)),
          reason: 'the shell keeps running until it is hung up',
        );
        for (final pid in [101, 102]) {
          expect(
            _first(sent, pid, ProcessSignal.sigstop),
            lessThan(shellHangUp),
            reason: '$pid is frozen before the shell is hung up',
          );
        }
        for (final pid in [100, 101, 102]) {
          expect(
            _first(sent, pid, ProcessSignal.sighup),
            lessThan(_first(sent, pid, ProcessSignal.sigcont)),
            reason: '$pid gets SIGHUP while still stopped',
          );
        }
        expect(
          _last(sent, ProcessSignal.sigcont),
          lessThan(_first(sent, 100, ProcessSignal.sigkill)),
        );
      },
    );

    test(
      'kills a child forked by a HUP-ignoring survivor after the root died',
      () async {
        final sent = <(int, ProcessSignal)>[];
        final table = _FakeTable([
          [_p(100, 1), _p(101, 100), _p(200, 1)],
          [_p(100, 1), _p(101, 100), _p(200, 1)],
          // The shell died at once; 101 ignored SIGHUP, was re-parented to
          // launchd and then forked 102.
          [_p(101, 1), _p(200, 1)],
          [_p(101, 1), _p(102, 101), _p(200, 1)],
        ]);

        await _killer(table, sent).killTree(100);

        expect(_pids(sent, ProcessSignal.sigkill), {101, 102});
        expect(sent.map((s) => s.$1), isNot(contains(200)));
      },
    );

    test(
      'remembers children forked during the grace even if their parent exits',
      () async {
        final sent = <(int, ProcessSignal)>[];
        final table = _FakeTable([
          [_p(100, 1), _p(101, 100)],
          [_p(100, 1), _p(101, 100)],
          // During the grace: 101 forks 102, then exits; 102 is re-parented.
          [_p(101, 1), _p(102, 101)],
          [_p(102, 1)],
        ]);

        await _killer(
          table,
          sent,
          grace: const Duration(milliseconds: 100),
        ).killTree(100);

        expect(_pids(sent, ProcessSignal.sigkill), {102});
      },
    );

    test('returns early once every victim is gone', () async {
      final sent = <(int, ProcessSignal)>[];
      final table = _FakeTable([
        [_p(100, 1), _p(101, 100)],
        [_p(100, 1), _p(101, 100)],
        [_p(300, 1)],
      ]);

      await _killer(
        table,
        sent,
        grace: const Duration(seconds: 30),
      ).killTree(100).timeout(const Duration(seconds: 5));

      expect(_pids(sent, ProcessSignal.sigkill), isEmpty);
    });

    test(
      'a failing ps still hangs up and kills the root, then throws',
      () async {
        final sent = <(int, ProcessSignal)>[];
        await expectLater(
          _killer(_FailingTable(), sent).killTree(100),
          throwsA(isA<ProcessTableException>()),
        );
        expect(sent.first, (100, ProcessSignal.sighup));
        expect(sent.map((s) => s.$1).toSet(), {100});
        expect(
          _first(sent, 100, ProcessSignal.sighup),
          lessThan(_first(sent, 100, ProcessSignal.sigcont)),
        );
        expect(
          _first(sent, 100, ProcessSignal.sigcont),
          lessThan(_first(sent, 100, ProcessSignal.sigkill)),
        );
      },
    );

    test('stops freezing after a bounded number of rounds', () async {
      final sent = <(int, ProcessSignal)>[];
      await _killer(_GrowingTable(), sent).killTree(100);
      expect(_pids(sent, ProcessSignal.sigkill), containsAll([100, 101, 102]));
    });

    test('never signals itself, launchd or pid 0', () async {
      final sent = <(int, ProcessSignal)>[];
      final killer = _killer(
        _FakeTable([
          [_p(50, 1), _p(4242, 50), _p(1, 50), _p(0, 50)],
        ]),
        sent,
      );
      await killer.killTree(50);
      expect(sent.map((s) => s.$1).toSet(), {50});
      sent.clear();
      await killer.killTree(4242);
      await killer.killTree(1);
      await killer.killTree(0);
      expect(sent, isEmpty);
    });
  });
}
