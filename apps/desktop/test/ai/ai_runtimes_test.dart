import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/host.dart' show AiStatus;
import 'package:shellx_ai/shellx_ai.dart' show AgentTextItem, AiSessionState;
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ai/ai_agents.dart';
import 'package:shellx_desktop/src/ai/ai_runtimes.dart';
import 'package:shellx_desktop/src/terminal/agent_status.dart';
import 'package:shellx_desktop/src/terminal/agent_status_notifier.dart';
import 'package:shellx_desktop/src/terminal/tab_attention.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../cli/support/cli_container.dart';
import '../support/ai_fakes.dart';
import '../support/ai_tabs.dart';
import '../support/fake_local_sessions.dart';

void main() {
  late ProviderContainer c;
  late FakeAiRuntimes fakes;

  ProviderContainer boot(
    FakeScenario scenario, {
    List<Override> overrides = const [],
  }) {
    fakes = FakeAiRuntimes(scenario);
    c = cliContainer(
      FakeLocalSessions(),
      overrides: [...fakes.overrides, ...overrides],
    );
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

  test('a long turn that waited for the user still ends "finished": the '
      'runtime reports on the A12 clock, the answer does not restart the '
      'turn (D13)', () async {
    final t0 = DateTime.utc(2026, 10, 14, 12);
    var now = t0;
    boot(
      FakeScenario(
        turns: [
          [FakeSteps.permission('t1', 'Edit a.ts')],
        ],
      ),
      overrides: [agentStatusClockProvider.overrideWithValue(() => now)],
    );
    final ai = openTestAiTab(c, cwd: testAiCwd, select: false);
    final pane = ai.ai!.id;
    final r = runtimes().runtimeFor(pane)!;
    // The turn: running at 0 s, the question at 290 s, answered at 296 s,
    // over at 300 s. Each report is stamped as the test's clock says.
    final seconds = [0, 290, 296, 300];
    final reported = <AiStatus>[];
    final bridge = r.onStatus!;
    r.onStatus = (status) {
      now = t0.add(Duration(seconds: seconds[reported.length]));
      reported.add(status);
      bridge(status);
    };
    await r.start();
    await r.send([const TextBlock('edit')]);
    await pumpEventQueue();
    expect(reported, [AiStatus.running, AiStatus.needsInput]);
    expect(a12(pane), AgentState.needsInput);
    r.answerPermission(r.state.currentPermission!.id, 'allow-once');
    await r.whenIdle();
    await pumpEventQueue();
    expect(reported, [
      AiStatus.running,
      AiStatus.needsInput,
      AiStatus.running,
      AiStatus.idle,
    ]);
    final record = c.read(agentStatusProvider)[pane]!;
    expect(record.state, AgentState.done, reason: 'not watched: done');
    expect(record.runningSince, t0, reason: 'the turn began at 0 s');
    expect(
      [for (final e in c.read(tabAttentionProvider).history) e.notice.body],
      ['Claude finished', 'Claude needs your input'],
      reason: 'a 300 s turn is long, whenever its last question was answered',
    );
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

  test('stopAll closes the registry: a runtime asked for during the quit '
      'wait is never made, so none outlives the stop (§6)', () async {
    boot(const FakeScenario());
    final ai = openTestAiTab(c, cwd: testAiCwd);
    await runtimes().runtimeFor(ai.ai!.id)!.start();
    final stopping = runtimes().stopAll(); // the 4 s wait of the quit
    final late = openTestAiTab(c, cwd: testAiCwd);
    expect(runtimes().runtimeFor(late.ai!.id), isNull);
    expect(runtimes().runtimeFor(ai.ai!.id), isNull);
    await stopping;
    expect(runtimes().runtimeFor(late.ai!.id), isNull);
    expect(fakes.requests, hasLength(1), reason: 'only the one that stopped');
    expect(fakes.launcher.channels.single.stopCalls, 1);
  });

  group('the tab label is kept until it can change', () {
    final at = DateTime.utc(2026, 10, 14);
    late int computed;
    late AiLabelCache cache;
    late AiSessionState state;

    setUp(() {
      computed = 0;
      cache = AiLabelCache((s) {
        computed++;
        return s.label;
      });
      state = AiSessionState(agentId: 'claude', agentName: 'Claude', cwd: '/w');
    });

    test('streamed chunks of the answer do not ask again', () {
      expect(cache.of(state), isNull);
      state.beginTurn([const TextBlock('Fix   the login\nbug please')], at);
      expect(cache.of(state), 'Fix the login bug please');
      expect(computed, 2);
      // The answer's first chunk adds an item; the rest only grow it.
      for (var i = 0; i < 200; i++) {
        state.applyUpdate(AgentMessageChunk(TextBlock('chunk $i ')), at);
        expect(cache.of(state), 'Fix the login bug please');
      }
      expect(computed, 3, reason: 'once for the answer\'s item, not per chunk');
    });

    test('the session title replaces the prompt, and going again is free', () {
      state.beginTurn([const TextBlock('first prompt')], at);
      expect(cache.of(state), 'first prompt');
      state.applyUpdate(
        const SessionInfoUpdated(hasTitle: true, title: ' Login fix '),
        at,
      );
      expect(cache.of(state), 'Login fix');
      expect(cache.of(state), 'Login fix');
      expect(computed, 2);
      state.applyUpdate(
        const SessionInfoUpdated(hasTitle: true, title: null),
        at,
      );
      expect(cache.of(state), 'first prompt', reason: 'a cleared title');
    });

    test('a prompt that arrives in chunks (a replayed session) is read '
        'whole', () {
      state.applyUpdate(
        const UserMessageChunk(TextBlock('Fix the '), messageId: 'm1'),
        at,
        history: true,
      );
      expect(cache.of(state), 'Fix the');
      state.applyUpdate(
        const UserMessageChunk(TextBlock('login bug'), messageId: 'm1'),
        at,
        history: true,
      );
      expect(state.timeline.items, hasLength(1), reason: 'one message');
      expect(cache.of(state), 'Fix the login bug');
    });

    test('a prompt longer than 40 characters is cut as before', () {
      state.beginTurn([TextBlock('x' * 200)], at);
      expect(cache.of(state), state.label);
      expect(cache.of(state), '${'x' * 40}…');
    });
  });

  test('a streamed answer reads the tab label when it can have changed, '
      'not after every chunk', () async {
    var reads = 0;
    boot(
      FakeScenario(
        turns: [
          [for (var i = 0; i < 150; i++) FakeSteps.text('chunk $i ')],
        ],
      ),
      overrides: [
        aiLabelReaderProvider.overrideWithValue((state) {
          reads++;
          return state.label;
        }),
      ],
    );
    final ai = openTestAiTab(c, cwd: testAiCwd, select: false);
    final r = runtimes().runtimeFor(ai.ai!.id)!;
    await r.start();
    await r.send([const TextBlock('Fix the login bug')]);
    await r.whenIdle();
    await pumpEventQueue();
    expect(tab(ai.id).label, 'Fix the login bug');
    expect(
      r.state.timeline.items.whereType<AgentTextItem>().single.text,
      contains('chunk 149'),
      reason: 'the whole answer streamed',
    );
    // Before, once per burst of chunks: more than a hundred reads.
    expect(reads, lessThanOrEqualTo(8));
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
