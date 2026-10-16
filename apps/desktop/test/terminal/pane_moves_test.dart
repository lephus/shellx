import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_desktop/src/terminal/desktop_terminal.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';
import 'package:shellx_desktop/src/terminal/pane_moves.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:xterm/xterm.dart';

PaneNode two(int a, int b) => PaneSplit(
  axis: SplitAxis.row,
  ratio: 0.5,
  first: PaneLeaf(a),
  second: PaneLeaf(b),
);

PaneSession session(int id) => PaneSession(
  id: id,
  index: id,
  shell: 'zsh',
  title: '',
  origin: SessionOrigin.desktop,
  phoneAttached: false,
  runningCommand: false,
  driver: DriverSide.desktop,
  terminal: DesktopTerminal(platform: TerminalTargetPlatform.macos),
  selection: DesktopTerminalController(),
);

/// A tab (id = its first pane's id) holding [ids] in a chain of row splits.
TerminalTab tabWithPanes(List<int> ids) {
  PaneNode layout = PaneLeaf(ids.first);
  for (final id in ids.skip(1)) {
    layout = splitPane(layout, ids.first, id, SplitAxis.row);
  }
  return TerminalTab(
    id: ids.first,
    origin: SessionOrigin.desktop,
    layout: layout,
    panes: {for (final id in ids) id: session(id)},
    focusedPaneId: ids.first,
    paneHistory: [ids.first, ...ids.skip(1)],
  );
}

List<int> paneIdsOf(TerminalTab t) => paneIds(t.layout);

void main() {
  test('swapLeaves works whatever the ids are: the stand-in is in no leaf, '
      'an AI pane (-1, V2-1 D3) included', () {
    expect(paneIds(swapLeaves(two(-1, 5), -1, 5)), [5, -1]);
    expect(paneIds(swapLeaves(two(5, -1), 5, -1)), [-1, 5]);
    final deeper = PaneSplit(
      axis: SplitAxis.column,
      ratio: 0.3,
      first: two(-2, -1),
      second: PaneLeaf(7),
    );
    expect(paneIds(swapLeaves(deeper, -1, 7)), [-2, 7, -1]);
    expect(paneIds(swapLeaves(deeper, -2, -1)), [-1, -2, 7]);
    expect(paneIds(swapLeaves(two(0, 1), 0, 1)), [1, 0]);
  });

  test('swapLeaves exchanges two sessions and nothing else', () {
    final t = PaneSplit(
      axis: SplitAxis.column,
      ratio: 0.3,
      first: two(1, 2),
      second: PaneLeaf(3),
    );
    final s = swapLeaves(t, 1, 3) as PaneSplit;
    expect(paneIds(s), [3, 2, 1]);
    expect(s.ratio, 0.3);
    expect(s.axis, SplitAxis.column);
  });

  test('swapping a pane with itself or an absent one changes nothing', () {
    final t = two(1, 2);
    expect(swapLeaves(t, 1, 1), t);
    expect(swapLeaves(t, 1, 9), t);
  });

  test('swap by direction uses the real neighbour', () {
    final t = two(1, 2); // 1 left of 2
    expect(paneIds(swapInDirection(t, 1, PaneDirection.right)!), [2, 1]);
    expect(swapInDirection(t, 1, PaneDirection.left), isNull);
  });

  test('break pane: the tab keeps the rest, the pane becomes a tab of its '
      'own', () {
    final tab = tabWithPanes([1, 2, 3]);
    final r = breakPane(tab, 2)!;
    expect(paneIdsOf(r.from), [1, 3]);
    expect(paneIdsOf(r.detached), [2]);
    expect(r.detached.id, 2, reason: 'a tab id is a session id (A3 D1)');
    expect(r.detached.focusedPaneId, 2);
    expect(r.detached.panes[2], same(tab.panes[2]), reason: 'same session');
    expect(r.from.id, tab.id, reason: 'the tab keeps its identity');
  });

  test('break keeps the tab custom title, focus moves to the history', () {
    final tab = tabWithPanes([
      1,
      2,
      3,
    ]).copyWith(customTitle: 'api', focusedPaneId: 2, paneHistory: [2, 3, 1]);
    final r = breakPane(tab, 2)!;
    expect(r.from.customTitle, 'api');
    expect(r.from.focusedPaneId, 3);
    expect(r.from.paneHistory, [3, 1]);
    expect(r.detached.customTitle, isNull);
  });

  test('breaking the creator pane gives the new tab the pane id only when '
      'free; the caller may name another', () {
    final tab = tabWithPanes([1, 2]);
    final r = breakPane(tab, 1, detachedId: 900)!;
    expect(r.detached.id, 900);
    expect(r.from.id, 1, reason: 'the old tab keeps its id');
    expect(paneIdsOf(r.detached), [1]);
  });

  test('a zoom on the moved pane ends; a zoom elsewhere stays', () {
    final zoomed = tabWithPanes([1, 2, 3]).copyWith(zoomedPaneId: 2);
    expect(breakPane(zoomed, 2)!.from.zoomedPaneId, isNull);
    expect(breakPane(zoomed, 1)!.from.zoomedPaneId, 2);
    final last = tabWithPanes([1, 2]).copyWith(zoomedPaneId: 1);
    expect(breakPane(last, 2)!.from.zoomedPaneId, isNull, reason: 'one pane');
  });

  test('breaking the only pane is refused', () {
    expect(breakPane(tabWithPanes([1]), 1), isNull);
  });

  test('breaking a pane the tab does not hold is refused', () {
    expect(breakPane(tabWithPanes([1, 2]), 9), isNull);
  });

  test('join: the pane leaves one tab and splits the focused pane of the '
      'other', () {
    final from = tabWithPanes([1, 2]);
    final to = tabWithPanes([5]);
    final r = joinPane(from, to, 2)!;
    expect(paneIdsOf(r.from!), [1]);
    expect(paneIdsOf(r.to), [5, 2]);
    expect(r.to.focusedPaneId, 2);
    expect(r.to.paneHistory, [2, 5]);
    expect(r.to.panes[2], same(from.panes[2]));
  });

  test('joining the only pane of a tab leaves no tab behind, session kept', () {
    final r = joinPane(tabWithPanes([1]), tabWithPanes([5]), 1)!;
    expect(r.from, isNull);
    expect(paneIdsOf(r.to), [5, 1]);
  });

  test('join into a tab with a zoom ends the zoom (the pane is seen)', () {
    final to = tabWithPanes([5, 6]).copyWith(zoomedPaneId: 5);
    expect(joinPane(tabWithPanes([1, 2]), to, 2)!.to.zoomedPaneId, isNull);
  });

  test('joining a tab with itself, or a pane it lacks, is refused', () {
    final a = tabWithPanes([1, 2]);
    expect(joinPane(a, a, 2), isNull);
    expect(joinPane(a, tabWithPanes([5]), 9), isNull);
  });

  test('the multiset of session ids is the same before and after (never '
      'orphan one)', () {
    final from = tabWithPanes([1, 2, 3]);
    final to = tabWithPanes([7, 8]);
    final r = joinPane(from, to, 3)!;
    final before = [...paneIdsOf(from), ...paneIdsOf(to)]..sort();
    final after = [...paneIdsOf(r.from!), ...paneIdsOf(r.to)]..sort();
    expect(after, before);
    final broken = breakPane(from, 3)!;
    final afterBreak = [
      ...paneIdsOf(broken.from),
      ...paneIdsOf(broken.detached),
    ]..sort();
    expect(afterBreak, paneIdsOf(from).toList()..sort());
  });

  test('a desktop pane joining a tab a phone opened makes it a desktop tab '
      '(A11 review M2)', () {
    final phone = TerminalTab(
      id: 5,
      origin: SessionOrigin.phone,
      layout: PaneLeaf(5),
      panes: {5: session(5)},
      focusedPaneId: 5,
      paneHistory: const [5],
    );
    final r = joinPane(tabWithPanes([1, 2]), phone, 2)!;
    expect(r.to.origin, SessionOrigin.desktop);
    expect(
      joinPane(tabWithPanes([1, 2]), tabWithPanes([7]), 2)!.to.origin,
      SessionOrigin.desktop,
    );
  });
}
