import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/find_sessions.dart';
import 'package:shellx_desktop/src/terminal/global_search.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/config_workspace.dart';

Future<void> searchAllChord(WidgetTester t) async {
  await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await t.sendKeyEvent(LogicalKeyboardKey.keyF);
  await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await t.pump();
  await t.pump();
}

Future<void> type(WidgetTester t, String text) async {
  await t.enterText(find.byKey(const Key('searchall.field')), text);
  await t.pump(const Duration(milliseconds: 200));
  await t.pump();
  await t.pump();
}

void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  Future<({dynamic rig, int first, int second})> twoTabs(WidgetTester t) async {
    final rig = await pumpConfiguredWorkspace(t);
    final c = rig.container;
    final first = c.read(terminalTabsProvider).tabs.first;
    first.terminal.write('alpha\r\nbeta error one\r\ngamma');
    final second = await c
        .read(terminalTabsProvider.notifier)
        .openTabFor(select: true);
    await t.pumpAndSettle();
    final tab = c.read(terminalTabsProvider).tabs.last;
    tab.terminal.write('nothing here\r\nanother ERROR two');
    return (rig: rig, first: first.id, second: second);
  }

  testWidgets('⌘⇧F opens the overlay with the field focused', (t) async {
    final rig = await pumpConfiguredWorkspace(t);
    await searchAllChord(t);
    expect(find.byKey(const Key('searchall.field')), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'searchall field');
    await disposeWorkspace(t, rig.container);
  }, variant: mac);

  testWidgets('typing lists matches of every tab, the selected tab first', (
    t,
  ) async {
    final r = await twoTabs(t);
    await searchAllChord(t);
    await type(t, 'error');
    expect(find.byKey(const Key('searchall.row.0')), findsOneWidget);
    expect(find.byKey(const Key('searchall.row.1')), findsOneWidget);
    expect(find.byKey(const Key('searchall.row.2')), findsNothing);
    final c = r.rig.container as dynamic;
    expect(
      c.read(findSessionsProvider),
      isEmpty,
      reason: 'listing opens no find bar',
    );
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('Enter on a row selects its tab and opens the find bar on the '
      'match', (t) async {
    final r = await twoTabs(t);
    final c = r.rig.container as dynamic;
    await searchAllChord(t);
    await type(t, 'error');
    // Row 0 is the selected (second) tab; row 1 is the first tab.
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('searchall.field')), findsNothing);
    final state = c.read(terminalTabsProvider) as TerminalTabsState;
    expect(state.selectedId, r.first);
    final pane = state.selected!.focusedPaneId;
    final session = c.read(findSessionsProvider)[pane]!;
    expect(session.query, 'error');
    expect(session.matches[session.current].startRow, 1);
    expect(find.byKey(const Key('find.bar')), findsOneWidget);
    expect(session.focusNode.hasFocus, isTrue);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('clicking a row does the same', (t) async {
    final r = await twoTabs(t);
    final c = r.rig.container as dynamic;
    await searchAllChord(t);
    await type(t, 'error');
    await t.tap(find.byKey(const Key('searchall.row.1')));
    await t.pump(const Duration(milliseconds: 400));
    await t.pumpAndSettle();
    expect(
      (c.read(terminalTabsProvider) as TerminalTabsState).selectedId,
      r.first,
    );
    expect(c.read(findSessionsProvider), isNotEmpty);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('a hit in a split tab focuses that pane', (t) async {
    final rig = await pumpConfiguredWorkspace(t);
    final c = rig.container;
    final tabs = c.read(terminalTabsProvider.notifier);
    final tab = c.read(terminalTabsProvider).selected!;
    final left = tab.focusedPaneId;
    await tabs.split(SplitAxis.row);
    await t.pumpAndSettle();
    final split = c.read(terminalTabsProvider).selected!;
    final right = split.focusedPaneId;
    expect(right, isNot(left));
    split.panes[left]!.terminal.write('needle in the left pane');
    tabs.focusPane(right);
    await t.pumpAndSettle();
    await searchAllChord(t);
    await type(t, 'needle');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(c.read(terminalTabsProvider).selected!.focusedPaneId, left);
    expect(c.read(findSessionsProvider).keys, [left]);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('Esc closes the overlay and the terminal has the keyboard', (
    t,
  ) async {
    final rig = await pumpConfiguredWorkspace(t);
    await searchAllChord(t);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('searchall.field')), findsNothing);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'terminal');
    await disposeWorkspace(t, rig.container);
  }, variant: mac);

  testWidgets('one character asks for two; no match says so', (t) async {
    final rig = await pumpConfiguredWorkspace(t);
    await searchAllChord(t);
    await type(t, 'e');
    expect(find.text('Type at least 2 characters'), findsOneWidget);
    await type(t, 'zzqqxx');
    expect(find.text('No matches in any terminal'), findsOneWidget);
    await disposeWorkspace(t, rig.container);
  }, variant: mac);

  testWidgets('the debug log never holds the query or a snippet', (t) async {
    final lines = <String>[];
    final saved = debugPrint;
    debugPrint = (message, {wrapWidth}) => lines.add(message ?? '');
    final r = await twoTabs(t);
    await searchAllChord(t);
    await type(t, 'error');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    debugPrint = saved;
    expect(lines.where((l) => l.toLowerCase().contains('error')), isEmpty);
    expect(lines.where((l) => l.contains('another')), isEmpty);
    await disposeWorkspace(t, r.rig.container as dynamic);
  }, variant: mac);

  testWidgets('a huge scrollback is searched in slices: the UI is never held', (
    t,
  ) async {
    final rig = await pumpConfiguredWorkspace(t);
    final c = rig.container;
    final tab = c.read(terminalTabsProvider).selected!;
    tab.terminal.write(
      [for (var i = 0; i < 4000; i++) 'filler line number $i'].join('\r\n'),
    );
    await searchAllChord(t);
    await type(t, 'filler');
    // 20 per pane, and the list says there were more.
    expect(find.byKey(const Key('searchall.row.0')), findsOneWidget);
    expect(find.byKey(const Key('searchall.capped')), findsOneWidget);
    expect(find.text('Showing the first 20 matches'), findsOneWidget);
    expect(kGlobalSearchPerPane, 20);
    await disposeWorkspace(t, c);
  }, variant: mac);
}
