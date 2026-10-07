import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TextField, ValueKey;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart' show SessionLimitException;
import 'package:shellx_desktop/src/restore/restore_snapshot.dart';
import 'package:shellx_desktop/src/terminal/closed_items.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/config_workspace.dart';

Future<void> reopenChord(WidgetTester t) async {
  await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await t.sendKeyEvent(LogicalKeyboardKey.keyT);
  await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await t.pump();
  await t.pump();
}

String textOf(PaneSession pane) => pane.terminal.buffer.getText();

void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  testWidgets('⌘⇧T brings the closed tab back, selected, with its '
      'scrollback above a divider and a new shell', (t) async {
    final rig = await pumpConfiguredWorkspace(t);
    final c = rig.container;
    final tabs = c.read(terminalTabsProvider.notifier);
    final second = await tabs.openTabFor(select: true);
    await t.pumpAndSettle();
    c.read(terminalTabsProvider).tabs.last.terminal.write('hello history');
    final sessionsBefore = rig.local.sessions.length;
    tabs.close(second);
    await t.pumpAndSettle();
    expect(c.read(closedItemsProvider).length, 1);
    expect(rig.local.sessions.length, sessionsBefore - 1);

    await reopenChord(t);
    await t.pumpAndSettle();
    final state = c.read(terminalTabsProvider);
    expect(state.tabs, hasLength(2));
    final tab = state.selected!;
    expect(tab.id, state.tabs.last.id, reason: 'the reopened tab is selected');
    expect(textOf(tab.focused), contains('hello history'));
    expect(textOf(tab.focused), contains('Session restored'));
    expect(rig.local.sessions.length, sessionsBefore, reason: 'no leak');
    expect(
      c.read(closedItemsProvider).length,
      0,
      reason: 'it is out of the ring',
    );
    // Only the new shell is written to, and nothing was replayed into it.
    expect(rig.local.views[tab.focusedPaneId]!.writes, isEmpty);
    expect(state.notice, isA<ReopenedNotice>());
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('a pane closed from a split tab comes back beside the focused '
      'one and takes the focus', (t) async {
    final rig = await pumpConfiguredWorkspace(t);
    final c = rig.container;
    final tabs = c.read(terminalTabsProvider.notifier);
    await tabs.split(SplitAxis.row);
    await t.pumpAndSettle();
    final tab = c.read(terminalTabsProvider).selected!;
    expect(tab.paneCount, 2);
    final doomed = tab.focusedPaneId;
    tab.panes[doomed]!.terminal.write('pane text');
    tabs.closePane(doomed);
    await t.pumpAndSettle();
    expect(c.read(terminalTabsProvider).selected!.paneCount, 1);

    await reopenChord(t);
    await t.pumpAndSettle();
    final after = c.read(terminalTabsProvider).selected!;
    expect(after.id, tab.id);
    expect(after.paneCount, 2);
    expect(after.focusedPaneId, isNot(doomed));
    expect(textOf(after.focused), contains('pane text'));
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('with nothing closed, ⌘⇧T says so', (t) async {
    final rig = await pumpConfiguredWorkspace(t);
    final c = rig.container;
    await reopenChord(t);
    expect(c.read(terminalTabsProvider).notice, isA<ReopenNothingNotice>());
    expect(c.read(terminalTabsProvider).tabs, hasLength(1));
    await disposeWorkspace(t, c);
  }, variant: mac);

  test('the history is memory only: its code has no file access and no '
      'way to the restore store or the settings', () {
    final source = File(
      'lib/src/terminal/closed_items.dart',
    ).readAsStringSync();
    final imports = RegExp(
      r"^import '([^']+)'",
      multiLine: true,
    ).allMatches(source).map((m) => m.group(1)!).toList();
    expect(imports, isNot(contains('dart:io')));
    for (final bad in [
      'restore_store',
      'restore_persistence',
      'settings_store',
    ]) {
      expect(imports.any((i) => i.contains(bad)), isFalse, reason: bad);
    }
  });

  testWidgets('closing while a restore runs records nothing', (t) async {
    final rig = await pumpConfiguredWorkspace(t);
    final c = rig.container;
    final tabs = c.read(terminalTabsProvider.notifier);
    final second = await tabs.openTabFor(select: true);
    await t.pumpAndSettle();
    final gate = rig.local.cwdGates['/slow'] = Completer<void>();
    final key = newPaneKey();
    final running = tabs.restore(
      RestorePlan(
        snapshot: RestoreSnapshot(
          savedAt: DateTime.utc(2026, 10, 7),
          cleanExit: true,
          selectedTab: key,
          workspaces: [
            SavedWorkspace(id: 'default', tabs: [key]),
          ],
          tabs: [
            SavedTab(
              key: key,
              focused: key,
              layout: SavedPane(key: key, cwd: '/slow'),
            ),
          ],
        ),
        textByKey: const {},
      ),
    );
    await t.pump();
    expect(tabs.restoring, isTrue);
    tabs.close(second);
    await t.pump();
    expect(c.read(closedItemsProvider).length, 0);
    gate.complete();
    await running;
    await t.pumpAndSettle();
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('a close never logs what the terminal showed', (t) async {
    final logs = <String>[];
    final original = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
    final rig = await pumpConfiguredWorkspace(t);
    final c = rig.container;
    final tabs = c.read(terminalTabsProvider.notifier);
    final second = await tabs.openTabFor(select: true);
    await t.pumpAndSettle();
    c.read(terminalTabsProvider).tabs.last.terminal.write('hello history');
    tabs.close(second);
    await t.pumpAndSettle();
    await reopenChord(t);
    await t.pumpAndSettle();
    debugPrint = original;
    expect(logs.join().contains('hello history'), isFalse);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('a refused reopen puts the item back', (t) async {
    final rig = await pumpConfiguredWorkspace(t);
    final c = rig.container;
    final tabs = c.read(terminalTabsProvider.notifier);
    final second = await tabs.openTabFor(select: true);
    await t.pumpAndSettle();
    c.read(terminalTabsProvider).tabs.last.terminal.write('keep me');
    tabs.close(second);
    await t.pumpAndSettle();
    rig.local.openError = const SessionLimitException(2);
    await reopenChord(t);
    await t.pumpAndSettle();
    expect(c.read(closedItemsProvider).length, 1);
    rig.local.openError = null;
    await reopenChord(t);
    await t.pumpAndSettle();
    expect(c.read(terminalTabsProvider).tabs, hasLength(2));
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('the palette offers "Reopen closed tab" only when there is '
      'something to reopen', (t) async {
    final rig = await pumpConfiguredWorkspace(t);
    final c = rig.container;
    Future<void> palette() async {
      await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.keyP);
      await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'reopen');
      await t.pumpAndSettle();
    }

    await palette();
    expect(find.byKey(const ValueKey('palette.row.0')), findsNothing);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    final tabs = c.read(terminalTabsProvider.notifier);
    final second = await tabs.openTabFor(select: true);
    await t.pumpAndSettle();
    c.read(terminalTabsProvider).tabs.last.terminal.write('worth keeping');
    tabs.close(second);
    await t.pumpAndSettle();
    await palette();
    expect(
      t.getSemantics(find.byKey(const ValueKey('palette.row.0'))).label,
      startsWith('Reopen closed tab'),
    );
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(c.read(terminalTabsProvider).tabs, hasLength(2));
    await disposeWorkspace(t, c);
  }, variant: mac);
}
