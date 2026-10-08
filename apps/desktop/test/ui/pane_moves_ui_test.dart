import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart' show SshTarget;
import 'package:shellx_desktop/src/terminal/closed_items.dart';
import 'package:shellx_desktop/src/terminal/focus_history.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/config_workspace.dart';

Future<void> openPalette(WidgetTester t) async {
  await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await t.sendKeyEvent(LogicalKeyboardKey.keyP);
  await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await t.pump();
  await t.pump();
}

/// Runs the palette entry whose title is [title]: types it, presses Enter.
Future<void> runEntry(WidgetTester t, String title) async {
  await openPalette(t);
  await t.enterText(
    find.descendant(
      of: find.byKey(const ValueKey('a9.palette')),
      matching: find.byType(TextField),
    ),
    title,
  );
  await t.pump();
  await t.sendKeyEvent(LogicalKeyboardKey.enter);
  await t.pumpAndSettle();
}

void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  testWidgets('Move pane to its own tab: a tab more, the shell untouched', (
    t,
  ) async {
    final rig = await pumpConfiguredWorkspace(t);
    final c = rig.container;
    final tabs = c.read(terminalTabsProvider.notifier);
    await tabs.split(SplitAxis.row);
    await t.pumpAndSettle();
    final tab = c.read(terminalTabsProvider).selected!;
    final moved = tab.focusedPaneId;
    final terminal = tab.panes[moved]!.terminal;
    terminal.write('scrollback of the moved pane');
    final sessions = rig.local.sessions.length;

    await runEntry(t, 'Move pane to its own tab');

    final state = c.read(terminalTabsProvider);
    expect(state.tabs, hasLength(2));
    expect(state.selected!.id, moved, reason: 'the new tab is selected');
    expect(state.selected!.panes[moved]!.terminal, same(terminal));
    expect(
      terminal.buffer.getText(),
      contains('scrollback of the moved pane'),
      reason: 'no scrollback lost',
    );
    expect(state.tabs.first.paneCount, 1);
    expect(rig.local.sessions.length, sessions, reason: 'no session ended');
    expect(rig.local.closed, isEmpty, reason: 'no shell was closed');
    expect(c.read(closedItemsProvider).length, 0, reason: 'not a close');
    expect(
      c.read(sidebarWorkspacesProvider).workspaceOf(moved),
      c.read(sidebarWorkspacesProvider).workspaceOf(state.tabs.first.id),
      reason: 'the new tab sits in the same workspace',
    );
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('breaking out the pane that created the tab gives the new tab '
      'another id and keeps the old tab', (t) async {
    final rig = await pumpConfiguredWorkspace(t);
    final c = rig.container;
    final tabs = c.read(terminalTabsProvider.notifier);
    final first = c.read(terminalTabsProvider).selected!;
    await tabs.split(SplitAxis.row);
    await t.pumpAndSettle();
    expect(tabs.breakPane(first.id), isTrue);
    await t.pumpAndSettle();
    final state = c.read(terminalTabsProvider);
    expect(state.tabs.map((x) => x.id).toSet(), hasLength(2));
    expect(state.tabs.first.id, first.id);
    expect(state.selected!.id, kSyntheticTabIdBase);
    expect(state.selected!.paneOrder, [first.id]);
    expect(state.tabOfSession(first.id)!.id, kSyntheticTabIdBase);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('Swap with the pane on the right changes the order, the focus '
      'stays on the same shell', (t) async {
    final rig = await pumpConfiguredWorkspace(t);
    final c = rig.container;
    final tabs = c.read(terminalTabsProvider.notifier);
    await tabs.split(SplitAxis.row);
    await t.pumpAndSettle();
    final before = c.read(terminalTabsProvider).selected!;
    final left = before.paneOrder.first;
    tabs.focusPane(left);
    await t.pumpAndSettle();
    final sizes = rig.local.views[left]!.resizes.length;

    await runEntry(t, 'Swap pane with the one on the right');

    final after = c.read(terminalTabsProvider).selected!;
    expect(after.paneOrder, before.paneOrder.reversed.toList());
    expect(after.focusedPaneId, left, reason: 'the focus follows the shell');
    expect(rig.local.closed, isEmpty);
    expect(
      rig.local.views[left]!.resizes.length,
      greaterThanOrEqualTo(sizes),
      reason: 'sizes only ever go to the live session',
    );
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('swap is off with nothing on that side (not in the palette)', (
    t,
  ) async {
    final rig = await pumpConfiguredWorkspace(t);
    final c = rig.container;
    await c.read(terminalTabsProvider.notifier).split(SplitAxis.row);
    await t.pumpAndSettle();
    final tab = c.read(terminalTabsProvider).selected!;
    c.read(terminalTabsProvider.notifier).focusPane(tab.paneOrder.first);
    await t.pumpAndSettle();
    await openPalette(t);
    await t.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('a9.palette')),
        matching: find.byType(TextField),
      ),
      'Swap pane with the one',
    );
    await t.pump();
    expect(find.text('Swap pane with the one on the right'), findsOneWidget);
    expect(find.text('Swap pane with the one on the left'), findsNothing);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('Move pane to tab: the pane joins the other tab, an emptied tab '
      'goes, the shell lives, the closing history stays empty', (t) async {
    final rig = await pumpConfiguredWorkspace(t);
    final c = rig.container;
    final tabs = c.read(terminalTabsProvider.notifier);
    final first = c.read(terminalTabsProvider).tabs.first;
    first.terminal.write('left behind');
    final second = await tabs.openTabFor(select: true);
    await t.pumpAndSettle();
    final moving = c.read(terminalTabsProvider).selected!;
    moving.terminal.write('travelling text');
    final terminal = moving.terminal;
    final sessions = rig.local.sessions.length;

    await runEntry(t, 'Move pane to tab');

    final state = c.read(terminalTabsProvider);
    expect(state.tabs.map((x) => x.id), [first.id], reason: 'emptied tab goes');
    expect(state.selected!.id, first.id);
    expect(state.selected!.paneOrder, [first.id, second]);
    expect(state.selected!.focusedPaneId, second);
    expect(state.selected!.panes[second]!.terminal, same(terminal));
    expect(terminal.buffer.getText(), contains('travelling text'));
    expect(rig.local.sessions.length, sessions);
    expect(rig.local.closed, isEmpty);
    expect(c.read(closedItemsProvider).length, 0);
    expect(
      c.read(sidebarWorkspacesProvider).workspaceOf(second),
      isNull,
      reason: 'the emptied tab left the sidebar',
    );
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('Move tab to a workspace from the palette, SSH workspaces '
      'included', (t) async {
    final rig = await pumpConfiguredWorkspace(t);
    final c = rig.container;
    final side = c.read(sidebarWorkspacesProvider.notifier);
    final work = side.createFor(name: 'Work');
    final tab = c.read(terminalTabsProvider).selected!;
    expect(c.read(sidebarWorkspacesProvider).workspaceOf(tab.id), isNot(work));

    await runEntry(t, 'Move tab to Work');
    expect(c.read(sidebarWorkspacesProvider).workspaceOf(tab.id), work);

    final ssh = side.createForHost(SshTarget.parse('devbox')!);
    await runEntry(t, 'Move tab to devbox');
    expect(c.read(sidebarWorkspacesProvider).workspaceOf(tab.id), ssh);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('a pane menu lists the moves; join through the menu', (t) async {
    final rig = await pumpConfiguredWorkspace(t);
    final c = rig.container;
    final tabs = c.read(terminalTabsProvider.notifier);
    final first = c.read(terminalTabsProvider).tabs.first;
    await tabs.openTabFor(select: true);
    await t.pumpAndSettle();
    await tabs.split(SplitAxis.row);
    await t.pumpAndSettle();
    await t.tapAt(
      t.getCenter(find.byType(Scaffold).first),
      buttons: kSecondaryButton,
      kind: PointerDeviceKind.mouse,
    );
    await t.pump(const Duration(milliseconds: 400));
    await t.pumpAndSettle();
    // The menu focuses the pane under the pointer first.
    final pane = c.read(terminalTabsProvider).selected!.focusedPaneId;
    expect(find.byKey(const Key('menu.breakPane')), findsOneWidget);
    expect(find.byKey(const Key('menu.swapPane')), findsOneWidget);
    expect(find.byKey(const Key('menu.moveToTab')), findsOneWidget);
    await t.tap(find.byKey(const Key('menu.moveToTab')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(Key('menu.moveToTab.${first.id}')));
    await t.pumpAndSettle();
    final state = c.read(terminalTabsProvider);
    expect(state.tabOfSession(pane)!.id, first.id);
    expect(state.selected!.id, first.id);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('focus history follows a moved pane', (t) async {
    final rig = await pumpConfiguredWorkspace(t);
    final c = rig.container;
    final tabs = c.read(terminalTabsProvider.notifier);
    c.read(focusHistoryProvider);
    final first = c.read(terminalTabsProvider).tabs.first;
    await tabs.openTabFor(select: true);
    await t.pumpAndSettle();
    final moving = c.read(terminalTabsProvider).selected!;
    await tabs.split(SplitAxis.row);
    await t.pumpAndSettle();
    final pane = moving.id;
    tabs.focusPane(pane);
    await t.pumpAndSettle();
    expect(tabs.joinPane(pane, first.id), isTrue);
    await t.pumpAndSettle();
    expect(c.read(focusHistoryProvider).current, FocusEntry(first.id, pane));
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('a moved pane tells its session the new size once, after it '
      'settles (A10 D20)', (t) async {
    final rig = await pumpConfiguredWorkspace(
      t,
      settle: const Duration(milliseconds: 80),
    );
    final c = rig.container;
    final tabs = c.read(terminalTabsProvider.notifier);
    final first = c.read(terminalTabsProvider).tabs.first;
    final second = await tabs.openTabFor(select: true);
    await t.pumpAndSettle();
    tabs.flushResizes();
    final view = rig.local.views[second]!;
    final before = view.resizes.length;

    final oldSize = (
      c.read(terminalTabsProvider).selected!.terminal.viewWidth,
      c.read(terminalTabsProvider).selected!.terminal.viewHeight,
    );
    expect(tabs.joinPane(second, first.id), isTrue);
    await t.pump();
    // Selecting the tab re-sends the size the session already has.
    final shown = view.resizes.length;
    expect(view.resizes.skip(before), everyElement(oldSize));
    await t.pump(const Duration(milliseconds: 20));
    expect(view.resizes.length, shown, reason: 'not while it still moves');
    await t.pump(const Duration(milliseconds: 200));
    await t.pumpAndSettle();
    expect(view.resizes.length, shown + 1, reason: 'the new size, once');
    final terminal = c
        .read(terminalTabsProvider)
        .selected!
        .panes[second]!
        .terminal;
    expect(view.resizes.last, (terminal.viewWidth, terminal.viewHeight));
    expect(view.resizes.last, isNot(oldSize));
    await disposeWorkspace(t, c);
  }, variant: mac);
}
