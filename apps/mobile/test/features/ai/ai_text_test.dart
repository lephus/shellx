import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_mobile/features/ai/domain/ai_text.dart';

import '../../support/fakes.dart';

/// V2-2 D6 and §5.2: diff lines and markdown blocks.
void main() {
  test('a diff region: shared lines are context, the middle is removed then added', () {
    expect(
      diffLines('a\nb\nc\nd', 'a\nB\nC\nd'),
      [
        (mark: ' ', text: 'a'),
        (mark: '-', text: 'b'),
        (mark: '-', text: 'c'),
        (mark: '+', text: 'B'),
        (mark: '+', text: 'C'),
        (mark: ' ', text: 'd'),
      ],
    );
    expect(diffLines(null, 'x\ny'), [(mark: '+', text: 'x'), (mark: '+', text: 'y')]);
    expect(diffLines('same', 'same'), [(mark: ' ', text: 'same')]);
  });

  test('markdown blocks split at blank lines, never inside a code fence', () {
    expect(markdownBlocks('# T\n\nText\nmore\n\n```\ncode\n\ncode2\n```\n\nend'), [
      '# T',
      'Text\nmore',
      '```\ncode\n\ncode2\n```',
      'end',
    ]);
    expect(markdownBlocks(''), isEmpty);
  });

  group('diff lines, edges', () {
    test('nothing on a side', () {
      expect(diffLines('', ''), isEmpty);
      expect(diffLines('a\nb', ''), [(mark: '-', text: 'a'), (mark: '-', text: 'b')]);
      expect(diffLines('', 'a'), [(mark: '+', text: 'a')]);
      expect(diffLines(null, ''), isEmpty);
    });

    test('a final newline does not make a line: the desktop counts plus and minus the same way', () {
      expect(diffLines(null, 'x\ny\n'), [(mark: '+', text: 'x'), (mark: '+', text: 'y')]);
      expect(diffLines('a\nb\n', 'a\nc\n'), [
        (mark: ' ', text: 'a'),
        (mark: '-', text: 'b'),
        (mark: '+', text: 'c'),
      ]);
    });

    test('a blank line in the text is a line', () {
      expect(diffLines('a\n\nb', 'a\n\nB'), [
        (mark: ' ', text: 'a'),
        (mark: ' ', text: ''),
        (mark: '-', text: 'b'),
        (mark: '+', text: 'B'),
      ]);
    });

    test('Windows line endings are not part of a line (a new file keeps its CRLF on the wire)', () {
      expect(diffLines(null, 'x\r\ny\r\n'), [(mark: '+', text: 'x'), (mark: '+', text: 'y')]);
      expect(diffLines('a\r\nb', 'a\r\nB'), [
        (mark: ' ', text: 'a'),
        (mark: '-', text: 'b'),
        (mark: '+', text: 'B'),
      ]);
      // One side with CRLF and the other without: the same line is the same line.
      expect(diffLines('a\r\nb', 'a\nB'), [
        (mark: ' ', text: 'a'),
        (mark: '-', text: 'b'),
        (mark: '+', text: 'B'),
      ]);
    });

    test('lines that repeat at both ends do not run into each other', () {
      // "a" is the whole shared start and the whole shared end of the second diff.
      expect(diffLines('a', 'a\na'), [(mark: ' ', text: 'a'), (mark: '+', text: 'a')]);
      expect(diffLines('a\na', 'a'), [(mark: ' ', text: 'a'), (mark: '-', text: 'a')]);
      expect(diffLines('x\nb\nx', 'x\nx'), [
        (mark: ' ', text: 'x'),
        (mark: '-', text: 'b'),
        (mark: ' ', text: 'x'),
      ]);
    });

    test('the region the desktop really sends: context around the change, and counts that agree', () {
      final ai = FakeAiSession('s1');
      final before = [for (var i = 1; i <= 20; i++) 'line $i'];
      final after = [...before]..replaceRange(9, 10, ['line 10 changed', 'line 10b']);
      ai.desktop.applyUpdate(
        SessionUpdate.fromJson({
          'sessionUpdate': 'tool_call',
          'toolCallId': 'c1',
          'kind': 'edit',
          'title': 'Edit',
          'content': [
            {'type': 'diff', 'path': '/p/a.ts', 'oldText': before.join('\n'), 'newText': after.join('\n')},
          ],
        }),
        DateTime(2026, 10, 14),
      );
      ai.sync();
      final diff = (ai.mirror.items.single as MirrorTool).diffs.single;
      final lines = diffLines(diff.oldText, diff.newText);
      expect(
        [for (final l in lines) '${l.mark}${l.text}'],
        [
          ' line 7',
          ' line 8',
          ' line 9',
          '-line 10',
          '+line 10 changed',
          '+line 10b',
          ' line 11',
          ' line 12',
          ' line 13',
        ],
      );
      // The numbers the desktop put on the card are what the lines say.
      expect(lines.where((l) => l.mark == '+'), hasLength(diff.plus));
      expect(lines.where((l) => l.mark == '-'), hasLength(diff.minus));
    });

    test('a new file from the desktop: every line added, as many as it counted', () {
      final ai = FakeAiSession('s1');
      ai.desktop.applyUpdate(
        SessionUpdate.fromJson({
          'sessionUpdate': 'tool_call',
          'toolCallId': 'c1',
          'kind': 'edit',
          'content': [
            {'type': 'diff', 'path': '/p/new.ts', 'newText': 'one\ntwo\nthree\n'},
          ],
        }),
        DateTime(2026, 10, 14),
      );
      ai.sync();
      final diff = (ai.mirror.items.single as MirrorTool).diffs.single;
      expect(diff.oldText, isNull);
      final lines = diffLines(diff.oldText, diff.newText);
      expect(lines, hasLength(3));
      expect(lines.every((l) => l.mark == '+'), isTrue);
      expect(lines, hasLength(diff.plus));
    });
  });

  group('markdown blocks, edges', () {
    test('only blank lines, or none', () {
      expect(markdownBlocks('\n\n  \n'), isEmpty);
      expect(markdownBlocks('one line'), ['one line']);
      expect(markdownBlocks('\n\nafter blanks\n\n'), ['after blanks']);
    });

    test('a run of blank lines (with spaces) is one break', () {
      expect(markdownBlocks('a\n\n\n   \n\nb'), ['a', 'b']);
    });

    test('a list and a table stay whole', () {
      expect(markdownBlocks('- a\n- b\n\n| x | y |\n|---|---|\n| 1 | 2 |'), [
        '- a\n- b',
        '| x | y |\n|---|---|\n| 1 | 2 |',
      ]);
    });

    test('a fence still open (the answer is streaming) holds the rest of the text', () {
      expect(markdownBlocks('before\n\n```dart\nfinal a = 1;\n\nfinal b = 2;'), [
        'before',
        '```dart\nfinal a = 1;\n\nfinal b = 2;',
      ]);
    });

    test('a ~~~ fence, an indented fence, and a fence with a language', () {
      expect(markdownBlocks('~~~\na\n\nb\n~~~\n\nend'), ['~~~\na\n\nb\n~~~', 'end']);
      expect(markdownBlocks('  ```js\n  a\n\n  b\n  ```\n\nend'), ['  ```js\n  a\n\n  b\n  ```', 'end']);
    });

    test('a fence inside a longer fence, or of the other kind, is text of the outer one', () {
      expect(markdownBlocks('````md\n```js\na\n\nb\n```\n\nmore\n````\n\nend'), [
        '````md\n```js\na\n\nb\n```\n\nmore\n````',
        'end',
      ]);
      expect(markdownBlocks('~~~\n```\na\n\nb\n~~~\n\nend'), ['~~~\n```\na\n\nb\n~~~', 'end']);
      // A closing fence is made of the same character, as long as the opening one, with nothing after it.
      expect(markdownBlocks('```\na\n```js\n\nb\n```\n\nend'), ['```\na\n```js\n\nb\n```', 'end']);
    });

    test('a line of inline code that starts with backticks is no fence', () {
      expect(markdownBlocks('```a``` is inline\n\nafter'), ['```a``` is inline', 'after']);
      // A tilde fence may have backticks in its info string.
      expect(markdownBlocks('~~~js `a`\ncode\n\nmore\n~~~\n\nend'), ['~~~js `a`\ncode\n\nmore\n~~~', 'end']);
    });

    test('Windows line endings', () {
      expect(markdownBlocks('# T\r\n\r\nText\r\nmore\r\n\r\n```\r\ncode\r\n\r\ncode2\r\n```\r\n\r\nend'), [
        '# T',
        'Text\nmore',
        '```\ncode\n\ncode2\n```',
        'end',
      ]);
    });

    test('while an answer streams, only its last block changes (V2-1 D17)', () {
      const answer =
          '# Plan\n\nFirst **bold** step.\nSecond line.\n\n- one\n- two\n\n```dart\nfinal a = 1;\n\nfinal b = 2;\n```\n\n'
          'Done; see [the docs](https://example.com).\n\n> quote\n\nend';
      List<String>? previous;
      for (var end = 0; end <= answer.length; end++) {
        final blocks = markdownBlocks(answer.substring(0, end));
        if (previous != null && previous.isNotEmpty) {
          // Everything but the last block of the shorter text is still there, as it was.
          expect(
            blocks.take(previous.length - 1).toList(),
            previous.take(previous.length - 1).toList(),
            reason: '$end',
          );
          expect(blocks.length, greaterThanOrEqualTo(previous.length), reason: '$end');
        }
        previous = blocks;
      }
      expect(previous, hasLength(7));
    });
  });
}
