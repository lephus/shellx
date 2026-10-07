import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/terminal_search.dart';
import 'package:xterm/core.dart';

Terminal terminal(String text, {int cols = 20, int rows = 5}) {
  final t = Terminal(maxLines: 1000)..resize(cols, rows);
  t.write(text);
  return t;
}

String textOf(Terminal t, SearchMatch m) =>
    t.buffer.getText(BufferRangeLine(m.begin, m.end));

void main() {
  test('finds every occurrence, case-insensitive by default', () {
    final t = terminal('Error one\r\nerror two\r\nno trouble\r\nERROR three');
    final r = searchBuffer(t.buffer, 'error');
    expect(r.matches, hasLength(3));
    expect(r.capped, isFalse);
    for (final m in r.matches) {
      expect(textOf(t, m).toLowerCase(), 'error');
    }
    expect(
      searchBuffer(t.buffer, 'error', matchCase: true).matches,
      hasLength(1),
    );
  });

  test('the end column is exclusive: the range reads back as the needle', () {
    final t = terminal('xx needle yy');
    final m = searchBuffer(t.buffer, 'needle').matches.single;
    expect((m.startRow, m.startCol, m.endRow, m.endCol), (0, 3, 0, 9));
    expect(textOf(t, m), 'needle');
  });

  test('a match can cross a wrapped row', () {
    final t = terminal('0123456789abcdefghijWRAPPED here', cols: 24);
    // 24 columns: "0123456789abcdefghijWRAP" | "PED here"
    final m = searchBuffer(t.buffer, 'wrapped').matches.single;
    expect(m.startRow, isNot(m.endRow));
    expect(textOf(t, m).replaceAll('\n', ''), 'WRAPPED');
  });

  test('scrollback is searched, not only the screen', () {
    final t = Terminal(maxLines: 1000)..resize(10, 3);
    for (var i = 0; i < 50; i++) {
      t.write('line $i\r\n');
    }
    final r = searchBuffer(t.buffer, 'line 7');
    expect(r.matches.single.startRow, lessThan(t.buffer.scrollBack));
  });

  test('wide characters and emoji map to the right cells', () {
    final t = terminal('日本語 test 😀 end');
    final jp = searchBuffer(t.buffer, 'test').matches.single;
    expect(textOf(t, jp), 'test');
    final em = searchBuffer(t.buffer, 'end').matches.single;
    expect(textOf(t, em), 'end');
    final cjk = searchBuffer(t.buffer, '本語').matches.single;
    expect(textOf(t, cjk), '本語');
  });

  test('Vietnamese folds case; the length never changes', () {
    final t = terminal('Đường đi');
    expect(searchBuffer(t.buffer, 'đường').matches, hasLength(1));
    expect(searchBuffer(t.buffer, 'ĐI').matches, hasLength(1));
    expect(foldCase('ÀÉĐİßABC').length, 8, reason: 'indices stay valid');
    expect(foldCase('ÀĐ'), 'àđ');
  });

  test('empty needle, empty buffer, no match', () {
    final t = terminal('abc');
    expect(searchBuffer(t.buffer, '').matches, isEmpty);
    expect(searchBuffer(t.buffer, 'zzz').matches, isEmpty);
    expect(searchBuffer(Terminal().buffer, 'a').matches, isEmpty);
  });

  test('matches do not overlap', () {
    final t = terminal('aaaa');
    expect(searchBuffer(t.buffer, 'aa').matches, hasLength(2));
  });

  test('stops at the cap and says so', () {
    final t = Terminal(maxLines: 5000)..resize(20, 5);
    for (var i = 0; i < 1500; i++) {
      t.write('x\r\n');
    }
    final r = searchBuffer(t.buffer, 'x');
    expect(r.matches, hasLength(kMaxSearchMatches));
    expect(r.capped, isTrue);
  });

  test('10 000 lines of 200 columns search in well under a second', () {
    final t = Terminal(maxLines: 10000)..resize(200, 40);
    final line = '${'abcdefghij' * 19}error\r\n';
    for (var i = 0; i < 10000; i++) {
      t.write(line);
    }
    final watch = Stopwatch()..start();
    final r = searchBuffer(t.buffer, 'error');
    watch.stop();
    expect(r.capped, isTrue);
    expect(watch.elapsedMilliseconds, lessThan(250)); // budget 50 ms, 5x slack
  });

  test('firstMatchFrom wraps to the first match', () {
    const ms = [SearchMatch(2, 0, 2, 1), SearchMatch(9, 0, 9, 1)];
    expect(firstMatchFrom(ms, 0), 0);
    expect(firstMatchFrom(ms, 3), 1);
    expect(firstMatchFrom(ms, 10), 0);
    expect(firstMatchFrom(const [], 0), -1);
  });

  test('toString never shows terminal text', () {
    expect(const SearchMatch(1, 2, 3, 4).toString(), isNot(contains('needle')));
  });

  test('decomposed Vietnamese in the buffer finds the precomposed needle', () {
    // "việt" typed as v i e + dot below + circumflex + t: the terminal
    // stores each mark in a cell of its own.
    final t = terminal('x vie\u0323\u0302t y');
    for (final needle in ['việt', 'vie\u0323\u0302t', 'vie\u0302\u0323t']) {
      final r = searchBuffer(t.buffer, needle);
      expect(r.matches, hasLength(1), reason: needle.runes.join(','));
      expect(r.matches.single.startCol, 2);
    }
    expect(searchBuffer(t.buffer, 'VIỆT').matches, hasLength(1));
  });

  test('precomposed text in the buffer finds a decomposed needle', () {
    final t = terminal('x việt y');
    expect(searchBuffer(t.buffer, 'vie\u0323\u0302t').matches, hasLength(1));
  });

  test(
    'a sliced search never holds the thread; the result arrives',
    () {
      final t = Terminal(maxLines: 100000)..resize(200, 40);
      final line = '${'abcdefghij' * 20}\r\n';
      t.write(line * 100000);
      final search = BufferSearch(t.buffer, 'no such text');
      final slices = <int>[];
      var done = false;
      while (!done) {
        final watch = Stopwatch()..start();
        done = search.step(const Duration(milliseconds: 4));
        slices.add(watch.elapsedMilliseconds);
      }
      expect(slices.length, greaterThan(1), reason: 'it was cut into slices');
      expect(slices.reduce((a, b) => a > b ? a : b), lessThan(16));
      expect(search.result.matches, isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
