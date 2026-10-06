import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
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

  testSidebar('in a 46 px row the × and a port under it split their 6 px '
      'overlap: the upper half closes, the lower half opens the port', (
    tester,
  ) async {
    local
      ..add(
        local.summary(
          1,
          origin: SessionOrigin.desktop,
          cwd: '$testHome/work/a/very/long/path/to/somewhere',
          ports: [3000],
        ),
      )
      ..add(local.summary(2, origin: SessionOrigin.desktop));
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
    await tester.tapAt(Offset(x, top + 25));
    await tester.pumpAndSettle();
    expect(h.urlOpener.ports, [3000]);
    expect(local.closed, isEmpty);
    await tester.tapAt(Offset(x, top + 23));
    await tester.pumpAndSettle();
    expect(local.closed, [1]);
  });
}
