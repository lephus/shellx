import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_acp/shellx_acp.dart' show TextBlock;
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/ai/ai_runtimes.dart';
import 'package:shellx_desktop/src/mux/daemon_state.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/restore/restore_persistence.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/tray/tray_action.dart';
import 'package:shellx_desktop/src/tray/tray_actions.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

import '../mux/fake_daemon.dart';
import '../support/ai_fakes.dart';
import '../support/ai_tabs.dart';
import '../support/fakes.dart';
import '../support/restore_fakes.dart';

/// V2-1b final review (deferred minor): every quit asks while an AI agent is
/// at work — a running turn, or messages waiting for it — as closing its tab
/// does. The agents run in this window's process, so they stop on any quit,
/// the one that leaves the shells in the background service as well.
void main() {
  const oneBusy = 'An AI agent is still working in 1 tab. Quitting stops it.';
  const twoBusy = 'AI agents are still working in 2 tabs. Quitting stops them.';

  group('in-process (the background service is off)', () {
    late TestHarness h;
    late ProviderContainer c;
    late Set<int> busy;

    Future<void> boot({int sessions = 0}) async {
      h = TestHarness();
      c = ProviderContainer.test(
        overrides: [desktopServicesProvider.overrideWithValue(h.services())],
      );
      busy = {};
      c.read(terminalTabsProvider.notifier).aiBusy = busy.contains;
      for (var i = 0; i < sessions; i++) {
        await h.sessions.open(cols: 80, rows: 24);
      }
      await pumpEventQueue();
    }

    /// An AI tab; [working] makes the agent in it busy.
    int aiTab({bool working = false}) {
      final id = openTestAiTab(c, cwd: '/w/project').id;
      if (working) busy.add(id);
      return id;
    }

    ConfirmRequest? asked() => c.read(windowRouterProvider).confirm;
    Future<void> run(TrayAction a) => c.read(trayActionsProvider).handle(a);

    test('only an AI agent at work: the quit asks, in its own words, and '
        'stops on "Quit"', () async {
      await boot();
      aiTab(working: true);
      final done = run(const Quit());
      await pumpEventQueue();
      final request = asked()!;
      expect(request.title, 'Quit ShellX?');
      expect(request.body, oneBusy);
      expect(request.confirmLabel, 'Quit');
      expect(h.quits, 0);
      request.complete(true);
      await done;
      expect(h.quits, 1);
    });

    test('cancel stays: nothing quits', () async {
      await boot();
      aiTab(working: true);
      final done = run(const Quit());
      await pumpEventQueue();
      asked()!.complete(false);
      await done;
      expect(h.quits, 0);
      expect(asked(), isNull);
    });

    test(
      'terminal tabs too: the A1 words, and the agents after them',
      () async {
        await boot(sessions: 2);
        aiTab(working: true);
        aiTab(working: true);
        final done = run(const Quit());
        await pumpEventQueue();
        final body = asked()!.body;
        expect(body, contains('2 open tabs will be closed'));
        expect(body, endsWith(twoBusy));
        asked()!.complete(true);
        await done;
        expect(h.quits, 1);
      },
    );

    test('terminal tabs only: the A1 question, as before', () async {
      await boot(sessions: 1);
      aiTab();
      final done = run(const Quit());
      await pumpEventQueue();
      expect(asked()!.body, isNot(contains('AI')));
      asked()!.complete(true);
      await done;
    });

    test('an AI agent that is not at work, or no AI tab at all: no '
        'question, as before', () async {
      await boot();
      aiTab();
      await run(const Quit());
      expect(asked(), isNull);
      expect(h.quits, 1);
    });

    test('Quit(confirm: false) — the installer, the Restart Manager — never '
        'asks', () async {
      await boot();
      aiTab(working: true);
      await run(const Quit(confirm: false));
      expect(asked(), isNull);
      expect(h.quits, 1);
    });

    test('"Quit Completely" is Quit without the service, with the same '
        'question', () async {
      await boot();
      aiTab(working: true);
      final done = run(const QuitAll());
      await pumpEventQueue();
      expect(asked()!.body, oneBusy);
      asked()!.complete(true);
      await done;
      expect(h.quits, 1);
    });

    test(
      'a second quit while the question is open leaves one question',
      () async {
        await boot();
        aiTab(working: true);
        final first = run(const Quit());
        await pumpEventQueue();
        final second = run(const Quit());
        await pumpEventQueue();
        await first; // replaced: answered "no"
        expect(asked(), isNotNull);
        asked()!.complete(true);
        await second;
        expect(h.quits, 1);
      },
    );

    FakeAiRuntimes withRuntimes() {
      h = TestHarness();
      final fakes = FakeAiRuntimes(
        FakeScenario(
          turns: [
            [FakeSteps.waitCancel()],
          ],
        ),
      );
      c = ProviderContainer.test(
        overrides: [
          desktopServicesProvider.overrideWithValue(h.services()),
          ...fakes.overrides,
        ],
      );
      return fakes;
    }

    test('the runtimes decide: a running turn, and a message waiting for an '
        'agent that is still starting, are at work', () async {
      withRuntimes();
      final runtimes = c.read(aiRuntimesProvider.notifier);
      final first = runtimes.runtimeFor(
        openTestAiTab(c, cwd: testAiCwd).ai!.id,
      )!;
      await first.start();
      await first.send([const TextBlock('go')]);
      await pumpEventQueue();
      expect(first.state.turn, isNotNull);
      var done = run(const Quit());
      await pumpEventQueue();
      expect(asked()!.body, oneBusy);
      asked()!.complete(false);
      await done;
      expect(h.quits, 0, reason: 'declined');
      first.cancel();
      await first.whenIdle();

      final second = runtimes.runtimeFor(
        openTestAiTab(c, cwd: testAiCwd).ai!.id,
      )!;
      unawaited(second.start());
      await second.send([const TextBlock('queued')]);
      expect(second.state.turn, isNull, reason: 'the agent is starting');
      expect(second.state.queue, isNotEmpty);
      done = run(const Quit());
      await pumpEventQueue();
      expect(asked()!.body, oneBusy);
      asked()!.complete(false);
      await done;
      expect(h.quits, 0);
    });

    test('an agent that is idle is not at work: no question', () async {
      withRuntimes();
      final runtimes = c.read(aiRuntimesProvider.notifier);
      final r = runtimes.runtimeFor(openTestAiTab(c, cwd: testAiCwd).ai!.id)!;
      await r.start();
      await run(const Quit());
      expect(asked(), isNull);
      expect(h.quits, 1);
    });
  });

  group('with the background service on', () {
    late TestHarness h;
    late RecordingFiles files;
    late FakeConnector connector;
    late FakeDaemon daemon;
    late ProviderContainer c;
    late Set<int> busy;

    Future<void> boot({List<int> ids = const [1, 2]}) async {
      h = TestHarness();
      files = RecordingFiles()..diskLayout = true;
      connector = FakeConnector()..files = files;
      daemon = FakeDaemon('a' * 32, ids: ids);
      c = ProviderContainer.test(
        overrides: [
          daemonModeProvider.overrideWithValue(true),
          desktopServicesProvider.overrideWithValue(h.services()),
          restoreStoreProvider.overrideWithValue(files),
          daemonConnectorProvider.overrideWithValue(connector),
        ],
      );
      busy = {};
      c.read(sidebarWorkspacesProvider);
      c.read(restorePersistenceProvider.notifier).start();
      c.read(terminalTabsProvider.notifier).aiBusy = busy.contains;
      connector.queue.add(() async => daemon.attach());
      await c.read(daemonStateProvider.notifier).connectAtStartup();
      await pumpEventQueue();
    }

    int aiTab({bool working = false}) {
      final id = openTestAiTab(c, cwd: '/w/project').id;
      if (working) busy.add(id);
      return id;
    }

    ConfirmRequest? asked() => c.read(windowRouterProvider).confirm;
    Future<void> run(TrayAction a) => c.read(trayActionsProvider).handle(a);

    test('"Quit" with no shell but an AI agent at work: asks (the agents '
        'stop with the window), then leaves the service alone', () async {
      await boot(ids: const []);
      aiTab(working: true);
      final done = run(const Quit());
      await pumpEventQueue();
      final request = asked()!;
      expect(request.title, 'Quit ShellX?');
      expect(request.body, oneBusy);
      expect(request.confirmLabel, 'Quit');
      expect(h.quits, 0);
      request.complete(true);
      await done;
      expect(h.quits, 1);
      expect(daemon.quits, 0, reason: 'the service is not asked to quit');
    });

    test('"Quit" with no shell but an AI agent at work: "no" stays', () async {
      await boot(ids: const []);
      aiTab(working: true);
      final done = run(const Quit());
      await pumpEventQueue();
      asked()!.complete(false);
      await done;
      expect(h.quits, 0);
      expect(files.layouts.where((l) => l.cleanExit), isEmpty);
    });

    test('"Quit" with shells, the first time: the explanation says that the '
        'agents stop too', () async {
      await boot();
      aiTab(working: true);
      final done = run(const Quit());
      await pumpEventQueue();
      final request = asked()!;
      expect(request.title, 'Your shells keep running');
      expect(request.body, contains('2 tabs keep running'));
      expect(request.body, endsWith(oneBusy));
      expect(request.confirmLabel, 'Quit');
      expect(request.secondaryLabel, 'Quit Completely');
      request.complete(true);
      await done;
      expect(h.quits, 1);
      expect(daemon.quits, 0);
    });

    test('"Quit" with shells, once the explanation was read: only the agents '
        'are asked about', () async {
      await boot();
      h.settings.values[SettingKeys.quitKeepsSessionsExplained] = true;
      aiTab(working: true);
      final done = run(const Quit());
      await pumpEventQueue();
      final request = asked()!;
      expect(request.title, 'Quit ShellX?');
      expect(request.body, oneBusy);
      request.complete(true);
      await done;
      expect(h.quits, 1);
      expect(daemon.quits, 0);
    });

    test('"Quit" with shells, once explained, and no agent at work: no '
        'dialog at all, as before', () async {
      await boot();
      h.settings.values[SettingKeys.quitKeepsSessionsExplained] = true;
      aiTab();
      await run(const Quit());
      expect(asked(), isNull);
      expect(h.quits, 1);
    });

    test('Quit(confirm: false) never asks', () async {
      await boot(ids: const []);
      aiTab(working: true);
      await run(const Quit(confirm: false));
      expect(asked(), isNull);
      expect(h.quits, 1);
    });

    test('"Quit Completely" with no shell but agents at work: asks, with '
        'the count', () async {
      await boot(ids: const []);
      aiTab(working: true);
      aiTab(working: true);
      final done = run(const QuitAll());
      await pumpEventQueue();
      final request = asked()!;
      expect(request.title, 'Quit ShellX?');
      expect(request.body, twoBusy);
      expect(request.confirmLabel, 'Quit Completely');
      request.complete(true);
      await done;
      expect(daemon.quits, 1);
      expect(h.quits, 1);
    });

    test('"Quit Completely" with shells and an agent at work: both are '
        'said', () async {
      await boot();
      aiTab(working: true);
      final done = run(const QuitAll());
      await pumpEventQueue();
      final body = asked()!.body;
      expect(body, contains('2 open tabs'));
      expect(body, endsWith(oneBusy));
      asked()!.complete(true);
      await done;
      expect(daemon.quits, 1);
    });

    test(
      '"Quit Completely" with nothing at work: no question, as before',
      () async {
        await boot(ids: const []);
        aiTab();
        await run(const QuitAll());
        expect(asked(), isNull);
        expect(daemon.quits, 1);
      },
    );
  });
}
