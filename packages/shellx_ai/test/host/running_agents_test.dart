import 'dart:io';

import 'package:shellx_ai/host.dart';
import 'package:test/test.dart';

import '../support/scripts.dart';

void main() {
  late Directory tmp;
  late File file;
  final spawned = <Process>[];
  final t0 = DateTime.utc(2026, 10, 14, 9);
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('running');
    file = File('${tmp.path}/ai/running.json');
  });
  tearDown(() async {
    // A test that failed midway must not leave its process behind.
    for (final p in spawned) {
      p.kill(ProcessSignal.sigkill);
      await p.exitCode.timeout(const Duration(seconds: 10));
    }
    spawned.clear();
    tmp.deleteSync(recursive: true);
  });

  test('add and remove persist; concurrent adds keep every record', () async {
    final r = RunningAgents(file);
    await Future.wait([
      for (var i = 1; i <= 10; i++)
        r.add(RunningRecord(pid: i, command: '/usr/bin/node', startedAt: t0)),
    ]);
    await r.remove(3);
    expect(
      RunningAgents(file).read().map((e) => e.pid),
      unorderedEquals([1, 2, 4, 5, 6, 7, 8, 9, 10]),
    );
  });

  test('sweep kills only matching leftovers, then clears the file', () async {
    final killed = <int>[];
    final now = {
      1: (
        command: '/opt/homebrew/bin/node',
        startedAt: t0.add(const Duration(seconds: 1)),
      ),
      2: (command: '/usr/bin/python3', startedAt: t0),
      3: (command: 'node', startedAt: t0.add(const Duration(hours: 1))),
      5: (command: r'C:\Program Files\nodejs\NODE.EXE', startedAt: t0),
    };
    final r = RunningAgents(
      file,
      isWindows: false, // the tree killer is what is asked about
      info: (pid) async => now[pid],
      killPid: (pid) async => killed.add(pid),
    );
    for (final (pid, cmd) in [
      (1, '/usr/local/bin/node'),
      (2, '/usr/local/bin/node'),
      (3, 'node'),
      (4, 'node'),
      (5, r'C:\nodejs\node.exe'),
    ]) {
      await r.add(RunningRecord(pid: pid, command: cmd, startedAt: t0));
    }
    expect(await r.sweep(), 2);
    expect(killed, [1, 5], reason: '2: other program; 3: pid reused; 4: gone');
    expect(r.read(), isEmpty);
  });

  test('a corrupt file is treated as empty', () async {
    file
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('{not json');
    final r = RunningAgents(
      file,
      info: (_) async => fail('nothing to look up'),
    );
    expect(await r.sweep(), 0);
    expect(r.read(), isEmpty);
  });

  test('parseEtime', () {
    expect(parseEtime('05:03'), const Duration(minutes: 5, seconds: 3));
    expect(
      parseEtime(' 1:02:03'),
      const Duration(hours: 1, minutes: 2, seconds: 3),
    );
    expect(parseEtime('2-01:00:00'), const Duration(days: 2, hours: 1));
    expect(parseEtime('soon'), isNull);
  });

  // A real process, both ways of stopping a leftover: the fallback killer
  // (`killProcessByPid`; taskkill /T on Windows) and the way of Windows, a pid
  // at a time from one read of the process table (run here as well).
  for (final windows in [false, true]) {
    test(
      'lookupProcess and the sweep on a real process '
      '(${windows ? 'a pid at a time, as on Windows' : 'killProcessByPid'})',
      () async {
        final proc = await Process.start(
          Platform.resolvedExecutable,
          dartScript(tmp, 'ready', readyThenIgnoreStdin),
        );
        spawned.add(proc);
        final started = DateTime.now();
        // The VM has the final name (macOS: `dart` becomes `dartvm`) once the
        // script runs; a lookup before that, then a sweep after, would not
        // match.
        await proc.stdout.first.timeout(const Duration(seconds: 10));
        final info = await lookupProcess(proc.pid);
        expect(info, isNotNull);
        final name = info!.command
            .replaceAll(r'\', '/')
            .split('/')
            .last
            .toLowerCase();
        expect(name, anyOf('dart', 'dart.exe', 'dartvm', 'dartvm.exe'));
        expect(
          info.startedAt.difference(started).abs(),
          lessThan(const Duration(seconds: 30)),
        );

        final r = RunningAgents(file, isWindows: windows);
        await r.add(
          RunningRecord(
            pid: proc.pid,
            command: info.command,
            startedAt: started,
          ),
        );
        expect(await r.sweep(), 1);
        await proc.exitCode.timeout(const Duration(seconds: 10));
      },
    );
  }
}
