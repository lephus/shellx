import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/tab_attention.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/terminal/pane_tree_view.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_intents.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_workspace_page.dart';
import 'package:shellx_desktop/src/ui/window_focus.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

import '../support/ai_fakes.dart';
import '../support/ai_tabs.dart';
import '../support/config_workspace.dart';

/// A split AI tab (the AI pane over a terminal, V2-1 D3) in the window: what
/// the menus, the shortcuts and the panels do with a pane that is not a
/// terminal's. (V2-1 B10: no pane moves into or out of an AI tab. The tab
/// list refuses `breakPane`, `joinPane` and `swapFocusedPane`; the menus, the
/// shortcuts and the palette must not offer what it refuses.)
void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  Future<ProviderContainer> workspace(WidgetTester t) async {
    final rig = await pumpConfiguredWorkspace(
      t,
      platform: TargetPlatform.macOS,
      extra: FakeAiRuntimes(const FakeScenario()).overrides,
    );
    return rig.container;
  }

  /// An AI tab with a terminal under its AI pane (⌘D in the AI pane), selected.
  Future<TerminalTab> splitAiTab(WidgetTester t, ProviderContainer c) async {
    final ai = openTestAiTab(c, title: 'Fix login', cwd: testAiCwd);
    await c.read(terminalTabsProvider.notifier).openAiTerminal(ai.id);
    await t.pumpAndSettle();
    return c.read(terminalTabsProvider).tabs.firstWhere((x) => x.id == ai.id);
  }

  Future<void> rightClickTerminal(WidgetTester t) async {
    await t.tapAt(
      t.getCenter(find.byType(PaneTerminal).first),
      buttons: kSecondaryButton,
      kind: PointerDeviceKind.mouse,
    );
    await t.pump(const Duration(milliseconds: 400));
    await t.pumpAndSettle();
  }

  TerminalWorkspacePageState page(WidgetTester t) =>
      t.state<TerminalWorkspacePageState>(find.byType(TerminalWorkspacePage));

  bool enabled(WidgetTester t, Intent intent) =>
      page(t).actionsMap[intent.runtimeType]!.isEnabled(intent);

  testWidgets('the menu of an AI tab\'s terminal pane has no Break, Swap or '
      'Move to tab', (t) async {
    final c = await workspace(t);
    final ai = await splitAiTab(t, c);
    expect(ai.isSplit, isTrue);
    expect(ai.panes, hasLength(1));
    await rightClickTerminal(t);
    // The menu is the terminal's own...
    expect(find.byKey(const Key('menu.splitRight')), findsOneWidget);
    expect(find.byKey(const Key('menu.zoomPane')), findsOneWidget);
    // ...but nothing in it moves the pane (tab 100 is a destination the
    // list would refuse).
    expect(find.byKey(const Key('menu.breakPane')), findsNothing);
    expect(find.byKey(const Key('menu.swapPane')), findsNothing);
    expect(find.byKey(const Key('menu.moveToTab')), findsNothing);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('a terminal pane\'s Move to tab lists the terminal tabs, never '
      'an AI tab', (t) async {
    final c = await workspace(t);
    final tabs = c.read(terminalTabsProvider.notifier);
    final first = c.read(terminalTabsProvider).tabs.first;
    final ai = openTestAiTab(c, title: 'Fix login', cwd: null, select: false);
    await tabs.openTabFor(select: true);
    await t.pumpAndSettle();
    final here = c.read(terminalTabsProvider).selected!;
    expect(
      c.read(sidebarWorkspacesProvider).orderedTabIds,
      containsAll([first.id, ai.id, here.id]),
    );
    await rightClickTerminal(t);
    expect(find.byKey(const Key('menu.moveToTab')), findsOneWidget);
    await t.tap(find.byKey(const Key('menu.moveToTab')));
    await t.pumpAndSettle();
    expect(find.byKey(Key('menu.moveToTab.${first.id}')), findsOneWidget);
    expect(find.byKey(Key('menu.moveToTab.${ai.id}')), findsNothing);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('Break pane is off in a split AI tab, on in a split terminal '
      'tab', (t) async {
    final c = await workspace(t);
    final ai = await splitAiTab(t, c);
    expect(c.read(terminalTabsProvider).selected!.id, ai.id);
    expect(enabled(t, const BreakPaneIntent()), isFalse);
    // A terminal tab of two panes can still break one out.
    final tabs = c.read(terminalTabsProvider.notifier);
    tabs.select(c.read(terminalTabsProvider).tabs.first.id);
    await tabs.split(SplitAxis.row);
    await t.pumpAndSettle();
    expect(c.read(terminalTabsProvider).selected!.isAi, isFalse);
    expect(enabled(t, const BreakPaneIntent()), isTrue);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('Move pane to tab is off into an AI tab and out of one (by id '
      'and by place)', (t) async {
    final c = await workspace(t);
    final tabs = c.read(terminalTabsProvider.notifier);
    final first = c.read(terminalTabsProvider).tabs.first;
    final ai = openTestAiTab(c, title: 'Fix login', cwd: null, select: false);
    final terminal2 = await tabs.openTabFor(select: true);
    await t.pumpAndSettle();
    final order = c.read(sidebarWorkspacesProvider).orderedTabIds;
    // From a terminal tab: another terminal tab, yes; the AI tab, no.
    expect(enabled(t, JoinPaneIntent(tabId: first.id)), isTrue);
    expect(enabled(t, JoinPaneIntent(tabId: ai.id)), isFalse);
    expect(
      enabled(t, JoinPaneIntent(position: order.indexOf(first.id) + 1)),
      isTrue,
    );
    expect(
      enabled(t, JoinPaneIntent(position: order.indexOf(ai.id) + 1)),
      isFalse,
    );
    // From the AI tab: nowhere.
    tabs.select(ai.id);
    await t.pumpAndSettle();
    expect(enabled(t, JoinPaneIntent(tabId: first.id)), isFalse);
    expect(enabled(t, JoinPaneIntent(tabId: terminal2)), isFalse);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('a cancelled close of the AI pane announces nothing: the AI pane '
      'is still there', (t) async {
    final c = await workspace(t);
    final ai = await splitAiTab(t, c);
    final tabs = c.read(terminalTabsProvider.notifier)..aiBusy = (_) => true;
    t.takeAnnouncements();
    unawaited(page(t).closePane(ai, ai.ai!.id));
    await t.pump();
    final request = c.read(windowRouterProvider).confirm!;
    expect(request.title, 'Stop the turn and close?');
    request.complete(false);
    await t.pump();
    await t.pump();
    expect(c.read(terminalTabsProvider).tabs.any((x) => x.id == ai.id), isTrue);
    expect(
      t.takeAnnouncements().map((a) => a.message),
      isNot(contains(startsWith('Pane closed'))),
    );
    tabs.aiBusy = null;
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('a notice of the AI pane in a split AI tab is named by the tab '
      'as it is now, in the panel', (t) async {
    final c = await workspace(t);
    final ai = await splitAiTab(t, c);
    final pane = ai.ai!.id;
    // Not in view: the window is not in front.
    c.read(windowFocusProvider.notifier).set(false);
    c
        .read(tabAttentionProvider.notifier)
        .addAiNotice(ai.id, pane, body: 'Claude finished');
    await t.pump();
    expect(c.read(tabAttentionProvider).history.single.tabLabel, 'Fix login');
    // The session gets its title later.
    c
        .read(terminalTabsProvider.notifier)
        .updateAiPane(pane, (p) => p.copyWith(title: 'Fix the login bug'));
    await t.pumpAndSettle();
    await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyI);
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await t.pumpAndSettle();
    final panel = find.byKey(const Key('panel'));
    expect(panel, findsOneWidget);
    expect(
      find.descendant(of: panel, matching: find.text('Fix the login bug')),
      findsOneWidget,
      reason: 'the name now, not the one it arrived with',
    );
    expect(
      find.descendant(of: panel, matching: find.text('Fix login')),
      findsNothing,
    );
    await disposeWorkspace(t, c);
  }, variant: mac);
}
