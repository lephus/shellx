import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

String f(String s) => SgrFilter().filter(s);

void main() {
  group('passes through', () {
    test('plain text and other escapes byte for byte', () {
      const s =
          'héllo \x1b[2J\x1b[1;1H\x1b[?25l\x1b]0;t\x07\x1b[38;5;22m\x1b[0m\x1b(B';
      expect(f(s), s);
    });
    test('ordinary SGR, including 256 and RGB colours', () {
      const s = '\x1b[1;31m\x1b[38;2;153;153;153m\x1b[48;5;244m\x1b[0m\x1b[m';
      expect(f(s), s);
    });
    test('a 22 that is a colour argument is not an attribute', () {
      expect(f('\x1b[38;5;22m'), '\x1b[38;5;22m');
      expect(f('\x1b[48;2;22;22;22m'), '\x1b[48;2;22;22;22m');
    });
    test('a lone ESC not followed by [ and a too long CSI', () {
      final long = '\x1b[${'1;' * 100}m';
      expect(f('\x1b7\x1bM$long'), '\x1b7\x1bM$long');
    });
  });

  group('drops', () {
    test('private-prefixed m: modifyOtherKeys', () {
      expect(f('a\x1b[>4;2mb\x1b[>4mc\x1b[?4md\x1b[<1me'), 'abcde');
    });
    test('underline colour in both forms', () {
      expect(
        f('\x1b[58:2::255:0:0m\x1b[58;2;255;0;0m\x1b[58;5;9m\x1b[59m'),
        '',
      );
      expect(f('\x1b[1;58;2;1;2;3;3m'), '\x1b[1;3m');
    });
  });

  group('rewrites', () {
    test('22 also ends bold', () => expect(f('\x1b[22m'), '\x1b[21;22m'));
    test(
      '22 among others',
      () => expect(f('\x1b[39;22;24m'), '\x1b[39;21;22;24m'),
    );
    test('4:0 and 4:x', () {
      expect(f('\x1b[4:0m'), '\x1b[24m');
      expect(f('\x1b[4:3m'), '\x1b[4m');
      expect(f('\x1b[1;4:3;38:5:244m'), '\x1b[1;4;38;5;244m');
    });
    test('colon colours', () {
      expect(f('\x1b[38:2::153:153:153m'), '\x1b[38;2;153;153;153m');
      expect(f('\x1b[48:2:1:2:3m'), '\x1b[48;2;1;2;3m');
      expect(f('\x1b[38:5:244m'), '\x1b[38;5;244m');
    });
  });

  group('streaming', () {
    test('every split point of a stream gives the same result', () {
      const s = 'x\x1b[>4;2my\x1b[4:0mz\x1b[38:2::1:2:3m\x1b[22mé\x1b';
      final whole = f(s);
      for (var cut = 0; cut <= s.length; cut++) {
        final filt = SgrFilter();
        expect(
          filt.filter(s.substring(0, cut)) + filt.filter(s.substring(cut)),
          whole,
          reason: 'cut $cut',
        );
      }
    });
    test('byte by byte', () {
      const s = '\x1b[>4;2m\x1b[4:0mhi\x1b[22m';
      final filt = SgrFilter();
      expect(s.split('').map(filt.filter).join(), f(s));
    });
    test('an endless unfinished sequence is released, not held', () {
      final filt = SgrFilter(maxSequence: 16);
      final junk = '\x1b[${'1;' * 20}';
      expect(filt.filter(junk), junk);
    });
  });
}
