import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/shell_escape.dart';

void main() {
  group('posix and fish (A10 D18)', () {
    String e(String s) => escapePath(s, ShellFamily.posix);

    test('plain paths are left alone', () {
      expect(e('/Users/me/a.png'), '/Users/me/a.png');
      expect(e('/tmp/a-b_c.d,e@f+g=h%i:j'), '/tmp/a-b_c.d,e@f+g=h%i:j');
    });

    test('spaces and shell characters get a backslash', () {
      expect(
        e('/Users/me/My Docs/a (1).png'),
        r'/Users/me/My\ Docs/a\ \(1\).png',
      );
      expect(e(r"/tmp/$(rm -rf ~)"), r'/tmp/\$\(rm\ -rf\ ~\)');
      expect(e("/tmp/it's"), r"/tmp/it\'s");
      expect(
        e('/tmp/a;b&c|d>e<f*g?h[i]{j}!k#l\\m"n`o'),
        r'/tmp/a\;b\&c\|d\>e\<f\*g\?h\[i\]\{j\}\!k\#l\\m\"n\`o',
      );
    });

    test('Vietnamese, CJK and emoji stay as they are', () {
      expect(e('/Users/me/Tệp ảnh.png'), r'/Users/me/Tệp\ ảnh.png');
      expect(e('/tmp/日本語😀'), '/tmp/日本語😀');
    });

    test('a tilde is only special at the start', () {
      expect(e('~/a'), r'\~/a');
      expect(e('/tmp/a~b'), '/tmp/a~b');
    });

    test('control characters refuse the whole path', () {
      for (final bad in [
        '/tmp/a\nb',
        '/tmp/a\x00b',
        '/tmp/a\x1bb',
        '/tmp/a\x7fb',
      ]) {
        expect(hasUnsafeCharacters(bad), isTrue);
        expect(() => e(bad), throwsFormatException);
      }
    });
  });

  group('PowerShell and cmd', () {
    test('safe names are bare, others quoted', () {
      expect(
        escapePath(r'C:\Users\me\a.png', ShellFamily.powershell),
        r'C:\Users\me\a.png',
      );
      expect(
        escapePath(r'C:\My Docs\a.png', ShellFamily.powershell),
        r"'C:\My Docs\a.png'",
      );
      expect(
        escapePath(r"C:\it's\a.png", ShellFamily.powershell),
        r"'C:\it''s\a.png'",
      );
      expect(
        escapePath(r'C:\My Docs\a.png', ShellFamily.cmd),
        r'"C:\My Docs\a.png"',
      );
    });
  });

  group('hostile names', () {
    test('posix: leading dash, equals, very long, C1 and separators', () {
      expect(escapePath('-rf', ShellFamily.posix), './-rf');
      expect(escapePath('=ls', ShellFamily.posix), r'\=ls');
      final long = '/tmp/${'a b' * 20000}';
      expect(escapePath(long, ShellFamily.posix).length, long.length + 20000);
      for (final bad in ['/a\u0085b', '/a\u009bb', '/a\u2028b', '/a\u2029b']) {
        expect(() => escapePath(bad, ShellFamily.posix), throwsFormatException);
      }
    });

    test('a newline can never reach a shell in any family', () {
      for (final f in ShellFamily.values) {
        expect(() => escapePath('/a\nb', f), throwsFormatException);
        expect(() => escapePath('/a\rb', f), throwsFormatException);
      }
    });

    test('powershell: comma, at, dollar, backtick, dash, smart quotes', () {
      String e(String s) => escapePath(s, ShellFamily.powershell);
      expect(e('C:\\a,b'), "'C:\\a,b'");
      expect(e(r'C:\$(calc)'), r"'C:\$(calc)'");
      expect(e('C:\\a`b'), "'C:\\a`b'");
      expect(e('-rf'), "'-rf'");
      expect(e('C:\\a\u2019; calc'), "'C:\\a\u2019\u2019; calc'");
    });

    test('cmd: percent and double quote are refused, others quoted', () {
      expect(
        () => escapePath(r'C:\%PATH%', ShellFamily.cmd),
        throwsFormatException,
      );
      expect(
        () => escapePath('C:\\a"b', ShellFamily.cmd),
        throwsFormatException,
      );
      expect(escapePath(r'C:\a&b.png', ShellFamily.cmd), r'"C:\a&b.png"');
    });
  });

  group('review fixes', () {
    String ps(String s) => escapePath(s, ShellFamily.powershell);

    test('powershell: only ASCII is bare, the rest is single-quoted', () {
      expect(
        ps('C:\\x\\a\u201c\$(calc)\u201d'),
        "'C:\\x\\a\u201c\$(calc)\u201d'",
      );
      expect(ps('C:\\a\u00a0b'), "'C:\\a\u00a0b'");
      expect(ps('C:\\a\u2003b'), "'C:\\a\u2003b'");
      expect(ps('\u2013x'), "'\u2013x'");
      expect(ps('\u2014x'), "'\u2014x'");
      expect(ps('C:\\T\u1ec7p.txt'), "'C:\\T\u1ec7p.txt'");
    });

    test('cmd: non-ASCII names are quoted', () {
      expect(
        escapePath('C:\\T\u1ec7p.txt', ShellFamily.cmd),
        '"C:\\T\u1ec7p.txt"',
      );
      expect(escapePath('C:\\a\u00a0b', ShellFamily.cmd), '"C:\\a\u00a0b"');
    });

    test('bidi controls and zero-width characters refuse the drop', () {
      for (final c in [
        '\u202a',
        '\u202b',
        '\u202c',
        '\u202d',
        '\u202e',
        '\u2066',
        '\u2067',
        '\u2068',
        '\u2069',
        '\u200b',
        '\ufeff',
        '\u200e',
        '\u200f',
      ]) {
        for (final f in ShellFamily.values) {
          expect(() => escapePath('/a${c}b', f), throwsFormatException);
        }
      }
    });

    test('a tilde after = or : is escaped too', () {
      expect(escapePath('/a=~b', ShellFamily.posix), r'/a=\~b');
      expect(escapePath('/a:~b', ShellFamily.posix), r'/a:\~b');
    });
  });

  test('several paths end with a space, so typing can go on', () {
    expect(escapePaths(['/a b', '/c'], ShellFamily.posix), r'/a\ b /c ');
    expect(
      () => escapePaths(['/a', '/b\n'], ShellFamily.posix),
      throwsFormatException,
    );
  });

  test('the family follows the shell and the platform', () {
    expect(shellFamilyOf('zsh', windows: false), ShellFamily.posix);
    expect(shellFamilyOf('fish', windows: false), ShellFamily.posix);
    expect(shellFamilyOf('pwsh.exe', windows: true), ShellFamily.powershell);
    expect(shellFamilyOf('cmd.exe', windows: true), ShellFamily.cmd);
    expect(shellFamilyOf('nu', windows: true), ShellFamily.powershell);
    expect(shellFamilyOf('nu', windows: false), ShellFamily.posix);
  });
}
