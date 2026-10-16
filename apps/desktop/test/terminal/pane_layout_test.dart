import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';

/// 1 | (2 / 3): split 1 right, then split 2 down.
PaneNode tee() => splitPane(
  splitPane(const PaneLeaf(1), 1, 2, SplitAxis.row),
  2,
  3,
  SplitAxis.column,
);

void main() {
  test('split puts the new pane after the target, ratio 0.5 (D3)', () {
    final t = tee();
    expect(paneIds(t), [1, 2, 3]);
    expect(
      t,
      const PaneSplit(
        axis: SplitAxis.row,
        ratio: 0.5,
        first: PaneLeaf(1),
        second: PaneSplit(
          axis: SplitAxis.column,
          ratio: 0.5,
          first: PaneLeaf(2),
          second: PaneLeaf(3),
        ),
      ),
    );
    expect(splitPane(t, 99, 4, SplitAxis.row), t); // unknown target
  });

  test('remove lets the sibling take the place; last leaf → null', () {
    expect(paneIds(removePane(tee(), 2)!), [1, 3]);
    expect(removePane(tee(), 1), isA<PaneSplit>());
    expect(paneIds(removePane(tee(), 1)!), [2, 3]);
    expect(removePane(const PaneLeaf(1), 1), isNull);
    expect(removePane(tee(), 42), tee());
  });

  test('sibling leaf is the first leaf of the other branch (D8)', () {
    expect(siblingLeaf(tee(), 1), 2);
    expect(siblingLeaf(tee(), 3), 2);
    expect(siblingLeaf(tee(), 2), 3);
    expect(siblingLeaf(const PaneLeaf(1), 1), isNull);
  });

  test('rects in the unit square', () {
    final r = paneRects(tee());
    expect(r[1], const Rect.fromLTRB(0, 0, 0.5, 1));
    expect(r[2], const Rect.fromLTRB(0.5, 0, 1, 0.5));
    expect(r[3], const Rect.fromLTRB(0.5, 0.5, 1, 1));
    expect(splitRect(tee(), '1'), const Rect.fromLTRB(0.5, 0, 1, 1));
    expect(splitRect(tee(), '0'), isNull); // a leaf, not a split
  });

  group('neighbour (D9)', () {
    test('left/right/up/down in a T, no wrap', () {
      final t = tee();
      expect(neighbourPane(t, 2, PaneDirection.left), 1);
      expect(neighbourPane(t, 3, PaneDirection.left), 1);
      expect(neighbourPane(t, 2, PaneDirection.down), 3);
      expect(neighbourPane(t, 3, PaneDirection.up), 2);
      expect(neighbourPane(t, 1, PaneDirection.left), isNull);
      expect(neighbourPane(t, 2, PaneDirection.up), isNull);
    });

    test('the pane holding the centre line wins; else MRU on a tie', () {
      // 1's centre y is 0.5: [0.5, 1) holds it → 3 (half-open intervals).
      expect(neighbourPane(tee(), 1, PaneDirection.right), 3);
      // Move the inner divider: 2 now spans y 0..0.7 and holds 0.5.
      final moved = withRatio(tee(), '1', 0.7);
      expect(neighbourPane(moved, 1, PaneDirection.right), 2);
    });

    test('2×2 grid moves straight', () {
      var g = splitPane(const PaneLeaf(1), 1, 2, SplitAxis.row);
      g = splitPane(g, 1, 3, SplitAxis.column);
      g = splitPane(g, 2, 4, SplitAxis.column);
      // 1 2
      // 3 4
      expect(neighbourPane(g, 1, PaneDirection.right), 2);
      expect(neighbourPane(g, 3, PaneDirection.right), 4);
      expect(neighbourPane(g, 4, PaneDirection.up), 2);
    });
  });

  test('equalize three columns → 1/3 each; nested axes count max (D11)', () {
    var c = splitPane(const PaneLeaf(1), 1, 2, SplitAxis.row);
    c = splitPane(c, 2, 3, SplitAxis.row);
    final e = equalized(c) as PaneSplit;
    expect(e.ratio, closeTo(1 / 3, 1e-9));
    expect((e.second as PaneSplit).ratio, 0.5);
    final rects = paneRects(e);
    for (final id in [1, 2, 3]) {
      expect(rects[id]!.width, closeTo(1 / 3, 1e-9));
    }
    expect(paneSpan(tee(), SplitAxis.row), 2);
    expect(paneSpan(tee(), SplitAxis.column), 2);
    final only = equalizedAt(withRatio(c, '', 0.8), '1');
    expect((only as PaneSplit).ratio, 0.8); // root untouched
  });

  test(
    'withRatio clamps to [0.05, 0.95]; a path to a leaf changes nothing',
    () {
      expect((withRatio(tee(), '', 0.99) as PaneSplit).ratio, 0.95);
      expect((withRatio(tee(), '', -1) as PaneSplit).ratio, 0.05);
      expect(withRatio(tee(), '0', 0.3), tee());
      expect(nodeAt(tee(), '10'), const PaneLeaf(2));
      expect(nodeAt(tee(), '00'), isNull);
    },
  );

  test('nearest ancestor split of an axis (D12)', () {
    expect(ancestorSplit(tee(), 3, SplitAxis.column), '1');
    expect(ancestorSplit(tee(), 3, SplitAxis.row), '');
    expect(ancestorSplit(tee(), 1, SplitAxis.column), isNull);
    expect(ancestorSplit(const PaneLeaf(1), 1, SplitAxis.row), isNull);
  });

  group('splitExtents (device-pixel snapping, divider from the second)', () {
    for (final dpr in [1.0, 1.25, 2.0]) {
      test('dpr $dpr: the first extent lands on a device pixel; the three '
          'parts fill the extent exactly', () {
        for (final extent in [300.0, 641.6, 1099.2]) {
          for (final ratio in [0.05, 0.333, 0.5, 0.71, 0.95]) {
            final (first, second) = splitExtents(extent, ratio, 1, dpr);
            final device = first * dpr;
            expect(device, closeTo(device.roundToDouble(), 1e-9));
            expect(
              (first - extent * ratio).abs(),
              lessThanOrEqualTo(0.5 / dpr + 1e-9),
            );
            expect(first + 1 + second, closeTo(extent, 1e-9));
          }
        }
      });
    }

    test('never negative, even in a box smaller than the divider', () {
      expect(splitExtents(0.5, 0.5, 1, 1), (0.0, 0.0));
      final (a, b) = splitExtents(10, 0.99, 1, 1);
      expect(a + b, 9);
      expect(b, greaterThanOrEqualTo(0));
    });

    test('splitPixelSize walks the same snapped extents', () {
      const tree = PaneSplit(
        axis: SplitAxis.row,
        ratio: 0.333,
        first: PaneLeaf(1),
        second: PaneSplit(
          axis: SplitAxis.column,
          ratio: 0.5,
          first: PaneLeaf(2),
          second: PaneLeaf(3),
        ),
      );
      const area = Size(1000, 601);
      expect(splitPixelSize(tree, '', area, 1, 1), area);
      // 333 | 1 | 666; then 300.5 rounds to 301, 1, 299.
      expect(splitPixelSize(tree, '1', area, 1, 1), const Size(666, 601));
      expect(splitPixelSize(tree, '0', area, 1, 1), isNull);
      expect(panePixelSizes(tree, area, 1, 1), {
        1: const Size(333, 601),
        2: const Size(666, 301),
        3: const Size(666, 299),
      });
    });
  });

  test('replaceLeaf swaps one leaf, keeps shape and ratios (A8 D22)', () {
    const tree = PaneSplit(
      axis: SplitAxis.row,
      ratio: 0.3,
      first: PaneLeaf(1),
      second: PaneSplit(
        axis: SplitAxis.column,
        ratio: 0.6,
        first: PaneLeaf(2),
        second: PaneLeaf(3),
      ),
    );
    expect(
      replaceLeaf(tree, 2, 9),
      const PaneSplit(
        axis: SplitAxis.row,
        ratio: 0.3,
        first: PaneLeaf(1),
        second: PaneSplit(
          axis: SplitAxis.column,
          ratio: 0.6,
          first: PaneLeaf(9),
          second: PaneLeaf(3),
        ),
      ),
    );
    expect(replaceLeaf(tree, 7, 9), tree);
  });
}
