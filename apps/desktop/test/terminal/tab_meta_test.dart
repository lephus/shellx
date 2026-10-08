import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/tab_meta.dart';

void main() {
  test(
    'a description is one line of at most 120 graphemes without controls',
    () {
      expect(TabMeta.cleanDescription('  a\nb\tc  '), 'a b c');
      expect(TabMeta.cleanDescription('x\x00y\x1b[2J'), 'xy[2J');
      expect(TabMeta.cleanDescription('é' * 200).characters.length, 120);
      expect(
        TabMeta.cleanDescription('👩‍👩‍👧‍👦' * 130).characters.length,
        120,
      );
    },
  );

  test('bidirectional overrides and line separators do not survive', () {
    expect(TabMeta.cleanDescription('a\u202Eb\u2066c\u200Fd\u2028e'), 'abcde');
    expect(TabMeta.cleanDescription('\u202E\n \t'), '');
  });

  test('status wire names round-trip; unknown becomes none', () {
    for (final s in TabStatus.values) {
      expect(TabStatus.fromWire(s.wire), s);
    }
    expect(TabStatus.fromWire('weird'), TabStatus.none);
    expect(TabStatus.fromWire(3), TabStatus.none);
    expect(TabStatus.fromWire(null), TabStatus.none);
  });

  test('toString never shows the description (privacy)', () {
    expect(
      const TabMeta(
        pinned: true,
        description: 'secret',
        status: TabStatus.done,
      ).toString(),
      '…',
    );
  });

  test('sortPinnedFirst keeps the order inside each group', () {
    expect(sortPinnedFirst([1, 2, 3, 4, 5], (id) => id == 2 || id == 4), [
      2,
      4,
      1,
      3,
      5,
    ]);
    expect(sortPinnedFirst([1, 2], (_) => false), [1, 2]);
  });
}
