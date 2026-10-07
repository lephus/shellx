import 'package:shellx_core/src/util/terminal_links.dart';
import 'package:test/test.dart';

List<String> urls(String text) => [for (final l in findLinks(text)) l.target];

List<(String, int?, int?)> paths(String text) => [
  for (final l in findLinks(text, paths: true))
    if (l.kind == TerminalLinkKind.path) (l.target, l.line, l.column),
];

void main() {
  group('URLs (A10 D6)', () {
    test('plain, with query, sentence punctuation is not part of it', () {
      expect(urls('see https://example.com/a?b=1.'), [
        'https://example.com/a?b=1',
      ]);
      expect(urls('(https://example.com/x), and "http://a.b/c";'), [
        'https://example.com/x',
        'http://a.b/c',
      ]);
      expect(urls('**https://example.com**'), ['https://example.com']);
    });

    test('a closing bracket that closes one inside stays', () {
      expect(urls('https://en.wikipedia.org/wiki/Dart_(language)'), [
        'https://en.wikipedia.org/wiki/Dart_(language)',
      ]);
      expect(urls('[x](https://example.com/a)'), ['https://example.com/a']);
    });

    test('only http and https; no host, no link', () {
      expect(urls('ftp://x.y file:///etc/passwd javascript:alert(1)'), isEmpty);
      expect(urls('https:// http://'), isEmpty);
    });

    test('IPv6, ports, unicode paths, case-insensitive scheme', () {
      expect(urls('HTTP://[::1]:8080/x'), ['HTTP://[::1]:8080/x']);
      expect(urls('https://vi.wikipedia.org/wiki/Việt_Nam'), [
        'https://vi.wikipedia.org/wiki/Việt_Nam',
      ]);
    });

    test('longer than 2048 is not a link', () {
      expect(urls('https://a.b/${'x' * 2100}'), isEmpty);
    });

    test('linkAt answers for the characters of the link only', () {
      const text = 'go to https://example.com now';
      expect(linkAt(text, 5), isNull);
      expect(linkAt(text, 6)!.target, 'https://example.com');
      expect(linkAt(text, 24)!.target, 'https://example.com');
      expect(linkAt(text, 25), isNull);
    });
  });

  group('paths (A10 D7)', () {
    test('absolute, home, dot-relative, with a line and column', () {
      expect(paths('open /usr/local/bin/dart now'), [
        ('/usr/local/bin/dart', null, null),
      ]);
      expect(paths('~/work/a.txt:12:3 ./x.dart ../y/z.md'), [
        ('~/work/a.txt', 12, 3),
        ('./x.dart', null, null),
        ('../y/z.md', null, null),
      ]);
      expect(paths('lib/main.dart(42,7): error'), [('lib/main.dart', 42, 7)]);
    });

    test('a trailing full stop is not part of the path', () {
      expect(paths('wrote /tmp/out.txt.'), [('/tmp/out.txt', null, null)]);
    });

    test('words with a slash and no extension are not paths', () {
      expect(paths('and/or yes/no 1/2'), isEmpty);
    });

    test('a URL path is not also a file path', () {
      expect(paths('https://example.com/a/b.txt'), isEmpty);
    });

    test('Windows drive paths', () {
      expect(paths(r'at C:\Users\Nguyễn\a.txt:9'), [
        (r'C:\Users\Nguyễn\a.txt', 9, null),
      ]);
    });

    test('toString never shows the target', () {
      expect(
        findLinks('https://example.com').single.toString(),
        isNot(contains('example')),
      );
    });
  });

  group('OSC 8 targets (A10 D10)', () {
    test('http and https only, bounded, no controls', () {
      expect(isSafeHyperlinkUri('https://example.com/a'), isTrue);
      expect(isSafeHyperlinkUri('javascript:alert(1)'), isFalse);
      expect(isSafeHyperlinkUri('file:///etc/passwd'), isFalse);
      expect(isSafeHyperlinkUri('https://example.com/\n'), isFalse);
      expect(isSafeHyperlinkUri('https://a.b/${'x' * 2100}'), isFalse);
      expect(isSafeHyperlinkUri('//example.com'), isFalse);
    });

    test(
      'visible text that is the address, or on its host, needs no question',
      () {
        expect(
          hyperlinkTextMatches(
            'https://example.com/a',
            'https://example.com/a',
          ),
          isTrue,
        );
        expect(
          hyperlinkTextMatches(
            'https://example.com/b',
            'https://example.com/a',
          ),
          isTrue,
        );
        expect(
          hyperlinkTextMatches('click here', 'https://example.com/a'),
          isFalse,
        );
        expect(
          hyperlinkTextMatches('https://paypal.com', 'https://evil.example'),
          isFalse,
        );
      },
    );

    test(
      'curly quotes and CJK full stop are trimmed like other punctuation',
      () {
        expect(urls('see https://example.com/a”'), ['https://example.com/a']);
        expect(urls('see https://example.com/a‘'), ['https://example.com/a']);
        expect(urls('see https://example.com/a’'), ['https://example.com/a']);
        expect(urls('see https://example.com/a“'), ['https://example.com/a']);
        expect(urls('see https://example.com/a。'), ['https://example.com/a']);
      },
    );

    test('200k-char hostile input finishes in reasonable time (< 50 ms)', () {
      final stopwatch = Stopwatch()..start();
      final huge = 'https://a.b/${'x' * 2000})))))))))))))))))))))))))))))))))';
      final result = findLinks(huge);
      stopwatch.stop();
      expect(result, isNotEmpty);
      expect(stopwatch.elapsedMilliseconds, lessThan(50));
    });

    test('200k closing parens finishes in reasonable time', () {
      final stopwatch = Stopwatch()..start();
      final text = 'https://example.com${')' * 200000}';
      final result = findLinks(text);
      stopwatch.stop();
      expect(result, isNotEmpty);
      expect(stopwatch.elapsedMilliseconds, lessThan(50));
    });
  });

  group('path performance', () {
    test('200k-char path finishes in reasonable time', () {
      final stopwatch = Stopwatch()..start();
      final text = '/a${'.' * 200000}';
      findLinks(text, paths: true);
      stopwatch.stop();
      // Should either find one link or none, but not hang
      expect(stopwatch.elapsedMilliseconds, lessThan(50));
    });
  });
}
