import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/core.dart' show BufferRangeLine;
import 'package:shellx_desktop/src/terminal/desktop_terminal.dart';
import 'package:shellx_desktop/src/terminal/terminal_buffer_text.dart';

const _open = '\x1b]8;;';
const _st = '\x1b\\';

DesktopTerminal term({int cols = 40, int rows = 5}) =>
    DesktopTerminal(maxLines: 200)..resize(cols, rows);

void main() {
  test('text between open and close points at the address', () {
    final t = term();
    t.write(
      'go ${_open}https://example.com/a$_st'
      'here$_open$_st now',
    );
    final link = t.hyperlinks.at(0, 4)!;
    expect(link.uri, 'https://example.com/a');
    expect(t.hyperlinks.at(0, 2), isNull, reason: 'before the link');
    expect(t.hyperlinks.at(0, 3), isNotNull, reason: 'the first cell');
    expect(t.hyperlinks.at(0, 6), isNotNull, reason: 'the last cell');
    expect(t.hyperlinks.at(0, 7), isNull, reason: 'the end is exclusive');
    expect(t.hyperlinks.at(0, 20), isNull);
  });

  test('a URI that holds a semicolon arrives whole', () {
    final t = term();
    t.write(
      '${_open}https://example.com/a;b=1$_st'
      'x$_open$_st',
    );
    expect(t.hyperlinks.at(0, 0)!.uri, 'https://example.com/a;b=1');
  });

  test('params such as id= do not matter', () {
    final t = term();
    t.write(
      '\x1b]8;id=7;https://example.com$_st'
      'x$_open$_st',
    );
    expect(t.hyperlinks.at(0, 0)!.uri, 'https://example.com');
  });

  test('anything but http and https is never recorded (A10 D10)', () {
    final t = term();
    for (final uri in [
      'javascript:alert(1)',
      'file:///etc/passwd',
      'ssh://h',
      'https://a.b/\x01',
    ]) {
      t.write('$_open$uri${_st}x$_open$_st');
    }
    expect(t.hyperlinks.length, 0);
  });

  test('a link split over a wrapped row is one link', () {
    final t = term(cols: 10);
    t.write(
      '${_open}https://example.com$_st'
      '0123456789ABCDEF$_open$_st',
    );
    expect(t.hyperlinks.at(0, 5), isNotNull);
    expect(t.hyperlinks.at(1, 5), isNotNull);
    expect(t.hyperlinks.at(1, 5)!.uri, t.hyperlinks.at(0, 5)!.uri);
  });

  test('an unclosed link makes no range; a new open replaces it', () {
    final t = term();
    t.write(
      '${_open}https://a.b/1${_st}one ${_open}https://a.b/2$_st'
      'two$_open$_st',
    );
    expect(t.hyperlinks.length, 1);
    expect(t.hyperlinks.at(0, 5)!.uri, 'https://a.b/2');
  });

  test('2 000 ranges at most; ranges that left the scrollback go', () {
    final t = DesktopTerminal(maxLines: 50)..resize(20, 3);
    for (var i = 0; i < 2200; i++) {
      t.write('${_open}https://a.b/$i${_st}x$_open$_st\r\n');
    }
    expect(
      t.hyperlinks.length,
      lessThanOrEqualTo(60),
      reason: 'only lines still in the buffer keep a link',
    );
  });

  test('the visible text of a range reads back for the confirmation', () {
    final t = term();
    t.write(
      '${_open}https://evil.example$_st'
      'https://paypal.com$_open$_st',
    );
    final link = t.hyperlinks.at(0, 1)!;
    final shown = t.buffer.getText(
      BufferRangeLine(link.begin.offset, link.end.offset),
    );
    expect(shown, 'https://paypal.com');
  });

  group('logicalLineAt (A10 D9)', () {
    test('joins wrapped rows and maps units to cells', () {
      final t = term(cols: 10);
      t.write('see https://example.com/path now');
      final line = logicalLineAt(t.buffer, 1);
      expect(line.text, 'see https://example.com/path now');
      expect(line.firstRow, 0);
      final at = line.text.indexOf('example');
      expect(line.beginOf(at), isNot(line.beginOf(0)));
      expect(line.indexOfCell(1, 2), 12);
      expect(line.indexOfCell(3, 9), isNull, reason: 'past the text');
    });

    test('a wide character is one index for both of its cells', () {
      final t = term();
      t.write('日本 x');
      final line = logicalLineAt(t.buffer, 0);
      expect(line.text, '日本 x');
      expect(line.indexOfCell(0, 0), 0);
      expect(line.indexOfCell(0, 1), 0);
      expect(line.indexOfCell(0, 2), 1);
      expect(line.endAfter(0).x, 2);
    });

    test('never reads more than 8 rows', () {
      final t = term(cols: 5, rows: 20);
      t.write('x' * 100);
      expect(logicalLineAt(t.buffer, 10).text.length, lessThanOrEqualTo(8 * 5));
    });

    test('a row past the buffer is empty', () {
      expect(logicalLineAt(term().buffer, 99).isEmpty, isTrue);
    });
  });

  test('toString never shows the address', () {
    final t = term();
    t.write(
      '${_open}https://secret.example$_st'
      'x$_open$_st',
    );
    expect(t.hyperlinks.at(0, 0).toString(), isNot(contains('secret')));
  });
}
