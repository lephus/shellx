import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/cli/pane_text.dart';
import 'package:xterm/xterm.dart';

Terminal term(String output, {int cols = 10, int rows = 4}) =>
    Terminal(maxLines: 1000)
      ..resize(cols, rows)
      ..write(output);

/// Every page of a read, following `next` until the last.
List<String> pages(Terminal t, {int? lines, bool ansi = false}) {
  final out = <String>[];
  int? offset = 0;
  while (offset != null) {
    final page = readPage(t, lines: lines, ansi: ansi, offset: offset);
    out.add(page.text);
    offset = page.next;
  }
  return out;
}

void main() {
  test('screen text: visible rows, wrapped rows joined, trailing blanks '
      'dropped', () {
    final t = term('one\r\ntwo\r\n0123456789abc\r\n');
    expect(screenText(t), 'two\n0123456789abc\n');
    expect(readPage(t).text, 'two\n0123456789abc\n');
  });

  test('--lines reaches into the scrollback', () {
    final t = term([for (var i = 0; i < 20; i++) 'line $i'].join('\r\n'));
    expect(readPage(t, lines: 3).text, 'line 17\nline 18\nline 19\n');
    expect(readPage(t, lines: 100).text.split('\n').first, 'line 0');
  });

  test('alt screen: the screen is what vim shows', () {
    final t = term('shell\r\n\x1b[?1049h\x1b[Hvim here');
    expect(screenText(t), 'vim here\n');
  });

  test('cells the program skipped read as spaces', () {
    final t = term('a\x1b[3Cb', cols: 20);
    expect(screenText(t), 'a   b\n');
  });

  test('--ansi keeps SGR only, never title or clipboard sequences', () {
    final t = term(
      '\x1b]0;title\x07\x1b[31mred\x1b[0m ok\x1b]52;c;aGk=\x07',
      cols: 20,
    );
    final text = readPage(t, lines: 5, ansi: true).text;
    expect(text, '\x1b[0;31mred\x1b[0m ok\n');
    // Regression guards only: cells never hold OSC (the guarantee is that
    // the text is re-encoded from cells).
    expect(text, isNot(contains(']0;')));
    expect(text, isNot(contains(']52;')));
    expect(readPage(t, lines: 5).text, 'red ok\n');
  });

  test('pages are ≤ 48 KiB of UTF-8, whole lines, and chain with next', () {
    final line = 'é' * 300; // 600 bytes
    final t = Terminal(maxLines: 10000)..resize(400, 5);
    for (var i = 0; i < 200; i++) {
      t.write('$line\r\n');
    }
    final all = pages(t, lines: 200);
    expect(all, hasLength(3)); // 200 × 601 B = 120,200 B
    for (final page in all) {
      expect(utf8.encode(page).length, lessThanOrEqualTo(kReadPageBytes));
      expect(page, endsWith('\n'));
    }
    expect(all.join(), '${List.filled(200, line).join('\n')}\n');
  });

  test('one logical line over a page is cut across pages, never inside a '
      'character or an SGR sequence', () {
    final t = Terminal(maxLines: 10000)..resize(100, 5);
    final long = StringBuffer();
    for (var i = 0; i < 8000; i++) {
      long.write('\x1b[3${i % 7 + 1}m😀é${i % 10}');
    }
    t.write('$long\x1b[0m\r\nend\r\n');
    for (final ansi in [false, true]) {
      final all = pages(t, lines: 2, ansi: ansi);
      expect(all.length, greaterThan(1));
      for (final page in all) {
        expect(utf8.encode(page).length, lessThanOrEqualTo(kReadPageBytes));
        expect(utf8.decode(utf8.encode(page)), page); // no lone surrogate
        expect(RegExp(r'\x1b\[[0-9;]*$').hasMatch(page), isFalse);
      }
      final text = all.join();
      expect(text, endsWith('\nend\n'));
      expect(text, ansi ? contains('\x1b[') : isNot(contains('\x1b[')));
      final plain = text.replaceAll(RegExp(r'\x1b\[[0-9;]*m'), '');
      expect(
        plain.split('\n').first,
        [for (var i = 0; i < 8000; i++) '😀é${i % 10}'].join(),
      );
    }
  });

  test('logicalLines from a row starts at its logical line; last keeps the '
      'newest', () {
    final t = term('aa\r\n0123456789xy\r\nzz\r\n', rows: 10);
    expect(logicalLines(t.buffer), ['aa', '0123456789xy', 'zz']);
    expect(logicalLines(t.buffer, fromRow: 2), ['0123456789xy', 'zz']);
    expect(logicalLines(t.buffer, last: 2), ['0123456789xy', 'zz']);
    expect(cursorRow(t), 4);
  });
}
