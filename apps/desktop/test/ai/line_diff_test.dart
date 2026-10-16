import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/ai/ai_off_thread.dart';
import 'package:shellx_desktop/src/ai/line_diff.dart';

void main() {
  test('a line diff: same, removed, added, with line numbers', () {
    final d = computeLineDiff(('a\nb\nc\n', 'a\nB\nc\nd\n'));
    expect(
      [for (final l in d) (l.op, l.text)],
      [
        (DiffOp.same, 'a'),
        (DiffOp.removed, 'b'),
        (DiffOp.added, 'B'),
        (DiffOp.same, 'c'),
        (DiffOp.added, 'd'),
      ],
    );
    expect(d[2].newNo, 2);
    expect(d[1].oldNo, 2);
    expect(diffStat(d), (added: 2, removed: 1));
  });

  test('CRLF and LF read the same (§6 Windows); a new file is all added', () {
    expect(
      computeLineDiff((
        'a\r\nb\r\n',
        'a\nb\n',
      )).every((l) => l.op == DiffOp.same),
      isTrue,
    );
    expect(diffStat(computeLineDiff(('', 'x\ny\n'))), (added: 2, removed: 0));
  });

  test('context: three lines around each change, gaps as null', () {
    final old = [for (var i = 0; i < 20; i++) 'l$i'].join('\n');
    final now = old.replaceFirst('l10', 'L10');
    final shown = withContext(computeLineDiff((old, now)));
    expect(shown.first, isNull);
    expect(shown.last, isNull);
    expect(shown.whereType<DiffLine>().length, 3 + 2 + 3);
  });

  test('long texts go off the UI isolate; short ones never do', () async {
    var trips = 0;
    Future<R> counting<Q, R>(R Function(Q) work, Q input) async {
      trips++;
      return work(input);
    }

    await lineDiff(counting, 'a\n', 'b\n');
    expect(trips, 0);
    final big = List.filled(kInlineDiffLines + 1, 'x').join('\n');
    final d = await lineDiff(counting, big, '$big\ny');
    expect(trips, 1);
    expect(diffStat(d).added, 1);
    expect(inlineOffThread(computeLineDiff, ('a', 'a')), completes);
  });
}
