import 'dart:async';
import 'dart:ui';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart' hide AgentEvent;
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/cli/cli_event_bus.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/terminal/agent_status.dart';
import 'package:shellx_desktop/src/terminal/agent_status_notifier.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/tab_attention.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/window_focus.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

import '../support/fake_local_sessions.dart';

final t0 = DateTime.utc(2026, 10, 7, 12);

void main() {
  late FakeLocalSessions local;
  late ProviderContainer c;
  var elapsed = Duration.zero;

  TerminalTabs tabs() => c.read(terminalTabsProvider.notifier);
  AgentStatusNotifier agents() => c.read(agentStatusProvider.notifier);
  Map<int, AgentPane> records() => c.read(agentStatusProvider);

  AgentEvent ev(
    int pane,
    AgentEventKind k, {
    int s = 0,
    AgentKind agent = AgentKind.claude,
    String? session,
  }) => AgentEvent(
    pane: pane,
    agent: agent,
    kind: k,
    at: t0.add(Duration(seconds: s)),
    session: session,
  );

  void setActive(bool active) {
    final router = c.read(windowRouterProvider.notifier);
    active ? router.showTerminal() : router.hideWindow();
    c.read(windowFocusProvider.notifier).set(active);
  }

  /// Tab 1 = panes 1 | 100 (100 focused); tab 2 = pane 2.
  Future<void> boot({bool active = true, DateTime Function()? clock}) async {
    elapsed = Duration.zero;
    c = ProviderContainer.test(
      overrides: [
        localSessionsProvider.overrideWithValue(local),
        appL10nProvider.overrideWithValue(
          lookupAppLocalizations(const Locale('en')),
        ),
        settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
        agentStatusClockProvider.overrideWithValue(
          clock ?? () => t0.add(elapsed),
        ),
      ],
    );
    c.read(terminalTabsProvider);
    c.read(sidebarWorkspacesProvider);
    c.read(tabAttentionProvider);
    await tabs().split(SplitAxis.row);
    setActive(active);
  }

  setUp(() {
    local = FakeLocalSessions();
    local.add(local.summary(1, origin: SessionOrigin.desktop, title: 'zsh'));
    local.add(local.summary(2, origin: SessionOrigin.desktop, title: 'api'));
  });

  test('an unknown pane is dropped; a known one gets a record', () async {
    await boot();
    expect(agents().ingest(ev(77, AgentEventKind.running)), isFalse);
    expect(records(), isEmpty);
    expect(agents().ingest(ev(1, AgentEventKind.running)), isTrue);
    expect(records()[1]!.state, AgentState.running);
  });

  test('20 events a second per pane; the 21st is dropped, a new second '
      'starts afresh, other panes are untouched', () async {
    await boot();
    for (var i = 0; i < 20; i++) {
      expect(agents().ingest(ev(1, AgentEventKind.running, s: i)), isTrue);
    }
    expect(agents().ingest(ev(1, AgentEventKind.idle, s: 21)), isFalse);
    expect(records()[1]!.state, AgentState.running);
    expect(agents().ingest(ev(2, AgentEventKind.running)), isTrue);
    elapsed = const Duration(milliseconds: 1001);
    expect(agents().ingest(ev(1, AgentEventKind.idle, s: 22)), isTrue);
  });

  test('a pane that closes loses its record', () async {
    await boot();
    agents().ingest(ev(1, AgentEventKind.running));
    agents().ingest(ev(100, AgentEventKind.running));
    tabs().closePane(1);
    expect(records().keys, [100]);
  });

  test('a shell that ended loses its record', () async {
    await boot();
    agents().ingest(ev(100, AgentEventKind.needsInput));
    local.summaries.removeWhere((s) => s.id == 100);
    local.views[100]!.end(3);
    await pumpEventQueue();
    expect(records(), isEmpty);
    expect(agents().ingest(ev(100, AgentEventKind.running)), isFalse);
  });

  test('running with 20 s of pane silence becomes idle; output keeps it '
      'running; needsInput never decays', () {
    fakeAsync((async) {
      unawaited(boot(clock: () => t0.add(async.elapsed)));
      async.flushMicrotasks();
      agents().ingest(ev(1, AgentEventKind.running));
      agents().ingest(ev(100, AgentEventKind.needsInput));
      async.elapse(const Duration(seconds: 15));
      expect(records()[1]!.state, AgentState.running);
      local.views[1]!.emit('still working');
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 15)); // 30 s, but 15 s silent
      expect(records()[1]!.state, AgentState.running);
      async.elapse(const Duration(seconds: 6)); // 21 s silent
      expect(records()[1]!.state, AgentState.idle);
      expect(records()[100]!.state, AgentState.needsInput);
      async.elapse(const Duration(minutes: 5));
      expect(records()[100]!.state, AgentState.needsInput);
      c.dispose();
      expect(async.pendingTimers, isEmpty);
    });
  });

  test(
    'the human typing answers a question; a script\'s send does not',
    () async {
      await boot();
      agents().ingest(ev(100, AgentEventKind.needsInput));
      // A pane's own keyboard path (the terminal view).
      final pane = c.read(terminalTabsProvider).tabOfSession(100)!.panes[100]!;
      expect(records()[100]!.state, AgentState.needsInput);
      pane.terminal.sendUserText('y');
      expect(records()[100]!.state, AgentState.running);
      // The terminal's own replies are not the human.
      agents().ingest(ev(100, AgentEventKind.needsInput, s: 5));
      pane.terminal.onOutput?.call('\x1b[0n');
      expect(records()[100]!.state, AgentState.needsInput);
      // Typing into a pane without a question changes nothing.
      pane.terminal.sendUserText('x');
      expect(records()[100]!.state, AgentState.running);
      final before = records();
      pane.terminal.sendUserText('x');
      expect(identical(records(), before), isTrue);
    },
  );

  test('done becomes idle when the pane comes into view', () async {
    await boot();
    // Pane 1 is in tab 1 but the focus is on 100.
    agents().ingest(ev(1, AgentEventKind.running));
    agents().ingest(ev(1, AgentEventKind.idle, s: 1));
    expect(records()[1]!.state, AgentState.done);
    tabs().focusPane(1);
    expect(records()[1]!.state, AgentState.idle);
  });

  test('done stays done while the window is not in front', () async {
    await boot(active: false);
    agents().ingest(ev(100, AgentEventKind.running));
    agents().ingest(ev(100, AgentEventKind.idle, s: 1));
    expect(records()[100]!.state, AgentState.done);
    setActive(true);
    expect(records()[100]!.state, AgentState.idle);
  });

  test('the tab shows the most urgent of its panes', () async {
    await boot();
    expect(c.read(agentTabStateProvider(1)), isNull);
    agents().ingest(ev(1, AgentEventKind.start));
    expect(c.read(agentTabStateProvider(1)), AgentState.idle);
    agents().ingest(ev(100, AgentEventKind.running));
    expect(c.read(agentTabStateProvider(1)), AgentState.running);
    agents().ingest(ev(1, AgentEventKind.needsInput, s: 1));
    expect(c.read(agentTabStateProvider(1)), AgentState.needsInput);
    expect(c.read(agentTabStateProvider(2)), isNull);
    expect(c.read(agentTabStateProvider(999)), isNull);
  });

  test('the record moves with its pane (A11 break and join)', () async {
    await boot();
    agents().ingest(ev(1, AgentEventKind.needsInput));
    expect(tabs().breakPane(1), isTrue);
    expect(records()[1]!.state, AgentState.needsInput);
    final own = c.read(terminalTabsProvider).tabOfSession(1)!.id;
    expect(own, isNot(1)); // a tab of its own now
    expect(c.read(agentTabStateProvider(own)), AgentState.needsInput);
    expect(c.read(agentTabStateProvider(1)), isNull);
    expect(tabs().joinPane(1, 1), isTrue);
    expect(c.read(agentTabStateProvider(1)), AgentState.needsInput);
  });

  test('agent.status goes out only when what shows changes', () async {
    await boot();
    final out = <Map<String, Object?>>[];
    c.read(cliEventBusProvider).events.listen(out.add);
    List<Map<String, Object?>> status() => [
      for (final e in out)
        if (e['kind'] == 'agent.status') e,
    ];
    agents().ingest(ev(100, AgentEventKind.start));
    agents().ingest(ev(100, AgentEventKind.running, s: 1));
    agents().ingest(ev(100, AgentEventKind.running, s: 2)); // same
    agents().ingest(ev(100, AgentEventKind.notice, s: 3)); // same
    agents().ingest(ev(100, AgentEventKind.end, s: 4));
    await pumpEventQueue();
    expect(
      [for (final e in status()) e['status']],
      ['idle', 'running', 'none'],
    );
    expect(status().first, {
      'kind': 'agent.status',
      'pane': 100,
      'tab': 1,
      'agent': 'claude',
      'status': 'idle',
    });
  });

  test('records and changes show nothing in toString', () async {
    await boot();
    agents().ingest(ev(1, AgentEventKind.running, session: 'secret'));
    expect('${records()[1]}', '…');
    final change = AgentStatusChange(
      pane: 1,
      tab: 1,
      agent: AgentKind.claude,
      state: AgentState.running,
    );
    expect('$change', '…');
  });

  test('a reconnect gives the record to the new pane id (A8 D22)', () async {
    local.notifyOnOpen = true;
    local.summaries.clear();
    local.views.clear();
    final devbox = SshTarget.parse('devbox')!;
    local.add(
      local.summary(
        1,
        origin: SessionOrigin.desktop,
        remote: SessionRemote(
          launch: SshLaunch(devbox),
          connected: true,
          home: '/home/me',
        ),
      ),
    );
    await boot();
    agents().ingest(ev(1, AgentEventKind.needsInput));
    final sent = <AgentStatusChange>[];
    agents().changes.listen(sent.add);
    // The connection is lost: the pane stays (it can reconnect).
    local.summaries.removeWhere((s) => s.id == 1);
    local.views[1]!.end(255);
    await pumpEventQueue();
    expect(records().keys, [1]);
    final fresh = await tabs().reconnect(1);
    await pumpEventQueue();
    expect(fresh, isNotNull);
    expect(records().keys, [fresh]);
    expect(records()[fresh]!.state, AgentState.needsInput);
    expect(c.read(agentTabStateProvider(1)), AgentState.needsInput);
    expect(sent, isEmpty); // the same pane to the user: nothing changed
  });
}
