import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/terminal/inline_name_field.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_workspace_page.dart';
import 'package:shellx_desktop/src/ui/terminal/workspace_header.dart';
import 'package:shellx_desktop/src/ui/theme/shellx_desktop_theme.dart';

import 'sidebar_test_harness.dart';

Finder header(String id) => find.byKey(ValueKey('ws.$id'));

/// Default [1, 2] and "Workspace 2" [100] (selected).
Future<String> twoWorkspaces(WidgetTester tester) async {
  local
    ..add(local.summary(1, origin: SessionOrigin.desktop))
    ..add(local.summary(2, origin: SessionOrigin.desktop));
  await pumpSidebar(tester);
  await workspaces().create();
  workspaces().endRename();
  // No name field was built, so nothing handed the keyboard back yet.
  tester
      .state<TerminalWorkspacePageState>(find.byType(TerminalWorkspacePage))
      .focusTerminal();
  await tester.pumpAndSettle();
  return sidebar().workspaces.last.id;
}

Future<TestGesture> startDrag(WidgetTester tester, Finder from) async {
  final gesture = await tester.startGesture(
    tester.getCenter(from),
    kind: PointerDeviceKind.mouse,
  );
  await gesture.moveBy(const Offset(0, 8));
  await tester.pump();
  return gesture;
}

Future<void> hover(WidgetTester tester, TestGesture g, Offset at) async {
  await g.moveTo(at);
  await tester.pump();
  await g.moveTo(at + const Offset(0, 1));
  await tester.pump();
}

Future<void> sendChord(
  WidgetTester tester,
  List<LogicalKeyboardKey> held,
  LogicalKeyboardKey key,
) async {
  for (final k in held) {
    await tester.sendKeyDownEvent(k);
  }
  await tester.sendKeyEvent(key);
  for (final k in held.reversed) {
    await tester.sendKeyUpEvent(k);
  }
  await tester.pump();
}

void main() {
  setUpSidebar();

  testSidebar('one workspace looks like A1: no header (D10)', (tester) async {
    local.add(local.summary(1, origin: SessionOrigin.desktop));
    await pumpSidebar(tester);
    expect(find.byType(WorkspaceHeader), findsNothing);
    expect(row(1), findsOneWidget);
  });

  testSidebar('headers show name and count; a click collapses and hides '
      'the rows; a collapsed group holding the selected tab is marked '
      '(UI-A2 §3)', (tester) async {
    final ws = await twoWorkspaces(tester);
    final def = header(kDefaultWorkspaceId);
    expect(
      find.descendant(of: def, matching: find.text('Default')),
      findsOneWidget,
    );
    expect(find.descendant(of: def, matching: find.text('2')), findsOneWidget);
    expect(
      find.descendant(of: header(ws), matching: find.text('Workspace 2')),
      findsOneWidget,
    );
    expect(tester.getSize(def).height, ShellxSizes.workspaceHeader);
    container.read(terminalTabsProvider.notifier).select(1);
    await tester.pump();
    await tester.tap(find.descendant(of: def, matching: find.text('Default')));
    await tester.pump(kDoubleTapTimeout);
    await tester.pumpAndSettle();
    expect(sidebar().workspace(kDefaultWorkspaceId)!.collapsed, isTrue);
    expect(row(1), findsNothing);
    expect(find.byKey(const Key('header.collapsedMark')), findsOneWidget);
    expect(tabs().selectedId, 1); // the terminal still shows it
  });

  testSidebar('double-click on the name renames the workspace; Enter keeps', (
    tester,
  ) async {
    final ws = await twoWorkspaces(tester);
    final name = find.descendant(
      of: header(ws),
      matching: find.text('Workspace 2'),
    );
    await tester.tap(name);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(name);
    await tester.pumpAndSettle();
    final field = find.descendant(
      of: header(ws),
      matching: find.byKey(const Key('row.renameField')),
    );
    expect(field, findsOneWidget);
    await tester.enterText(field, 'Backend');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(sidebar().workspace(ws)!.name, 'Backend');
    expect(sidebar().workspace(ws)!.collapsed, isFalse); // no toggle
  });

  testSidebar('header menu: Delete is disabled for Default; deleting moves '
      'the tabs and shows the neutral toast (D11, D16)', (tester) async {
    final ws = await twoWorkspaces(tester);
    await tester.tap(header(kDefaultWorkspaceId), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    final delete = tester.widget<PopupMenuItem<Object?>>(
      find.byKey(const Key('menu.ws.delete')),
    );
    expect(delete.enabled, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(header(ws), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu.ws.delete')));
    await tester.pumpAndSettle();
    expect(sidebar().workspaces, hasLength(1));
    expect(sidebar().tabsOf(kDefaultWorkspaceId), [1, 2, 100]);
    expect(
      find.text('Deleted workspace “Workspace 2”. Its tabs moved to Default.'),
      findsOneWidget,
    );
    expect(find.byType(WorkspaceHeader), findsNothing);
  });

  testSidebar('the header + (shown on hover) opens a tab in that workspace', (
    tester,
  ) async {
    final ws = await twoWorkspaces(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(header(ws)));
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: header(ws),
        matching: find.byKey(const Key('header.add')),
      ),
    );
    await tester.pumpAndSettle();
    expect(sidebar().tabsOf(ws), hasLength(2));
    await mouse.removePointer();
  });

  testSidebar('dragging a row onto the lower half of another reorders it; a '
      'drop line shows meanwhile (D18, UI-A2 §6)', (tester) async {
    await twoWorkspaces(tester);
    final g = await startDrag(tester, row(1));
    await hover(tester, g, tester.getBottomLeft(row(2)) + const Offset(30, -4));
    expect(find.byKey(const Key('drop.line')), findsOneWidget);
    await g.up();
    await tester.pumpAndSettle();
    expect(sidebar().tabsOf(kDefaultWorkspaceId), [2, 1]);
    expect(find.byKey(const Key('drop.line')), findsNothing);
  });

  testSidebar('dragging onto a collapsed header expands it after 600 ms and '
      'drops at its end', (tester) async {
    final ws = await twoWorkspaces(tester);
    workspaces().setCollapsed(ws, true);
    await tester.pumpAndSettle();
    final g = await startDrag(tester, row(1));
    await hover(tester, g, tester.getCenter(header(ws)));
    await tester.pump(const Duration(milliseconds: 650));
    expect(sidebar().workspace(ws)!.collapsed, isFalse);
    await hover(tester, g, tester.getCenter(header(ws)));
    await g.up();
    await tester.pumpAndSettle();
    expect(sidebar().tabsOf(ws), [100, 1]);
  });

  testSidebar('an empty workspace shows its hint and accepts a drop', (
    tester,
  ) async {
    final ws = await twoWorkspaces(tester);
    workspaces().moveTab(100, kDefaultWorkspaceId);
    await tester.pumpAndSettle();
    final hint = find.byKey(ValueKey('empty.$ws'));
    expect(
      find.descendant(
        of: hint,
        matching: find.text('Empty. Drag a tab here or press +.'),
      ),
      findsOneWidget,
    );
    final g = await startDrag(tester, row(2));
    await hover(tester, g, tester.getCenter(hint));
    await g.up();
    await tester.pumpAndSettle();
    expect(sidebar().tabsOf(ws), [2]);
  });

  testSidebar('keyboard tree: ↑ from a group\'s first row reaches its header '
      'without changing the tab; Enter collapses, → expands, ↑ selects the '
      'row above (D14)', (tester) async {
    final ws = await twoWorkspaces(tester); // tab 100 selected
    await sendChord(tester, [
      LogicalKeyboardKey.controlLeft,
    ], LogicalKeyboardKey.f6);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(tabs().selectedId, 100);
    expect(
      find.byWidgetPredicate((w) => w is WorkspaceHeader && w.focused),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(sidebar().workspace(ws)!.collapsed, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(sidebar().workspace(ws)!.collapsed, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(tabs().selectedId, 2);
  });

  testSidebar('⌘⇧N opens the new header\'s name field; Enter names it and '
      'gives the keyboard back to the terminal (D15)', (tester) async {
    local.add(local.summary(1, origin: SessionOrigin.desktop));
    await pumpSidebar(tester);
    await sendChord(tester, [
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.shiftLeft,
    ], LogicalKeyboardKey.keyN);
    await tester.pumpAndSettle();
    final ws = sidebar().workspaces.last.id;
    final field = find.descendant(
      of: header(ws),
      matching: find.byKey(const Key('row.renameField')),
    );
    expect(field, findsOneWidget);
    await tester.enterText(field, 'Ops');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(sidebar().workspace(ws)!.name, 'Ops');
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      isNot('inline name'),
    );
  });

  testSidebar('header semantics: name, count, expanded state (UI-A2 §8)', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await twoWorkspaces(tester);
    expect(find.bySemanticsLabel('Workspace Default, 2 tabs'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'tab 1 of 2 in Default$')),
      findsOneWidget,
    );
    // Review: the expanded state, and the custom actions (no Delete on
    // Default).
    expect(
      tester.getSemantics(find.bySemanticsLabel('Workspace Default, 2 tabs')),
      isSemantics(
        isHeader: true,
        isButton: true,
        hasExpandedState: true,
        isExpanded: true,
        customActions: [
          const CustomSemanticsAction(label: 'Rename workspace'),
          const CustomSemanticsAction(label: 'New tab in this workspace'),
        ],
      ),
    );
    expect(
      tester.getSemantics(
        find.bySemanticsLabel('Workspace Workspace 2, 1 tab'),
      ),
      isSemantics(
        customActions: [
          const CustomSemanticsAction(label: 'Rename workspace'),
          const CustomSemanticsAction(label: 'New tab in this workspace'),
          const CustomSemanticsAction(label: 'Delete workspace'),
        ],
      ),
    );
    handle.dispose();
  });

  // ---- beyond the brief -------------------------------------------------

  TerminalWorkspacePageState page(WidgetTester tester) => tester
      .state<TerminalWorkspacePageState>(find.byType(TerminalWorkspacePage));

  testSidebar('a click that jitters under 4 px still selects; a longer '
      'move drags instead (UI-A2 §6)', (tester) async {
    await twoWorkspaces(tester); // tab 100 selected
    final g = await tester.startGesture(
      tester.getCenter(row(2)),
      kind: PointerDeviceKind.mouse,
    );
    await g.moveBy(const Offset(3, 0));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    expect(tabs().selectedId, 2);
    final drag = await startDrag(tester, row(1));
    await drag.up();
    await tester.pumpAndSettle();
    expect(tabs().selectedId, 2); // a drag never selects
  });

  testSidebar('dragging onto the upper half of a row in another workspace '
      'drops before it; dragging away cancels without a change', (
    tester,
  ) async {
    final ws = await twoWorkspaces(tester);
    var g = await startDrag(tester, row(1));
    await hover(tester, g, tester.getTopLeft(row(100)) + const Offset(30, 4));
    expect(
      find.descendant(
        of: find.ancestor(of: row(100), matching: find.byType(Stack)).first,
        matching: find.byKey(const Key('drop.line')),
      ),
      findsOneWidget,
    );
    await g.up();
    await tester.pumpAndSettle();
    expect(sidebar().tabsOf(ws), [1, 100]);
    expect(sidebar().tabsOf(kDefaultWorkspaceId), [2]);
    expect(tabs().selectedId, 100); // the selection stays

    g = await startDrag(tester, row(2));
    await hover(tester, g, tester.getBottomLeft(row(1)) + const Offset(30, -4));
    expect(find.byKey(const Key('drop.line')), findsOneWidget);
    await hover(tester, g, const Offset(700, 300)); // over the terminal
    expect(find.byKey(const Key('drop.line')), findsNothing);
    await g.up();
    await tester.pumpAndSettle();
    expect(sidebar().tabsOf(ws), [1, 100]);
    expect(sidebar().tabsOf(kDefaultWorkspaceId), [2]);
  });

  testSidebar('a drag held near the bottom of the list scrolls it', (
    tester,
  ) async {
    for (var id = 1; id <= 40; id++) {
      local.add(local.summary(id, origin: SessionOrigin.desktop));
    }
    await pumpSidebar(tester);
    final controller = page(tester).sidebarScroll;
    expect(controller.offset, 0);
    final list = find.byType(ListView);
    final g = await startDrag(tester, row(1));
    await hover(tester, g, tester.getBottomLeft(list) + const Offset(30, -8));
    await tester.pump(const Duration(milliseconds: 500));
    expect(controller.offset, greaterThan(60));
    final held = controller.offset;
    await hover(tester, g, tester.getCenter(list)); // out of the zone
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.offset, held + 0); // stopped
    await g.up();
    await tester.pumpAndSettle();
  });

  testSidebar('a collapsed workspace holding the selected tab takes the '
      'keyboard ring; ← from a row goes to its header; F2 there renames '
      'and Esc gives the keyboard back to the list (D14, UI-A2 §4)', (
    tester,
  ) async {
    final ws = await twoWorkspaces(tester); // tab 100 selected
    workspaces().setCollapsed(ws, true);
    await tester.pumpAndSettle();
    await sendChord(tester, [
      LogicalKeyboardKey.controlLeft,
    ], LogicalKeyboardKey.f6);
    expect(page(tester).sidebarFocus.hasPrimaryFocus, isTrue);
    bool focused(String id) => tester
        .widget<WorkspaceHeader>(
          find.descendant(
            of: header(id),
            matching: find.byType(WorkspaceHeader),
          ),
        )
        .focused;
    expect(focused(ws), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(tabs().selectedId, 2);
    expect(focused(ws), isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(tabs().selectedId, 2);
    expect(focused(kDefaultWorkspaceId), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.pumpAndSettle();
    final field = find.descendant(
      of: header(kDefaultWorkspaceId),
      matching: find.byKey(const Key('row.renameField')),
    );
    expect(field, findsOneWidget);
    await tester.enterText(field, 'nope');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(sidebar().workspace(kDefaultWorkspaceId)!.name, isNull);
    expect(page(tester).sidebarFocus.hasPrimaryFocus, isTrue);
    expect(focused(kDefaultWorkspaceId), isTrue);
    // ← on an expanded header collapses it, → expands, → again enters.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(sidebar().workspace(kDefaultWorkspaceId)!.collapsed, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(sidebar().workspace(kDefaultWorkspaceId)!.collapsed, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(tabs().selectedId, 1);
  });

  testSidebar('Shift+F10 on a header opens its menu; Collapse from it', (
    tester,
  ) async {
    final ws = await twoWorkspaces(tester);
    await sendChord(tester, [
      LogicalKeyboardKey.controlLeft,
    ], LogicalKeyboardKey.f6);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp); // ws's header
    await tester.pump();
    await sendChord(tester, [
      LogicalKeyboardKey.shiftLeft,
    ], LogicalKeyboardKey.f10);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('menu.ws.newTab')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('menu.ws.toggle')),
        matching: find.text('Collapse'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('menu.ws.toggle')));
    await tester.pumpAndSettle();
    expect(sidebar().workspace(ws)!.collapsed, isTrue);
  });

  testSidebar('in a 46 px row a shown × wins its whole column over a port '
      'under it; elsewhere a port keeps its full 24 px', (tester) async {
    local
      ..add(
        local.summary(
          1,
          origin: SessionOrigin.desktop,
          cwd: '$testHome/work/a/very/long/path/to/somewhere',
          ports: [3000],
        ),
      )
      ..add(local.summary(2, origin: SessionOrigin.desktop, ports: [4000]));
    await pumpSidebar(tester);
    expect(tabs().selectedId, 1); // × shown
    final close = tester.getRect(
      find.descendant(of: row(1), matching: find.byKey(const Key('row.close'))),
    );
    final port = tester.getRect(find.byKey(const Key('port.3000')));
    final top = tester.getTopLeft(row(1)).dy;
    final x = max(close.left, port.left) + 2;
    expect(x, lessThan(min(close.right, port.right))); // one column
    expect(close.bottom - top, 27);
    expect(port.top - top, 21);
    // The bottom edge of the visible 20 px × (y 5–25), and its hit area
    // below it, close the tab.
    await tester.tapAt(Offset(close.center.dx, top + 24.5));
    await tester.pumpAndSettle();
    expect(local.closed, [1]);
    expect(h.urlOpener.ports, isEmpty);

    // Row 2 (selected now): its port sits left of the × column and takes
    // its whole 24 px, the top 6 px included.
    expect(tabs().selectedId, 2);
    final port2 = tester.getRect(find.byKey(const Key('port.4000')));
    await tester.tapAt(Offset(port2.center.dx, port2.top + 1));
    await tester.pumpAndSettle();
    expect(h.urlOpener.ports, [4000]);
  });

  // ---- review fix round 1 ------------------------------------------------

  Finder grabbing() => find.byWidgetPredicate(
    (w) => w is MouseRegion && w.cursor == SystemMouseCursors.grabbing,
  );

  testSidebar('a drag held in the bottom zone until its source row scrolled '
      'away still ends on release: no grabbing cursor, no more scrolling', (
    tester,
  ) async {
    for (var id = 1; id <= 40; id++) {
      local.add(local.summary(id, origin: SessionOrigin.desktop));
    }
    await pumpSidebar(tester);
    final controller = page(tester).sidebarScroll;
    final list = find.byType(ListView);
    final g = await startDrag(tester, row(1));
    expect(grabbing(), findsOneWidget);
    await hover(tester, g, tester.getBottomLeft(list) + const Offset(30, -8));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(row(1), findsNothing); // the source scrolled out of the list
    // Released over the terminal: no target takes it.
    await g.moveTo(const Offset(700, 300));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    expect(grabbing(), findsNothing);
    final at = controller.offset;
    await tester.pump(const Duration(milliseconds: 500));
    expect(controller.offset, at);
    expect(sidebar().tabsOf(kDefaultWorkspaceId).first, 1); // not moved
  });

  testSidebar('the tree cursor reaches screen readers: a header under the '
      'cursor is focused in semantics, and landing on it or toggling it is '
      'announced (D14, UI-A2 §8)', (tester) async {
    final handle = tester.ensureSemantics();
    final ws = await twoWorkspaces(tester);
    await sendChord(tester, [
      LogicalKeyboardKey.controlLeft,
    ], LogicalKeyboardKey.f6);
    tester.takeAnnouncements();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(
      tester.getSemantics(
        find.bySemanticsLabel('Workspace Workspace 2, 1 tab'),
      ),
      isSemantics(isFocused: true),
    );
    expect(tester.takeAnnouncements().map((a) => a.message), [
      'Workspace Workspace 2, 1 tab, expanded',
    ]);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(sidebar().workspace(ws)!.collapsed, isTrue);
    expect(tester.takeAnnouncements().map((a) => a.message), [
      'Workspace Workspace 2, 1 tab, contains the selected tab, '
          'collapsed',
    ]);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(tester.takeAnnouncements().map((a) => a.message), [
      'Workspace Workspace 2, 1 tab, expanded',
    ]);
    handle.dispose();
  });

  testSidebar("a drop is announced with the tab's new place", (tester) async {
    final ws = await twoWorkspaces(tester);
    tester.takeAnnouncements();
    final g = await startDrag(tester, row(1));
    await hover(tester, g, tester.getCenter(header(ws)));
    await g.up();
    await tester.pumpAndSettle();
    expect(sidebar().tabsOf(ws), [100, 1]); // an open header: its end
    expect(
      tester.takeAnnouncements().single.message,
      endsWith('tab 2 of 2 in Workspace 2'),
    );
  });

  testSidebar('a click on the chevron toggles at once; the header looks '
      'pressed while the button is down', (tester) async {
    final ws = await twoWorkspaces(tester);
    final chevron = find.descendant(
      of: header(ws),
      matching: find.byIcon(Icons.chevron_right),
    );
    final g = await tester.startGesture(
      tester.getCenter(chevron),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    final box = tester.widget<AnimatedContainer>(
      find
          .descendant(of: header(ws), matching: find.byType(AnimatedContainer))
          .first,
    );
    expect(
      (box.decoration! as BoxDecoration).color,
      ShellxDesktopColors.rowPressed,
    );
    await g.up();
    await tester.pump(); // no double-tap wait on the chevron
    expect(sidebar().workspace(ws)!.collapsed, isTrue);
  });

  testSidebar('drop target look adds no layout shift; the 8 px above a '
      'header drops into it; no drop line where the tab already is', (
    tester,
  ) async {
    final ws = await twoWorkspaces(tester);
    final name = find.descendant(
      of: header(ws),
      matching: find.text('Workspace 2'),
    );
    final before = tester.getTopLeft(name);
    var g = await startDrag(tester, row(1)); // row 1's lower half: no-op
    expect(find.byKey(const Key('drop.line')), findsNothing);
    await hover(tester, g, tester.getTopLeft(row(2)) + const Offset(30, 4));
    expect(find.byKey(const Key('drop.line')), findsNothing); // still no-op
    await hover(tester, g, tester.getCenter(header(ws)));
    expect(
      tester
          .widget<WorkspaceHeader>(find.byType(WorkspaceHeader).last)
          .dropTarget,
      isTrue,
    );
    expect(tester.getTopLeft(name), before);
    await hover(
      tester,
      g,
      tester.getTopLeft(header(ws)) + const Offset(30, -4),
    );
    expect(
      tester
          .widget<WorkspaceHeader>(find.byType(WorkspaceHeader).last)
          .dropTarget,
      isTrue,
    );
    await g.up();
    await tester.pumpAndSettle();
    expect(sidebar().tabsOf(ws), [100, 1]);
    g = await startDrag(tester, row(2));
    await g.up();
    await tester.pumpAndSettle();
    expect(sidebar().tabsOf(kDefaultWorkspaceId), [2]);
  });

  testSidebar('End reaches the last row; ⌥↑ on a header moves nothing', (
    tester,
  ) async {
    final ws = await twoWorkspaces(tester);
    tabs();
    container.read(terminalTabsProvider.notifier).select(1);
    await tester.pump();
    await sendChord(tester, [
      LogicalKeyboardKey.controlLeft,
    ], LogicalKeyboardKey.f6);
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();
    expect(tabs().selectedId, 100);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp); // ws's header
    await tester.pump();
    await sendChord(tester, [
      LogicalKeyboardKey.altLeft,
    ], LogicalKeyboardKey.arrowUp);
    expect(sidebar().tabsOf(ws), [100]);
    expect(sidebar().tabsOf(kDefaultWorkspaceId), [1, 2]);
    expect(
      tester
          .widget<WorkspaceHeader>(
            find.descendant(
              of: header(ws),
              matching: find.byType(WorkspaceHeader),
            ),
          )
          .focused,
      isTrue,
    );
  });

  testSidebar('scrolling under a held drag drops the stale slot', (
    tester,
  ) async {
    for (var id = 1; id <= 40; id++) {
      local.add(local.summary(id, origin: SessionOrigin.desktop));
    }
    await pumpSidebar(tester);
    final list = find.byType(ListView);
    final g = await startDrag(tester, row(1));
    await hover(tester, g, tester.getBottomLeft(list) + const Offset(30, -8));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const Key('drop.line')), findsNothing);
    await g.up();
    await tester.pumpAndSettle();
    expect(sidebar().tabsOf(kDefaultWorkspaceId).first, 1); // not moved
  });

  testSidebar('a tab name field survives a row closing above it: the typed '
      'text stays and Enter keeps it', (tester) async {
    for (var id = 1; id <= 3; id++) {
      local.add(local.summary(id, origin: SessionOrigin.desktop));
    }
    await pumpSidebar(tester);
    container.read(terminalTabsProvider.notifier).select(3);
    await tester.pump();
    workspaces().startRename(const RenameTab(3));
    await tester.pumpAndSettle();
    final field = find.byKey(const Key('row.renameField'));
    await tester.enterText(field, 'ap');
    local.close(1);
    await tester.pumpAndSettle();
    expect(row(1), findsNothing);
    expect(
      find.descendant(of: row(3), matching: find.text('ap')),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(tabs().tabs.firstWhere((t) => t.id == 3).label, 'ap');
    await tester.pump(const Duration(seconds: 1));
    expect(tabs().tabs.firstWhere((t) => t.id == 3).label, 'ap');
  });

  testSidebar('a workspace name field survives a row closing above it', (
    tester,
  ) async {
    final ws = await twoWorkspaces(tester);
    workspaces().startRename(RenameWorkspace(ws));
    await tester.pumpAndSettle();
    final field = find.descendant(
      of: header(ws),
      matching: find.byKey(const Key('row.renameField')),
    );
    await tester.enterText(field, 'Bac');
    local.close(1);
    await tester.pumpAndSettle();
    expect(row(1), findsNothing);
    expect(
      find.descendant(of: field, matching: find.text('Bac')),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(sidebar().workspace(ws)!.name, 'Bac');
  });

  testSidebar('the keyboard ring appears at once, without a fade', (
    tester,
  ) async {
    final ws = await twoWorkspaces(tester); // tab 100 selected
    bool ringShown(Finder of) => tester
        .widgetList<DecoratedBox>(
          find.descendant(of: of, matching: find.byType(DecoratedBox)),
        )
        .any((d) {
          final border = (d.decoration as BoxDecoration).border;
          return border is Border &&
              border.top.color == ShellxDesktopColors.accent &&
              border.top.width == ShellxSizes.focusRing;
        });
    await sendChord(tester, [
      LogicalKeyboardKey.controlLeft,
    ], LogicalKeyboardKey.f6);
    expect(ringShown(row(100)), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(ringShown(header(ws)), isTrue);
  });

  testWidgets('a name field rebuilt elsewhere for the same item does not '
      'commit late over the open one', (tester) async {
    final commits = <String>[];
    Widget field(Key key) => MaterialApp(
      home: Material(
        child: InlineNameField(
          key: key,
          identity: const ('tab', 3),
          initial: 'zsh 3',
          style: ShellxText.body,
          label: 'Tab name',
          onCommit: commits.add,
          onCancel: () {},
        ),
      ),
    );
    await tester.pumpWidget(field(const ValueKey(1)));
    await tester.enterText(find.byType(TextField), 'ap');
    await tester.pumpWidget(field(const ValueKey(2))); // a fresh field
    await tester.pump();
    expect(commits, isEmpty);
    await tester.pumpWidget(const SizedBox()); // the open one goes away
    await tester.pump();
    expect(commits, ['zsh 3']);
  });
}
