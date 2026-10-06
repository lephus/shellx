import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/cli/pane_waiter.dart';
import 'package:xterm/xterm.dart';

final class FakeProbe implements PaneProbe {
  @override
  bool hooked = true;
  @override
  bool running = true;
  @override
  bool exited = false;
  @override
  int? exitCode;
  final out = StreamController<void>.broadcast(sync: true);
  final ch = StreamController<void>.broadcast(sync: true);
  @override
  Stream<void> get output => out.stream;
  @override
  Stream<void> get changes => ch.stream;
  @override
  final Terminal terminal = Terminal(maxLines: 1000)..resize(40, 5);
  void print(String s) {
    terminal.write(s);
    out.add(null);
  }
}

Matcher failure(String code) =>
    isA<CliFailure>().having((f) => f.code, 'code', code);

void main() {
  test('idle: prompt back and quiet for 500 ms', () {
    fakeAsync((async) {
      final p = FakeProbe();
      Map<String, Object?>? r;
      unawaited(
        waitIdle(
          p,
          quiet: const Duration(milliseconds: 500),
          timeout: const Duration(seconds: 30),
        ).then((v) => r = v),
      );
      async.elapse(const Duration(seconds: 2));
      expect(r, isNull); // still running
      p.running = false;
      p.ch.add(null);
      async.elapse(const Duration(milliseconds: 400));
      p.print('x');
      async.elapse(const Duration(milliseconds: 400));
      expect(r, isNull); // output reset the quiet timer
      async.elapse(const Duration(milliseconds: 150));
      expect(r, isNotNull);
    });
  });

  test('idle: a change elsewhere (same state) does not reset the quiet '
      'timer', () {
    fakeAsync((async) {
      final p = FakeProbe()..running = false;
      Map<String, Object?>? r;
      unawaited(
        waitIdle(
          p,
          quiet: const Duration(milliseconds: 500),
          timeout: const Duration(seconds: 30),
        ).then((v) => r = v),
      );
      async.elapse(const Duration(milliseconds: 400));
      p.ch.add(null);
      async.elapse(const Duration(milliseconds: 150));
      expect(r, isNotNull);
    });
  });

  test('idle without hooks: 2 s of silence', () {
    fakeAsync((async) {
      final p = FakeProbe()..hooked = false;
      Map<String, Object?>? r;
      unawaited(
        waitIdle(
          p,
          quiet: const Duration(milliseconds: 500),
          timeout: const Duration(seconds: 30),
        ).then((v) => r = v),
      );
      async.elapse(const Duration(milliseconds: 1900));
      expect(r, isNull);
      async.elapse(const Duration(milliseconds: 200));
      expect(r, isNotNull);
    });
  });

  test('exit returns the code; timeout fails with timeout', () {
    fakeAsync((async) {
      final p = FakeProbe();
      Map<String, Object?>? r;
      unawaited(
        waitExit(p, timeout: const Duration(seconds: 5)).then((v) => r = v),
      );
      p.exited = true;
      p.exitCode = 3;
      p.ch.add(null);
      async.flushMicrotasks();
      expect(r, {'exitCode': 3});
      Object? err;
      unawaited(
        waitExit(FakeProbe(), timeout: const Duration(seconds: 5)).catchError((
          Object e,
        ) {
          err = e;
          return <String, Object?>{};
        }),
      );
      async.elapse(const Duration(seconds: 6));
      expect(err, failure('timeout'));
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('match: existing text counts unless fromNow; later output '
      'matches', () {
    fakeAsync((async) {
      final p = FakeProbe()..print('Serving HTTP on 0.0.0.0\r\n');
      Map<String, Object?>? old;
      unawaited(
        waitMatch(
          p,
          RegExp('Serving HTTP', multiLine: true),
          fromNow: false,
          timeout: const Duration(seconds: 5),
        ).then((v) => old = v),
      );
      async.elapse(const Duration(milliseconds: 150));
      expect(old!['match'], 'Serving HTTP');
      expect(old!['line'], 'Serving HTTP on 0.0.0.0');
      Map<String, Object?>? fresh;
      unawaited(
        waitMatch(
          p,
          RegExp(r'ready in \d+', multiLine: true),
          fromNow: true,
          timeout: const Duration(seconds: 5),
        ).then((v) => fresh = v),
      );
      Map<String, Object?>? again;
      unawaited(
        waitMatch(
          p,
          RegExp('Serving', multiLine: true),
          fromNow: true,
          timeout: const Duration(seconds: 5),
        ).then((v) => again = v),
      );
      async.elapse(const Duration(milliseconds: 150));
      expect(fresh, isNull);
      expect(again, isNull); // before the cursor: not looked at
      p.print('ready in 42 ms\r\n');
      async.elapse(const Duration(milliseconds: 150));
      expect(fresh!['match'], 'ready in 42');
      expect(fresh!['line'], 'ready in 42 ms');
      expect(again, isNull);
    });
  });

  test('match: output is looked at once per 100 ms', () {
    fakeAsync((async) {
      final p = FakeProbe();
      Map<String, Object?>? r;
      unawaited(
        waitMatch(
          p,
          RegExp('go'),
          fromNow: true,
          timeout: const Duration(seconds: 5),
        ).then((v) => r = v),
      );
      async.elapse(const Duration(milliseconds: 150));
      p.print('g');
      async.elapse(const Duration(milliseconds: 50));
      p.print('o');
      async.elapse(const Duration(milliseconds: 40));
      expect(r, isNull);
      async.elapse(const Duration(milliseconds: 20));
      expect(r!['match'], 'go');
    });
  });

  test('a client that goes away ends the wait at once (D21)', () {
    fakeAsync((async) {
      final gone = Completer<void>();
      Object? err;
      final timers = async.pendingTimers.length;
      unawaited(
        waitIdle(
          FakeProbe(),
          quiet: const Duration(milliseconds: 500),
          timeout: const Duration(minutes: 60),
          cancelled: gone.future,
        ).catchError((Object e) {
          err = e;
          return <String, Object?>{};
        }),
      );
      gone.complete();
      async.flushMicrotasks();
      expect(err, failure('cancelled'));
      expect(async.pendingTimers.length, timers); // the 60-minute timer went
    });
  });

  test('a pane that exits fails idle/match with exited', () {
    fakeAsync((async) {
      final p = FakeProbe();
      final errs = <Object>[];
      unawaited(
        waitMatch(
          p,
          RegExp('never'),
          fromNow: false,
          timeout: const Duration(seconds: 5),
        ).catchError((Object e) {
          errs.add(e);
          return <String, Object?>{};
        }),
      );
      unawaited(
        waitIdle(
          p,
          quiet: const Duration(milliseconds: 500),
          timeout: const Duration(seconds: 5),
        ).catchError((Object e) {
          errs.add(e);
          return <String, Object?>{};
        }),
      );
      p.exited = true;
      p.ch.add(null);
      async.elapse(const Duration(milliseconds: 150));
      expect(errs, [failure('exited'), failure('exited')]);
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('CommandInjector: pastes after the first cwd report, or after '
      'quiet, at most 5 s', () {
    fakeAsync((async) {
      final p = FakeProbe()..hooked = false;
      final pasted = <(int, String)>[];
      final inj = CommandInjector((_) => p, (pane, text) {
        pasted.add((pane, text));
      });
      inj.inject(7, 'npm run dev');
      p.print('Last login…\r\n');
      async.elapse(const Duration(milliseconds: 1400));
      expect(pasted, isEmpty);
      async.elapse(const Duration(milliseconds: 200)); // 1.5 s quiet
      expect(pasted, [(7, 'npm run dev')]);

      final q = FakeProbe()..hooked = false;
      final pasted2 = <String>[];
      CommandInjector((_) => q, (_, t) => pasted2.add(t)).inject(8, 'ls');
      q.hooked = true; // first OSC 7
      q.ch.add(null);
      async.flushMicrotasks();
      expect(pasted2, ['ls']);

      final r = FakeProbe()..hooked = false;
      final pasted3 = <String>[];
      CommandInjector((_) => r, (_, t) => pasted3.add(t)).inject(9, 'x');
      for (var i = 0; i < 10; i++) {
        r.print('.');
        async.elapse(const Duration(milliseconds: 500));
      }
      expect(pasted3, ['x']); // 5 s cap

      final s = FakeProbe()..hooked = false;
      final pasted4 = <String>[];
      CommandInjector((_) => s, (_, t) => pasted4.add(t)).inject(10, 'y');
      s.exited = true;
      s.ch.add(null);
      async.elapse(const Duration(seconds: 6));
      expect(pasted4, isEmpty); // the shell is gone: nothing typed
      expect(async.pendingTimers, isEmpty);
    });
  });
}
