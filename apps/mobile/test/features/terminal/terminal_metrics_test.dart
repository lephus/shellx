import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/features/terminal/presentation/widgets/pinch_zoom.dart';
import 'package:shellx_mobile/features/terminal/presentation/terminal_metrics.dart';

void main() {
  group('measureTerminalGrid', () {
    // flutter_test renders every glyph as a square 1em wide.
    final style = shellxTerminalStyle(10);

    test('fits whole cells', () {
      // Cell = 10 px wide, 12 px tall (line height 1.2).
      expect(measureTerminalGrid(const Size(805, 250), style, TextScaler.noScaling), (cols: 80, rows: 20));
    });

    test('Review Focus 4: null when not even one cell fits', () {
      expect(measureTerminalGrid(const Size(805, 0), style, TextScaler.noScaling), isNull);
      expect(measureTerminalGrid(const Size(5, 400), style, TextScaler.noScaling), isNull);
    });

    test('text scaling makes cells bigger', () {
      expect(measureTerminalGrid(const Size(800, 240), style, const TextScaler.linear(2)), (cols: 40, rows: 10));
    });
  });

  group('PinchZoomTracker', () {
    test('spreading two fingers to twice the distance doubles the size', () {
      final tracker = PinchZoomTracker();
      tracker.down(1, const Offset(100, 100), 14);
      tracker.down(2, const Offset(200, 100), 14);
      expect(tracker.move(2, const Offset(300, 100)), 28);
    });

    test('rounds to 0.5 steps, clamps to 8..32, ignores sub-step moves', () {
      final tracker = PinchZoomTracker();
      tracker.down(1, Offset.zero, 14);
      tracker.down(2, const Offset(100, 0), 14);
      expect(tracker.move(2, const Offset(101, 0)), isNull); // 14.14 → 14.0
      expect(tracker.move(2, const Offset(104, 0)), 14.5); // 14.56 → 14.5
      expect(tracker.move(2, const Offset(1000, 0)), 32);
      expect(tracker.move(2, const Offset(1, 0)), 8);
    });

    test('one finger never zooms; a third finger pauses zooming', () {
      final tracker = PinchZoomTracker();
      tracker.down(1, Offset.zero, 14);
      expect(tracker.move(1, const Offset(500, 0)), isNull);
      tracker.down(2, const Offset(600, 0), 14);
      tracker.down(3, const Offset(50, 50), 14);
      expect(tracker.move(2, const Offset(900, 0)), isNull);
      tracker.up(3);
      // New baseline: pointer 1 at (500, 0), pointer 2 at (900, 0) → 400 px.
      expect(tracker.move(2, const Offset(1300, 0)), 28); // 800 px → ×2
    });
  });

  testWidgets('PinchToZoom reports the pinched font size', (tester) async {
    final sizes = <double>[];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: PinchToZoom(
          fontSize: 14,
          onFontSize: sizes.add,
          child: const SizedBox.expand(),
        ),
      ),
    );
    final first = await tester.startGesture(const Offset(300, 300), pointer: 1);
    final second = await tester.startGesture(const Offset(400, 300), pointer: 2);
    await second.moveTo(const Offset(500, 300));
    await first.up();
    await second.up();
    expect(sizes.last, 28);
  });
}
