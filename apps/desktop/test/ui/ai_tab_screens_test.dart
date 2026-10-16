import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/terminal/agent_status.dart';
import 'package:shellx_desktop/src/terminal/agent_status_notifier.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/config/search_all_overlay.dart';
import 'package:shellx_desktop/src/ui/window_focus.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

import '../support/ai_fakes.dart';
import '../support/ai_tabs.dart';
import '../support/config_workspace.dart';

/// V2-1 §7: an AI tab without a terminal pane goes through every screen of
/// §4.7 without a crash, and each does the AI thing.
void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  Future<void> chord(
    WidgetTester t,
    LogicalKeyboardKey key, {
    bool shift = false,
  }) async {
    await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    if (shift) await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyEvent(key);
    if (shift) await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await t.pumpAndSettle();
  }

  Future<(ProviderContainer, TerminalTab)> aiWorkspace(WidgetTester t) async {
    // V2-1b Task 17: the AI pane starts its runtime when shown.
    final w = await pumpConfiguredWorkspace(
      t,
      platform: TargetPlatform.macOS,
      extra: FakeAiRuntimes(const FakeScenario()).overrides,
    );
    final ai = openTestAiTab(w.container, title: 'Fix login', cwd: testAiCwd);
    w.container.read(terminalFocusRequestProvider.notifier).request();
    await t.pumpAndSettle();
    return (w.container, ai);
  }

  testWidgets('the sidebar row: AI mark, title, agent line, A12 state', (
    t,
  ) async {
    final (c, ai) = await aiWorkspace(t);
    expect(find.byKey(const Key('dot.ai')), findsOneWidget);
    expect(find.text('Fix login'), findsWidgets);
    expect(t.widget<Text>(find.byKey(Key('row.ai.${ai.id}'))).data, 'Claude');
    final status = c.read(agentStatusProvider.notifier);
    for (final kind in [AgentEventKind.start, AgentEventKind.needsInput]) {
      status.ingest(
        AgentEvent(
          pane: ai.ai!.id,
          agent: AgentKind.claude,
          kind: kind,
          at: DateTime.now(),
        ),
      );
    }
    await t.pumpAndSettle();
    expect(
      t.widget<Text>(find.byKey(Key('row.ai.${ai.id}'))).data,
      'Needs input · Claude',
    );
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('⌘A, ⌘C, ⌘V, ⌘F and copy mode do nothing in the AI pane', (
    t,
  ) async {
    final (c, ai) = await aiWorkspace(t);
    for (final key in [
      LogicalKeyboardKey.keyA,
      LogicalKeyboardKey.keyC,
      LogicalKeyboardKey.keyV,
      LogicalKeyboardKey.keyF,
    ]) {
      await chord(t, key);
    }
    await chord(t, LogicalKeyboardKey.keyM, shift: true);
    expect(t.takeException(), isNull);
    expect(find.byKey(ValueKey('find.${ai.ai!.id}')), findsNothing);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('search all lists terminal panes only', (t) async {
    final (c, ai) = await aiWorkspace(t);
    final sources = searchAllSources(c.read(terminalTabsProvider));
    expect(sources.map((s) => s.tabId), isNot(contains(ai.id)));
    expect(sources, isNotEmpty);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('the palette offers no pane moves into or out of an AI tab', (
    t,
  ) async {
    final (c, _) = await aiWorkspace(t);
    await chord(t, LogicalKeyboardKey.keyP, shift: true);
    await t.enterText(find.byType(TextField).last, 'move pane');
    await t.pumpAndSettle();
    expect(find.textContaining('Move pane to tab'), findsNothing);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    // A second terminal tab: tab 100 is a destination, the AI tab is not.
    await c.read(terminalTabsProvider.notifier).openTab();
    c.read(terminalFocusRequestProvider.notifier).request();
    await t.pumpAndSettle();
    await chord(t, LogicalKeyboardKey.keyP, shift: true);
    await t.enterText(find.byType(TextField).last, 'move pane');
    await t.pumpAndSettle();
    expect(find.textContaining('Move pane to tab'), findsWidgets);
    expect(find.text('Move pane to tab Fix login'), findsNothing);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('⌘D in the AI pane opens a terminal under it (D3)', (t) async {
    final (c, ai) = await aiWorkspace(t);
    await chord(t, LogicalKeyboardKey.keyD);
    final tab = c
        .read(terminalTabsProvider)
        .tabs
        .firstWhere((x) => x.id == ai.id);
    expect(tab.panes, hasLength(1));
    expect((tab.layout as PaneSplit).ratio, closeTo(kAiPaneRatio, 0.01));
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('⌘W closes the AI tab; a running turn asks first (D3)', (
    t,
  ) async {
    final (c, ai) = await aiWorkspace(t);
    final tabs = c.read(terminalTabsProvider.notifier)..aiBusy = (_) => true;
    await chord(t, LogicalKeyboardKey.keyW);
    final request = c.read(windowRouterProvider).confirm!;
    expect(request.title, 'Stop the turn and close?');
    expect(request.body, 'Claude is still working in this tab.');
    request.complete(true);
    await t.pumpAndSettle();
    expect(
      c.read(terminalTabsProvider).tabs.any((x) => x.id == ai.id),
      isFalse,
    );
    tabs.aiBusy = null;
    await disposeWorkspace(t, c);
  }, variant: mac);
}
