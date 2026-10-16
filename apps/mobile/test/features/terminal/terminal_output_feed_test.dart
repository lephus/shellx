import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/features/terminal/domain/terminal_output_feed.dart';

void main() {
  test('the front tab writes the first piece at once, then 128 KiB per 16 ms', () {
    fakeAsync((async) {
      final writes = <String>[];
      final feed = TerminalOutputFeed(writes.add);
      feed.add('x' * 300000);
      expect(writes.map((w) => w.length), [128 * 1024]);
      async.elapse(const Duration(milliseconds: 16));
      expect(writes.map((w) => w.length), [128 * 1024, 128 * 1024]);
      async.elapse(const Duration(milliseconds: 16));
      expect(writes.join().length, 300000);
      expect(feed.pendingLength, 0);
      async.elapse(const Duration(seconds: 1));
      expect(writes, hasLength(3));
    });
  });

  test('a back tab waits 250 ms and then writes at most 64 KiB at a time', () {
    fakeAsync((async) {
      final writes = <String>[];
      final feed = TerminalOutputFeed(writes.add)..isActive = false;
      feed.add('y' * 200000);
      expect(writes, isEmpty);
      async.elapse(const Duration(milliseconds: 249));
      expect(writes, isEmpty);
      async.elapse(const Duration(milliseconds: 1));
      expect(writes.map((w) => w.length), [64 * 1024]);
      async.elapse(const Duration(milliseconds: 250));
      async.elapse(const Duration(milliseconds: 250));
      async.elapse(const Duration(milliseconds: 250));
      expect(writes.join().length, 200000);
    });
  });

  test('coming to the front writes what waits at once', () {
    fakeAsync((async) {
      final writes = <String>[];
      final feed = TerminalOutputFeed(writes.add)..isActive = false;
      feed.add('z' * 1000);
      feed.isActive = true;
      expect(writes, ['z' * 1000]);
      async.elapse(const Duration(seconds: 1));
      expect(writes, hasLength(1));
    });
  });

  test('going to the back stops the fast ticks', () {
    fakeAsync((async) {
      final writes = <String>[];
      final feed = TerminalOutputFeed(writes.add);
      feed.add('a' * 300000); // one piece out, the rest waits for the tick
      feed.isActive = false;
      async.elapse(const Duration(milliseconds: 100));
      expect(writes, hasLength(1));
      async.elapse(const Duration(milliseconds: 200));
      expect(writes.length, greaterThan(1));
    });
  });

  test('the echo of what was just typed is written at once, even behind a burst elsewhere', () {
    fakeAsync((async) {
      var now = DateTime(2026, 10, 7, 9);
      final writes = <String>[];
      final feed = TerminalOutputFeed(writes.add, now: () => now);
      feed.noteInput();
      feed.add('a'); // the echo
      expect(writes, ['a']);
      now = now.add(const Duration(milliseconds: 300));
      feed.add('late'); // after the window it is ordinary output (written at once: nothing waits)
      expect(writes, ['a', 'late']);
    });
  });

  test('an echo does not jump the queue: pending output goes first', () {
    fakeAsync((async) {
      final writes = <String>[];
      final feed = TerminalOutputFeed(writes.add);
      feed.add('b' * 300000);
      feed.noteInput();
      feed.add('!'); // output is waiting: stays in order
      expect(writes.length, 1);
      async.elapse(const Duration(milliseconds: 40));
      expect(writes.join().endsWith('!'), isTrue);
      expect(writes.join().length, 300001);
    });
  });

  test('a big echo (a paste coming back) is paced like any output', () {
    fakeAsync((async) {
      final writes = <String>[];
      final feed = TerminalOutputFeed(writes.add);
      feed.noteInput();
      feed.add('c' * 10000);
      expect(writes.single.length, 10000, reason: 'nothing waited, so the first piece goes at once');
      feed.add('d' * 300000);
      async.elapse(const Duration(seconds: 1));
      expect(writes.join().length, 310000);
    });
  });

  test('over 2 MiB waiting: only the newest 1 MiB is kept, from a line start', () {
    fakeAsync((async) {
      final writes = <String>[];
      final feed = TerminalOutputFeed(writes.add)..isActive = false;
      for (var i = 0; i < 40; i++) {
        feed.add('${'e' * 99}\n' * 1000); // 100 000 characters
      }
      expect(feed.dropped, greaterThan(0));
      expect(feed.pendingLength, lessThanOrEqualTo(2 * 1024 * 1024));
      feed.isActive = true;
      async.elapse(const Duration(seconds: 2));
      final all = writes.join();
      expect(all.length, lessThanOrEqualTo(2 * 1024 * 1024));
      expect(all.startsWith('e' * 99 + '\n'), isTrue, reason: 'never cut mid-line');
    });
  });

  test('a surrogate pair is never split between two writes', () {
    fakeAsync((async) {
      final writes = <String>[];
      final feed = TerminalOutputFeed(writes.add, activeBudget: 10);
      feed.add('${'a' * 9}😀${'b' * 20}');
      async.elapse(const Duration(seconds: 1));
      for (final w in writes) {
        final u = w.codeUnitAt(w.length - 1);
        expect(u >= 0xD800 && u <= 0xDBFF, isFalse);
      }
      expect(writes.join(), '${'a' * 9}😀${'b' * 20}');
    });
  });

  test('drain writes everything now; clear forgets it; dispose stops', () {
    fakeAsync((async) {
      final writes = <String>[];
      final feed = TerminalOutputFeed(writes.add);
      feed.add('f' * 300000);
      feed.drain();
      expect(writes.join().length, 300000);
      feed.add('g' * 300000);
      feed.clear();
      async.elapse(const Duration(seconds: 1));
      expect(writes.join().length, 300000 + 128 * 1024);
      feed.dispose();
      feed.add('h');
      async.elapse(const Duration(seconds: 1));
      expect(writes.join().contains('h'), isFalse);
    });
  });

  test('a burst of 1 MiB in one tab leaves the frame budget: no write is bigger than the budget', () {
    fakeAsync((async) {
      final sizes = <int>[];
      final feed = TerminalOutputFeed((t) => sizes.add(t.length));
      feed.add('k' * (1024 * 1024));
      async.elapse(const Duration(seconds: 1));
      expect(sizes.reduce((a, b) => a > b ? a : b), lessThanOrEqualTo(128 * 1024));
      expect(sizes.fold<int>(0, (a, b) => a + b), 1024 * 1024);
    });
  });

  test('an echo only counts within 50 ms of the key and 10 per second; everything still arrives in order', () {
    fakeAsync((async) {
      var now = DateTime(2026, 10, 7, 9);
      final writes = <String>[];
      final feed = TerminalOutputFeed(writes.add, now: () => now);
      // Held key: a keystroke, then 30 small writes in the same instant.
      feed.noteInput();
      for (var i = 0; i < 30; i++) {
        feed.add('$i,');
      }
      async.elapse(const Duration(seconds: 1));
      expect(writes.join(), [for (var i = 0; i < 30; i++) '$i,'].join());
      // 60 ms after the key it is not an echo any more.
      writes.clear();
      feed.noteInput();
      now = now.add(const Duration(milliseconds: 60));
      feed.add('late');
      feed.add('x' * 300000);
      async.elapse(const Duration(seconds: 1));
      expect(writes.join().length, 4 + 300000);
      expect(writes.join().startsWith('late'), isTrue);
    });
  });

  test('many small chunks queue and leave in order within the budget', () {
    fakeAsync((async) {
      final writes = <String>[];
      final feed = TerminalOutputFeed(writes.add, activeBudget: 1000)..isActive = false;
      for (var i = 0; i < 500; i++) {
        feed.add('${i.toString().padLeft(4, '0')}-');
      }
      feed.isActive = true;
      async.elapse(const Duration(seconds: 2));
      expect(writes.every((w) => w.length <= 1000), isTrue);
      expect(writes.join(), [for (var i = 0; i < 500; i++) '${i.toString().padLeft(4, '0')}-'].join());
    });
  });

  group('a trim never loses a screen mode', () {
    String body(int n) => List.generate(n, (i) => 'row $i\n').join();

    TerminalOutputFeed small(List<String> writes) => TerminalOutputFeed(writes.add, cap: 2000, keep: 500);

    test('the alternate screen entered in the dropped part is re-entered first', () {
      fakeAsync((async) {
        final writes = <String>[];
        final feed = small(writes)..isActive = false;
        feed.add('\x1b[?1049h${body(400)}');
        feed.add(body(400));
        expect(feed.dropped, greaterThan(0));
        async.elapse(const Duration(seconds: 5));
        expect(writes.first, startsWith('\x1b[?1049h'));
      });
    });

    test('bracketed paste turned off in the dropped part is turned off again', () {
      fakeAsync((async) {
        final writes = <String>[];
        final feed = small(writes);
        feed.add('\x1b[?2004h');
        async.elapse(const Duration(milliseconds: 20));
        feed.isActive = false;
        feed.add('\x1b[?2004l${body(400)}');
        feed.add(body(400));
        expect(feed.dropped, greaterThan(0));
        async.elapse(const Duration(seconds: 5));
        expect(writes.skip(1).first, startsWith('\x1b[?2004l'));
      });
    });

    test('a mode already in effect on screen is not repeated', () {
      fakeAsync((async) {
        final writes = <String>[];
        final feed = small(writes);
        feed.add('\x1b[?1049h');
        async.elapse(const Duration(milliseconds: 20));
        feed.isActive = false;
        feed.add('\x1b[?1049h${body(400)}');
        feed.add(body(400));
        async.elapse(const Duration(seconds: 5));
        expect(writes.skip(1).join(), isNot(contains('\x1b[?1049h')));
      });
    });

    test('the last state wins when the dropped part switched back and forth', () {
      fakeAsync((async) {
        final writes = <String>[];
        final feed = small(writes)..isActive = false;
        feed.add('\x1b[?1049h${body(100)}\x1b[?1049l${body(300)}');
        feed.add(body(400));
        async.elapse(const Duration(seconds: 5));
        expect(writes.join(), isNot(contains('\x1b[?1049h')));
      });
    });
  });
}
