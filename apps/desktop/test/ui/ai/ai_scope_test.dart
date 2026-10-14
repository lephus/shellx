import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ai/ai_frame_notifier.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/ai/ai_scope.dart';

import '../../support/ai_fakes.dart';
import '../../support/ai_parts.dart';

/// Smoothness: what every item of the conversation reads.
void main() {
  testWidgets('a tab replaced under the same id does not rebuild what reads '
      'the scope; another tab does', (t) async {
    final runtime = partRuntime(FakeAiRuntimes(const FakeScenario()));
    final frames = AiFrameNotifier(runtime.state);
    final ui = AiPaneUi();
    addTearDown(() {
      frames.dispose();
      ui.dispose();
    });
    final pane = AiPaneState(
      id: -1,
      agentId: 'claude',
      agentName: 'Claude',
      title: 'New AI session',
      cwd: runtime.state.cwd,
    );
    TerminalTab tabWith(int id) => TerminalTab.ai(id: id, pane: pane);
    var builds = 0;
    // One widget, so only the scope can make it build again.
    final reader = Builder(
      builder: (context) {
        AiPaneScope.of(context);
        builds++;
        return const SizedBox();
      },
    );
    final tab = ValueNotifier(tabWith(kSyntheticTabIdBase));
    addTearDown(tab.dispose);
    await t.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<TerminalTab>(
          valueListenable: tab,
          builder: (context, tab, _) => AiPaneScope(
            runtime: runtime,
            frames: frames,
            tab: tab,
            pane: pane,
            ui: ui,
            child: reader,
          ),
        ),
      ),
    );
    expect(builds, 1);
    // The tab list made a new record of the same tab (a title, a focus…).
    tab.value = tabWith(kSyntheticTabIdBase);
    await t.pump();
    expect(builds, 1, reason: 'the same tab');
    tab.value = tabWith(kSyntheticTabIdBase + 1);
    await t.pump();
    expect(builds, 2, reason: 'another tab');
  });
}
