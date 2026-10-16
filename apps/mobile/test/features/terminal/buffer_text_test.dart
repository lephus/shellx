import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/features/terminal/domain/buffer_text.dart';
import 'package:xterm/core.dart';

Terminal term(String text, {int cols = 20, int rows = 5, int maxLines = 10000}) => Terminal(maxLines: maxLines)
  ..resize(cols, rows)
  ..write(text);

void main() {
  test('screen and scrollback, trailing blanks and empty lines removed', () {
    final t = term('one   \r\ntwo\r\n\r\nthree\r\n\r\n\r\n', rows: 3);
    expect(terminalText(t).text, 'one\ntwo\n\nthree');
    expect(terminalText(t).truncated, isFalse);
  });

  test('rows the terminal wrapped come back as one line', () {
    final t = term('0123456789abcdefghijWRAPPED TEXT here\r\nnext', cols: 20);
    expect(terminalText(t).text, '0123456789abcdefghijWRAPPED TEXT here\nnext');
  });

  test('a space at the end of a wrapped row is kept (it is inside the line)', () {
    final t = term('aaaaaaaaa bbbbbbbbbb ccc', cols: 10);
    expect(terminalText(t).text, 'aaaaaaaaa bbbbbbbbbb ccc');
  });

  test('the last 2000 lines only, and it says so', () {
    final t = term('', rows: 5, maxLines: 5000);
    for (var i = 0; i < 2500; i++) {
      t.write('line $i\r\n');
    }
    final r = terminalText(t);
    expect(r.truncated, isTrue);
    final lines = r.text.split('\n');
    expect(lines, hasLength(2000));
    expect(lines.last, 'line 2499');
    expect(lines.first, 'line 500');
  });

  test('over 200 000 characters the start is cut at a line', () {
    final t = term('', cols: 200, rows: 5, maxLines: 5000);
    for (var i = 0; i < 1500; i++) {
      t.write('${'x' * 150}$i\r\n');
    }
    final r = terminalText(t);
    expect(r.text.length, lessThanOrEqualTo(kViewAsTextMaxChars));
    expect(r.truncated, isTrue);
    expect(r.text.startsWith('x'), isTrue);
    expect(r.text.split('\n').first.length, greaterThan(150));
  });

  test('only the screen while a full-screen program uses the alternate buffer', () {
    final t = term('history 1\r\nhistory 2\r\n', rows: 3);
    t.write('\x1b[?1049hvim screen');
    expect(terminalText(t).text, 'vim screen');
    t.write('\x1b[?1049l');
    expect(terminalText(t).text, contains('history 1'));
  });

  test('Vietnamese, CJK and emoji are kept', () {
    final t = term('Xin chào 日本語 😀');
    expect(terminalText(t).text, 'Xin chào 日本語 😀');
  });

  test('an empty terminal is empty', () {
    expect(terminalText(Terminal()).text, '');
  });
}
