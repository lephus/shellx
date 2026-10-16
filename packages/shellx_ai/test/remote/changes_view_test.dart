import 'dart:convert';

import 'package:shellx_acp/shellx_acp.dart' show ToolDiff;
import 'package:shellx_ai/remote.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:test/test.dart';

int _jsonBytes(Object? value) => utf8.encode(jsonEncode(value)).length;

/// V2-2b B19: the bodies of `ai.changes`, `ai.diff` and a revert's `confirm`.
void main() {
  test('a view round-trips, with the kinds and counts the panel shows', () {
    const view = AiChangesView(
      scope: 'turn',
      turn: 3,
      files: [
        AiChangedFile(path: 'src/a.ts', kind: 'm', plus: 4, minus: 1),
        AiChangedFile(path: 'logo.png', kind: 'a'),
      ],
      after: ['src/a.ts'],
      first: 1,
      last: 3,
      done: 3,
    );
    final back = AiChangesView.fromJson(decodeBody(encodeChangesView(view))!);
    expect(back.scope, 'turn');
    expect(back.turn, 3);
    expect(
      [for (final f in back.files) (f.path, f.kind, f.plus, f.minus)],
      [('src/a.ts', 'm', 4, 1), ('logo.png', 'a', null, null)],
    );
    expect(back.files.last.binary, isTrue);
    expect(back.after, ['src/a.ts']);
    expect(
      (back.first, back.last, back.done, back.off, back.more),
      (1, 3, 3, null, 0),
    );
  });

  test('a file change reads as the panel letters it', () {
    expect(
      AiChangedFile.of(
        const FileChange(path: 'x', kind: ChangeKind.deleted, added: 0),
      ).kind,
      'd',
    );
    expect(
      AiChangedFile.of(
        const FileChange(path: 'x', kind: ChangeKind.added, added: 2),
      ).kind,
      'a',
    );
  });

  test('a reader keeps what it can and never throws', () {
    final view = AiChangesView.fromJson({
      'scope': 7,
      'files': [
        {'p': 'a', 'k': 'zz'},
        {'k': 'a'},
        'x',
      ],
      'after': ['a', 3],
      'turns': 'no',
      'more': -4,
    });
    expect(view.scope, 'session');
    expect([for (final f in view.files) (f.path, f.kind)], [('a', 'm')]);
    expect(view.after, ['a']);
    expect((view.first, view.last, view.more), (null, null, 0));
  });

  test('ten thousand changed files with long paths fit one body; the rest '
      'is counted (Review Focus 3)', () {
    final paths = [for (var i = 0; i < 10000; i++) 'src/${'d' * 300}/f$i.dart'];
    final view = AiChangesView(
      scope: 'session',
      files: [
        for (final p in paths)
          AiChangedFile(path: p, kind: 'm', plus: 1, minus: 1),
      ],
      after: [for (var i = 0; i < paths.length; i += 2) paths[i]],
    );
    final body = encodeChangesView(view);
    expect(body.length, lessThanOrEqualTo(kAiRecordBytes));
    final back = AiChangesView.fromJson(decodeBody(body)!);
    expect(back.files.length, lessThanOrEqualTo(kAiChangesMax));
    expect(back.files.length + back.more, 10000);
    final kept = {for (final f in back.files) f.path};
    expect(back.after.every(kept.contains), isTrue);
  });

  test('one file\'s diff: changed, new and deleted', () {
    expect(
      aiFileDiffBody(path: 'a', oldText: '1\n2\n3\n', newText: '1\n2\nX\n'),
      {'path': 'a', 'old': '1\n2\n3', 'new': '1\n2\nX', 'plus': 1, 'minus': 1},
    );
    expect(aiFileDiffBody(path: 'b', newText: 'hi\n'), {
      'path': 'b',
      'new': 'hi\n',
      'created': true,
      'plus': 1,
      'minus': 0,
    });
    final gone = aiFileDiffOf(
      aiFileDiffBody(path: 'c', oldText: 'x\ny\n', newText: '')!,
    )!;
    expect((gone.oldText, gone.newText, gone.minus), ('x\ny', '', 2));
  });

  test('a file of more than a megabyte of quotes and control characters '
      'still fits one body (Review Focus 3)', () {
    final old = '"\x01\\x\n' * (1 << 18); // 2.6 times its size once escaped
    final next = 'A${old.substring(1, old.length - 1)}B';
    final body = aiFileDiffBody(path: 'big.txt', oldText: old, newText: next)!;
    expect(_jsonBytes(body), lessThanOrEqualTo(kAiRecordBytes));
    expect(body['cut'], isTrue);
    expect(aiFileDiffOf(body)!.cut, isTrue);
  });

  test('the phone reads a diff body; binary and missing are no region', () {
    final region = aiFileDiffOf({
      'path': 'a.ts',
      'old': 'a',
      'new': 'b',
      'plus': 1,
      'minus': 1,
    })!;
    expect((region.path, region.oldText, region.newText), ('a.ts', 'a', 'b'));
    expect(aiFileDiffOf({'path': 'x.png', 'binary': true}), isNull);
    expect(aiFileDiffOf({'path': 'y', 'missing': true}), isNull);
    expect(aiFileDiffOf(const {}), isNull);
  });

  test('a confirm lists what fits of ten thousand touched files', () {
    final touched = [for (var i = 0; i < 10000; i++) 'src/${'t' * 100}/$i'];
    final body = encodeRevertConfirm(
      touched: touched,
      someClean: true,
      total: 12000,
    );
    expect(body.length, lessThanOrEqualTo(kAiRecordBytes));
    final question = AiRevertConfirm.fromJson(decodeBody(body)!);
    expect(question.touchedCount, 10000);
    expect(question.touched, isNotEmpty);
    expect((question.someClean, question.files), (true, 12000));
  });

  test(
    'the region of the mirror and of the diff page are one and the same',
    () {
      const d = ToolDiff(path: 'a', oldText: 'x\ny\n', newText: 'x\nz\n');
      expect(
        aiDiffRegion(d, 4096),
        aiTextDiffRegion(
          path: 'a',
          oldText: 'x\ny\n',
          newText: 'x\nz\n',
          side: 4096,
        ),
      );
    },
  );

  test('nothing of a view or a question is printed', () {
    const view = AiChangesView(
      scope: 'turn',
      files: [AiChangedFile(path: 'secret.ts', kind: 'm')],
    );
    expect(view.toString(), isNot(contains('secret')));
    expect(view.files.single.toString(), isNot(contains('secret')));
    expect(
      const AiRevertConfirm(touched: ['secret.ts']).toString(),
      isNot(contains('secret')),
    );
  });
}
