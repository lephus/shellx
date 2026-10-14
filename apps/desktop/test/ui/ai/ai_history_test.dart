import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/ai/ai_history.dart';

import '../../support/ai_fakes.dart';
import '../../support/ai_tabs.dart';
import '../../support/config_workspace.dart';

/// V2-1 D15: Session history.
void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  Future<(ProviderContainer, FakeAiRuntimes)> pane(
    WidgetTester t,
    FakeScenario scenario,
  ) async {
    final fakes = FakeAiRuntimes(scenario);
    final w = await pumpConfiguredWorkspace(
      t,
      platform: TargetPlatform.macOS,
      extra: fakes.overrides,
    );
    openTestAiTab(w.container, cwd: testAiCwd);
    await t.pumpAndSettle();
    return (w.container, fakes);
  }

  testWidgets('History lists this folder\'s sessions (the current one '
      'marked); one opens in a new tab that reopens it', (t) async {
    final (c, fakes) = await pane(
      t,
      FakeScenario(
        sessions: [
          {
            'sessionId': 'sess-0',
            'cwd': testAiCwd,
            'title': 'Fix login',
            'updatedAt': '2026-10-13T09:30:00Z',
          },
          {'sessionId': 'sess-1', 'cwd': testAiCwd, 'title': 'Now'},
        ],
      ),
    );
    await t.tap(find.byKey(const Key('ai.history')));
    await t.pumpAndSettle();
    expect(fakes.agent().received, contains('session/list'));
    expect(find.text('Fix login'), findsOneWidget);
    expect(find.text(aiHistoryWhen('2026-10-13T09:30:00Z')), findsOneWidget);
    expect(find.text('current session'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('ai.history.sess-0')));
    await t.pumpAndSettle();
    final tab = c.read(terminalTabsProvider).selected!;
    expect(tab.ai!.sessionId, 'sess-0');
    expect(tab.label, 'Fix login');
    expect(fakes.agent(1).received, contains('session/load:sess-0'));
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('no earlier session says so', (t) async {
    final (c, _) = await pane(t, const FakeScenario());
    await t.tap(find.byKey(const Key('ai.history')));
    await t.pumpAndSettle();
    expect(find.text('No earlier sessions for this folder.'), findsOneWidget);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('an agent that does not list sessions has no History', (t) async {
    final (c, _) = await pane(t, const FakeScenario(listSessions: false));
    expect(find.byKey(const Key('ai.history')), findsNothing);
    await disposeWorkspace(t, c);
  }, variant: mac);
}
