import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ui/ai/ai_timeline.dart';
import 'package:shellx_desktop/src/ui/ai/ai_tool_card.dart';

import '../../support/ai_fakes.dart';
import '../../support/ai_parts.dart';

/// I-5 and M-4 of the final review, in the pieces: how a long text is cut
/// for display, and how Claude's fence around a command result comes off.
void main() {
  final at = DateTime(2026, 10, 14, 9);

  group('aiCapLine', () {
    test('a line of up to 2 000 characters stays as it is', () {
      expect(aiCapLine(''), '');
      expect(aiCapLine('a' * 2000), 'a' * 2000);
    });

    test('a longer line is cut at 2 000 characters with "…"', () {
      expect(aiCapLine('a' * 2001), '${'a' * 2000}…');
      expect(aiCapLine('b' * (1 << 20)), '${'b' * 2000}…');
    });

    test('a surrogate pair is never cut in two (it cannot be drawn)', () {
      // U+1F600 is two UTF-16 units, the first at index 1999.
      final line = '${'a' * 1999}\u{1F600}${'b' * 20}';
      expect(line.length, 2021);
      expect(aiCapLine(line), '${'a' * 1999}…');
      // Not on the boundary: the pair stays whole.
      final fits = '${'a' * 1998}\u{1F600}${'b' * 20}';
      expect(aiCapLine(fits), '${'a' * 1998}\u{1F600}…');
    });
  });

  group('aiOutputOf', () {
    List<String> lines(String s) => s.isEmpty ? [''] : s.split('\n');

    test('an empty text, a short one and one with a trailing newline are '
        'whole', () {
      final empty = aiOutputOf('');
      expect(empty.head, '');
      expect(empty.tail, isNull);
      expect(empty.lines, 1);
      final short = aiOutputOf('a\nb\nc');
      expect(
        (short.head, short.tail, short.hidden, short.lines),
        ('a\nb\nc', null, 0, 3),
      );
      final ended = aiOutputOf('a\nb\n');
      expect(ended.head, 'a\nb\n', reason: 'the last line is empty');
      expect(ended.lines, 3);
    });

    test('over 400 lines the first 200 and the last 200 stay', () {
      String text(int n) => [for (var i = 0; i < n; i++) 'line $i'].join('\n');
      final out = aiOutputOf(text(1000));
      expect(out.lines, 1000);
      expect(out.hidden, 600);
      expect(lines(out.head), hasLength(200));
      expect(out.head, startsWith('line 0\n'));
      expect(lines(out.head).last, 'line 199');
      expect(lines(out.tail!), hasLength(200));
      expect(lines(out.tail!).first, 'line 800');
      expect(out.tail, endsWith('line 999'));
      // 400 lines are whole; one more hides one.
      expect(aiOutputOf(text(400)).tail, isNull);
      expect(aiOutputOf(text(400)).head, text(400));
      expect(aiOutputOf(text(401)).hidden, 1);
    });

    test('a megabyte on one line is its first 2 000 characters', () {
      final out = aiOutputOf('a' * (1 << 20));
      expect(out.head, '${'a' * 2000}…');
      expect(out.tail, isNull);
      expect((out.hidden, out.lines), (0, 1));
    });

    test('the characters are capped too: about 32 KB of the ends stay', () {
      final text = [
        for (var i = 0; i < 100; i++) 'row $i ${'x' * 994}',
      ].join('\n');
      expect(text.length, greaterThan(100 * 1000));
      final out = aiOutputOf(text);
      expect(out.tail, isNotNull);
      expect(out.head.length + out.tail!.length, lessThanOrEqualTo(32 * 1024));
      expect(out.head.length + out.tail!.length, greaterThan(28 * 1024));
      expect(
        lines(out.head).length + out.hidden + lines(out.tail!).length,
        out.lines,
        reason: 'nothing is lost or counted twice',
      );
      expect(out.head, startsWith('row 0 '));
      expect(out.tail, contains('row 99 '));
      // Each end is whole lines.
      expect(lines(out.head).last, endsWith('x' * 994));
      expect(lines(out.tail!).first, startsWith('row '));
    });

    test('lines with nothing between them are never left out: a text a bit '
        'over the budget, in a few lines, hides what it must and no more', () {
      final text = [
        for (var i = 0; i < 10; i++) 'k$i ${'y' * 4000}',
      ].join('\n');
      final out = aiOutputOf(text);
      // Each line is cut at 2 000: 10 lines of 2 002 are 20 KB, whole.
      expect(out.tail, isNull);
      expect(lines(out.head), hasLength(10));
      expect(lines(out.head).every((l) => l.length <= 2001), isTrue);
    });

    test('"Show all" gets every line, made once', () {
      final out = aiOutputOf('a\nb\nc');
      expect(out.allLines, ['a', 'b', 'c']);
      expect(identical(out.allLines, out.allLines), isTrue);
    });
  });

  group('aiCapText', () {
    String marker(int n) => '[$n left out]';

    test('a short text is itself', () {
      expect(aiCapText('', marker), '');
      expect(aiCapText('one\ntwo', marker), 'one\ntwo');
    });

    test('the middle of a long text is a line that counts what it left '
        'out', () {
      final text = [
        for (var i = 0; i < 5000; i++) 'log $i ${'z' * 80}',
      ].join('\n');
      final out = aiCapText(text, marker);
      expect(out.length, lessThanOrEqualTo(32 * 1024 + 40));
      final parts = out.split('\n');
      expect(parts.first, startsWith('log 0 '));
      expect(parts.last, startsWith('log 4999 '));
      final at = parts.indexWhere((l) => l.startsWith('['));
      expect(at, greaterThan(100));
      expect(parts[at], '[${5000 - at - (parts.length - at - 1)} left out]');
    });

    test('one huge line is cut, with nothing counted', () {
      expect(aiCapText('c' * 50000, marker), '${'c' * 2000}…');
    });
  });

  group('aiUnfence', () {
    test('the recorded result of Claude\'s Bash tool', () {
      expect(aiUnfence('```console\nhello.txt\n```'), 'hello.txt');
    });

    test('a result of several lines, and one with text after the fence', () {
      expect(aiUnfence('```console\na\nb\n\nc\n```'), 'a\nb\n\nc');
      expect(aiUnfence('```console\na\n```\n'), 'a');
      expect(aiUnfence('```console\na\n```  \n\n'), 'a');
    });

    test('no output at all is no text', () {
      expect(aiUnfence('```console\n```'), '');
      expect(aiUnfence('```console\n\n```'), '');
    });

    test('any info string, none, and longer and tilde fences', () {
      expect(aiUnfence('```\nx\n```'), 'x');
      expect(aiUnfence('```bash\nx\n```'), 'x');
      expect(aiUnfence('~~~\nx\n~~~'), 'x');
      // The agent made the fence longer than the one inside.
      expect(aiUnfence('````console\n```js\nx\n```\n````'), '```js\nx\n```');
    });

    test('text that is not wrapped in one fence stays as it is', () {
      for (final text in [
        '',
        'plain',
        'two\nlines',
        '```console\nno end',
        '```js\ncode```',
        'before\n```console\nx\n```',
        '```console\nx\n```\nafter',
        ' ```console\nx\n```',
        '```',
        '``',
      ]) {
        expect(aiUnfence(text), text, reason: text);
      }
    });

    test('a fence line inside it would close it early: this was not one '
        'wrapper, and it stays', () {
      const two = '```a\nx\n```\n\n```b\ny\n```';
      expect(aiUnfence(two), two);
    });
  });

  testWidgets('an output is prepared once per revision of its call, not '
      'whenever its card is built (ANSI, fence, split, join)', (t) async {
    final runtime = partRuntime(FakeAiRuntimes(const FakeScenario()));
    final s = runtime.state..beginTurn([const TextBlock('go')], at);
    await pumpAiPart(t, const AiTimeline(), runtime: runtime);
    await t.pump();
    AiToolCard.debugOutputPreps = 0;
    ToolCallStarted started(String text) => ToolCallStarted(
      'x',
      ToolCallFields(
        title: 'make',
        kind: ToolKind.execute,
        status: ToolCallStatus.completed,
        content: [ToolContentBlock(TextBlock(text))],
      ),
    );
    s.applyUpdate(started('\x1B[1mone\x1B[0m'), at);
    await t.pump();
    await t.pump();
    expect(find.textContaining('one'), findsWidgets);
    expect(AiToolCard.debugOutputPreps, 1);
    // Close it, open it, build the frames again: nothing is made again.
    final header = find.descendant(
      of: find.byType(AiToolCard),
      matching: find.byType(InkWell),
    );
    await t.tap(header.first);
    await t.pump();
    await t.tap(header.first);
    await t.pump();
    for (var i = 0; i < 3; i++) {
      s.touch();
      await t.pump(const Duration(seconds: 1));
    }
    expect(find.textContaining('one'), findsWidgets);
    expect(AiToolCard.debugOutputPreps, 1);
    // The call is updated: its new output is prepared, once.
    s.applyUpdate(started('two'), at);
    await t.pump();
    await t.pump();
    expect(find.textContaining('two'), findsWidgets);
    expect(AiToolCard.debugOutputPreps, 2);
  });
}
