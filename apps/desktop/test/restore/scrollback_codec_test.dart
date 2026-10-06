import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/restore/scrollback_codec.dart';
import 'package:xterm/xterm.dart';

Terminal term({int cols = 80, int rows = 24}) =>
    Terminal(maxLines: 10000)..resize(cols, rows);

/// The first local calendar day of [year] whose midnight-to-midnight span is
/// not 24 h (a DST switch), or null when the local zone has no DST.
DateTime? _firstDstDay(int year) {
  for (var d = DateTime(year, 1, 1); d.year == year;) {
    final next = DateTime(d.year, d.month, d.day + 1);
    if (next.difference(d) != const Duration(hours: 24)) return d;
    d = next;
  }
  return null;
}

void main() {
  group('encodeScrollback', () {
    test('plain lines, trailing blank rows dropped, CRLF joined', () {
      final t = term()..write('hello\r\nworld\r\n\r\n');
      expect(encodeScrollback(t), 'hello\r\nworld\r\n');
    });

    test('empty terminal gives an empty string', () {
      expect(encodeScrollback(term()), '');
    });

    test('16, 256 and truecolor foreground/background + attributes', () {
      final t = term()
        ..write(
          '\x1b[31mred\x1b[0m \x1b[1;4;38;5;208mo\x1b[0m '
          '\x1b[48;2;1;2;3mbg\x1b[0m \x1b[7;9;3;2mx\x1b[0m\r\n',
        );
      final out = encodeScrollback(t);
      expect(out, contains('\x1b[0;31mred'));
      expect(out, contains('\x1b[0;1;4;38;5;208mo'));
      expect(out, contains('\x1b[0;48;2;1;2;3mbg'));
      expect(out, contains('\x1b[0;2;3;7;9mx'));
      expect(out, endsWith('\x1b[0m\r\n'));
      // Bright named colours use 90–97.
      final b = term()..write('\x1b[92mg\x1b[0m\r\n');
      expect(encodeScrollback(b), contains('\x1b[0;92mg'));
    });

    test('blink is dropped, invisible cells become spaces', () {
      final t = term()..write('a\x1b[5mb\x1b[0m\x1b[8msecret\x1b[0mc\r\n');
      final out = encodeScrollback(t);
      expect(out, isNot(contains('secret')));
      expect(out.replaceAll(RegExp(r'\x1b\[[0-9;]*m'), ''), 'ab      c\r\n');
    });

    test('a wrapped line is one logical line (rewraps at a new width)', () {
      final t = term(cols: 10)..write('${'x' * 25}\r\nnext\r\n');
      expect(encodeScrollback(t), '${'x' * 25}\r\nnext\r\n');
    });

    test('wide characters are written once; gaps become spaces', () {
      final t = term()..write('中文 ok\r\na\x1b[5Cb\r\n');
      expect(encodeScrollback(t), '中文 ok\r\na     b\r\n');
    });

    test('a wide character pushed past the wrap column adds no space', () {
      // 5 columns: "abcd" fills four, "中" needs two, so it moves to the
      // next row and leaves the last cell of the first row empty.
      final t = term(cols: 5)..write('abcd中ef\r\n');
      expect(encodeScrollback(t), 'abcd中ef\r\n');
    });

    test('a wide character moved down by a resize adds no space', () {
      // At 6 columns the reflow moves "中" to the next row and leaves the
      // last cell of the first row empty.
      final t = term(cols: 10)..write('abcde中fg\r\n');
      t.resize(6, 24);
      expect(encodeScrollback(t), 'abcde中fg\r\n');
    });

    test('only the main buffer is saved while an alt screen is shown', () {
      final t = term()
        ..write('shell line\r\n')
        ..write('\x1b[?1049h') // vim enters the alt screen
        ..write('VIM SCREEN');
      expect(t.isUsingAltBuffer, isTrue);
      final out = encodeScrollback(t);
      expect(out, contains('shell line'));
      expect(out, isNot(contains('VIM SCREEN')));
    });

    test('keeps the last 2000 logical lines', () {
      final t = term();
      for (var i = 1; i <= 5000; i++) {
        t.write('$i\r\n');
      }
      final lines = encodeScrollback(t).split('\r\n')..removeLast();
      expect(lines.length, 2000);
      expect(lines.first, '3001');
      expect(lines.last, '5000');
    });

    test('byte cap drops whole oldest lines, never splits UTF-8 or SGR', () {
      final t = term(cols: 200);
      for (var i = 0; i < 10; i++) {
        t.write('\x1b[32m${'ế' * 150}\x1b[0m$i\r\n');
      }
      final out = encodeScrollback(t, maxBytes: 2000);
      expect(utf8.encode(out).length, lessThanOrEqualTo(2000));
      expect(out, endsWith('9\r\n'));
      for (final line in out.split('\r\n')..removeLast()) {
        expect(line, startsWith('\x1b[0;32m'));
        expect(line, matches(RegExp(r'\x1b\[0m\d$')));
      }
      expect(() => utf8.decode(utf8.encode(out)), returnsNormally);
    });

    test('round trip: encode → write into a fresh terminal → encode', () {
      final a = term()
        ..write(
          '\x1b[1;35mbold magenta\x1b[0m plain \x1b[38;2;9;8;7mrgb\x1b[0m\r\n'
          'second\r\n',
        );
      final once = encodeScrollback(a);
      final b = term()..write(once);
      expect(encodeScrollback(b), once);
    });
  });

  group('sanitizeRestored', () {
    test('keeps text, CR, LF, TAB, Vietnamese and valid SGR', () {
      const ok = 'Xin chào\t\x1b[0;31mđỏ\x1b[0m\r\n';
      expect(sanitizeRestored(ok), ok);
    });

    test('removes OSC 52, OSC 0, other CSI, DCS, C1, BEL and lone ESC', () {
      const longSgr =
          '\x1b[38;5;1;2;3;4;5;6;7;8;9;10;11;12;13;14;15;16;17;18;19;20;21;'
          '22;23;24m';
      // Over the 64-character parameter limit, so not a well-formed SGR.
      expect(longSgr.length - 3, greaterThanOrEqualTo(65));
      const evil =
          'a\x1b]52;c;ZXZpbA==\x07b\x1b]0;title\x1b\\c'
          '\x1b[2Jd\x1b[?1049he\x1bPqdcs\x1b\\f\u009b31mg\x07h\x1bZi'
          '$longSgr';
      expect(sanitizeRestored(evil), 'abcdefghi');
    });

    test('8-bit C1 introducers are removed with their parameters', () {
      // C1 CSI, C1 OSC ended by BEL, C1 OSC 52 ended by C1 ST, C1 OSC
      // ended by ESC \, C1 DCS / SOS / PM / APC ended by C1 ST.
      const evil =
          'a\u009b2Jb\u009d0;title\x07c\u009d52;c;ZXZpbA==\u009cd'
          '\u009d2;t\x1b\\e\u0090qdcs\u009cf\u0098sos\u009cg'
          '\u009epm\u009ch\u009fapc\u009ci\u0085j';
      expect(sanitizeRestored(evil), 'abcdefghij');
    });

    test('an unterminated C1 string swallows the rest', () {
      expect(sanitizeRestored('ok\u009d52;c;ZXZpbA=='), 'ok');
    });
  });

  group('divider and time', () {
    test('divider bytes', () {
      expect(
        restoreDivider('— Phiên được khôi phục · 14:32 —'),
        '\x1b[0m\x1b[2m— Phiên được khôi phục · 14:32 —\x1b[0m\r\n',
      );
    });

    test('today, yesterday, older — vi and en, always 24 h', () {
      final now = DateTime(2026, 10, 7, 9, 0);
      String vi(DateTime d) => formatRestoreTime(
        d,
        now,
        localeName: 'vi',
        yesterday: (t) => 'hôm qua $t',
      );
      String en(DateTime d) => formatRestoreTime(
        d,
        now,
        localeName: 'en',
        yesterday: (t) => 'yesterday $t',
      );
      expect(vi(DateTime(2026, 10, 7, 8, 5)), '08:05');
      expect(vi(DateTime(2026, 10, 6, 14, 32)), 'hôm qua 14:32');
      expect(en(DateTime(2026, 10, 6, 14, 32)), 'yesterday 14:32');
      expect(vi(DateTime(2026, 10, 1, 14, 32)), '1/10 14:32');
      expect(en(DateTime(2026, 10, 1, 14, 32)), 'Oct 1 14:32');
      // Across a year boundary, by calendar date.
      expect(en(DateTime(2025, 12, 31, 23, 59)).startsWith('Dec 31'), isTrue);
      expect(
        formatRestoreTime(
          DateTime(2025, 12, 31, 23, 59),
          DateTime(2026, 1, 1, 0, 1),
          localeName: 'en',
          yesterday: (t) => 'yesterday $t',
        ),
        'yesterday 23:59',
      );
    });

    final dst = _firstDstDay(2026);
    test(
      'yesterday by calendar date across a DST change',
      () {
        // The day after the switch: midnight to midnight is not 24 h, yet
        // the switch day is still "yesterday", and the day before it is
        // older.
        final switchDay = dst!;
        final now = DateTime(
          switchDay.year,
          switchDay.month,
          switchDay.day + 1,
          0,
          30,
        );
        String fmt(DateTime d) => formatRestoreTime(
          d,
          now,
          localeName: 'en',
          yesterday: (t) => 'yesterday $t',
        );
        expect(
          fmt(DateTime(switchDay.year, switchDay.month, switchDay.day, 14, 32)),
          'yesterday 14:32',
        );
        expect(
          fmt(
            DateTime(
              switchDay.year,
              switchDay.month,
              switchDay.day - 1,
              23,
              50,
            ),
          ),
          isNot(startsWith('yesterday')),
        );
        expect(fmt(DateTime(now.year, now.month, now.day, 0, 10)), '00:10');
      },
      skip: dst == null
          ? 'The local time zone has no DST; run with TZ=America/New_York '
                'or TZ=Europe/Berlin'
          : false,
    );
  });
}
