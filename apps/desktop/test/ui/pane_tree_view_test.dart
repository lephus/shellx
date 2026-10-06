import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';
import 'package:shellx_desktop/src/terminal/terminal_style.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_workspace_page.dart';
import 'package:shellx_desktop/src/ui/theme/shellx_desktop_theme.dart';
import 'package:xterm/xterm.dart';

import '../support/fake_local_sessions.dart';
import 'sidebar_test_harness.dart';

TerminalTabs panes() => container.read(terminalTabsProvider.notifier);
TerminalTab only() => tabs().tabs.single;

TerminalView viewOf(WidgetTester tester, int sessionId) => tester
    .widgetList<TerminalView>(find.byType(TerminalView))
    .firstWhere(
      (v) => identical(v.terminal, only().panes[sessionId]!.terminal),
    );

Future<void> splitRight(WidgetTester tester) async {
  await panes().split(SplitAxis.row);
  await tester.pump();
  await tester.pump();
}

Future<void> splitDown(WidgetTester tester) async {
  await panes().split(SplitAxis.column);
  await tester.pump();
  await tester.pump();
}

/// The pane rectangle: its header plus its terminal.
Rect paneRect(WidgetTester tester, int id) {
  final header = tester.getRect(find.byKey(Key('pane.header.$id')));
  final view = tester.getRect(
    find.byWidgetPredicate(
      (w) =>
          w is TerminalView &&
          identical(w.terminal, only().panes[id]!.terminal),
    ),
  );
  return header.expandToInclude(view);
}

Size cell() => measureTerminalCell(
  desktopTerminalStyle(kTerminalFontSizeDefault),
  TextScaler.noScaling,
);

void main() {
  setUp(() {
    local = FakeLocalSessions();
    local.add(local.summary(1, origin: SessionOrigin.desktop));
  });

  testSidebar('a one-pane tab has no header, outline or divider', (t) async {
    final semantics = t.ensureSemantics();
    await pumpSidebar(t);
    expect(find.byKey(const Key('pane.header.1')), findsNothing);
    expect(find.byKey(const Key('pane.focusOutline')), findsNothing);
    expect(find.byKey(const Key('pane.divider.')), findsNothing);
    expect(find.byKey(const Key('pane.zoomed')), findsNothing);
    expect(find.bySemanticsLabel('Terminal zsh 1'), findsOneWidget);
    semantics.dispose();
  });

  testSidebar('split right: two terminals, headers, outline on the new pane, '
      'keyboard in the new pane', (t) async {
    final semantics = t.ensureSemantics();
    await pumpSidebar(t);
    await splitRight(t);
    expect(find.byType(TerminalView), findsNWidgets(2));
    expect(find.byKey(const Key('pane.header.1')), findsOneWidget);
    expect(find.byKey(const Key('pane.header.100')), findsOneWidget);
    final outline = t.getRect(find.byKey(const Key('pane.focusOutline')));
    final right = t.getRect(find.byKey(const Key('pane.header.100')));
    expect(outline.left, right.left);
    final page = t.state<TerminalWorkspacePageState>(
      find.byType(TerminalWorkspacePage),
    );
    expect(viewOf(t, 100).focusNode, same(page.terminalFocus));
    expect(page.terminalFocus.hasFocus, isTrue);
    expect(find.bySemanticsLabel('Pane 2 of 2 — zsh 2'), findsOneWidget);
    // Each pane told its own session its own grid (P5).
    expect(local.views[1]!.resizes.last.$1, lessThan(80));
    expect(local.views[100]!.resizes, isNotEmpty);
    semantics.dispose();
  });

  testSidebar('panes tile the area: 22 px headers, a 1 px divider taken '
      'from the second pane, no gap or overlap', (t) async {
    await pumpSidebar(t);
    final area = t.getRect(find.byType(TerminalView));
    await splitRight(t);
    final left = paneRect(t, 1);
    final right = paneRect(t, 100);
    expect(t.getSize(find.byKey(const Key('pane.header.1'))).height, 22);
    expect(left.left, area.left);
    expect(right.right, area.right);
    // The divider contract of TerminalTabs._clampForPixels: first r·E,
    // then the line, then (1 − r)·E − divider.
    expect(left.width, area.width * 0.5);
    expect(right.left, left.right + ShellxSizes.paneDivider);
    expect(right.width, area.width * 0.5 - ShellxSizes.paneDivider);
    expect(left.top, area.top);
    expect(right.bottom, area.bottom);
    // The 6 px hit area is centred on the 1 px line.
    final hit = t.getRect(find.byKey(const Key('pane.divider.')));
    expect(hit.width, ShellxSizes.paneDividerHit);
    expect(hit.center.dx, left.right + ShellxSizes.paneDivider / 2);

    await splitDown(t);
    final top = paneRect(t, 100);
    final bottom = paneRect(t, 101);
    expect(bottom.top, top.bottom + ShellxSizes.paneDivider);
    expect(bottom.bottom, area.bottom);
    expect(bottom.left, right.left);
    expect(find.byKey(const Key('pane.divider.1')), findsOneWidget);
  });

  testSidebar('a divider at its clamp limit leaves each side its 20 × 5 '
      'cell minimum', (t) async {
    await pumpSidebar(t);
    await splitRight(t);
    final divider = find.byKey(const Key('pane.divider.'));
    await t.drag(divider, const Offset(-2000, 0));
    await t.pump();
    final min = cell();
    final left = paneRect(t, 1);
    expect(
      left.width,
      greaterThanOrEqualTo(ShellxSizes.paneMinCols * min.width + 20),
    );
    expect(
      only().panes[1]!.terminal.viewWidth,
      equals(ShellxSizes.paneMinCols),
    );
    await t.drag(divider, const Offset(4000, 0));
    await t.pump();
    expect(
      only().panes[100]!.terminal.viewWidth,
      equals(ShellxSizes.paneMinCols),
    );
    expect(paneRect(t, 100).right, t.getRect(find.byType(Scaffold)).right);

    await splitDown(t);
    final across = find.byKey(const Key('pane.divider.1'));
    await t.drag(across, const Offset(0, -2000));
    await t.pump();
    expect(
      only().panes[100]!.terminal.viewHeight,
      equals(ShellxSizes.paneMinRows),
    );
    await t.drag(across, const Offset(0, 4000));
    await t.pump();
    expect(
      only().panes[101]!.terminal.viewHeight,
      equals(ShellxSizes.paneMinRows),
    );
    // The divider's double-click recognizer waits out its timeout.
    await t.pump(kDoubleTapTimeout);
  });

  testSidebar('a click focuses the pane under the pointer', (t) async {
    await pumpSidebar(t);
    await splitRight(t);
    await t.tap(find.byKey(const Key('pane.header.1')));
    await t.pump();
    await t.pump();
    expect(only().focusedPaneId, 1);
    final page = t.state<TerminalWorkspacePageState>(
      find.byType(TerminalWorkspacePage),
    );
    expect(viewOf(t, 1).focusNode, same(page.terminalFocus));
    expect(page.terminalFocus.hasFocus, isTrue);
    final outline = t.getRect(find.byKey(const Key('pane.focusOutline')));
    expect(outline, paneRect(t, 1));
    // The header's double-click recognizer waits out its timeout.
    await t.pump(kDoubleTapTimeout);
  });

  testSidebar('dragging the divider resizes both sessions; double-click '
      'equalizes', (t) async {
    await pumpSidebar(t);
    await splitRight(t);
    final before1 = local.views[1]!.resizes.length;
    await t.drag(find.byKey(const Key('pane.divider.')), const Offset(-120, 0));
    await t.pump();
    expect((only().layout as PaneSplit).ratio, lessThan(0.5));
    expect(local.views[1]!.resizes.length, greaterThan(before1));
    await t.tap(find.byKey(const Key('pane.divider.')));
    await t.pump(kDoubleTapMinTime);
    await t.tap(find.byKey(const Key('pane.divider.')));
    // Not pumpAndSettle: the terminal cursor keeps scheduling frames.
    await t.pump(kDoubleTapTimeout);
    expect((only().layout as PaneSplit).ratio, 0.5);
  });

  testSidebar('the divider follows the pointer without jumping where it was '
      'grabbed', (t) async {
    await pumpSidebar(t);
    await splitRight(t);
    final hit = t.getRect(find.byKey(const Key('pane.divider.')));
    final line = paneRect(t, 1).right;
    // Grab the hit area at its left edge, move 50 px right.
    final gesture = await t.startGesture(hit.centerLeft + const Offset(0.5, 0));
    await gesture.moveBy(const Offset(30, 0));
    await gesture.moveBy(const Offset(20, 0));
    await gesture.up();
    await t.pump();
    expect(paneRect(t, 1).right, closeTo(line + 50, 1));
    await t.pump(kDoubleTapTimeout);
  });

  testSidebar('zoom shows only the focused pane with its indicator', (t) async {
    await pumpSidebar(t);
    final area = t.getRect(find.byType(TerminalView));
    await splitRight(t);
    final hidden = local.views[1]!.resizes.length;
    panes().toggleZoom();
    await t.pump();
    expect(find.byKey(const Key('pane.header.1')), findsNothing); // offstage
    expect(find.byKey(const Key('pane.zoomed')), findsOneWidget);
    expect(find.text('Zoomed · 2/2'), findsOneWidget);
    expect(find.byKey(const Key('pane.focusOutline')), findsNothing);
    expect(find.byKey(const Key('pane.divider.')), findsNothing);
    expect(paneRect(t, 100), area);
    // The hidden pane never sizes its session (D13).
    expect(local.views[1]!.resizes.length, hidden);
    // Clicking the indicator unzooms.
    await t.tap(find.byKey(const Key('pane.zoomed')));
    await t.pump();
    expect(only().zoomedPaneId, isNull);
    expect(find.byKey(const Key('pane.header.1')), findsOneWidget);
  });

  testSidebar('double-clicking a pane header zooms that pane', (t) async {
    await pumpSidebar(t);
    await splitRight(t);
    final header = find.byKey(const Key('pane.header.1'));
    await t.tap(header);
    await t.pump(kDoubleTapMinTime);
    await t.tap(header);
    await t.pump(kDoubleTapTimeout);
    expect(only().zoomedPaneId, 1);
    expect(only().focusedPaneId, 1);
  });

  testSidebar('the pane × closes that pane (no command running)', (t) async {
    await pumpSidebar(t);
    await splitRight(t);
    await t.tap(find.byKey(const Key('pane.close.100')));
    await t.pump();
    expect(only().paneOrder, [1]);
    expect(find.byKey(const Key('pane.header.1')), findsNothing);
    expect(find.byKey(const Key('pane.focusOutline')), findsNothing);
  });

  testSidebar('a middle click on a pane header closes the pane', (t) async {
    await pumpSidebar(t);
    await splitRight(t);
    final at = t.getCenter(find.byKey(const Key('pane.header.1')));
    final gesture = await t.startGesture(at, buttons: kMiddleMouseButton);
    await gesture.up();
    await t.pump();
    expect(only().paneOrder, [100]);
  });

  testSidebar('the driver pill sits in its own pane, below the header', (
    t,
  ) async {
    local.add(local.summary(2), notify: false); // phone-opened, phone drives
    await pumpSidebar(t);
    panes().select(2);
    await t.pump();
    await t.pump();
    expect(find.byKey(const Key('pane.driverPill')), findsOneWidget);
    await panes().split(SplitAxis.row);
    await t.pump();
    await t.pump();
    final tab = tabs().selected!;
    expect(tab.paneOrder, [2, 100]);
    final pill = t.getRect(find.byKey(const Key('pane.driverPill')));
    final header = t.getRect(find.byKey(const Key('pane.header.2')));
    expect(pill.top, greaterThanOrEqualTo(header.bottom));
    expect(pill.right, lessThanOrEqualTo(header.right));
  });
}
