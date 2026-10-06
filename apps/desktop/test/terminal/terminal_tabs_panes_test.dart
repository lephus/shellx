import 'dart:async';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:xterm/xterm.dart' show TerminalKey;

import '../support/fake_local_sessions.dart';

late FakeLocalSessions local;
late ProviderContainer container;

TerminalTabs tabs() => container.read(terminalTabsProvider.notifier);
TerminalTabsState state() => container.read(terminalTabsProvider);

void boot() {
  container = ProviderContainer.test(
    overrides: [
      localSessionsProvider.overrideWithValue(local),
      appL10nProvider.overrideWithValue(
        lookupAppLocalizations(const Locale('en')),
      ),
    ],
  );
  state();
}

TerminalTab only() => state().tabs.single;
TerminalTab only1() => state().tabs.firstWhere((t) => t.id == 1);

void main() {
  setUp(() => local = FakeLocalSessions());

  test('a session becomes a one-pane tab that reads like A2 (D1, D2)', () {
    local.add(local.summary(1, title: 'vim', cwd: '/Users/test/w'));
    boot();
    final tab = state().tabs.single;
    expect(tab.id, 1);
    expect(tab.layout, const PaneLeaf(1));
    expect(tab.paneOrder, [1]);
    expect(tab.focusedPaneId, 1);
    expect(tab.isSplit, isFalse);
    expect(tab.label, 'vim');
    expect(tab.cwd, '/Users/test/w');
    expect(identical(tab.terminal, tab.panes[1]!.terminal), isTrue);
    expect(state().tabOfSession(1), same(tab));
    expect(state().tabOfSession(2), isNull);
  });

  test('summary changes update the pane inside its tab', () {
    local.add(local.summary(1));
    boot();
    local.replace(local.summary(1, title: 'htop', runningCommand: true));
    expect(state().tabs.single.panes[1]!.title, 'htop');
    expect(state().tabs.single.runningCommand, isTrue);
    expect(tabs().runningPaneCount(1), 1);
    expect(tabs().needsCloseConfirm(1), isTrue);
    expect(tabs().needsPaneCloseConfirm(1), isTrue);
  });

  test('D5: a desktop session that appears while an open is pending waits '
      'for the opener; a phone session does not', () async {
    local.add(local.summary(1, origin: SessionOrigin.desktop));
    boot();
    local.openGate = Completer<void>();
    final opening = tabs().openTab();
    local.add(local.summary(7, origin: SessionOrigin.desktop));
    local.add(local.summary(8)); // phone
    expect(state().tabs.map((t) => t.id), [1, 8]);
    local.openGate!.complete();
    await opening;
    expect(state().tabs.map((t) => t.id), [1, 8, 7, 100]);
    expect(state().selectedId, 100);
  });

  test('D5: a desktop session held back by an open that fails gets its tab '
      'at once, without another change event', () async {
    local.add(local.summary(1, origin: SessionOrigin.desktop));
    boot();
    local.openGate = Completer<void>();
    local.openError = const SessionLimitException(32);
    final opening = tabs().openTab();
    local.add(local.summary(7, origin: SessionOrigin.desktop));
    expect(state().tabs.map((t) => t.id), [1]);
    local.openGate!.complete();
    await opening;
    expect(state().tabs.map((t) => t.id), [1, 7]);
    expect(state().opening, isFalse);
    expect(state().notice, isA<SessionLimitNotice>());
  });

  test('close(tab) closes every pane session and removes the tab', () {
    local.add(local.summary(1));
    local.add(local.summary(2));
    boot();
    tabs().close(1);
    expect(local.closed, [1]);
    expect(state().tabs.map((t) => t.id), [2]);
  });

  test('closePane on a one-pane tab closes the tab (D6)', () {
    local.add(local.summary(1));
    boot();
    tabs().closePane(1);
    expect(local.closed, [1]);
    expect(state().tabs, isEmpty);
  });

  test('a non-zero exit keeps the tab; Enter closes it (A1 D14)', () async {
    local.add(local.summary(1));
    boot();
    local.views[1]!.end(3);
    await pumpEventQueue();
    expect(state().tabs.single.exited, isTrue);
    expect(state().tabs.single.panes[1]!.exitCode, 3);
    state().tabs.single.terminal.keyInput(TerminalKey.enter);
    expect(state().tabs, isEmpty);
  });

  group('pane operations (A3)', () {
    setUp(() {
      local.add(
        local.summary(1, origin: SessionOrigin.desktop, cwd: '/Users/test/w'),
      );
    });

    test('split right: cwd, half grid, new pane after and focused '
        '(D3, D13, D17)', () async {
      boot();
      await tabs().split(SplitAxis.row);
      expect(local.openCwds.single, '/Users/test/w');
      expect(local.opens.single, (39, 23)); // 80×24 → (80−1)~/2 × (24−1)
      expect(only().id, 1);
      expect(
        only().layout,
        const PaneSplit(
          axis: SplitAxis.row,
          ratio: 0.5,
          first: PaneLeaf(1),
          second: PaneLeaf(100),
        ),
      );
      expect(only().focusedPaneId, 100);
      expect(only().terminal.viewWidth, 39);
      expect(state().opening, isFalse);
    });

    test('split down estimates half the rows', () async {
      boot();
      await tabs().split(SplitAxis.column);
      expect(local.opens.single, (80, 10)); // (24−1)~/2 − 1
    });

    test('D5: changes fired inside open() never make the pane a tab', () async {
      boot();
      local.afterOpen = (id) => local.replace(local.summaries.last);
      await tabs().split(SplitAxis.row);
      expect(state().tabs, hasLength(1));
      expect(only().paneOrder, [1, 100]);
    });

    test('the tab vanished while the pane was opening → own tab', () async {
      boot();
      local.openGate = Completer<void>();
      final split = tabs().split(SplitAxis.row);
      tabs().close(1);
      local.openGate!.complete();
      await split;
      expect(state().tabs.map((t) => t.id), [100]);
      expect(state().selectedId, 100);
    });

    test(
      'limit / spawn failure: tree unchanged, toast, usable again',
      () async {
        boot();
        local.openError = const SessionLimitException(32);
        await tabs().split(SplitAxis.row);
        expect(only().paneOrder, [1]);
        expect(state().notice, isA<SessionLimitNotice>());
        expect(state().opening, isFalse);
      },
    );

    test(
      'no room (D4): no open, neutral notice; the other axis fits',
      () async {
        boot();
        tabs().reportPaneMetrics(
          const PaneMetrics(
            area: Size(300, 400),
            minPane: Size(176, 100),
            divider: 1,
          ),
        );
        await tabs().split(SplitAxis.row);
        expect(local.opens, isEmpty);
        expect(state().notice, isA<PaneNoRoomNotice>());
        await tabs().split(SplitAxis.column);
        expect(local.opens, hasLength(1));
      },
    );

    test('close focuses the most recently used pane; the tab keeps its id '
        'when its first pane closes (D1, D8)', () async {
      boot();
      await tabs().split(SplitAxis.row); // 1 | 100
      tabs().focusPane(1);
      await tabs().split(SplitAxis.column); // (1 / 101) | 100
      expect(only().focusedPaneId, 101);
      tabs().closePane(101);
      expect(only().focusedPaneId, 1);
      tabs().closePane(1);
      expect(only().id, 1);
      expect(only().paneOrder, [100]);
      expect(only().focusedPaneId, 100);
      expect(local.closed, [101, 1]);
      tabs().closePane(100);
      expect(state().tabs, isEmpty);
    });

    test(
      'pane exits: 0 removes it, non-zero keeps it until Enter (D7)',
      () async {
        boot();
        await tabs().split(SplitAxis.row);
        await tabs().split(SplitAxis.row); // 1 | 100 | 101
        local.views[101]!.end(0);
        await pumpEventQueue();
        expect(only().paneOrder, [1, 100]);
        local.views[100]!.end(2);
        await pumpEventQueue();
        expect(only().panes[100]!.exited, isTrue);
        only().panes[100]!.terminal.keyInput(TerminalKey.enter);
        expect(only().paneOrder, [1]);
      },
    );

    test('only visible panes resize their sessions; unzoom re-sends (D10, '
        'D13)', () async {
      local.add(local.summary(2)); // a phone tab, not selected
      boot();
      await tabs().split(SplitAxis.row);
      final r1 = local.views[1]!.resizes;
      final r2 = local.views[2]!.resizes;
      expect(tabs().toggleZoom(), isTrue); // zooms 100
      final before = r1.length;
      only1().panes[1]!.terminal.resize(50, 20);
      expect(r1.length, before); // hidden by the zoom
      state().tabs.firstWhere((t) => t.id == 2).terminal.resize(60, 20);
      expect(r2, isEmpty); // not the selected tab
      expect(tabs().toggleZoom(), isFalse);
      expect(r1.last, (50, 20));
    });

    test('directional focus, unzooming first; no wrap (D9)', () async {
      boot();
      await tabs().split(SplitAxis.row);
      tabs().toggleZoom();
      expect(tabs().focusDirection(PaneDirection.left), isTrue);
      expect(only().focusedPaneId, 1);
      expect(only().zoomedPaneId, isNull);
      expect(tabs().focusDirection(PaneDirection.left), isFalse);
    });

    test(
      'split while zoomed unzooms; focusing a hidden pane unzooms',
      () async {
        boot();
        await tabs().split(SplitAxis.row);
        tabs().toggleZoom();
        await tabs().split(SplitAxis.column);
        expect(only().zoomedPaneId, isNull);
        tabs().toggleZoom(); // zoom 101
        tabs().focusPane(1);
        expect(only().zoomedPaneId, isNull);
      },
    );

    test(
      'equalize; keyboard resize moves the nearest same-axis divider; '
      'pixel minimums clamp; stale paths are ignored (D4, D11, D12)',
      () async {
        boot();
        await tabs().split(SplitAxis.row);
        await tabs().split(SplitAxis.row); // 1 | (100 | 101)
        tabs().equalize();
        expect((only().layout as PaneSplit).ratio, closeTo(1 / 3, 1e-9));
        tabs().resizeFocused(PaneDirection.right); // 101 → split '1'
        expect(
          ((only().layout as PaneSplit).second as PaneSplit).ratio,
          closeTo(0.55, 1e-9),
        );
        tabs().resizeFocused(PaneDirection.down); // no column split: no-op
        tabs().reportPaneMetrics(
          const PaneMetrics(
            area: Size(1000, 600),
            minPane: Size(176, 100),
            divider: 1,
          ),
        );
        tabs().setRatio(1, '', 0.05);
        expect((only().layout as PaneSplit).ratio, closeTo(0.176, 1e-9));
        tabs().setRatio(1, '', 0.99); // second side holds two panes
        // Inner split at 0.55: its second pane (101) needs 176 px of
        // X − 1 − snap(0.55·X) ≥ 0.45·X − 1.5 (half a pixel may go to the
        // rounding, Task 6 snapping), so the side needs X = 177.5 / 0.45;
        // the root's first side ends on the whole pixel before that.
        expect(
          (only().layout as PaneSplit).ratio,
          closeTo((1000 - 1 - 177.5 / 0.45).floorToDouble() / 1000, 1e-9),
        );
        tabs().equalizeAt(1, '1');
        expect(((only().layout as PaneSplit).second as PaneSplit).ratio, 0.5);
        final layout = only().layout;
        tabs().setRatio(1, '0', 0.3); // a leaf: ignored
        tabs().setRatio(1, '11', 0.3); // no node there: ignored
        tabs().setRatio(99, '', 0.3); // no such tab: ignored
        expect(only().layout, layout);
      },
    );

    test(
      'closing the zoomed pane unzooms and re-sends the grids (D8, D10)',
      () async {
        boot();
        await tabs().split(SplitAxis.row);
        await tabs().split(SplitAxis.row); // 1 | 100 | 101
        tabs().toggleZoom(); // zoom 101
        only().panes[1]!.terminal.resize(30, 20);
        final r1 = local.views[1]!.resizes;
        expect(r1, isNot(contains((30, 20))));
        tabs().closePane(101);
        expect(only().zoomedPaneId, isNull);
        expect(only().focusedPaneId, 100);
        expect(r1.last, (30, 20));
      },
    );

    test(
      'a removal that leaves one pane clears the zoom (criterion 13)',
      () async {
        boot();
        await tabs().split(SplitAxis.row); // 1 | 100, focus 100
        tabs().toggleZoom(); // zoom 100
        tabs().closePane(1);
        expect(only().id, 1);
        expect(only().isSplit, isFalse);
        expect(only().zoomedPaneId, isNull);
      },
    );

    test('close(tab) on a split tab closes every pane; counts and numbers '
        '(D6, D15, D23)', () async {
      local.add(local.summary(2));
      boot();
      await tabs().split(SplitAxis.row);
      await tabs().split(SplitAxis.row); // 1 | 100 | 101
      local.replace(local.summary(1, runningCommand: true));
      local.replace(
        local.summary(100, origin: SessionOrigin.desktop, runningCommand: true),
      );
      expect(tabs().runningPaneCount(1), 2);
      expect(tabs().needsPaneCloseConfirm(101), isFalse);
      expect(only1().paneNumber(100), 2);
      expect(only1().paneNumber(101), 3);
      expect(only1().paneCount, 3);
      tabs().close(1);
      expect(local.closed, unorderedEquals([1, 100, 101]));
      expect(state().tabs.map((t) => t.id), [2]);
    });

    test('a split never shows the new session as its own tab, even for one '
        'state (D5)', () async {
      boot();
      final seen = <List<int>>[];
      container.listen(
        terminalTabsProvider,
        (_, next) => seen.add([for (final t in next.tabs) t.id]),
      );
      await tabs().split(SplitAxis.row);
      expect(seen, everyElement([1]));
    });

    test('the pixel clamp keeps every nested pane at its minimum, with the '
        "nested ratios as they are (D4)", () async {
      boot();
      await tabs().split(SplitAxis.row);
      await tabs().split(SplitAxis.row); // 1 | (100 | 101), root 0.5
      tabs().reportPaneMetrics(
        const PaneMetrics(
          area: Size(1400, 600),
          minPane: Size(176, 100),
          divider: 1,
        ),
      );
      PaneSplit root() => only().layout as PaneSplit;
      PaneSplit inner() => root().second as PaneSplit;
      // The inner split is 0.5·1400 − 1 = 699 px wide.
      tabs().setRatio(1, '1', 0.9);
      expect(inner().ratio, closeTo(1 - 177 / 699, 1e-9));
      tabs().setRatio(1, '1', 0.7);
      expect(inner().ratio, 0.7);
      // 101 gets 0.3·X − 1 of the right side's X: X ≥ 177 / 0.3, and the
      // root's divider comes on top. (The old span rule allowed 101 to
      // shrink to 0.3·(2·176 + 1) − 1 ≈ 105 px.)
      // (Task 6 snapping: half a pixel may go to the inner rounding, and
      // the root's edge sits on a whole pixel.)
      tabs().setRatio(1, '', 0.99);
      const side = 177.5 / 0.3;
      expect(
        root().ratio,
        closeTo((1400 - 1 - side).floorToDouble() / 1400, 1e-9),
      );
      final px = panePixelSizes(only().layout, const Size(1400, 600), 1, 1);
      expect(px[101]!.width, greaterThanOrEqualTo(176));
      expect(px[101]!.width, lessThan(178));
      expect(px[100]!.width, greaterThanOrEqualTo(176));
      // Keys go through the same clamp.
      tabs().resizeFocused(PaneDirection.left); // 101: inner '1' → 0.65
      expect(inner().ratio, closeTo(0.65, 1e-9));
    });

    for (final dpr in [1.0, 1.25, 2.0]) {
      test('dpr $dpr: at every clamp limit each pane keeps its minimum in '
          'snapped pixels (splitExtents), nested ones too (D4)', () async {
        boot();
        await tabs().split(SplitAxis.row);
        await tabs().split(SplitAxis.column); // 1 | (100 / 101)
        tabs().focusPane(1);
        await tabs().split(SplitAxis.row); // (1 | 102) | (100 / 101)
        const area = Size(1099.2, 641.6);
        const min = Size(176.3, 100.7);
        tabs().reportPaneMetrics(
          PaneMetrics(
            area: area,
            minPane: min,
            divider: 1,
            devicePixelRatio: dpr,
          ),
        );
        void checkAll() {
          final sizes = panePixelSizes(only().layout, area, 1, dpr);
          for (final size in sizes.values) {
            expect(size.width, greaterThanOrEqualTo(min.width - 1e-9));
            expect(size.height, greaterThanOrEqualTo(min.height - 1e-9));
          }
        }

        // Each split to both limits and back. (Alternating extremes of a
        // nested ratio and its parent can make a side infeasible, where
        // Task 5's fair-point rule applies instead.)
        for (final path in ['0', '', '1']) {
          for (final r in [0.01, 0.99, 0.37]) {
            tabs().setRatio(only().id, path, r);
            checkAll();
          }
        }
        // The limit is reached, not merely respected: the first pane sits
        // within one device pixel of its minimum.
        tabs().setRatio(only().id, '0', 0.01);
        final first = panePixelSizes(only().layout, area, 1, dpr)[1]!;
        expect(first.width - min.width, lessThan(1 / dpr + 1e-9));
      });
    }

    test('too small for both sides: a drag may only relieve the more '
        'squeezed side (D4)', () async {
      boot();
      await tabs().split(SplitAxis.row); // 1 | 100 at 0.5
      tabs().reportPaneMetrics(
        const PaneMetrics(
          area: Size(300, 400),
          minPane: Size(176, 100),
          divider: 1,
        ),
      );
      // lo = 176/300, hi = 1 − 177/300: equal shortfall at their middle.
      const fair = (176 / 300 + 1 - 177 / 300) / 2;
      PaneSplit root() => only().layout as PaneSplit;
      tabs().setRatio(1, '', 0.9); // squeezes 100 further: refused
      expect(root().ratio, 0.5);
      tabs().setRatio(1, '', 0.1); // relieves 100, stops at the fair point
      expect(root().ratio, closeTo(fair, 1e-9));
    });

    test('a split that finishes after a tab switch keeps the tab the user '
        'chose (final m-1)', () async {
      local.add(local.summary(2));
      boot();
      local.openGate = Completer<void>();
      final split = tabs().split(SplitAxis.row);
      tabs().select(2);
      final r1 = local.views[1]!.resizes.length;
      local.openGate!.complete();
      await split;
      expect(state().selectedId, 2);
      expect(only1().paneOrder, [1, 100]);
      expect(only1().focusedPaneId, 100);
      // Tab 1 is hidden: its panes tell their sessions nothing (D13).
      expect(local.views[1]!.resizes.length, r1);
    });

    test('no room (D4) at the exact boundary: both snapped halves must hold '
        'the minimum (final m-2)', () async {
      boot();
      // 2·176 + 1 = 353: the old sum rule allowed it, but splitExtents
      // gives round(176.5) = 177 | 1 | 175, one pixel short.
      tabs().reportPaneMetrics(
        const PaneMetrics(
          area: Size(353, 400),
          minPane: Size(176, 100),
          divider: 1,
        ),
      );
      await tabs().split(SplitAxis.row);
      expect(local.opens, isEmpty);
      expect(state().notice, isA<PaneNoRoomNotice>());
      tabs().dismissNotice();
      // 354: 177 | 1 | 176.
      tabs().reportPaneMetrics(
        const PaneMetrics(
          area: Size(354, 400),
          minPane: Size(176, 100),
          divider: 1,
        ),
      );
      await tabs().split(SplitAxis.row);
      expect(local.opens, hasLength(1));
      expect(state().notice, isNull);
    });

    test('no room (D4) down: the same snapped rule on the height, at dpr '
        '1.25 (final m-2)', () async {
      boot();
      // 2·100 + 1 = 201 at dpr 1.25: round(100.5·1.25)/1.25 = 100.8, so the
      // second side gets 201 − 1 − 100.8 = 99.2 < 100.
      tabs().reportPaneMetrics(
        const PaneMetrics(
          area: Size(600, 201),
          minPane: Size(176, 100),
          divider: 1,
          devicePixelRatio: 1.25,
        ),
      );
      await tabs().split(SplitAxis.column);
      expect(local.opens, isEmpty);
      expect(state().notice, isA<PaneNoRoomNotice>());
    });

    test('a ratio for a split of the other axis is ignored: a drag never '
        'moves a split that took its path (final m-3)', () async {
      boot();
      await tabs().split(SplitAxis.row);
      await tabs().split(SplitAxis.column); // 1 | (100 / 101)
      tabs().closePane(1); // the root is now the column split
      final layout = only().layout as PaneSplit;
      expect(layout.axis, SplitAxis.column);
      tabs().setRatio(1, '', 0.3, axis: SplitAxis.row);
      expect(only().layout, layout);
      tabs().setRatio(1, '', 0.3, axis: SplitAxis.column);
      expect((only().layout as PaneSplit).ratio, 0.3);
    });

    test('keyboard resize and equalize unzoom first, and re-send the grids '
        'of the panes that come back (D10, final m-4)', () async {
      boot();
      await tabs().split(SplitAxis.row); // 1 | 100, focus 100
      tabs().toggleZoom();
      only().panes[1]!.terminal.resize(30, 20);
      final r1 = local.views[1]!.resizes;
      expect(r1, isNot(contains((30, 20))));
      tabs().resizeFocused(PaneDirection.left);
      expect(only().zoomedPaneId, isNull);
      expect((only().layout as PaneSplit).ratio, closeTo(0.45, 1e-9));
      expect(r1.last, (30, 20));

      tabs().toggleZoom();
      only().panes[1]!.terminal.resize(31, 20);
      tabs().equalize();
      expect(only().zoomedPaneId, isNull);
      expect((only().layout as PaneSplit).ratio, 0.5);
      expect(r1.last, (31, 20));

      // A resize with no split of that axis does nothing, zoom included.
      tabs().toggleZoom();
      tabs().resizeFocused(PaneDirection.down);
      expect(only().zoomedPaneId, 100);
    });

    test('an exited pane never resizes its session', () async {
      boot();
      await tabs().split(SplitAxis.row);
      local.views[100]!.end(2);
      await pumpEventQueue();
      final r = local.views[100]!.resizes;
      final before = r.length;
      only().panes[100]!.terminal.resize(30, 10);
      expect(r.length, before);
    });
  });

  test('A7 D29: a split opens with the tab id; a new tab with none', () async {
    boot();
    await tabs().openTab();
    await tabs().split(SplitAxis.row);
    expect(local.openTabIds, [null, 100]);
  });

  group('command-line opens (A7 D14, D15, D33)', () {
    test('openTabFor: not selected unless asked; returns the tab id; '
        'busy while another open is in flight', () async {
      boot();
      await tabs().openTab(); // 100, selected
      expect(await tabs().openTabFor(cwd: '/w'), 101);
      expect(local.openCwds.last, '/w');
      expect(state().selectedId, 100);
      expect(await tabs().openTabFor(select: true), 102);
      expect(state().selectedId, 102);
      local.openGate = Completer<void>();
      final user = tabs().openTab();
      await expectLater(tabs().openTabFor(), throwsA(isA<OpenBusyException>()));
      await expectLater(
        tabs().splitPaneFor(100, SplitAxis.row),
        throwsA(isA<OpenBusyException>()),
      );
      local.openGate!.complete();
      await user;
      expect(state().opening, isFalse);
    });

    test('openTabFor: failures throw and leave no notice', () async {
      boot();
      local.openError = const SessionLimitException(32);
      await expectLater(
        tabs().openTabFor(),
        throwsA(isA<SessionLimitException>()),
      );
      expect([state().notice, state().opening], [null, false]);
    });

    test('openTabFor: a shell that ended before it was placed is '
        'PaneGoneException; the selection stays', () async {
      boot();
      await tabs().openTab(); // 100
      local.afterOpen = (id) {
        local.summaries.removeWhere((s) => s.id == id);
      };
      await expectLater(
        tabs().openTabFor(select: true),
        throwsA(isA<PaneGoneException>()),
      );
      expect(state().selectedId, 100);
    });

    test('splitPaneFor an unselected tab: focus, zoom and selection stay; '
        'the new pane is next in focus history', () async {
      boot();
      await tabs().openTab(); // 100
      await tabs().split(SplitAxis.row); // 101, focused
      tabs().toggleZoom(); // 101 zoomed
      await tabs().openTab(); // 102, selected
      final id = await tabs().splitPaneFor(100, SplitAxis.column, cwd: '/c');
      expect(id, 103);
      expect(local.openCwds.last, '/c');
      expect(local.openTabIds.last, 100);
      final t = state().tabOfSession(103)!;
      expect(t.id, 100);
      expect(t.focusedPaneId, 101);
      expect(t.zoomedPaneId, 101);
      expect(t.paneHistory, [101, 103, 100]);
      expect(t.paneOrder, [100, 103, 101]);
      expect(state().selectedId, 102);
      expect(state().notice, isNull);
    });

    test('splitPaneFor with focus: the new pane is focused in its tab, the '
        'selection stays', () async {
      boot();
      await tabs().openTab(); // 100
      await tabs().openTab(); // 101, selected
      final id = await tabs().splitPaneFor(100, SplitAxis.row, focus: true);
      expect(state().tabOfSession(id)!.focusedPaneId, id);
      expect(state().selectedId, 101);
    });

    test('splitPaneFor: no room and a gone pane throw; no notice, no '
        'open', () async {
      boot();
      await tabs().openTab(); // 100
      tabs().reportPaneMetrics(
        const PaneMetrics(
          area: Size(300, 150),
          minPane: Size(176, 100),
          divider: 1,
        ),
      );
      await expectLater(
        tabs().splitPaneFor(100, SplitAxis.row),
        throwsA(isA<PaneNoRoomException>()),
      );
      await expectLater(
        tabs().splitPaneFor(999, SplitAxis.row),
        throwsA(isA<PaneGoneException>()),
      );
      expect(local.opens, hasLength(1));
      expect(state().notice, isNull);
    });

    test('splitPaneFor whose tab closed meanwhile: an own tab, not '
        'selected (D15)', () async {
      boot();
      await tabs().openTab(); // 100
      await tabs().openTab(); // 101, selected
      local.openGate = Completer<void>();
      final split = tabs().splitPaneFor(100, SplitAxis.row);
      tabs().close(100);
      local.openGate!.complete();
      expect(await split, 102);
      expect(state().tabs.map((t) => t.id), [101, 102]);
      expect(state().selectedId, 101);
    });
  });
}
