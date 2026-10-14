// The process table the agent's stop reads (V2-1 final review: an agent that
// leaves leaves its children): the rows of `ps` and of the Windows script,
// the descendants of a pid, and whether a row is still the same process.
import 'dart:io';

import 'package:shellx_ai/host.dart';
import 'package:test/test.dart';

void main() {
  final t0 = DateTime.utc(2026, 10, 14, 9);
  ProcessRow row(
    int pid,
    int parent, {
    String command = '/bin/sh',
    DateTime? at,
  }) => ProcessRow(
    pid: pid,
    parentPid: parent,
    command: command,
    startedAt: at ?? t0,
  );

  group('parsePsRows', () {
    // `ps -A -o pid=,ppid=,etime=,comm=` on macOS.
    const captured = '''
    1     0 01-12:53:30 /sbin/launchd
   70     1 01-12:53:27 /usr/libexec/logd
 4242   501       00:05 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome Helper (Renderer)
 4300  4242    05:09:08 -zsh
 9001  4242  2-03:04:05 /usr/bin/sleep
''';

    test('pid, parent, program and start, with the program\'s spaces', () {
      final now = DateTime.utc(2026, 10, 14, 12);
      final rows = parsePsRows(captured, now: now);
      expect(rows.map((r) => r.pid), [1, 70, 4242, 4300, 9001]);
      expect(rows.map((r) => r.parentPid), [0, 1, 501, 4242, 4242]);
      expect(
        rows[2].command,
        '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome Helper (Renderer)',
      );
      expect(rows[2].startedAt, now.subtract(const Duration(seconds: 5)));
      expect(
        rows[3].startedAt,
        now.subtract(const Duration(hours: 5, minutes: 9, seconds: 8)),
      );
      expect(
        rows[4].startedAt,
        now.subtract(const Duration(days: 2, hours: 3, minutes: 4, seconds: 5)),
      );
    });

    test('what is no row is skipped', () {
      final rows = parsePsRows('''

  garbage
  12 x 00:05 /bin/sh
  13 1 never /bin/sh
  14 1 00:05
  15 1 00:09 /bin/ok
''', now: t0);
      expect(rows.map((r) => r.pid), [15]);
      expect(parsePsRows('', now: t0), isEmpty);
    });

    test('a row shows nothing in toString (a program path names the user)', () {
      expect(row(1, 0, command: '/Users/ann/secret/tool').toString(), '…');
    });
  });

  group('parseCimRows', () {
    // The Windows script's lines: pid|parent|created (UTC, ISO 8601)|path.
    const captured = r'''
4|0|2026-10-14T05:00:00.1234567Z|
4242|1234|2026-10-14T09:12:03.1234567Z|C:\Program Files\nodejs\node.exe
5000|4242|2026-10-14T09:12:04Z|C:\Users\Ann\AppData\Local\Programs\Tool\tool.exe
''';

    test('pid, parent, program and start', () {
      final rows = parseCimRows(captured);
      expect(rows.map((r) => (r.pid, r.parentPid)), [
        (4, 0),
        (4242, 1234),
        (5000, 4242),
      ]);
      expect(rows[0].command, '');
      expect(rows[1].command, r'C:\Program Files\nodejs\node.exe');
      expect(rows[1].startedAt.isUtc, isTrue);
      expect(
        rows[1].startedAt.difference(DateTime.utc(2026, 10, 14, 9, 12, 3)),
        const Duration(microseconds: 123456),
        reason: 'seven digits of seconds, read to the microsecond',
      );
      expect(rows[2].startedAt, DateTime.utc(2026, 10, 14, 9, 12, 4));
    });

    test('what is no row is skipped, CRLF is no trouble', () {
      final rows = parseCimRows(
        'junk\r\n7|x|2026-10-14T09:00:00Z|a.exe\r\n8|1|not a time|a.exe\r\n'
        '9|1|2026-10-14T09:00:00Z|C:\\ok.exe\r\n10|1\r\n\r\n',
      );
      expect(rows.map((r) => r.pid), [9]);
      expect(rows.single.command, r'C:\ok.exe');
    });
  });

  group('descendantsIn', () {
    test('children, grandchildren, not the root, parents first', () {
      final rows = [
        row(10, 1),
        row(11, 10),
        row(12, 11),
        row(13, 10),
        row(14, 13),
        row(20, 1), // another tree
        row(21, 20),
      ];
      expect(descendantsIn(10, rows).map((r) => r.pid), [11, 13, 12, 14]);
      expect(descendantsIn(12, rows), isEmpty);
      expect(descendantsIn(99, rows), isEmpty, reason: 'not in the table');
    });

    test(
      'pid 0 and 1 are no roots; a row that is its own parent is no child',
      () {
        final rows = [row(1, 0), row(2, 1), row(0, 0), row(5, 5)];
        expect(descendantsIn(1, rows), isEmpty);
        expect(descendantsIn(0, rows), isEmpty);
        expect(descendantsIn(5, rows), isEmpty);
      },
    );

    test('a loop in the table ends', () {
      final rows = [row(10, 12), row(11, 10), row(12, 11)];
      expect(
        descendantsIn(10, rows).map((r) => r.pid),
        unorderedEquals([11, 12]),
      );
    });

    test('a child that began before the parent it names is no child (the '
        'parent pid was reused)', () {
      final rows = [
        row(10, 1, at: t0),
        row(11, 10, at: t0.add(const Duration(seconds: 5))),
        // Began an hour before pid 10 did: its parent was an earlier 10.
        row(12, 10, at: t0.subtract(const Duration(hours: 1))),
        row(13, 12, at: t0.subtract(const Duration(hours: 1))),
        // The ages are whole seconds: a second either way is the same time.
        row(14, 10, at: t0.subtract(const Duration(seconds: 1))),
      ];
      expect(descendantsIn(10, rows).map((r) => r.pid), [11, 14]);
    });
  });

  group('descendantsIn never lists a pid it is told to bar', () {
    test('a barred pid is neither listed nor walked through', () {
      final rows = [
        row(10, 1),
        row(11, 10),
        row(99, 10), // barred, "a child of 10"
        row(98, 99), // only under the barred pid
        row(97, 98),
        row(12, 11),
      ];
      expect(descendantsIn(10, rows, never: {99}).map((r) => r.pid), [11, 12]);
      expect(
        descendantsIn(10, rows).map((r) => r.pid),
        [11, 99, 12, 98, 97],
        reason: 'without the bar, all of it',
      );
    });

    test('a barred root has no descendants', () {
      final rows = [row(10, 1), row(11, 10)];
      expect(descendantsIn(10, rows, never: {10}), isEmpty);
    });

    test('pid 0 and 1 are never listed or walked through, bar or not', () {
      final rows = [
        row(10, 1),
        row(1, 10), // init, "a child of 10"
        row(0, 10),
        row(20, 1), // under init
        row(21, 0),
        row(11, 10),
      ];
      expect(descendantsIn(10, rows).map((r) => r.pid), [11]);
    });
  });

  group('ancestorsIn', () {
    test('the parent, its parent… up to but not pid 1', () {
      final rows = [row(1, 0), row(2, 1), row(3, 2), row(4, 3), row(5, 4)];
      expect(ancestorsIn(5, rows), [4, 3, 2]);
      expect(ancestorsIn(3, rows), [2]);
      expect(ancestorsIn(2, rows), isEmpty, reason: 'its parent is init');
    });

    test(
      'as far as the table has links: a parent without a row is the end',
      () {
        final rows = [row(5, 4), row(4, 3)]; // 3 has no row of its own
        expect(ancestorsIn(5, rows), [4, 3]);
        expect(ancestorsIn(9, rows), isEmpty, reason: 'not in the table');
      },
    );

    test('a loop ends, and a pid is listed once', () {
      final rows = [row(5, 4), row(4, 3), row(3, 5)];
      expect(ancestorsIn(5, rows), [4, 3]);
      expect(ancestorsIn(5, [row(5, 5)]), isEmpty);
    });
  });

  group('isSameProcess', () {
    test(
      'the pid, the program (by name) and the start (within a few seconds)',
      () {
        final then = row(7, 1, command: '/opt/homebrew/bin/node');
        bool same(ProcessRow now) => isSameProcess(then, now);
        expect(same(row(7, 1, command: '/usr/local/bin/NODE')), isTrue);
        expect(
          same(row(7, 99, command: '/usr/local/bin/node')),
          isTrue,
          reason: 'a parent may change',
        );
        expect(
          same(
            row(7, 1, command: 'node', at: t0.add(const Duration(seconds: 4))),
          ),
          isTrue,
        );
        expect(
          same(row(8, 1, command: 'node')),
          isFalse,
          reason: 'another pid',
        );
        expect(
          same(row(7, 1, command: '/bin/sleep')),
          isFalse,
          reason: 'another program',
        );
        expect(
          same(
            row(7, 1, command: 'node', at: t0.add(const Duration(seconds: 6))),
          ),
          isFalse,
          reason: 'the pid was reused later',
        );
        expect(
          isSameProcess(
            then,
            row(7, 1, command: 'node', at: t0.add(const Duration(seconds: 6))),
            tolerance: const Duration(minutes: 1),
          ),
          isTrue,
        );
      },
    );
  });

  group('firstTableReadLimit', () {
    test('Windows starts a PowerShell for the table: a stop waits for it only '
        'a little; elsewhere the reader\'s own limit is all there is', () {
      expect(
        firstTableReadLimit(isWindows: true),
        const Duration(milliseconds: 1500),
      );
      expect(firstTableReadLimit(isWindows: false), isNull);
      expect(firstTableReadLimit(), Platform.isWindows ? isNotNull : isNull);
    });
  });

  group('SharedProcessTable', () {
    /// A reader that answers [answer] after [delay], and counts its calls.
    ({ProcessTableReader read, List<Duration?> limits}) reader(
      List<ProcessRow>? Function(int call) answer, {
      Duration delay = const Duration(milliseconds: 50),
    }) {
      final limits = <Duration?>[];
      return (
        limits: limits,
        read: ({Duration? limit}) async {
          final call = limits.length;
          limits.add(limit);
          await Future<void>.delayed(delay);
          return answer(call);
        },
      );
    }

    test('whoever asks while a read is under way gets that read', () async {
      final r = reader((call) => [row(call + 1, 1)]);
      final table = SharedProcessTable(r.read);
      final all = await Future.wait([table(), table(), table()]);
      expect(r.limits, hasLength(1));
      expect(all.map((rows) => rows!.single.pid), [1, 1, 1]);
    });

    test('one asked for after it ended is a new read', () async {
      final r = reader((call) => [row(call + 1, 1)]);
      final table = SharedProcessTable(r.read);
      expect((await table())!.single.pid, 1);
      expect((await table())!.single.pid, 2);
      expect(r.limits, hasLength(2));
    });

    test('the read is made with the limit of the one who started it', () async {
      final r = reader((call) => const []);
      final table = SharedProcessTable(r.read);
      await Future.wait([
        table(limit: const Duration(seconds: 1)),
        table(limit: const Duration(seconds: 9)),
      ]);
      expect(r.limits, [const Duration(seconds: 1)]);
      await table();
      expect(r.limits.last, isNull);
    });

    test(
      'a read that fails fails them all, and the next one is made',
      () async {
        var calls = 0;
        final table = SharedProcessTable(({limit}) async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          if (calls == 1) throw StateError('ps broke');
          return <ProcessRow>[];
        });
        final first = [table(), table()];
        for (final f in first) {
          await expectLater(f, throwsA(isA<StateError>()));
        }
        expect(await table(), isEmpty);
        expect(calls, 2);
      },
    );

    test('a read that cannot be had (null) is shared as it is', () async {
      final r = reader((call) => null);
      final table = SharedProcessTable(r.read);
      expect(await Future.wait([table(), table()]), [null, null]);
      expect(r.limits, hasLength(1));
    });
  });

  test(
    'readProcessTable sees this process and the child it just started',
    () async {
      final child = await Process.start('/bin/sleep', ['30']);
      try {
        final rows = (await readProcessTable())!;
        final kid = rows.firstWhere((r) => r.pid == child.pid);
        expect(
          kid.parentPid,
          pid,
          reason: 'a child is a child of this process',
        );
        expect(sameProgram(kid.command, 'sleep'), isTrue);
        expect(
          kid.startedAt.difference(DateTime.now().toUtc()).abs(),
          lessThan(const Duration(seconds: 10)),
        );
        expect(descendantsIn(pid, rows).map((r) => r.pid), contains(child.pid));
        expect(
          (await readProcessTable())!.any((r) => r.pid == pid),
          isTrue,
          reason: 'this process is in the table too',
        );
      } finally {
        child.kill(ProcessSignal.sigkill);
        await child.exitCode;
      }
    },
    skip: Platform.isWindows,
  );
}
