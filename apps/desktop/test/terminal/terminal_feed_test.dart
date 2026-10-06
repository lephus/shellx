import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/terminal_feed.dart';

void main() {
  test('UTF-8 split across chunks is decoded whole', () {
    fakeAsync((async) {
      final written = <String>[];
      final feed = TerminalFeed(written.add);
      final bytes = utf8.encode('Tiếng Việt');
      feed.add(bytes.sublist(0, 3));
      feed.add(bytes.sublist(3));
      async.elapse(const Duration(milliseconds: 50));
      expect(written.join(), 'Tiếng Việt');
      feed.dispose();
    });
  });

  test('a burst is coalesced: one write now, the rest per tick', () {
    fakeAsync((async) {
      final written = <String>[];
      final feed = TerminalFeed(written.add);
      for (var i = 0; i < 1000; i++) {
        feed.add(utf8.encode('line $i\n'));
      }
      expect(written, hasLength(1)); // the first chunk, at once
      async.elapse(const Duration(milliseconds: 16));
      expect(written, hasLength(2)); // everything else in one write
      expect(written.join(), contains('line 999\n'));
      feed.dispose();
    });
  });

  test(
    'never writes more than the budget per tick (the UI keeps painting)',
    () {
      fakeAsync((async) {
        final written = <String>[];
        final feed = TerminalFeed(
          written.add,
          budget: 10,
          cap: 1000,
          keep: 500,
        );
        feed.add(utf8.encode('a')); // flushed now, starts the tick
        feed.add(utf8.encode('b' * 35));
        async.elapse(const Duration(milliseconds: 16));
        expect(written.last.length, 10);
        async.elapse(const Duration(milliseconds: 48));
        expect(written.skip(1).join(), 'b' * 35);
        expect(written.skip(1).every((w) => w.length <= 10), isTrue);
        feed.dispose();
      });
    },
  );

  test('pending output is capped, keeping the newest whole lines', () {
    fakeAsync((async) {
      final written = <String>[];
      final feed = TerminalFeed(written.add, budget: 4, cap: 40, keep: 20);
      feed.add(utf8.encode('x')); // flushed now
      for (var i = 0; i < 20; i++) {
        feed.add(utf8.encode('row$i\n'));
      }
      expect(feed.dropped, greaterThan(0));
      feed.drain();
      final rest = written.skip(1).join();
      expect(rest, endsWith('row19\n'));
      expect(rest, isNot(contains('row0\n')));
      expect(rest.split('\n').first, startsWith('row')); // starts at a line
      feed.dispose();
    });
  });

  test('drain writes everything pending at once', () {
    fakeAsync((async) {
      final written = <String>[];
      final feed = TerminalFeed(written.add, budget: 2);
      feed.add(utf8.encode('ab'));
      feed.add(utf8.encode('cdef'));
      feed.drain();
      expect(written.join(), 'abcdef');
      feed.dispose();
    });
  });
}
