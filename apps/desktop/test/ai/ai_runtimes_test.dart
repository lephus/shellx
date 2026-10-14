import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ai/ai_agents.dart';
import 'package:shellx_desktop/src/ai/ai_runtimes.dart';
import 'package:shellx_desktop/src/terminal/agent_status.dart';
import 'package:shellx_desktop/src/terminal/agent_status_notifier.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../cli/support/cli_container.dart';
import '../support/ai_fakes.dart';
import '../support/ai_tabs.dart';
import '../support/fake_local_sessions.dart';

void main() {
  late ProviderContainer c;
  late FakeAiRuntimes fakes;

  ProviderContainer boot(FakeScenario scenario) {
    fakes = FakeAiRuntimes(scenario);
    c = cliContainer(FakeLocalSessions(), overrides: fakes.overrides);
    return c;
  }

  AiRuntimes runtimes() => c.read(aiRuntimesProvider.notifier);
  TerminalTab tab(int id) =>
      c.read(terminalTabsProvider).tabs.firstWhere((t) => t.id == id);
  AgentState? a12(int pane) => c.read(agentStatusProvider)[pane]?.state;

  test('made on first use, with the folder and session; none without a '
      'folder (D5, D14)', () {
    boot(const FakeScenario());
    final none = openTestAiTab(c, cwd: null);
    expect(runtimes().runtimeFor(none.ai!.id), isNull);
    final ai = openTestAiTab(c, cwd: testAiCwd, sessionId: 'sess-9');
    final r = runtimes().runtimeFor(ai.ai!.id)!;
    expect(runtimes().runtimeFor(ai.ai!.id), same(r));
    expect(fakes.requests.single.cwd, testAiCwd);
    expect(fakes.requests.single.resumeSessionId, 'sess-9');
    expect(fakes.requests.single.agent.name, 'Claude');
    expect(fakes.launcher.channels, isEmpty, reason: 'made, not started');
  });

  test('the session title and id flow into the tab (D2, D14)', () async {
    boot(const FakeScenario(sessionId: 'sess-1'));
    final ai = openTestAiTab(c, cwd: testAiCwd);
    final r = runtimes().runtimeFor(ai.ai!.id)!;
    await r.start();
    await r.send([const TextBlock('Fix   the login\nbug please')]);
    await r.whenIdle();
    await pumpEventQueue();
    expect(tab(ai.id).ai!.sessionId, 'sess-1');
    expect(tab(ai.id).label, 'Fix the login bug please');
  });

  test('status reaches A12: running, then idle (D13)', () async {
    boot(const FakeScenario());
    final ai = openTestAiTab(c, cwd: testAiCwd, select: false);
    final r = runtimes().runtimeFor(ai.ai!.id)!;
    await r.start();
    await r.send([const TextBlock('hi')]);
    await r.whenIdle();
    await pumpEventQueue();
    expect(a12(ai.ai!.id), AgentState.done, reason: 'not watched: done');
  });

  test('a cancelled question ends as idle, not needs input '
      '(Review Focus 1)', () async {
    boot(
      FakeScenario(
        turns: [
          [FakeSteps.permission('t1', 'Edit a.ts')],
        ],
      ),
    );
    final ai = openTestAiTab(c, cwd: testAiCwd, select: false);
    final r = runtimes().runtimeFor(ai.ai!.id)!;
    await r.start();
    await r.send([const TextBlock('edit')]);
    await pumpEventQueue();
    expect(r.state.currentPermission, isNotNull);
    expect(a12(ai.ai!.id), AgentState.needsInput);
    r.cancel();
    await r.whenIdle();
    await pumpEventQueue();
    expect(a12(ai.ai!.id), isNot(AgentState.needsInput));
  });

  test('a pane that leaves stops its agent (Review Focus 3)', () async {
    boot(const FakeScenario());
    final ai = openTestAiTab(c, cwd: testAiCwd);
    await runtimes().runtimeFor(ai.ai!.id)!.start();
    c.read(terminalTabsProvider.notifier).close(ai.id);
    await pumpEventQueue();
    expect(fakes.launcher.channels.single.stopCalls, 1);
    expect(runtimes().existing(ai.ai!.id), isNull);
  });

  test('stopAll stops every agent (quit, §6)', () async {
    boot(const FakeScenario());
    for (var i = 0; i < 2; i++) {
      final ai = openTestAiTab(c, cwd: testAiCwd);
      await runtimes().runtimeFor(ai.ai!.id)!.start();
    }
    await runtimes().stopAll();
    expect([for (final ch in fakes.launcher.channels) ch.stopCalls], [1, 1]);
    expect([for (final ch in fakes.launcher.channels) ch.exited], [true, true]);
  });

  test('aiBusy is true while a turn runs (D3 close asks)', () async {
    boot(
      FakeScenario(
        turns: [
          [FakeSteps.waitCancel()],
        ],
      ),
    );
    final ai = openTestAiTab(c, cwd: testAiCwd);
    final r = runtimes().runtimeFor(ai.ai!.id)!;
    await r.start();
    final tabs = c.read(terminalTabsProvider.notifier);
    expect(tabs.aiBusy!(ai.id), isFalse);
    await r.send([const TextBlock('go')]);
    await pumpEventQueue();
    expect(tabs.aiBusy!(ai.id), isTrue);
    r.cancel();
    await r.whenIdle();
    expect(tabs.aiBusy!(ai.id), isFalse);
  });

  test('a custom agent is not reported to A12 (B5)', () async {
    boot(const FakeScenario());
    final agent = await c
        .read(aiCustomAgentsProvider.notifier)
        .add(name: 'Mine', command: '/opt/mine');
    final ai = openTestAiTab(
      c,
      agentId: agent.id,
      agentName: 'Mine',
      cwd: testAiCwd,
      select: false,
    );
    final r = runtimes().runtimeFor(ai.ai!.id)!;
    await r.start();
    await r.send([const TextBlock('hi')]);
    await r.whenIdle();
    expect(c.read(agentStatusProvider)[ai.ai!.id], isNull);
  });

  test('a sign-in request marks the agent in Settings › Agents (D7)', () async {
    boot(
      const FakeScenario(
        requireAuth: true,
        authMethods: [
          {
            'id': 'claude-login',
            'name': 'Log in with Claude',
            'type': 'terminal',
          },
        ],
      ),
    );
    final ai = openTestAiTab(c, cwd: testAiCwd);
    await runtimes().runtimeFor(ai.ai!.id)!.start();
    await pumpEventQueue();
    expect(c.read(aiNeedsLoginProvider), contains('claude'));
  });
}
