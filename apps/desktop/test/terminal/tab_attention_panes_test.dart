import 'dart:async';
import 'dart:ui';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/tab_attention.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/window_focus.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

import '../support/fake_local_sessions.dart';

void main() {
  late FakeLocalSessions local;
  late ProviderContainer c;

  AttentionState state() => c.read(tabAttentionProvider);
  TabAttention attention() => c.read(tabAttentionProvider.notifier);
  TerminalTabs tabs() => c.read(terminalTabsProvider.notifier);

  /// Notices reach listeners asynchronously; let them land.
  Future<void> settle() => pumpEventQueue();

  void setActive(bool active) {
    final router = c.read(windowRouterProvider.notifier);
    active ? router.showTerminal() : router.hideWindow();
    c.read(windowFocusProvider.notifier).set(active);
  }

  /// Tab 1 = panes 1 | 100, pane 100 focused; tab 2 alone.
  Future<void> boot({bool active = true}) async {
    c = ProviderContainer.test(
      overrides: [
        localSessionsProvider.overrideWithValue(local),
        appL10nProvider.overrideWithValue(
          lookupAppLocalizations(const Locale('en')),
        ),
        settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
      ],
    );
    c.read(terminalTabsProvider);
    c.read(sidebarWorkspacesProvider);
    state();
    await tabs().split(SplitAxis.row);
    setActive(active);
  }

  setUp(() {
    local = FakeLocalSessions();
    local.add(local.summary(1, origin: SessionOrigin.desktop, title: 'zsh'));
    local.add(local.summary(2, title: 'api'));
  });

  test('the focused pane is "seen"; another pane of the same tab is unread, '
      'bells included (D18)', () async {
    await boot();
    final arrivals = <AttentionArrival>[];
    attention().arrivals.listen(arrivals.add);
    local.notice(100, SessionNoticeKind.message, body: 'seen');
    local.notice(100, SessionNoticeKind.bell); // dropped (A4 D7)
    await settle();
    expect(state().unread, isEmpty);
    local.notice(1, SessionNoticeKind.message, body: 'build ok');
    local.notice(1, SessionNoticeKind.bell);
    await settle();
    expect(state().unread[1]!.count, 2);
    expect(state().unread[1]!.panes, {1: 2});
    expect(state().unreadPanes(1), {1});
    expect(state().paneHasUnread(1, 100), isFalse);
    expect(arrivals.map((a) => a.tabId), [1, 1]);
    expect(state().history.first.paneId, 1);
  });

  test('badge = sum over panes; dwell reads only the focused pane', () {
    fakeAsync((async) {
      unawaited(boot(active: false));
      async.flushMicrotasks();
      local.notice(1, SessionNoticeKind.message, body: 'a');
      local.notice(100, SessionNoticeKind.message, body: 'b');
      async.flushMicrotasks();
      expect(state().unread[1]!.count, 2);
      final reads = <int>[];
      attention().reads.listen(reads.add);
      setActive(true);
      async.elapse(const Duration(seconds: 2));
      expect(state().unread[1]!.panes, {1: 1}); // 100 (focused) read
      expect(reads, isEmpty); // the tab still has unread
      tabs().focusPane(1);
      async.elapse(const Duration(milliseconds: 999));
      expect(state().paneHasUnread(1, 1), isTrue);
      async.elapse(const Duration(milliseconds: 2));
      expect(state().hasUnread(1), isFalse);
      expect(reads, [1]);
    });
  });

  test('markRead(tab) reads every pane', () async {
    await boot(active: false);
    local.notice(1, SessionNoticeKind.message, body: 'a');
    local.notice(100, SessionNoticeKind.message, body: 'b');
    await settle();
    attention().markRead(1);
    expect(state().unread, isEmpty);
    expect(state().history.every((e) => e.read), isTrue);
  });

  test('a closed pane drops its unread; the tab id stays', () async {
    await boot();
    local.notice(1, SessionNoticeKind.message, body: 'a');
    await settle();
    final reads = <int>[];
    attention().reads.listen(reads.add);
    tabs().closePane(1);
    expect(state().hasUnread(1), isFalse);
    expect(state().history.single.read, isTrue);
    expect(reads, [1]);
    expect(c.read(terminalTabsProvider).tabs.first.id, 1);
  });

  test('jumpTo focuses the pane with the newest unread notice', () async {
    await boot(active: false);
    tabs().select(2);
    local.notice(100, SessionNoticeKind.message, body: 'older');
    local.notice(1, SessionNoticeKind.message, body: 'newest');
    await settle();
    expect(attention().jumpTo(1), isTrue);
    final tab = c.read(terminalTabsProvider).selected!;
    expect(tab.id, 1);
    expect(tab.focusedPaneId, 1);
    expect(state().hasUnread(1), isFalse);
  });
}
