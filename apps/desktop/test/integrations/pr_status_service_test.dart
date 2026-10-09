import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/integrations/pr_status.dart';
import 'package:shellx_desktop/src/integrations/pr_status_parse.dart';

final t0 = DateTime.utc(2026, 10, 8, 9);

String okJson({int number = 12}) => jsonEncode({
  'number': number,
  'state': 'OPEN',
  'isDraft': false,
  'url': 'https://github.com/o/r/pull/$number',
  'reviewDecision': '',
  'statusCheckRollup': [
    {'status': 'COMPLETED', 'conclusion': 'SUCCESS'},
  ],
});

/// A runner that answers at once with [answer], counting calls and the
/// calls running at the same moment.
final class FakeRunner implements GhRunner {
  GhResult Function(String cwd) answer = (_) => GhResult(0, okJson(), '');
  Completer<void>? gate;
  final calls = <({String exe, List<String> args, String cwd, Duration t})>[];
  final times = <DateTime>[];
  DateTime Function()? clock;
  int running = 0, maxRunning = 0;

  @override
  Future<GhResult> run(
    String exe,
    List<String> args, {
    required String cwd,
    required Duration timeout,
  }) async {
    calls.add((exe: exe, args: args, cwd: cwd, t: timeout));
    if (clock != null) times.add(clock!());
    running++;
    if (running > maxRunning) maxRunning = running;
    try {
      if (gate != null) await gate!.future;
      return answer(cwd);
    } finally {
      running--;
    }
  }
}

void main() {
  late FakeRunner runner;
  late int changes;

  PrStatusService make(
    FakeAsync fa, {
    String? gh = '/bin/gh',
    String? Function(String dir)? root,
  }) {
    final now = fa.getClock(t0).now;
    runner.clock = now;
    return PrStatusService(
      runner: runner,
      now: now,
      findGh: () async => gh,
      findRoot: (dir) async => (root ?? (d) => '/repo')(dir),
      onChange: () => changes++,
    );
  }

  setUp(() {
    runner = FakeRunner();
    changes = 0;
  });

  test('nothing is looked up before someone wants it', () {
    fakeAsync((fa) {
      final s = make(fa);
      fa.elapse(const Duration(minutes: 30));
      expect(runner.calls, isEmpty);
      expect(s.peek('/repo/sub', 'main'), isNull);
      s.dispose();
    });
  });

  test('a want runs one lookup with the fixed arguments in the repo root', () {
    fakeAsync((fa) {
      final s = make(fa);
      s.want('/repo/sub', 'feature/x');
      fa.flushMicrotasks();
      expect(runner.calls, hasLength(1));
      final c = runner.calls.single;
      expect(c.exe, '/bin/gh');
      expect(c.args, [
        'pr',
        'view',
        '--json',
        'number,state,isDraft,url,reviewDecision,statusCheckRollup,headRefName',
      ]);
      expect(c.cwd, '/repo');
      expect(c.t, const Duration(seconds: 8));
      // No user text anywhere in the argument vector.
      expect(c.args.join(' '), isNot(contains('feature')));
      expect(s.peek('/repo/sub', 'feature/x')!.number, 12);
      expect(changes, greaterThan(0));
      // Another branch is another key.
      expect(s.peek('/repo/sub', 'other'), isNull);
      s.dispose();
    });
  });

  test('a result for another branch is discarded (the checkout moved)', () {
    fakeAsync((fa) {
      runner.answer = (_) => GhResult(
        0,
        jsonEncode({...jsonDecode(okJson()) as Map, 'headRefName': 'y'}),
        '',
      );
      final s = make(fa);
      s.want('/repo', 'x');
      fa.flushMicrotasks();
      expect(runner.calls, hasLength(1));
      expect(s.peek('/repo', 'x'), isNull);
      s.want('/repo', 'y');
      fa.flushMicrotasks();
      expect(s.peek('/repo', 'y')!.number, 12);
      s.dispose();
    });
  });

  test('never two lookups at once', () {
    fakeAsync((fa) {
      runner.gate = Completer<void>();
      final s = make(fa);
      for (var i = 0; i < 5; i++) {
        s.want('/repo', 'b$i');
      }
      fa.flushMicrotasks();
      expect(runner.calls, hasLength(1));
      runner.gate!.complete();
      fa.flushMicrotasks();
      expect(runner.maxRunning, 1);
      s.dispose();
    });
  });

  test('at most 6 lookups a minute however many tabs ask', () {
    fakeAsync((fa) {
      final s = make(fa);
      for (var i = 0; i < 20; i++) {
        s.want('/repo', 'branch$i');
      }
      fa.flushMicrotasks();
      fa.elapse(const Duration(seconds: 59));
      expect(runner.calls.length, 6);
      fa.elapse(const Duration(seconds: 2));
      expect(runner.calls.length, inInclusiveRange(7, 12));
      // Any sliding 60 s window holds at most 6.
      fa.elapse(const Duration(minutes: 5));
      final times = runner.times;
      for (var i = 0; i + 6 < times.length; i++) {
        expect(
          times[i + 6].difference(times[i]),
          greaterThanOrEqualTo(const Duration(seconds: 60)),
        );
      }
      s.dispose();
    });
  });

  test('a success is refreshed after 120 s, not before', () {
    fakeAsync((fa) {
      final s = make(fa);
      s.want('/repo', 'main');
      fa.flushMicrotasks();
      fa.elapse(const Duration(seconds: 100));
      s.want('/repo', 'main'); // asking again changes nothing
      fa.elapse(const Duration(seconds: 19));
      expect(runner.calls, hasLength(1));
      fa.elapse(const Duration(seconds: 3));
      expect(runner.calls, hasLength(2));
      s.dispose();
    });
  });

  test('"no pull requests found" is remembered for 10 minutes', () {
    fakeAsync((fa) {
      runner.answer = (_) =>
          GhResult(1, '', 'no pull requests found for branch "x"');
      final s = make(fa);
      s.want('/repo', 'x');
      fa.flushMicrotasks();
      expect(s.peek('/repo', 'x'), isNull);
      for (var i = 0; i < 9; i++) {
        fa.elapse(const Duration(minutes: 1));
        s.want('/repo', 'x');
      }
      expect(runner.calls, hasLength(1));
      fa.elapse(const Duration(minutes: 1, seconds: 5));
      s.want('/repo', 'x');
      fa.flushMicrotasks();
      expect(runner.calls, hasLength(2));
      s.dispose();
    });
  });

  test('other failures back off 5, 10, 20, 30, 30 minutes', () {
    fakeAsync((fa) {
      runner.answer = (_) => GhResult(1, '', 'not logged in');
      final s = make(fa);
      final start = fa.getClock(t0).now();
      // The user keeps looking at the tab: it asks every 10 s.
      for (var n = 0; n < 6 * 150; n++) {
        s.want('/repo', 'x');
        fa.elapse(const Duration(seconds: 10));
      }
      final gaps = [
        for (var i = 1; i < runner.times.length; i++)
          runner.times[i].difference(runner.times[i - 1]).inMinutes,
      ];
      expect(runner.times.first.difference(start), Duration.zero);
      expect(gaps.take(5), [5, 10, 20, 30, 30]);
      s.dispose();
    });
  });

  test('a timeout is a failure: nothing shown, back off', () {
    fakeAsync((fa) {
      runner.answer = (_) => const GhResult.timedOut();
      final s = make(fa);
      s.want('/repo', 'x');
      fa.flushMicrotasks();
      expect(s.peek('/repo', 'x'), isNull);
      for (var i = 0; i < 4; i++) {
        fa.elapse(const Duration(minutes: 1));
        s.want('/repo', 'x');
      }
      expect(runner.calls, hasLength(1));
      fa.elapse(const Duration(minutes: 2));
      s.want('/repo', 'x');
      fa.flushMicrotasks();
      expect(runner.calls, hasLength(2));
      s.dispose();
    });
  });

  test('an answer that does not parse is a failure too', () {
    fakeAsync((fa) {
      runner.answer = (_) => GhResult(0, '{"number": "oops"}', '');
      final s = make(fa);
      s.want('/repo', 'x');
      fa.flushMicrotasks();
      expect(s.peek('/repo', 'x'), isNull);
      fa.elapse(const Duration(minutes: 3));
      s.want('/repo', 'x');
      fa.flushMicrotasks();
      expect(runner.calls, hasLength(1));
      s.dispose();
    });
  });

  test('no gh: the runner is never called', () {
    fakeAsync((fa) {
      final s = make(fa, gh: null);
      for (var i = 0; i < 10; i++) {
        s.want('/repo', 'b$i');
        fa.elapse(const Duration(minutes: 1));
      }
      expect(runner.calls, isEmpty);
      expect(s.ghMissing, isTrue);
      s.dispose();
    });
  });

  test('not in a git repository: the runner is never called', () {
    fakeAsync((fa) {
      final s = make(fa, root: (_) => null);
      s.want('/nowhere', 'main');
      fa.elapse(const Duration(minutes: 1));
      expect(runner.calls, isEmpty);
      s.dispose();
    });
  });

  test('the same repository from two folders is one lookup', () {
    fakeAsync((fa) {
      final s = make(fa);
      s.want('/repo/a', 'main');
      s.want('/repo/b', 'main');
      fa.flushMicrotasks();
      expect(runner.calls, hasLength(1));
      expect(s.peek('/repo/b', 'main'), isNotNull);
      s.dispose();
    });
  });

  test('dispose stops everything', () {
    fakeAsync((fa) {
      final s = make(fa);
      s.want('/repo', 'main');
      fa.flushMicrotasks();
      s.dispose();
      fa.elapse(const Duration(hours: 1));
      expect(runner.calls, hasLength(1));
      expect(fa.nonPeriodicTimerCount, 0);
    });
  });

  test('a looks-at-nothing branch or folder is not asked about', () {
    fakeAsync((fa) {
      final s = make(fa);
      s.want('', 'main');
      s.want('/repo', '');
      fa.flushMicrotasks();
      expect(runner.calls, isEmpty);
      s.dispose();
    });
  });

  group('what the app may ask for', () {
    test('only a local pane with a folder and a branch', () {
      expect(prTargetOf(remote: false, cwd: '/r', branch: 'main'), (
        '/r',
        'main',
      ));
      expect(prTargetOf(remote: true, cwd: '/r', branch: 'main'), isNull);
      expect(prTargetOf(remote: false, cwd: null, branch: 'main'), isNull);
      expect(prTargetOf(remote: false, cwd: '/r', branch: null), isNull);
      expect(prTargetOf(remote: false, cwd: '', branch: 'main'), isNull);
    });

    test('the environment adds three switches and no token', () {
      final env = ghEnvironment();
      expect(env.keys.toSet(), {
        'GH_PROMPT_DISABLED',
        'GH_NO_UPDATE_NOTIFIER',
        'NO_COLOR',
      });
      for (final k in env.keys) {
        expect(k.toUpperCase(), isNot(contains('TOKEN')));
      }
    });
  });

  test('privacy: nothing about a PR reaches the log', () {
    final lines = <String>[];
    final old = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) => lines.add(m ?? '');
    addTearDown(() => debugPrint = old);
    fakeAsync((fa) {
      final s = make(fa);
      s.want('/repo/secret-dir', 'feature/secret-branch');
      fa.flushMicrotasks();
      runner.answer = (_) => GhResult(1, '', 'secret-branch failed 12');
      fa.elapse(const Duration(minutes: 6));
      s.want('/repo/secret-dir', 'feature/secret-branch');
      fa.flushMicrotasks();
      s.dispose();
    });
    final all = lines.join('\n');
    expect(all, isNot(contains('secret')));
    expect(all, isNot(contains('github.com')));
    expect(all, isNot(contains('#12')));
  });

  test('PrInfo equality', () {
    final a = parsePrJson(okJson())!;
    final b = parsePrJson(okJson())!;
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(parsePrJson(okJson(number: 13))));
  });
}
