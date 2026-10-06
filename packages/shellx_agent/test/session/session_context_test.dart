import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

import '../support/session_rig.dart';

const _esc = '\x1b';
const _bel = '\x07';
String _osc7(String path, {String host = ''}) =>
    '$_esc]7;file://$host$path$_bel';

/// Answers each lookup when the test completes its completer.
final class _Lookup implements GitBranchLookup {
  final calls = <(String, bool)>[];
  final answers = <Completer<String?>>[];

  @override
  Future<String?> branchFor(String directory, {bool refresh = false}) {
    calls.add((directory, refresh));
    final answer = Completer<String?>();
    answers.add(answer);
    return answer.future;
  }
}

final class _Probe implements PortProbe {
  int calls = 0;
  @override
  Future<Map<int, Set<int>>> listening() async {
    calls++;
    return {
      300: {5173, 3000},
    };
  }

  @override
  Future<Map<int, int>> parents() async => {300: 100};
}

void main() {
  test('OSC 7 sets the summary cwd (decoded) and fires changes', () async {
    final rig = SessionRig();
    await rig.manager.open(cols: 80, rows: 24);
    var changes = 0;
    rig.manager.changes.listen((_) => changes++);
    rig.pty(0).emit(_osc7('/Users/test/T%C3%A0i%20li%E1%BB%87u'));
    await pumpEventQueue();
    expect(rig.manager.sessions.single.cwd, '/Users/test/Tài liệu');
    expect(changes, greaterThan(0));
  });

  test('a malformed OSC 7 keeps the cwd; another host clears cwd and '
      'branch (D2)', () async {
    final lookup = _Lookup();
    final rig = SessionRig(gitHeads: lookup);
    await rig.manager.open(cols: 80, rows: 24);
    rig.pty(0).emit(_osc7('/r'));
    await pumpEventQueue(); // the pty stream delivers asynchronously
    lookup.answers.last.complete('main');
    await pumpEventQueue();
    expect(rig.manager.sessions.single.gitBranch, 'main');
    rig.pty(0).emit('$_esc]7;file:///bad%zz$_bel');
    await pumpEventQueue();
    expect(rig.manager.sessions.single.cwd, '/r');
    rig.pty(0).emit(_osc7('/home/r', host: 'build-server'));
    await pumpEventQueue();
    final summary = rig.manager.sessions.single;
    expect((summary.cwd, summary.gitBranch), (null, null));
  });

  test(
    'a late answer for an older directory is dropped (Review Focus 2)',
    () async {
      final lookup = _Lookup();
      final rig = SessionRig(gitHeads: lookup);
      await rig.manager.open(cols: 80, rows: 24);
      rig.pty(0).emit(_osc7('/a'));
      rig.pty(0).emit(_osc7('/b'));
      await pumpEventQueue();
      expect(lookup.calls, [('/a', false), ('/b', false)]);
      lookup.answers[1].complete('b-branch');
      await pumpEventQueue();
      lookup.answers[0].complete('a-branch');
      await pumpEventQueue();
      expect(rig.manager.sessions.single.gitBranch, 'b-branch');
    },
  );

  test('OSC 133;D looks the branch up again with refresh', () async {
    final lookup = _Lookup();
    final rig = SessionRig(gitHeads: lookup);
    await rig.manager.open(cols: 80, rows: 24);
    rig.pty(0).emit(_osc7('/r'));
    rig.pty(0).emit('$_esc]133;C$_bel$_esc]133;D;0$_bel');
    await pumpEventQueue();
    expect(lookup.calls.last, ('/r', true));
  });

  test(
    'a real repository: the branch appears, and follows git switch',
    () async {
      final temp = Directory.systemTemp.createTempSync('shellx-ctx-');
      addTearDown(() => temp.deleteSync(recursive: true));
      Directory('${temp.path}/.git').createSync();
      final head = File('${temp.path}/.git/HEAD')
        ..writeAsStringSync('ref: refs/heads/main\n');
      final rig = SessionRig(gitHeads: GitHeadReader());
      await rig.manager.open(cols: 80, rows: 24);

      Future<void> until(String branch) async {
        for (var i = 0; i < 200; i++) {
          if (rig.manager.sessions.single.gitBranch == branch) return;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        fail('branch never became $branch');
      }

      rig.pty(0).emit(_osc7(Uri.directory(temp.path).path));
      await until('main');
      head.writeAsStringSync('ref: refs/heads/dev\n');
      rig.pty(0).emit('$_esc]133;C$_bel$_esc]133;D;0$_bel');
      await until('dev');
    },
    testOn: 'mac-os || linux',
  );

  test('watchPorts: ports of the shell tree reach the summary; hidden = no '
      'probe call (spec criterion 4)', () {
    fakeAsync((async) {
      final probe = _Probe();
      final rig = SessionRig(portProbe: probe);
      rig.manager.open(cols: 80, rows: 24);
      async.flushMicrotasks();
      rig.pty(0).processId = 100;
      async.elapse(const Duration(seconds: 10));
      expect(probe.calls, 0);
      rig.manager.watchPorts(true);
      async.elapse(Duration.zero);
      expect(rig.manager.sessions.single.ports, [3000, 5173]);
      rig.manager.watchPorts(false);
      final calls = probe.calls;
      async.elapse(const Duration(seconds: 30));
      expect(probe.calls, calls);
    });
  });

  test('watchPorts: a shell pid known only after the watcher started is '
      'picked up (Task 4 review)', () {
    fakeAsync((async) {
      final probe = _Probe();
      final rig = SessionRig(portProbe: probe);
      rig.manager.open(cols: 80, rows: 24);
      async.flushMicrotasks();
      rig.manager.watchPorts(true);
      async.elapse(Duration.zero);
      expect(probe.calls, 0); // no pid: nothing to scan
      rig.pty(0).processId = 100;
      rig.pty(0).emit('\$ ');
      async.elapse(Duration.zero);
      expect(rig.manager.sessions.single.ports, [3000, 5173]);
    });
  });

  test('watchPorts: an exited shell (pid may be reused) loses its ports at '
      'once, before its session is gone (Task 4 review)', () {
    fakeAsync((async) {
      final probe = _Probe();
      final rig = SessionRig(portProbe: probe);
      rig.manager.open(cols: 80, rows: 24);
      async.flushMicrotasks();
      rig.pty(0).processId = 100;
      rig.manager.watchPorts(true);
      async.elapse(Duration.zero);
      expect(rig.manager.sessions.single.ports, [3000, 5173]);
      // The output stream stays open: the session is listed for up to the
      // 2 s drain grace, with the dead shell's pid still set.
      rig.pty(0).exit(0, closeOutput: false);
      async.elapse(const Duration(milliseconds: 500));
      expect(rig.manager.sessions.single.ports, isEmpty);
    });
  });

  test('sessionInfos is unchanged (A1); sessionInfosWithContext adds cwd '
      'and branch', () async {
    final lookup = _Lookup();
    final rig = SessionRig(gitHeads: lookup);
    await rig.manager.open(cols: 80, rows: 24);
    rig.pty(0).emit(_osc7('/w'));
    await pumpEventQueue(); // the pty stream delivers asynchronously
    lookup.answers.last.complete('main');
    await pumpEventQueue();
    expect(rig.manager.sessionInfos.single.toMap().containsKey('cwd'), isFalse);
    final rich = rig.manager.sessionInfosWithContext.single;
    expect((rich.cwd, rich.branch), ('/w', 'main'));
  });
}
