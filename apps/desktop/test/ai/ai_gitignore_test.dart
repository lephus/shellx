import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shellx_desktop/src/ai/ai_gitignore.dart';

/// V2-1 B12: ShellX's own `.gitignore` reading, and the folder walks.
void main() {
  group('AiGitIgnore', () {
    AiGitIgnore rules(String text) => AiGitIgnore()..add('', text);

    test('names match at any depth; a trailing / is folders only', () {
      final r = rules('*.log\nbuild/\n# a comment\n\n');
      expect(r.ignores('a.log', dir: false), isTrue);
      expect(r.ignores('src/deep/a.log', dir: false), isTrue);
      expect(r.ignores('build', dir: true), isTrue);
      expect(r.ignores('app/build', dir: true), isTrue);
      expect(r.ignores('build', dir: false), isFalse);
      expect(r.ignores('a.txt', dir: false), isFalse);
    });

    test('a slash anchors to the file\'s folder; ** spans folders', () {
      final r = rules('/root.txt\ndocs/*.md\n**/gen\nsecret/**\n');
      expect(r.ignores('root.txt', dir: false), isTrue);
      expect(r.ignores('sub/root.txt', dir: false), isFalse);
      expect(r.ignores('docs/a.md', dir: false), isTrue);
      expect(r.ignores('docs/x/a.md', dir: false), isFalse);
      expect(r.ignores('gen', dir: true), isTrue);
      expect(r.ignores('a/b/gen', dir: true), isTrue);
      expect(r.ignores('secret/x/y.txt', dir: false), isTrue);
    });

    test('! takes a file back; the last matching line wins; classes', () {
      final r = rules('*.log\n!keep.log\n[ab].txt\n');
      expect(r.ignores('x.log', dir: false), isTrue);
      expect(r.ignores('keep.log', dir: false), isFalse);
      expect(r.ignores('a.txt', dir: false), isTrue);
      expect(r.ignores('c.txt', dir: false), isFalse);
    });

    test('a deeper .gitignore wins over the root one', () {
      final r = AiGitIgnore()
        ..add('', '*.tmp\n')
        ..add('pkg', '!*.tmp\n');
      expect(r.ignores('a.tmp', dir: false), isTrue);
      expect(r.ignores('pkg/a.tmp', dir: false), isFalse);
    });

    test('a rule that cannot be compiled is skipped, never thrown: the '
        'other lines still count', () {
      // `foo[` ends in `[` (a RangeError once), `[z-a]` is a backwards
      // range, `[` alone has nothing after it.
      for (final bad in ['foo[', '[', '[z-a]', 'x/[', 'a[!']) {
        final r = AiGitIgnore();
        expect(() => r.add('', 'one.txt\n$bad\ntwo.txt\n'), returnsNormally);
        expect(r.ignores('one.txt', dir: false), isTrue, reason: bad);
        expect(r.ignores('two.txt', dir: false), isTrue, reason: bad);
        expect(r.ignores('three.txt', dir: false), isFalse, reason: bad);
      }
    });

    test('a byte order mark at the start of the file is not part of the '
        'first rule (git skips it too)', () {
      final r = rules('\uFEFFbuild/\n*.log\n');
      expect(r.ignores('build', dir: true), isTrue);
      expect(r.ignores('a.log', dir: false), isTrue);
    });
  });

  group('walks', () {
    late Directory root;
    setUp(() {
      root = Directory.systemTemp.createTempSync('ai_walk');
      void file(String rel, [String text = 'x']) => File(p.join(root.path, rel))
        ..createSync(recursive: true)
        ..writeAsStringSync(text);
      file('.gitignore', 'build/\n*.log\n');
      file('.git/HEAD', 'ref');
      file('b.txt');
      file('a.log');
      file('src/main.dart');
      file('build/out.js');
      file('build/inner/deep.js');
    });
    tearDown(() => root.deleteSync(recursive: true));

    test('a folder: folders first, .git hidden, ignored marked', () {
      final top = aiListDir((root.path, ''));
      expect(
        [for (final e in top) e.path],
        ['build', 'src', '.gitignore', 'a.log', 'b.txt'],
      );
      expect(
        [for (final e in top) e.ignored],
        [true, false, false, true, false],
      );
      final inner = aiListDir((root.path, 'build'));
      expect(inner.every((e) => e.ignored), isTrue, reason: 'under build/');
    });

    test('the index keeps what .gitignore keeps and never enters .git', () {
      expect(aiIndexProject(root.path), [
        '.gitignore',
        'b.txt',
        'src/main.dart',
      ]);
    });

    test('a .gitignore that is not valid UTF-8 still counts (a Latin-1 '
        'comment must not drop every rule)', () {
      // "build/\n# caf<E9>\n*.log\n" with a lone 0xE9 byte.
      File(p.join(root.path, '.gitignore')).writeAsBytesSync(
        Uint8List.fromList([
          ...'build/\n# caf'.codeUnits,
          0xE9,
          ...'\n*.log\n'.codeUnits,
        ]),
      );
      final top = aiListDir((root.path, ''));
      expect({
        for (final e in top) e.path: e.ignored,
      }, containsPair('build', true));
      expect(top.firstWhere((e) => e.path == 'a.log').ignored, isTrue);
      expect(aiIndexProject(root.path), isNot(contains('a.log')));
      expect(aiIndexProject(root.path), contains('src/main.dart'));
    });

    test('a rule that cannot be compiled never fails the folder or the '
        'index', () {
      File(
        p.join(root.path, '.gitignore'),
      ).writeAsStringSync('build/\nbroken[\n*.log\n');
      final top = aiListDir((root.path, ''));
      expect(top.firstWhere((e) => e.path == 'build').ignored, isTrue);
      expect(top.firstWhere((e) => e.path == 'a.log').ignored, isTrue);
      expect(aiIndexProject(root.path), [
        '.gitignore',
        'b.txt',
        'src/main.dart',
      ]);
    });
  });
}
