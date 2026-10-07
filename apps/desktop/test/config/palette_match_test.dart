import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/ui/config/command_palette.dart';

PaletteEntry e(String id, String title, {String? subtitle}) => PaletteEntry(
  id: id,
  title: title,
  subtitle: subtitle,
  kind: PaletteKind.action,
  shortcut: null,
  intent: const DoNothingIntent(),
);

void main() {
  test('folding: case and Vietnamese marks (D33)', () {
    expect(foldForSearch('Chia xuống dưới'), 'chia xuong duoi');
    expect(foldForSearch('Đóng cả TAB'), 'dong ca tab');
    expect(foldForSearch('Tải lại cấu hình'), 'tai lai cau hinh');
    // Decomposed input (combining marks) folds the same way.
    expect(foldForSearch('xuống'), 'xuong');
  });

  test('prefix > word start > inside > subsequence; no match is null', () {
    final prefix = matchScore('chia', 'Chia sang phải')!;
    final word = matchScore('phai', 'Chia sang phải')!;
    final inside = matchScore('ang', 'Chia sang phải')!;
    final sub = matchScore('csp', 'Chia sang phải')!;
    expect(prefix, greaterThan(word));
    expect(word, greaterThan(inside));
    expect(inside, greaterThan(sub));
    expect(matchScore('zz', 'Chia sang phải'), isNull);
    expect(matchScore('', 'anything'), 0);
  });

  test('empty query: recent first, then the original order', () {
    final entries = [e('a', 'A'), e('b', 'B'), e('c', 'C')];
    expect(filterPalette(entries, '', ['c']).map((x) => x.id), ['c', 'a', 'b']);
  });

  test(
    'a query ranks by score, then recency; commands match their text too',
    () {
      final entries = [
        e('split', 'Chia sang phải'),
        e('down', 'Chia xuống dưới'),
        e('lint', 'Lint', subtitle: 'npm run lint'),
      ];
      expect(filterPalette(entries, 'chia xuong', const []).first.id, 'down');
      expect(filterPalette(entries, 'chia', ['down']).map((x) => x.id), [
        'down',
        'split',
      ]);
      expect(filterPalette(entries, 'npm', const []).single.id, 'lint');
    },
  );

  test('chia and chìa rank alike; the highlight covers the mark', () {
    expect(matchScore('chia', 'Chìa khoá'), matchScore('chia', 'Chia khoa'));
    expect(matchScore('chia', 'Chìa khoá'), 4000);
    expect(matchRanges('chia', 'Chìa khoá'), [(0, 4)]);
    // Decomposed: the combining mark stays inside the range.
    expect(matchRanges('chia', 'Chi\u0300a khoa'), [(0, 5)]);
    expect(matchRanges('khoa', 'Chìa khoá'), [(5, 9)]);
    expect(matchRanges('csp', 'Chia sang phải'), [(0, 1), (5, 6), (10, 11)]);
  });

  test('word start: any boundary, later occurrences too', () {
    expect(matchScore('b', 'aab b'), greaterThan(matchScore('b', 'aab')!));
    expect(
      matchScore('run', 'npm-run'),
      greaterThan(matchScore('un', 'npm-run')!),
    );
    expect(matchScore('x', 'a/b_x'), greaterThan(matchScore('x', 'abx')!));
  });

  test('a command text matches as text, never as scattered letters', () {
    final entries = [e('lint', 'Lint', subtitle: 'run the linter now')];
    expect(filterPalette(entries, 'npm', const []), isEmpty);
    expect(filterPalette(entries, 'rnl', const []), isEmpty);
    expect(filterPalette(entries, 'linter', const []).single.id, 'lint');
  });
}
