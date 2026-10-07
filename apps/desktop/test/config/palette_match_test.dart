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
}
