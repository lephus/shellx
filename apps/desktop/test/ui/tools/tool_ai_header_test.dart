import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ai/ai_project_files.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/tools/tool_dock.dart';
import 'package:shellx_desktop/src/ui/window_focus.dart';

import '../../support/ai_fakes.dart';
import '../../support/ai_tabs.dart';
import '../../support/config_workspace.dart';
import '../../support/fake_project.dart';
import '../../support/tool_harness.dart';

void main() {
  testWidgets('🧩 on the AI pane opens the workspace\'s tools and closes the '
      'Changes panel (D4)', (t) async {
    final rig = ToolRig();
    final files = FakeProject(testAiCwd, {'a.txt': 'x\n'})..onSnapshot = null;
    final fakes = FakeAiRuntimes(
      FakeScenario(
        turns: [
          [FakeSteps.text('Done.')],
        ],
      ),
      checkpoints: files,
    );
    final w = await pumpConfiguredWorkspace(
      t,
      platform: TargetPlatform.macOS,
      harness: rig.harness,
      extra: [
        ...rig.overrides,
        ...fakes.overrides,
        aiProjectFilesProvider.overrideWithValue(files),
      ],
    );
    rig.container = w.container;
    final c = w.container;
    final tool = rig.add(kDefaultWorkspaceId, 'localhost:5173');
    openTestAiTab(c, cwd: testAiCwd);
    c.read(terminalFocusRequestProvider.notifier).request();
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('ai.composer')), 'go');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('ai.panel')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('ai.sidePanel')), findsOneWidget);
    await t.tap(find.byKey(const Key('ai.tools')));
    await t.pumpAndSettle();
    expect(c.read(toolDockProvider).of(kDefaultWorkspaceId).active, tool.id);
    expect(find.byKey(const ValueKey('tool.dockSlot')), findsOneWidget);
    expect(find.byKey(const Key('ai.sidePanel')), findsNothing);
    await disposeWorkspace(t, c);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
