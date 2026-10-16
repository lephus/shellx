import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ai/ai_open.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../../support/ai_fakes.dart';
import '../../support/config_workspace.dart';

/// V2-1 D5: where AI tabs come from.
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

  List<TerminalTab> aiTabs(ProviderContainer c) => [
    for (final tab in c.read(terminalTabsProvider).tabs)
      if (tab.isAi) tab,
  ];

  testWidgets('⌘⇧E: an AI tab with the default agent in the workspace\'s '
      'project root, selected and started', (t) async {
    final fakes = FakeAiRuntimes(const FakeScenario());
    final w = await pumpConfiguredWorkspace(
      t,
      platform: TargetPlatform.macOS,
      extra: fakes.overrides,
    );
    w.container
        .read(sidebarWorkspacesProvider.notifier)
        .setRoot(kDefaultWorkspaceId, testAiCwd);
    await chord(t, LogicalKeyboardKey.keyE, shift: true);
    final ai = aiTabs(w.container).single;
    expect(ai.ai!.agentId, 'claude');
    expect(ai.ai!.agentName, 'Claude');
    expect(ai.ai!.title, 'New AI session');
    expect(ai.cwd, testAiCwd);
    expect(w.container.read(terminalTabsProvider).selectedId, ai.id);
    expect(fakes.launcher.channels, hasLength(1));
    // No root: the folder of the tab in front (here the AI tab's).
    w.container
        .read(sidebarWorkspacesProvider.notifier)
        .setRoot(kDefaultWorkspaceId, null);
    await chord(t, LogicalKeyboardKey.keyE, shift: true);
    expect(aiTabs(w.container).map((x) => x.cwd), [testAiCwd, testAiCwd]);
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('no root and a shell in front without a folder: the pane '
      'asks for one (D5)', (t) async {
    final fakes = FakeAiRuntimes(const FakeScenario());
    final w = await pumpConfiguredWorkspace(
      t,
      platform: TargetPlatform.macOS,
      extra: fakes.overrides,
    );
    await t.tap(find.byKey(const Key('sidebar.newAi')));
    await t.pumpAndSettle();
    expect(aiTabs(w.container).single.cwd, isNull);
    expect(find.text('Choose a project folder'), findsOneWidget);
    expect(fakes.made, isEmpty);
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('new-tab-kind = ai: ⌘T, the + button and an empty start open '
      'AI tabs; "New terminal tab" still opens a shell', (t) async {
    final fakes = FakeAiRuntimes(const FakeScenario());
    final w = await pumpConfiguredWorkspace(
      t,
      platform: TargetPlatform.macOS,
      config: 'new-tab-kind = ai\n',
      extra: fakes.overrides,
    );
    final c = w.container;
    await chord(t, LogicalKeyboardKey.keyT);
    expect(aiTabs(w.container), hasLength(1));
    await t.tap(find.byKey(const Key('sidebar.newTab')));
    await t.pumpAndSettle();
    expect(aiTabs(w.container), hasLength(2));
    final shells = w.local.opens.length;
    await t.tap(
      find.byKey(const Key('sidebar.newTab')),
      buttons: kSecondaryButton,
    );
    await t.pumpAndSettle();
    expect(find.byKey(const Key('menu.new.ai')), findsOneWidget);
    await t.tap(find.byKey(const Key('menu.new.terminal')));
    await t.pumpAndSettle();
    expect(w.local.opens, hasLength(shells + 1));
    expect(c.read(terminalTabsProvider).selected!.isAi, isFalse);
    // Nothing open: start-up and activation open an AI session too.
    final tabs = c.read(terminalTabsProvider.notifier);
    for (final tab in [...c.read(terminalTabsProvider).tabs]) {
      tabs.close(tab.id);
    }
    await t.pumpAndSettle();
    await tabs.ensureTab();
    await t.pumpAndSettle();
    expect(c.read(terminalTabsProvider).tabs.single.isAi, isTrue);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('B8: in a server\'s workspace a new tab stays on the server '
      'even with new-tab-kind = ai', (t) async {
    final fakes = FakeAiRuntimes(const FakeScenario());
    final w = await pumpConfiguredWorkspace(
      t,
      platform: TargetPlatform.macOS,
      config: 'new-tab-kind = ai\n',
      extra: fakes.overrides,
    );
    final server = w.container
        .read(sidebarWorkspacesProvider.notifier)
        .createForHost(SshTarget.parse('devbox')!);
    await w.container.read(aiOpenerProvider).newTabIn(server);
    await t.pumpAndSettle();
    expect(aiTabs(w.container), isEmpty);
    expect(w.local.openLaunches.last, isA<SshLaunch>());
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('new-tab-kind = terminal (the default): ⌘T and + stay shells; '
      'the + menu offers "New AI session"', (t) async {
    final fakes = FakeAiRuntimes(const FakeScenario());
    final w = await pumpConfiguredWorkspace(
      t,
      platform: TargetPlatform.macOS,
      extra: fakes.overrides,
    );
    await chord(t, LogicalKeyboardKey.keyT);
    expect(aiTabs(w.container), isEmpty);
    await t.tap(
      find.byKey(const Key('sidebar.newTab')),
      buttons: kSecondaryButton,
    );
    await t.pumpAndSettle();
    expect(find.byKey(const Key('menu.new.terminal')), findsNothing);
    await t.tap(find.byKey(const Key('menu.new.ai')));
    await t.pumpAndSettle();
    expect(aiTabs(w.container), hasLength(1));
    await disposeWorkspace(t, w.container);
  }, variant: mac);
}
