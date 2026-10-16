import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/terminal/session_tab_row.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_workspace_page.dart';

import '../support/ai_fakes.dart';
import '../support/ai_tabs.dart';
import '../support/config_workspace.dart';

void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  testWidgets('the list counts an AI row\'s second line: End scrolls the last '
      'of many AI rows fully into view (V2-1 §4.7)', (t) async {
    final rig = await pumpConfiguredWorkspace(
      t,
      platform: TargetPlatform.macOS,
      extra: FakeAiRuntimes(const FakeScenario()).overrides,
    );
    final c = rig.container;
    // No folder yet: the tabs show their pane's folder picker, no agent runs.
    final ids = [
      for (var i = 0; i < 25; i++)
        openTestAiTab(c, title: 'Session $i', cwd: null, select: false).id,
    ];
    await t.pumpAndSettle();
    // The row's own height, with its agent line (UI-A1 §1.3).
    final scaler = MediaQuery.textScalerOf(t.element(find.byType(ListView)));
    final first = find.byKey(ValueKey('tab.${ids.first}'));
    expect(
      t.getSize(first).height,
      SessionTabRow.heightFor(scaler, context: true),
    );

    t
        .state<TerminalWorkspacePageState>(find.byType(TerminalWorkspacePage))
        .sidebarFocus
        .requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.end);
    await t.pumpAndSettle();

    expect(c.read(terminalTabsProvider).selectedId, ids.last);
    final last = find.byKey(ValueKey('tab.${ids.last}'));
    expect(last, findsOneWidget, reason: 'scrolled into the built rows');
    final list = t.getRect(find.byType(ListView));
    final row = t.getRect(last);
    expect(
      list.top <= row.top && row.bottom <= list.bottom,
      isTrue,
      reason: 'the last row is fully in view, not under the fold',
    );
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('the drag ghost of an AI tab carries the AI mark, not a shell '
      'status dot', (t) async {
    final rig = await pumpConfiguredWorkspace(
      t,
      platform: TargetPlatform.macOS,
      extra: FakeAiRuntimes(const FakeScenario()).overrides,
    );
    final c = rig.container;
    final ai = openTestAiTab(c, title: 'Fix login', cwd: null, select: false);
    await t.pumpAndSettle();
    final g = await t.startGesture(
      t.getCenter(find.byKey(ValueKey('tab.${ai.id}'))),
      kind: PointerDeviceKind.mouse,
    );
    await g.moveBy(const Offset(0, 8));
    await t.pump();
    await g.moveBy(const Offset(0, 8));
    await t.pump();
    final ghost = find.byKey(const Key('drag.ghost'));
    expect(ghost, findsOneWidget);
    expect(
      find.descendant(of: ghost, matching: find.byKey(const Key('dot.ai'))),
      findsOneWidget,
    );
    expect(
      find.descendant(of: ghost, matching: find.byKey(const Key('dot.idle'))),
      findsNothing,
      reason: 'a shell\'s green dot says nothing about an agent',
    );
    await g.up();
    await t.pumpAndSettle();
    await disposeWorkspace(t, c);
  }, variant: mac);
}
