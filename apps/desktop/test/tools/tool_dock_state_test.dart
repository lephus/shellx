import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/tools/tool_dock_state.dart';

const a = 'aaaaaaaaaa', b = 'bbbbbbbbbb', c = 'cccccccccc';

void main() {
  group('ToolDockState', () {
    test('opened adds a chip once and shows it (D4, D5)', () {
      final s = const ToolDockState().opened(a).opened(b).opened(a);
      expect(s.open, isTrue);
      expect(s.tools, [a, b]);
      expect(s.active, a);
    });

    test('without: the chip after shows, else the one before; the last '
        'chip closes the dock (D5, D10)', () {
      final s = const ToolDockState().opened(a).opened(b).opened(c);
      expect(s.activated(b).without(b).active, c);
      expect(s.without(c).active, b);
      expect(s.without(a).active, c, reason: 'not the one on show');
      final last = const ToolDockState(width: 0.6, zoom: true).opened(a);
      final closed = last.without(a);
      expect(
        [closed.open, closed.zoom, closed.tools, closed.width],
        [false, false, <String>[], 0.6],
      );
      expect(s.without('zzzzzzzzzz'), s);
    });

    test('toJson / tryParse round-trip (D14)', () {
      final s = const ToolDockState(width: 0.5).opened(a).opened(b);
      expect(s.toJson(), {
        'open': true,
        'zoom': false,
        'width': 0.5,
        'active': b,
        'tools': [a, b],
      });
      expect(ToolDockState.tryParse(s.toJson()), s);
    });

    test('tryParse repairs, never throws (D14)', () {
      expect(ToolDockState.tryParse(null), isNull);
      expect(ToolDockState.tryParse('x'), isNull);
      final repaired = ToolDockState.tryParse({
        'open': 'yes',
        'zoom': true,
        'width': 3,
        'active': 'nope',
        'tools': [a, a, 'BAD', 7, b],
      })!;
      expect(repaired.open, isFalse);
      expect(repaired.zoom, isTrue);
      expect(repaired.width, kToolDockDefaultWidth);
      expect(repaired.tools, [a, b]);
      expect(repaired.active, a);
      final empty = ToolDockState.tryParse({'open': true, 'zoom': true})!;
      expect([empty.open, empty.zoom, empty.active], [false, false, null]);
    });

    test('toString shows no ids', () {
      expect(
        const ToolDockState().opened(a).toString(),
        'ToolDockState(open: true, zoom: false, tools: 1)',
      );
    });
  });

  group('toolDockLayout (D3, §8)', () {
    final dock = const ToolDockState().opened(a);

    test('closed, not embedded or empty: the panes take everything', () {
      for (final d in [
        null,
        const ToolDockState(),
        dock.copyWith(open: false),
      ]) {
        final l = toolDockLayout(width: 1000, dock: d, embedded: true);
        expect([l.paneWidth, l.showsDock], [1000, false]);
      }
      final off = toolDockLayout(width: 1000, dock: dock, embedded: false);
      expect(off.showsDock, isFalse);
    });

    test('45 % by default, beside the panes and the handle', () {
      final l = toolDockLayout(width: 1000, dock: dock, embedded: true);
      expect(l.dockWidth, 450);
      expect(l.paneWidth, 1000 - kToolDockHandle - 450);
      expect(l.dockLeft, l.paneWidth + kToolDockHandle);
      expect(l.showsHandle, isTrue);
    });

    test('at least 320 px for the dock and 360 px for the panes', () {
      final narrow = toolDockLayout(
        width: 700,
        dock: dock.copyWith(width: 0.1),
        embedded: true,
      );
      expect(narrow.dockWidth, kToolDockMinWidth);
      final wide = toolDockLayout(
        width: 700,
        dock: dock.copyWith(width: 0.9),
        embedded: true,
      );
      expect(wide.paneWidth, kToolPaneMinWidth);
    });

    test('too narrow: no dock unless zoomed; zoomed covers everything and '
        'leaves the panes their width', () {
      final small = toolDockLayout(width: 600, dock: dock, embedded: true);
      expect([small.showsDock, small.paneWidth], [false, 600]);
      final zoomedSmall = toolDockLayout(
        width: 600,
        dock: dock.copyWith(zoom: true),
        embedded: true,
      );
      expect([zoomedSmall.dockLeft, zoomedSmall.dockWidth], [0, 600]);
      final zoomed = toolDockLayout(
        width: 1000,
        dock: dock.copyWith(zoom: true),
        embedded: true,
      );
      expect(
        [zoomed.dockLeft, zoomed.dockWidth, zoomed.showsHandle],
        [0, 1000, false],
      );
      expect(
        zoomed.paneWidth,
        1000 - kToolDockHandle - 450,
        reason: 'no resize',
      );
    });

    test('toolDockCoversPanes: exactly when the layout puts the dock over '
        'the whole area — embedded, open, with chips, zoomed — at any width '
        '(D3, §8)', () {
      final open = const ToolDockState().opened(a);
      for (final (dock, embedded, covers) in [
        (null, true, false),
        (const ToolDockState(), true, false),
        (open, true, false),
        (open.copyWith(zoom: true), true, true),
        (open.copyWith(zoom: true), false, false),
        (open.copyWith(zoom: true, open: false), true, false),
        (const ToolDockState(open: true, zoom: true), true, false),
      ]) {
        expect(
          toolDockCoversPanes(dock, embedded: embedded),
          covers,
          reason: '$dock, embedded: $embedded',
        );
        for (final width in [400.0, 600.0, 879.0, 1400.0]) {
          final layout = toolDockLayout(
            width: width,
            dock: dock,
            embedded: embedded,
          );
          expect(layout.dockLeft == 0, covers, reason: '$dock at $width px');
        }
      }
    });

    test('a drag keeps a fraction within the pixel minimums', () {
      expect(toolDockFraction(width: 1000, dockWidth: 500), 0.5);
      expect(toolDockFraction(width: 1000, dockWidth: 100), 0.32);
      expect(
        toolDockFraction(width: 1000, dockWidth: 990),
        (1000 - kToolDockHandle - kToolPaneMinWidth) / 1000,
      );
      expect(
        toolDockFraction(width: 500, dockWidth: 300),
        kToolDockDefaultWidth,
      );
    });
  });
}
