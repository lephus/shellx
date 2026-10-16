import 'dart:ui';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart' hide AgentEvent;
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/terminal/agent_status.dart';
import 'package:shellx_desktop/src/terminal/agent_status_notifier.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/tab_attention.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/tools/tool_dock.dart';
import 'package:shellx_desktop/src/tools/tool_embed.dart';
import 'package:shellx_desktop/src/tools/tool_registry.dart';
import 'package:shellx_desktop/src/ui/window_focus.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

import '../support/fake_local_sessions.dart';

/// V2-3 D3, D4 with A4 and A12: a pane under a zoomed tool dock or under the
/// panel of a workspace shown without a tab is not in view — what it says
/// badges its tab and arrives (system notification, phone push), and it is
/// read only once the panes show again.
void main() {
  late FakeLocalSessions local;
  late ProviderContainer c;
  final t0 = DateTime.utc(2026, 10, 16, 9);

  /// What the window's listeners last heard (the badge, the notifications
  /// and the sidebar listen; none of them reads): asserting on these, never
  /// on a read, which would itself refresh what the providers depend on.
  late AttentionState heard;
  late Map<int, AgentPane> agentsHeard;
  late List<AttentionArrival> arrivals;

  ToolDockController dock() => c.read(toolDockProvider.notifier);
  AgentStatusNotifier agents() => c.read(agentStatusProvider.notifier);

  void setActive(bool active) {
    final router = c.read(windowRouterProvider.notifier);
    active ? router.showTerminal() : router.hideWindow();
    c.read(windowFocusProvider.notifier).set(active);
  }

  /// Tab 1 (pane 1, focused) is selected in an active window; the default
  /// workspace's dock shows a tool beside the panes. The attention and the
  /// agents are listened to, as the app's badge, notifications and sidebar
  /// do.
  void boot() {
    c = ProviderContainer.test(
      overrides: [
        localSessionsProvider.overrideWithValue(local),
        appL10nProvider.overrideWithValue(
          lookupAppLocalizations(const Locale('en')),
        ),
        settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
        agentStatusClockProvider.overrideWithValue(() => t0),
        // `tool-embed = auto` embeds on macOS.
        toolPlatformProvider.overrideWithValue(TargetPlatform.macOS),
      ],
    );
    c.read(terminalTabsProvider);
    c.read(sidebarWorkspacesProvider);
    c.read(toolDockProvider);
    arrivals = [];
    c.listen<AttentionState>(
      tabAttentionProvider,
      (_, next) => heard = next,
      fireImmediately: true,
    );
    listenAttention(c, onArrival: arrivals.add);
    c.listen<Map<int, AgentPane>>(
      agentStatusProvider,
      (_, next) => agentsHeard = next,
      fireImmediately: true,
    );
    setActive(true);
    final tool = c
        .read(toolRegistryProvider.notifier)
        .add(ws: kDefaultWorkspaceId, name: 'Board', url: 'localhost:5173')!;
    dock().open(kDefaultWorkspaceId, tool.id);
  }

  AgentEvent event(AgentEventKind kind, {int s = 0, String? message}) =>
      AgentEvent(
        pane: 1,
        agent: AgentKind.claude,
        kind: kind,
        at: t0.add(Duration(seconds: s)),
        message: message,
      );

  setUp(() {
    local = FakeLocalSessions();
    local.add(local.summary(1, origin: SessionOrigin.desktop, title: 'zsh'));
    local.add(local.summary(2, origin: SessionOrigin.desktop, title: 'api'));
  });

  test('beside the panes the dock covers nothing: the focused pane\'s notice '
      'is seen and its bell dropped, as without tools (A4 D7)', () {
    fakeAsync((async) {
      boot();
      async.elapse(Duration.zero);
      expect(c.read(terminalTabsProvider).selectedId, 1);
      local.notice(1, SessionNoticeKind.message, body: 'seen');
      local.notice(1, SessionNoticeKind.bell);
      async.flushMicrotasks();
      expect(heard.unread, isEmpty);
      expect(heard.history.single.read, isTrue);
      expect(arrivals, isEmpty);
    });
  });

  test('a zoomed dock covers the panes: a message and a bell from the '
      'selected tab\'s focused pane are unread and arrive; after Restore the '
      'dwell reads them in 1 s (A4 D7, D10; V2-3 D3)', () {
    fakeAsync((async) {
      boot();
      dock().setZoom(kDefaultWorkspaceId, true);
      async.elapse(Duration.zero);
      local.notice(1, SessionNoticeKind.message, body: 'Build finished');
      local.notice(1, SessionNoticeKind.bell);
      async.flushMicrotasks();
      expect(heard.unread[1]?.count, 2);
      expect(heard.paneHasUnread(1, 1), isTrue);
      expect(heard.history.where((e) => e.read), isEmpty);
      expect(
        [for (final a in arrivals) (a.tabId, a.kind)],
        [(1, AttentionKind.message), (1, AttentionKind.bell)],
      );
      async.elapse(const Duration(seconds: 5));
      expect(heard.hasUnread(1), isTrue, reason: 'no dwell while covered');
      dock().setZoom(kDefaultWorkspaceId, false); // Restore
      async.elapse(const Duration(milliseconds: 999));
      expect(heard.hasUnread(1), isTrue);
      async.elapse(const Duration(milliseconds: 1));
      expect(heard.hasUnread(1), isFalse);
      expect(heard.history.every((e) => e.read), isTrue);
    });
  });

  test('a workspace shown without a tab covers the panes: the notice is '
      'unread and arrives; once a tab is chosen the dwell reads it in 1 s '
      '(A4 D10; V2-3 R14)', () {
    fakeAsync((async) {
      boot();
      final ws = c
          .read(sidebarWorkspacesProvider.notifier)
          .createFor(name: 'B');
      final tool = c
          .read(toolRegistryProvider.notifier)
          .add(ws: ws, name: 'Docs', url: 'localhost:4000')!;
      dock().open(ws, tool.id);
      dock().showLoose(ws);
      async.elapse(Duration.zero);
      local.notice(1, SessionNoticeKind.message, body: 'Tests passed');
      async.flushMicrotasks();
      expect(heard.unread[1]?.count, 1);
      expect(arrivals.single.tabId, 1);
      async.elapse(const Duration(seconds: 5));
      expect(heard.hasUnread(1), isTrue, reason: 'no dwell while covered');
      // The tab still selected underneath, chosen again (its row): R14.
      dock().clearLoose();
      async.elapse(const Duration(milliseconds: 999));
      expect(heard.hasUnread(1), isTrue);
      async.elapse(const Duration(milliseconds: 1));
      expect(heard.hasUnread(1), isFalse);
    });
  });

  test("Claude's permission request from the covered focused pane badges "
      'its tab and arrives (A12 D10 through A4)', () {
    fakeAsync((async) {
      boot();
      dock().setZoom(kDefaultWorkspaceId, true);
      async.elapse(Duration.zero);
      agents().ingest(
        event(AgentEventKind.needsInput, message: 'Allow Bash(rm -rf build)?'),
      );
      async.flushMicrotasks();
      expect(agentsHeard[1]!.state, AgentState.needsInput);
      expect(local.notified.single.$3, 'Allow Bash(rm -rf build)?');
      expect(heard.unread[1]?.count, 1);
      expect(heard.history.single.read, isFalse);
      expect(arrivals.single.tabId, 1);
      expect(arrivals.single.text, contains('Allow Bash(rm -rf build)?'));
    });
  });

  test('an agent that finishes under a zoomed dock is done (unread), not '
      'idle; Restore reads it, as the window coming back does (A12 D9)', () {
    fakeAsync((async) {
      boot();
      dock().setZoom(kDefaultWorkspaceId, true);
      async.elapse(Duration.zero);
      agents().ingest(event(AgentEventKind.running));
      agents().ingest(event(AgentEventKind.idle, s: 1));
      expect(agentsHeard[1]!.state, AgentState.done);
      dock().setZoom(kDefaultWorkspaceId, false); // Restore
      async.elapse(Duration.zero);
      expect(agentsHeard[1]!.state, AgentState.idle);
    });
  });
}
