import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/context_line.dart';

/// 6 px per character: widths are easy to reason about.
double _m(String s) => s.runes.length * 6.0;

void main() {
  group('displayPath (UI-A2 §2.3)', () {
    test('POSIX: home becomes ~ only on a whole component', () {
      String d(String p) => displayPath(p, home: '/Users/r', windows: false);
      expect(d('/Users/r'), '~');
      expect(d('/Users/r/work/x'), '~/work/x');
      expect(d('/Users/r2/x'), '/Users/r2/x');
      expect(d('/opt'), '/opt');
      expect(
        displayPath('/Users/r/w', home: '/Users/r/', windows: false),
        '~/w',
      );
      expect(
        displayPath('/Users/R/w', home: '/Users/r', windows: false),
        '/Users/R/w',
      );
    });

    test('Windows: case-insensitive, both separators', () {
      String d(String p) => displayPath(p, home: r'C:\Users\r', windows: true);
      expect(d(r'c:\users\R\src'), r'~\src');
      expect(d(r'C:\Users\r'), '~');
      expect(d(r'D:\src'), r'D:\src');
    });
  });

  group('ellipsis', () {
    test('ellipsizeEnd keeps the start', () {
      expect(ellipsizeEnd('feature-branch', 48, _m), 'feature…');
      expect(ellipsizeEnd('main', 48, _m), 'main');
      expect(ellipsizeEnd('main', 3, _m), '');
    });

    test('ellipsizePath drops middle components first, then characters', () {
      const p = '~/work/shellx/apps/desktop';
      expect(ellipsizePath(p, 999, _m, windows: false), p);
      expect(ellipsizePath(p, 126, _m, windows: false), '~/…/apps/desktop');
      expect(ellipsizePath(p, 66, _m, windows: false), '~/…/desktop');
      expect(
        ellipsizePath(p, 40, _m, windows: false),
        ellipsizeMiddle(p, 40, _m),
      );
      expect(ellipsizePath(r'C:\a\b\c\d', 48, _m, windows: true), r'C:\…\c\d');
    });

    test('ellipsizeMiddle keeps both ends', () {
      expect(ellipsizeMiddle('~/workspace', 36, _m), '~/w…ce');
    });
  });

  group('ellipsis keeps grapheme clusters whole', () {
    // macOS hands out decomposed (NFD) names: "Tài liệu" with combining
    // marks; and emoji joined by ZWJ, and flags of two regional letters.
    const nfd = 'Tài liệu';
    const emoji = '👨‍👩‍👧 dev 🇻🇳🇺🇸 x';

    bool isMark(String cluster) {
      final r = cluster.runes.first;
      return r >= 0x300 && r <= 0x36F;
    }

    void wholeClusters(String text, String result) {
      final original = text.characters.toSet();
      for (final c in result.characters) {
        if (c == '…') continue;
        expect(isMark(c), isFalse, reason: 'orphan mark in "$result"');
        expect(original, contains(c), reason: 'split cluster in "$result"');
      }
    }

    test('ellipsizeEnd never cuts inside a letter or an emoji', () {
      expect(ellipsizeEnd('liệu', 24, _m), 'li…');
      for (final text in [nfd, emoji]) {
        for (var w = 0.0; w <= 120; w += 3) {
          wholeClusters(text, ellipsizeEnd(text, w, _m));
        }
      }
    });

    test('ellipsizeMiddle never leaves a mark or half an emoji', () {
      for (final text in [nfd, emoji]) {
        for (var w = 0.0; w <= 120; w += 3) {
          wholeClusters(text, ellipsizeMiddle(text, w, _m));
        }
      }
    });
  });

  group('layoutContextLine (UI-A2 §2.2)', () {
    test('everything fits', () {
      final l = layoutContextLine(
        branch: 'main',
        path: '~/w',
        ports: [3000],
        width: 168,
        measure: _m,
        windows: false,
      );
      expect(
        (l.branch, l.path, l.morePorts, l.truncated),
        ('main', '~/w', 0, false),
      );
      expect(l.ports, [3000]);
    });

    test('the path is cut in the middle first', () {
      final l = layoutContextLine(
        branch: 'main',
        path: '~/work/shellx/apps/desktop',
        ports: const [],
        width: 168,
        measure: _m,
        windows: false,
      );
      expect(
        (l.branch, l.path, l.truncated),
        ('main', '~/…/apps/desktop', true),
      );
    });

    test('ports keep at most 60 % and are never cut; the rest is +N', () {
      final l = layoutContextLine(
        branch: null,
        path: null,
        ports: [3000, 5173, 8080, 9229, 24678],
        width: 168,
        measure: _m,
        windows: false,
      );
      expect(l.ports, [3000, 5173]);
      expect((l.morePorts, l.truncated), (3, true));
    });

    test('a long branch is cut at the end; no room → the path is dropped', () {
      final l = layoutContextLine(
        branch: 'feature-very-long-name',
        path: '~/w',
        ports: [3000],
        width: 100,
        measure: _m,
        windows: false,
      );
      expect(
        (l.branch, l.path, l.ports.single, l.truncated),
        ('feature…', null, 3000, true),
      );
    });

    test('nothing known → empty', () {
      final l = layoutContextLine(
        branch: null,
        path: null,
        ports: const [],
        width: 168,
        measure: _m,
        windows: false,
      );
      expect(l.isEmpty, isTrue);
    });
  });
}
