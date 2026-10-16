import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ai/ai_runtimes.dart';
import 'package:shellx_desktop/src/terminal/agent_status.dart';
import 'package:shellx_desktop/src/terminal/agent_status_notifier.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../cli/support/cli_container.dart';
import '../support/ai_fakes.dart';
import '../support/ai_tabs.dart';
import '../support/fake_local_sessions.dart';

/// V2-1b final review: what the runtimes carry into the rest of the app
/// (M-1 the tab's title, M-5 the sidebar badge, M-9 closing a tab).
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

  group('M-1: a restored tab keeps its saved title', () {
    const saved = 'Hello.txt world to ShellX';
    const prompt = 'Read hello.txt, then change the word world to ShellX';
    const replay = [
      {
        'sessionUpdate': 'user_message_chunk',
        'content': {'type': 'text', 'text': prompt},
      },
      {
        'sessionUpdate': 'agent_message_chunk',
        'content': {'type': 'text', 'text': 'Done.'},
      },
    ];

    test(
      'the replay of its prompts does not rename it (nor layout.json)',
      () async {
        boot(const FakeScenario(sessionId: 'sess-1', history: replay));
        final ai = openTestAiTab(
          c,
          cwd: testAiCwd,
          sessionId: 'sess-1',
          title: saved,
        );
        final r = runtimes().runtimeFor(ai.ai!.id)!;
        await r.start();
        await pumpEventQueue();
        expect(r.state.timeline.items, isNotEmpty, reason: 'the replay ran');
        expect(tab(ai.id).label, saved);
        expect(tab(ai.id).ai!.title, saved);
        expect(tab(ai.id).ai!.sessionId, 'sess-1');
      },
    );

    test('the agent\'s own title replaces it, whenever it comes', () async {
      boot(const FakeScenario(sessionId: 'sess-1', history: replay));
      final ai = openTestAiTab(
        c,
        cwd: testAiCwd,
        sessionId: 'sess-1',
        title: saved,
      );
      final r = runtimes().runtimeFor(ai.ai!.id)!;
      await r.start();
      await pumpEventQueue();
      r.state.applyUpdate(
        const SessionInfoUpdated(hasTitle: true, title: ' A better title '),
        DateTime.utc(2026, 10, 14),
      );
      await pumpEventQueue();
      expect(tab(ai.id).label, 'A better title');
      // And a changed one again.
      r.state.applyUpdate(
        const SessionInfoUpdated(hasTitle: true, title: 'Another'),
        DateTime.utc(2026, 10, 14),
      );
      await pumpEventQueue();
      expect(tab(ai.id).label, 'Another');
    });

    test('a session opened with no title yet (History, or a tab that was '
        'saved with none) is named by its first prompt', () async {
      boot(const FakeScenario(sessionId: 'sess-1', history: replay));
      // The opener gives "New AI session" when there is no title to show.
      final ai = openTestAiTab(c, cwd: testAiCwd, sessionId: 'sess-1');
      final r = runtimes().runtimeFor(ai.ai!.id)!;
      await r.start();
      await pumpEventQueue();
      expect(tab(ai.id).label, 'Read hello.txt, then change the word wor…');
    });

    test('a session that could not be reopened and started anew is named '
        'by what the user writes now, not by the old title', () async {
      boot(
        const FakeScenario(
          sessionId: 'sess-new',
          loadSessionError: {'code': -32002, 'message': 'not found'},
        ),
      );
      final ai = openTestAiTab(
        c,
        cwd: testAiCwd,
        sessionId: 'sess-gone',
        title: saved,
      );
      final r = runtimes().runtimeFor(ai.ai!.id)!;
      await r.start();
      await pumpEventQueue();
      expect(r.state.sessionId, 'sess-new');
      expect(tab(ai.id).label, saved, reason: 'nothing to name it by yet');
      await r.send([const TextBlock('Fresh start')]);
      await r.whenIdle();
      await pumpEventQueue();
      expect(tab(ai.id).label, 'Fresh start');
    });
  });

  group('M-5: a runtime dropped mid-turn ends its A12 status', () {
    test('running: the sidebar badge does not stay "Running"', () async {
      boot(
        FakeScenario(
          turns: [
            [FakeSteps.waitCancel()],
          ],
        ),
      );
      final ai = openTestAiTab(c, cwd: testAiCwd, select: false);
      final pane = ai.ai!.id;
      final r = runtimes().runtimeFor(pane)!;
      await r.start();
      await r.send([const TextBlock('go')]);
      await pumpEventQueue();
      expect(a12(pane), AgentState.running);
      // The agent is switched off, or the folder changes: the runtime goes
      // while its pane stays.
      runtimes().forget(pane);
      await pumpEventQueue();
      expect(a12(pane), isNull);
      expect(tab(ai.id).ai, isNotNull, reason: 'the pane is still there');
    });

    test('a question waiting: the badge does not stay "Needs you"', () async {
      boot(
        FakeScenario(
          turns: [
            [FakeSteps.permission('t1', 'Edit a.ts')],
          ],
        ),
      );
      final ai = openTestAiTab(c, cwd: testAiCwd, select: false);
      final pane = ai.ai!.id;
      final r = runtimes().runtimeFor(pane)!;
      await r.start();
      await r.send([const TextBlock('edit')]);
      await pumpEventQueue();
      expect(a12(pane), AgentState.needsInput);
      runtimes().forget(pane);
      await pumpEventQueue();
      expect(a12(pane), isNull);
    });

    test('an agent that was never heard from leaves nothing behind', () async {
      boot(const FakeScenario());
      final ai = openTestAiTab(c, cwd: testAiCwd, select: false);
      final pane = ai.ai!.id;
      runtimes().runtimeFor(pane);
      runtimes().forget(pane);
      await pumpEventQueue();
      expect(a12(pane), isNull);
    });
  });

  group('M-9: a tab with messages waiting is busy, started or not', () {
    test('closing asks while the agent starts with a message queued', () async {
      boot(const FakeScenario());
      final ai = openTestAiTab(c, cwd: testAiCwd);
      final r = runtimes().runtimeFor(ai.ai!.id)!;
      final tabs = c.read(terminalTabsProvider.notifier);
      expect(tabs.aiBusy!(ai.id), isFalse);
      unawaited(r.start());
      expect(await r.send([const TextBlock('first, queued')]), isTrue);
      expect(r.state.turn, isNull, reason: 'no turn yet: the agent starts');
      expect(r.state.queue, hasLength(1));
      expect(tabs.aiBusy!(ai.id), isTrue);
      await r.whenIdle();
      expect(tabs.aiBusy!(ai.id), isFalse, reason: 'the turn ran and ended');
    });

    test('a running turn still counts, and an idle tab does not', () async {
      boot(
        FakeScenario(
          turns: [
            [FakeSteps.waitCancel()],
          ],
        ),
      );
      final ai = openTestAiTab(c, cwd: testAiCwd);
      final r = runtimes().runtimeFor(ai.ai!.id)!;
      final tabs = c.read(terminalTabsProvider.notifier);
      await r.start();
      expect(tabs.aiBusy!(ai.id), isFalse);
      await r.send([const TextBlock('go')]);
      await pumpEventQueue();
      expect(tabs.aiBusy!(ai.id), isTrue);
      r.cancel();
      await r.whenIdle();
      expect(tabs.aiBusy!(ai.id), isFalse);
    });
  });
}
