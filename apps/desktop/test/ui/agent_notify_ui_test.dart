import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart' hide AgentEvent;
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart'
    show appL10nProvider;
import 'package:shellx_desktop/src/terminal/agent_status.dart';
import 'package:shellx_desktop/src/terminal/agent_status_notifier.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/tab_attention.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/window_focus.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

import '../support/fake_local_sessions.dart';
import 'sidebar_test_harness.dart';

void main() {
  var now = DateTime.utc(2026, 10, 7, 12);
  late InMemorySettingsStore settings;

  setUp(() {
    now = DateTime.utc(2026, 10, 7, 12);
    settings = InMemorySettingsStore();
    local = FakeLocalSessions();
    local.add(local.summary(1, origin: SessionOrigin.desktop));
    local.add(local.summary(2, origin: SessionOrigin.desktop));
  });

  AgentEvent ev(
    int pane,
    AgentEventKind k, {
    int s = 0,
    String? message,
    AgentKind agent = AgentKind.claude,
  }) => AgentEvent(
    pane: pane,
    agent: agent,
    kind: k,
    at: now.add(Duration(seconds: s)),
    message: message,
  );

  Future<void> pump(WidgetTester t, {bool active = true}) async {
    await pumpSidebar(
      t,
      overrides: [
        agentStatusClockProvider.overrideWithValue(() => now),
        settingsStoreProvider.overrideWithValue(settings),
      ],
    );
    container.read(terminalTabsProvider.notifier).select(2);
    final router = container.read(windowRouterProvider.notifier);
    active ? router.showTerminal() : router.hideWindow();
    container.read(windowFocusProvider.notifier).set(active);
    await t.pump();
  }

  AgentStatusNotifier agents() => container.read(agentStatusProvider.notifier);
  AttentionState attention() => container.read(tabAttentionProvider);

  /// Notices reach the listener a turn later.
  Future<void> settle(WidgetTester t) async {
    await t.pump();
    await t.pump();
  }

  testSidebar('needs_input from a pane in another tab: one notification '
      'for that pane, a ring and an unread on its tab only', (t) async {
    await pump(t);
    agents().ingest(
      ev(1, AgentEventKind.needsInput, message: 'Allow Bash(rm -rf x)?'),
    );
    await settle(t);
    expect(local.notified, [(1, 'Claude Code', 'Allow Bash(rm -rf x)?')]);
    expect(attention().unread.keys, [1]);
    expect(attention().paneHasUnread(1, 1), isTrue);
    expect(attention().hasUnread(2), isFalse);
  });

  testSidebar('without a message the words are the default ones', (t) async {
    await pump(t);
    agents().ingest(ev(1, AgentEventKind.needsInput, agent: AgentKind.codex));
    await settle(t);
    expect(local.notified, [(1, 'Codex', 'Codex needs your input')]);
  });

  testSidebar('a hook notification and the OSC / bell right after it are '
      'one', (t) async {
    await pump(t);
    agents().ingest(ev(1, AgentEventKind.needsInput, message: 'Allow?'));
    await settle(t);
    expect(attention().unread[1]!.count, 1);
    // The agent's own OSC 9 and bell, 1 and 2 s later.
    now = now.add(const Duration(seconds: 1));
    local.notice(1, SessionNoticeKind.message, body: 'Claude needs input');
    now = now.add(const Duration(seconds: 1));
    local.notice(1, SessionNoticeKind.bell);
    await settle(t);
    expect(attention().unread[1]!.count, 1);
    expect(attention().history, hasLength(1));
    // Past 3 s from the hook event they count again.
    now = now.add(const Duration(seconds: 2)); // 4 s
    local.notice(1, SessionNoticeKind.message, body: 'later');
    await settle(t);
    expect(attention().unread[1]!.count, 2);
  });

  testSidebar('the merge is for the pane of the hook event only; a command '
      'that ended is never merged', (t) async {
    await pump(t);
    agents().ingest(ev(1, AgentEventKind.needsInput, message: 'Allow?'));
    await settle(t);
    local.notice(2, SessionNoticeKind.message, body: 'other pane');
    local.notice(
      1,
      SessionNoticeKind.command,
      command: CompletedCommand(
        commandLine: 'make',
        exitCode: 0,
        duration: const Duration(seconds: 40),
      ),
    );
    await settle(t);
    // Pane 2 is in view: its own notice is kept as read, not merged away.
    expect(attention().history.map((e) => e.paneId), contains(2));
    expect(attention().unread[1]!.count, 2);
  });

  testSidebar('a pane without hook events: the OSC notice works as '
      'before', (t) async {
    await pump(t);
    local.notice(1, SessionNoticeKind.message, body: 'hello');
    await settle(t);
    expect(attention().unread[1]!.count, 1);
    expect(local.notified, isEmpty);
  });

  testSidebar('a notice without a message says nothing; with one it '
      'says it', (t) async {
    await pump(t);
    agents().ingest(ev(1, AgentEventKind.notice));
    await settle(t);
    expect(local.notified, isEmpty);
    agents().ingest(
      ev(1, AgentEventKind.notice, s: 6, message: 'Subagent done'),
    );
    await settle(t);
    expect(local.notified, [(1, 'Claude Code', 'Subagent done')]);
    // A notice does not give the pane a state.
    expect(container.read(agentStatusProvider), isEmpty);
  });

  testSidebar('start, running and end never notify', (t) async {
    await pump(t);
    agents().ingest(ev(1, AgentEventKind.start));
    agents().ingest(ev(1, AgentEventKind.running, s: 1));
    agents().ingest(ev(1, AgentEventKind.end, s: 2, message: 'bye'));
    await settle(t);
    expect(local.notified, isEmpty);
    expect(attention().unread, isEmpty);
  });

  testSidebar('at most one hook notification per pane in 5 s', (t) async {
    await pump(t);
    agents().ingest(ev(1, AgentEventKind.needsInput, message: 'one'));
    agents().ingest(ev(1, AgentEventKind.needsInput, s: 3, message: 'two'));
    agents().ingest(ev(2, AgentEventKind.needsInput, s: 3, message: 'other'));
    agents().ingest(ev(1, AgentEventKind.needsInput, s: 6, message: 'three'));
    await settle(t);
    expect(
      [for (final n in local.notified) (n.$1, n.$3)],
      [(1, 'one'), (2, 'other'), (1, 'three')],
    );
  });

  testSidebar('finished: not after a 2 s turn, yes after a 40 s turn in a '
      'pane nobody watches, not in the watched one', (t) async {
    await pump(t);
    agents().ingest(ev(1, AgentEventKind.running));
    agents().ingest(ev(1, AgentEventKind.idle, s: 2));
    await settle(t);
    expect(local.notified, isEmpty);
    agents().ingest(ev(1, AgentEventKind.running, s: 10));
    agents().ingest(ev(1, AgentEventKind.idle, s: 50));
    await settle(t);
    expect(local.notified, [(1, 'Claude Code', 'Claude Code finished')]);
    expect(container.read(agentStatusProvider)[1]!.state, AgentState.done);
    // The pane in view (tab 2): the same turn tells nothing.
    agents().ingest(ev(2, AgentEventKind.running, s: 10));
    agents().ingest(ev(2, AgentEventKind.idle, s: 50));
    await settle(t);
    expect(local.notified, hasLength(1));
    expect(container.read(agentStatusProvider)[2]!.state, AgentState.idle);
  });

  testSidebar('the A4 rules apply: the pane in view is not rung', (t) async {
    await pump(t);
    agents().ingest(ev(2, AgentEventKind.needsInput, message: 'Allow?'));
    await settle(t);
    // It went through the same entry (and a phone push there) ...
    expect(local.notified, [(2, 'Claude Code', 'Allow?')]);
    // ... and the window did not ring the pane the user is looking at.
    expect(attention().unread, isEmpty);
    expect(attention().history.single.read, isTrue);
  });

  testSidebar('Vietnamese words for the default notifications', (t) async {
    await pumpSidebar(
      t,
      locale: const Locale('vi'),
      overrides: [
        agentStatusClockProvider.overrideWithValue(() => now),
        settingsStoreProvider.overrideWithValue(settings),
        appL10nProvider.overrideWithValue(
          lookupAppLocalizations(const Locale('vi')),
        ),
      ],
    );
    container.read(terminalTabsProvider.notifier).select(2);
    agents().ingest(ev(1, AgentEventKind.needsInput));
    agents().ingest(ev(1, AgentEventKind.running, s: 10));
    agents().ingest(ev(1, AgentEventKind.idle, s: 60));
    await settle(t);
    expect(
      [for (final n in local.notified) n.$3],
      ['Claude Code cần bạn trả lời', 'Claude Code đã xong'],
    );
  });

  testSidebar('no message or session id is ever printed', (t) async {
    final printed = <String>[];
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) printed.add(message);
    };
    try {
      await pump(t);
      agents().ingest(
        AgentEvent(
          pane: 1,
          agent: AgentKind.claude,
          kind: AgentEventKind.needsInput,
          at: now,
          message: 'TOPSECRET message',
          session: 'sess-TOPSECRET',
        ),
      );
      local.notice(1, SessionNoticeKind.message, body: 'TOPSECRET osc');
      agents().ingest(
        ev(1, AgentEventKind.end, s: 9, message: 'TOPSECRET end'),
      );
      await settle(t);
    } finally {
      debugPrint = original;
    }
    expect(printed.where((l) => l.contains('TOPSECRET')), isEmpty);
  });
}
