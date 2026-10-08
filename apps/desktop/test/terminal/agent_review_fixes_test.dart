import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart' hide AgentEvent;
import 'package:shellx_core/shellx_core.dart' show DriverSide;
import 'package:shellx_desktop/l10n/app_localizations.dart';
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
  var now = t0;

  TerminalTabs tabs() => c.read(terminalTabsProvider.notifier);
  AgentStatusNotifier agents() => c.read(agentStatusProvider.notifier);
  Map<int, AgentPane> records() => c.read(agentStatusProvider);
  AttentionState attention() => c.read(tabAttentionProvider);

  AgentEvent ev(int pane, AgentEventKind k, {int s = 0, String? message}) =>
      AgentEvent(
        pane: pane,
        agent: AgentKind.claude,
        kind: k,
        at: t0.add(Duration(seconds: s)),
        message: message,
      );

  /// Tab 1 = panes 1 | 100 (100 focused), tab 2 = pane 2 selected.
  Future<void> boot() async {
    now = t0;
    c = ProviderContainer.test(
      overrides: [
        localSessionsProvider.overrideWithValue(local),
        appL10nProvider.overrideWithValue(
          lookupAppLocalizations(const Locale('en')),
        ),
        settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
        agentStatusClockProvider.overrideWithValue(() => now),
      ],
    );
    c.read(terminalTabsProvider);
    c.read(sidebarWorkspacesProvider);
    c.read(tabAttentionProvider);
    await tabs().split(SplitAxis.row);
    tabs().select(2);
    c.read(windowRouterProvider.notifier).showTerminal();
    c.read(windowFocusProvider.notifier).set(true);
  }

  setUp(() {
    local = FakeLocalSessions();
    local.add(local.summary(1, origin: SessionOrigin.desktop));
    local.add(local.summary(2, origin: SessionOrigin.desktop));
  });

  test('1: the live region of a tab speaks at most once a minute', () async {
    await boot();
    Set<int> live() => c.read(agentLiveTabsProvider);
    agents().ingest(ev(1, AgentEventKind.needsInput));
    expect(live(), {1});
    agents().ingest(ev(1, AgentEventKind.running, s: 1));
    expect(live(), isEmpty);
    now = now.add(const Duration(seconds: 30));
    agents().ingest(ev(1, AgentEventKind.needsInput, s: 30));
    expect(live(), isEmpty); // 30 s after the last one
    agents().ingest(ev(1, AgentEventKind.running, s: 31));
    now = now.add(const Duration(seconds: 31)); // 61 s
    agents().ingest(ev(1, AgentEventKind.needsInput, s: 61));
    expect(live(), {1});
  });

  test('2: an OSC just before the hook event is one notification', () async {
    await boot();
    local.notice(1, SessionNoticeKind.message, body: 'Claude needs input');
    await pumpEventQueue();
    now = now.add(const Duration(seconds: 1));
    agents().ingest(ev(1, AgentEventKind.needsInput, s: 1, message: 'Allow?'));
    await pumpEventQueue();
    expect(local.notified, isEmpty);
    expect(attention().unread[1]!.count, 1);
    // 4 s after the OSC the hook speaks again.
    now = now.add(const Duration(seconds: 4));
    agents().ingest(ev(1, AgentEventKind.needsInput, s: 8, message: 'Again?'));
    await pumpEventQueue();
    expect(local.notified, hasLength(1));
  });

  test('3: opening and closing many panes leaves nothing behind', () async {
    await boot();
    for (var i = 0; i < 12; i++) {
      local.notifyOnOpen = true;
      await tabs().split(SplitAxis.row);
      final id = c.read(terminalTabsProvider).selected!.focusedPaneId;
      agents().ingest(ev(id, AgentEventKind.needsInput, message: 'x'));
      agents().ingest(ev(id, AgentEventKind.end, s: 1));
      local.notice(id, SessionNoticeKind.bell);
      await pumpEventQueue();
      tabs().closePane(id);
      await pumpEventQueue();
    }
    final alive = c
        .read(terminalTabsProvider)
        .tabs
        .expand((t) => t.panes.keys)
        .toSet();
    expect(agents().trackedPanes.difference(alive), isEmpty);
  });

  test('4: a paste or the phone answering also answers the question', () async {
    local.replace(
      local.summary(
        1,
        origin: SessionOrigin.desktop,
        attachedMobileId: 'phone',
        driver: DriverSide.desktop,
      ),
    );
    await boot();
    agents().ingest(ev(100, AgentEventKind.needsInput));
    tabs().noteUserInput(100); // a paste from the window
    expect(records()[100]!.state, AgentState.running);
    // The phone, attached to pane 1, takes the driver back by typing.
    agents().ingest(ev(1, AgentEventKind.needsInput, s: 2));
    local.views[1]!.driverController.add(DriverSide.phone);
    expect(records()[1]!.state, AgentState.running);
    // A pane the phone is not on: a driver change is not an answer.
    agents().ingest(ev(100, AgentEventKind.needsInput, s: 3));
    local.views[100]!.driverController.add(DriverSide.phone);
    expect(records()[100]!.state, AgentState.needsInput);
  });

  test('5: a late running after end does not bring the record back', () async {
    await boot();
    agents().ingest(ev(1, AgentEventKind.running, s: 5));
    agents().ingest(ev(1, AgentEventKind.end, s: 6));
    expect(records(), isEmpty);
    agents().ingest(ev(1, AgentEventKind.running, s: 4)); // reordered
    expect(records(), isEmpty);
    // A genuinely newer start is welcome; so is anything after the window.
    agents().ingest(ev(1, AgentEventKind.start, s: 7));
    expect(records()[1]!.state, AgentState.idle);
    agents().ingest(ev(1, AgentEventKind.end, s: 8));
    now = now.add(const Duration(seconds: 6));
    agents().ingest(ev(1, AgentEventKind.running, s: 3));
    expect(records()[1]!.state, AgentState.running);
  });
}
