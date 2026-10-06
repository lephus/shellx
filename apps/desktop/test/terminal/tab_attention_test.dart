import 'dart:ui';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
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
  AppLocalizations l10n() => c.read(appL10nProvider);

  /// Notices reach listeners asynchronously; let them land.
  Future<void> settle() => pumpEventQueue();

  void setActive(bool active) {
    final router = c.read(windowRouterProvider.notifier);
    active ? router.showTerminal() : router.hideWindow();
    c.read(windowFocusProvider.notifier).set(active);
  }

  void boot({bool active = false, String locale = 'en'}) {
    c = ProviderContainer.test(
      overrides: [
        localSessionsProvider.overrideWithValue(local),
        appL10nProvider.overrideWithValue(
          lookupAppLocalizations(Locale(locale)),
        ),
        settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
      ],
    );
    c.read(terminalTabsProvider);
    c.read(sidebarWorkspacesProvider);
    state();
    setActive(active);
  }

  setUp(() {
    local = FakeLocalSessions();
    local.add(local.summary(1, origin: SessionOrigin.desktop, title: 'zsh'));
    local.add(local.summary(2, title: 'api'));
    local.add(local.summary(3, title: 'web'));
  });

  test(
    'a notice for an unselected tab is unread with its text (D8, D9)',
    () async {
      boot(active: true);
      final arrivals = <AttentionArrival>[];
      attention().arrivals.listen(arrivals.add);
      local.notice(
        2,
        SessionNoticeKind.message,
        title: 'CI',
        body: 'green\nok',
      );
      local.notice(2, SessionNoticeKind.message, body: 'two');
      await settle();
      expect(state().unread[2]!.count, 2);
      expect(state().unread[2]!.text(l10n()), 'two');
      expect(state().history.first.text(l10n()), 'two');
      expect(state().history.last.text(l10n()), 'CI: green ok');
      expect(state().totalUnread, 2);
      expect(arrivals.map((a) => a.tabId), [2, 2]);
    },
  );

  test('the text is worded when shown, in the language shown then (F-4); '
      'a failed command is marked', () async {
    boot(locale: 'vi');
    local.notice(
      2,
      SessionNoticeKind.command,
      command: const CompletedCommand(
        commandLine: 'npm test',
        exitCode: 1,
        duration: Duration(seconds: 45),
      ),
    );
    local.notice(2, SessionNoticeKind.bell);
    await settle();
    final en = lookupAppLocalizations(const Locale('en'));
    expect(state().unread[2]!.text(en), 'Bell');
    expect(state().history.last.text(en), '✗ npm test · exit 1 · 45 s');
    expect(state().history.last.failed, isTrue);
    expect(state().history.first.failed, isFalse);
  });

  test('listenAttention re-subscribes when the provider rebuilds', () async {
    boot();
    final arrivals = <int>[];
    final reads = <int>[];
    final listener = listenAttention(
      c,
      onArrival: (a) => arrivals.add(a.tabId),
      onRead: reads.add,
    );
    local.notice(2, SessionNoticeKind.message, body: 'one');
    await settle();
    expect(arrivals, [2]);
    c.invalidate(tabAttentionProvider);
    state(); // rebuilt
    await settle();
    local.notice(3, SessionNoticeKind.message, body: 'two');
    await settle();
    expect(arrivals, [2, 3]);
    attention().markRead(3);
    expect(reads, [3]);
    listener.close();
    local.notice(2, SessionNoticeKind.message, body: 'three');
    await settle();
    expect(arrivals, [2, 3]);
  });

  test(
    'a command notice uses the push wording in the app language (D5)',
    () async {
      boot(locale: 'vi');
      local.notice(
        2,
        SessionNoticeKind.command,
        command: const CompletedCommand(
          commandLine: 'npm test',
          exitCode: 1,
          duration: Duration(seconds: 45),
        ),
      );
      await settle();
      expect(state().unread[2]!.text(l10n()), '✗ npm test · mã 1 · 45 giây');
    },
  );

  test('selected tab + active window: seen, no unread, no arrival; a bell '
      'there is dropped (D7)', () async {
    boot(active: true); // tab 1 is selected
    final arrivals = <AttentionArrival>[];
    attention().arrivals.listen(arrivals.add);
    local.notice(1, SessionNoticeKind.message, body: 'seen');
    local.notice(1, SessionNoticeKind.bell);
    await settle();
    expect(state().unread, isEmpty);
    expect(state().history.single.read, isTrue);
    expect(arrivals, isEmpty);
  });

  test('selected tab while the window is inactive: unread + arrival', () async {
    boot();
    final arrivals = <AttentionArrival>[];
    attention().arrivals.listen(arrivals.add);
    local.notice(1, SessionNoticeKind.message, body: 'away');
    await settle();
    expect(state().hasUnread(1), isTrue);
    expect(arrivals.single.tabId, 1);
  });

  test('a notice for a session that is not a tab here is ignored', () async {
    boot();
    local.notice(42, SessionNoticeKind.message, body: 'elsewhere');
    await settle();
    expect(state().unread, isEmpty);
    expect(state().history, isEmpty);
  });

  test('reading needs 1 s on the tab with the window active (D10)', () {
    fakeAsync((async) {
      boot(active: true);
      local.notice(2, SessionNoticeKind.message, body: 'x');
      async.flushMicrotasks();
      c.read(terminalTabsProvider.notifier).select(2);
      async.elapse(const Duration(milliseconds: 900));
      c.read(terminalTabsProvider.notifier).select(3);
      async.elapse(const Duration(seconds: 2));
      expect(state().hasUnread(2), isTrue); // left before 1 s
      c.read(terminalTabsProvider.notifier).select(2);
      async.elapse(const Duration(milliseconds: 500));
      setActive(false); // blur restarts
      async.elapse(const Duration(seconds: 2));
      expect(state().hasUnread(2), isTrue);
      setActive(true);
      // A notice for another tab meanwhile does not restart the clock.
      async.elapse(const Duration(milliseconds: 600));
      local.notice(3, SessionNoticeKind.message, body: 'y');
      async.elapse(const Duration(milliseconds: 399));
      expect(state().hasUnread(2), isTrue);
      async.elapse(const Duration(milliseconds: 1));
      expect(state().hasUnread(2), isFalse);
      expect(
        state().history.where((e) => e.tabId == 2).every((e) => e.read),
        isTrue,
      );
      expect(state().hasUnread(3), isTrue);
    });
  });

  test('a notice for the selected tab of an inactive window is read 1 s '
      'after the window comes back (D10)', () {
    fakeAsync((async) {
      boot();
      local.notice(1, SessionNoticeKind.message, body: 'away');
      async.elapse(const Duration(seconds: 5));
      expect(state().hasUnread(1), isTrue);
      setActive(true);
      async.elapse(const Duration(milliseconds: 999));
      expect(state().hasUnread(1), isTrue);
      async.elapse(const Duration(milliseconds: 1));
      expect(state().hasUnread(1), isFalse);
    });
  });

  test(
    'hiding the window restarts the 1 s read even with focus kept (D10)',
    () {
      fakeAsync((async) {
        boot(active: true);
        local.notice(2, SessionNoticeKind.message, body: 'x');
        async.flushMicrotasks();
        c.read(terminalTabsProvider.notifier).select(2);
        async.elapse(const Duration(milliseconds: 700));
        final router = c.read(windowRouterProvider.notifier);
        router.hideWindow(); // focus flag untouched
        async.elapse(const Duration(seconds: 2));
        expect(state().hasUnread(2), isTrue);
        router.showTerminal();
        async.elapse(const Duration(milliseconds: 999));
        expect(state().hasUnread(2), isTrue);
        async.elapse(const Duration(milliseconds: 1));
        expect(state().hasUnread(2), isFalse);
      });
    },
  );

  test('markRead / markAllRead; reads stream reports tab ids (D23)', () async {
    boot();
    final reads = <int>[];
    attention().reads.listen(reads.add);
    local.notice(2, SessionNoticeKind.message, body: 'a');
    local.notice(3, SessionNoticeKind.bell);
    await settle();
    attention().markRead(2);
    expect(state().hasUnread(2), isFalse);
    attention().markAllRead();
    expect(state().unread, isEmpty);
    expect(state().history.every((e) => e.read), isTrue);
    expect(reads, [2, 3]);
  });

  test('consecutive bells of a tab merge in history (D11)', () async {
    boot();
    final t = DateTime(2026, 10, 7, 9);
    local.notice(2, SessionNoticeKind.bell, at: t);
    local.notice(
      2,
      SessionNoticeKind.bell,
      at: t.add(const Duration(seconds: 6)),
    );
    await settle();
    expect(state().history, hasLength(1));
    expect(state().history.single.repeat, 2);
    expect(state().history.single.at, t.add(const Duration(seconds: 6)));
    expect(state().unread[2]!.count, 2);
    expect(state().unread[2]!.text(l10n()), 'Bell');
  });

  test('a flood keeps the newest 50 in history (D11)', () async {
    boot();
    for (var i = 0; i < 60; i++) {
      local.notice(2, SessionNoticeKind.message, body: '$i');
    }
    await settle();
    expect(state().history, hasLength(TabAttention.historyLimit));
    expect(state().history.first.text(l10n()), '59');
    expect(state().history.last.text(l10n()), '10');
    expect(state().unread[2]!.count, 60);
  });

  test(
    'a removed tab loses its unread; its history stays, closed (D26)',
    () async {
      boot();
      final reads = <int>[];
      attention().reads.listen(reads.add);
      local.notice(2, SessionNoticeKind.message, body: 'bye');
      await settle();
      c.read(terminalTabsProvider.notifier).close(2);
      await settle();
      expect(state().hasUnread(2), isFalse);
      expect(state().history.single.closed, isTrue);
      expect(state().history.single.tabLabel, 'api');
      expect(state().history.single.read, isTrue); // nothing left to read
      expect(reads, [2]);
      expect(attention().jumpTo(2), isFalse);
    },
  );

  test(
    'markAllRead after a tab closed leaves nothing unread (D11, D26)',
    () async {
      boot();
      local.notice(2, SessionNoticeKind.message, body: 'a');
      local.notice(3, SessionNoticeKind.message, body: 'b');
      await settle();
      c.read(terminalTabsProvider.notifier).close(2);
      await settle();
      attention().markAllRead();
      expect(state().totalUnread, 0);
      expect(state().history.every((e) => e.read), isTrue);
    },
  );

  test('markRead / markAllRead without unread change nothing; markAllRead '
      'is one update', () async {
    boot();
    var updates = 0;
    c.listen(tabAttentionProvider, (_, _) => updates++);
    attention().markRead(2);
    attention().markAllRead();
    expect(updates, 0);
    local.notice(2, SessionNoticeKind.message, body: 'a');
    local.notice(3, SessionNoticeKind.message, body: 'b');
    await settle();
    updates = 0;
    attention().markAllRead();
    expect(updates, 1);
    expect(state().unread, isEmpty);
  });

  group('noticeText (D9)', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    SessionNotice message({String? title, String? body}) => SessionNotice(
      sessionId: 1,
      kind: SessionNoticeKind.message,
      at: DateTime(2026, 10, 7),
      title: title,
      body: body,
    );

    test('a title without a body is just the title', () {
      expect(noticeText(message(title: 'CI'), l10n), 'CI');
      expect(noticeText(message(title: 'CI', body: ' '), l10n), 'CI');
    });

    test('C0, C1 controls and line/paragraph separators become one space', () {
      expect(
        noticeText(message(body: 'a\u0085b\u009bc\u2028d\u2029e\tf'), l10n),
        'a b c d e f',
      );
    });

    test('a command notice without its command does not throw', () {
      final n = SessionNotice(
        sessionId: 1,
        kind: SessionNoticeKind.command,
        at: DateTime(2026, 10, 7),
      );
      expect(noticeText(n, l10n), '');
    });
  });

  test('next unread follows sidebar order after the selected tab, wrapping '
      '(D13)', () async {
    boot();
    expect(attention().nextUnread(), isNull);
    local.notice(3, SessionNoticeKind.bell);
    local.notice(2, SessionNoticeKind.bell);
    await settle();
    expect(attention().nextUnread(), 2); // selected is 1
    c.read(terminalTabsProvider.notifier).select(2);
    expect(attention().nextUnread(), 3);
    c.read(terminalTabsProvider.notifier).select(3);
    expect(attention().nextUnread(), 2);
  });

  test('next unread follows sidebar order, not tab order, and includes '
      'collapsed workspaces (D13)', () async {
    boot();
    final workspaces = c.read(sidebarWorkspacesProvider.notifier);
    await workspaces.create(moveTab: 2); // sidebar: 1, 3 | 2
    final ws = c.read(sidebarWorkspacesProvider).workspaceOf(2)!;
    workspaces.setCollapsed(ws, true);
    local.notice(2, SessionNoticeKind.bell);
    local.notice(3, SessionNoticeKind.bell);
    await settle();
    expect(attention().nextUnread(), 3); // selected is 1
    c.read(terminalTabsProvider.notifier).select(3);
    expect(attention().nextUnread(), 2); // hidden, still found
  });

  test(
    'jumpTo selects, expands the workspace, reads, asks for focus (D16)',
    () async {
      boot();
      final workspaces = c.read(sidebarWorkspacesProvider.notifier);
      await workspaces.create(moveTab: 3);
      final ws = c.read(sidebarWorkspacesProvider).workspaceOf(3)!;
      workspaces.setCollapsed(ws, true);
      local.notice(3, SessionNoticeKind.message, body: 'here');
      await settle();
      expect(attention().jumpTo(3), isTrue);
      expect(c.read(terminalTabsProvider).selectedId, 3);
      expect(
        c.read(sidebarWorkspacesProvider).workspace(ws)!.collapsed,
        isFalse,
      );
      expect(state().hasUnread(3), isFalse);
      expect(c.read(terminalFocusRequestProvider), 1);
      expect(attention().jumpTo(99), isFalse);
    },
  );

  test('badge label caps at 99+', () {
    expect(unreadBadgeLabel(1), '1');
    expect(unreadBadgeLabel(99), '99');
    expect(unreadBadgeLabel(100), '99+');
  });

  test('A7 D23: command-line entries are history only', () async {
    boot(active: true);
    final arrivals = <AttentionArrival>[];
    attention().arrivals.listen(arrivals.add);
    final a = attention();
    a.addCommandLine(title: 'cron', body: 'done');
    final s = state();
    expect(s.history.first.tabId, kCommandLineTabId);
    expect(s.history.first.tabLabel, 'Command line');
    expect(s.history.first.text(l10n()), 'cron: done');
    expect(s.history.first.read, isFalse);
    expect(s.unread, isEmpty);
    expect(s.totalUnread, 0);
    expect(a.jumpTo(kCommandLineTabId), isFalse); // raises the window only
    // Announced as an arrival with its own title, for the system
    // notification (treated as unfocused there).
    expect(arrivals.single.tabId, kCommandLineTabId);
    expect(arrivals.single.title, 'cron');
    expect(arrivals.single.text, 'done');
    // Never "Tab closed": tab 0 is never in the tab list.
    await c.read(terminalTabsProvider.notifier).openTab();
    await settle();
    expect(state().history.first.closed, isFalse);
    expect(state().history.first.read, isFalse);
    a.markRead(kCommandLineTabId);
    expect(state().history.first.read, isTrue);
  });

  test('A7 D23: mark all as read includes command-line entries', () {
    boot();
    attention().addCommandLine(body: 'one');
    attention().markAllRead();
    expect(state().history.single.read, isTrue);
  });

  test('A7 D23: command-line entries count toward the 50-entry history', () {
    boot();
    for (var i = 0; i < 60; i++) {
      attention().addCommandLine(body: '$i');
    }
    expect(state().history, hasLength(TabAttention.historyLimit));
    expect(state().history.first.notice.body, '59');
  });
}
