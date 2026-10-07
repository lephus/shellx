import 'package:flutter/widgets.dart' show FocusManager;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/focus_history.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/config_workspace.dart';

/// ⌘⌃[ (back) or ⌘⌃] (forward).
Future<void> walk(WidgetTester t, {required bool back}) async {
  await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await t.sendKeyEvent(
    back ? LogicalKeyboardKey.bracketLeft : LogicalKeyboardKey.bracketRight,
  );
  await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await t.pumpAndSettle();
}

void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  testWidgets('⌘⌃[ and ⌘⌃] walk back and forward through the tabs used, and '
      'walking adds no history', (t) async {
    final rig = await pumpConfiguredWorkspace(t);
    final c = rig.container;
    final tabs = c.read(terminalTabsProvider.notifier);
    final one = c.read(terminalTabsProvider).selectedId!;
    final two = await tabs.openTabFor(select: true);
    final three = await tabs.openTabFor(select: true);
    await t.pumpAndSettle();
    final history = c.read(focusHistoryProvider);
    expect(c.read(terminalTabsProvider).selectedId, three);
    final length = history.length;

    await walk(t, back: true);
    expect(c.read(terminalTabsProvider).selectedId, two);
    await walk(t, back: true);
    expect(c.read(terminalTabsProvider).selectedId, one);
    await walk(t, back: true);
    expect(c.read(terminalTabsProvider).selectedId, one, reason: 'the start');
    await walk(t, back: false);
    expect(c.read(terminalTabsProvider).selectedId, two);
    expect(history.length, length, reason: 'going back is not a visit');
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'terminal',
      reason: 'the terminal has the keyboard',
    );
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('a closed tab is skipped', (t) async {
    final rig = await pumpConfiguredWorkspace(t);
    final c = rig.container;
    final tabs = c.read(terminalTabsProvider.notifier);
    final one = c.read(terminalTabsProvider).selectedId!;
    final two = await tabs.openTabFor(select: true);
    final three = await tabs.openTabFor(select: true);
    tabs.select(one);
    await t.pumpAndSettle();
    final history = c.read(focusHistoryProvider);
    tabs.close(two);
    await t.pumpAndSettle();
    expect(history.length, 4, reason: 'closing a tab is not a visit');
    await walk(t, back: true);
    expect(c.read(terminalTabsProvider).selectedId, three);
    await walk(t, back: true);
    expect(c.read(terminalTabsProvider).selectedId, one);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('closing the tab you are in: the successor is not a visit, and '
      'back does not return to where you already are', (t) async {
    final rig = await pumpConfiguredWorkspace(t);
    final c = rig.container;
    final tabs = c.read(terminalTabsProvider.notifier);
    final one = c.read(terminalTabsProvider).selectedId!;
    await tabs.openTabFor(select: true);
    final three = await tabs.openTabFor(select: true);
    await t.pumpAndSettle();
    final history = c.read(focusHistoryProvider);
    final length = history.length;
    tabs.close(three);
    await t.pumpAndSettle();
    expect(history.length, length);
    final landed = c.read(terminalTabsProvider).selectedId!;
    expect(landed, isNot(three));
    await walk(t, back: true);
    expect(
      c.read(terminalTabsProvider).selectedId,
      one,
      reason: 'the tab before the one the close handed over',
    );
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('panes of a split tab are places too', (t) async {
    final rig = await pumpConfiguredWorkspace(t);
    final c = rig.container;
    final tabs = c.read(terminalTabsProvider.notifier);
    await tabs.split(SplitAxis.row);
    await t.pumpAndSettle();
    final tab = c.read(terminalTabsProvider).selected!;
    final second = tab.focusedPaneId;
    final first = tab.paneOrder.firstWhere((id) => id != second);
    tabs.focusPane(first);
    await t.pumpAndSettle();
    await walk(t, back: true);
    expect(c.read(terminalTabsProvider).selected!.focusedPaneId, second);
    await walk(t, back: false);
    expect(c.read(terminalTabsProvider).selected!.focusedPaneId, first);
    await disposeWorkspace(t, c);
  }, variant: mac);
}
