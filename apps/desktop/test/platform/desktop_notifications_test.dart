import 'dart:ui';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/platform/desktop_notifications.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/tab_attention.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/window_focus.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

import '../support/fake_local_sessions.dart';
import '../support/fakes.dart';

void main() {
  late RecordingNotifier notifier;
  late InMemorySettingsStore settings;
  late List<int> opened;
  late List<String> logs;
  late DateTime now;
  late DesktopNotifications n;

  AttentionArrival msg(
    int tab,
    String text, {
    AttentionKind kind = AttentionKind.message,
  }) => AttentionArrival(tabId: tab, kind: kind, text: text, at: now);

  void boot() {
    notifier = RecordingNotifier();
    settings = InMemorySettingsStore();
    opened = [];
    logs = [];
    now = DateTime(2026, 10, 7, 9);
    n = DesktopNotifications(
      notifier: notifier,
      settings: settings,
      l10n: lookupAppLocalizations(const Locale('en')),
      onOpen: opened.add,
      now: () => now,
      log: logs.add,
    );
  }

  test('D14 matrix with "only when not in front" on (default)', () {
    fakeAsync((async) {
      boot();
      n.arrived(
        msg(1, 'a'),
        title: 'api',
        windowFocused: true,
        tabSelected: false,
      );
      n.arrived(
        msg(2, 'b'),
        title: 'web',
        windowFocused: false,
        tabSelected: true,
      );
      async.flushMicrotasks();
      expect(notifier.shown.map((s) => (s.title, s.body, s.id)), [
        ('web', 'b', DesktopNotifications.idFor(2)),
      ]);
    });
  });

  test('"only when not in front" off: an unselected tab notifies even when '
      'focused; a bell still needs an unfocused window', () {
    fakeAsync((async) {
      boot();
      settings.values[SettingKeys.desktopNotificationsOnlyUnfocused] = false;
      n.arrived(
        msg(1, 'a'),
        title: 'api',
        windowFocused: true,
        tabSelected: false,
      );
      n.arrived(
        msg(3, 'Bell', kind: AttentionKind.bell),
        title: 'zsh',
        windowFocused: true,
        tabSelected: false,
      );
      n.arrived(
        msg(4, 'Bell', kind: AttentionKind.bell),
        title: 'vim',
        windowFocused: false,
        tabSelected: false,
      );
      async.flushMicrotasks();
      expect(notifier.shown.map((s) => (s.title, s.body)), [
        ('api', 'a'),
        ('vim', 'Bell in this tab'),
      ]);
    });
  });

  test('switched off: nothing is posted; the settings are read on every '
      'notice (no restart)', () {
    fakeAsync((async) {
      boot();
      settings.values[SettingKeys.desktopNotifications] = false;
      n.arrived(
        msg(1, 'a'),
        title: 'api',
        windowFocused: false,
        tabSelected: false,
      );
      async.flushMicrotasks();
      expect(notifier.shown, isEmpty);
      settings.values[SettingKeys.desktopNotifications] = true;
      n.arrived(
        msg(1, 'b'),
        title: 'api',
        windowFocused: false,
        tabSelected: false,
      );
      async.flushMicrotasks();
      expect(notifier.shown.single.body, 'b');
    });
  });

  test('a burst posts the first at once and one coalesced after 3 s (D15)', () {
    fakeAsync((async) {
      boot();
      for (var i = 1; i <= 20; i++) {
        n.arrived(
          msg(1, '$i'),
          title: 'api',
          windowFocused: false,
          tabSelected: false,
        );
      }
      async.flushMicrotasks();
      expect(notifier.shown.single.body, '1');
      async.elapse(const Duration(seconds: 3));
      expect(notifier.shown.map((s) => s.body), [
        '1',
        '19 new notifications · 20',
      ]);
      expect(notifier.shown.map((s) => s.id).toSet(), {
        DesktopNotifications.idFor(1),
      });
    });
  });

  test('at most 6 posts per tab per 60 s, 20 per app (D15)', () {
    fakeAsync((async) {
      boot();
      for (var i = 0; i < 10; i++) {
        n.arrived(
          msg(1, '$i'),
          title: 'api',
          windowFocused: false,
          tabSelected: false,
        );
        async.elapse(const Duration(seconds: 4)); // past each burst window
        now = now.add(const Duration(seconds: 4));
      }
      expect(notifier.shown, hasLength(6));
      for (var tab = 10; tab < 40; tab++) {
        n.arrived(
          msg(tab, 'x'),
          title: 't',
          windowFocused: false,
          tabSelected: false,
        );
      }
      async.flushMicrotasks();
      expect(notifier.shown, hasLength(20));
      // The window slides: 60 s after the first post, tab 1 may post again.
      now = DateTime(2026, 10, 7, 9, 1);
      n.arrived(
        msg(1, 'again'),
        title: 'api',
        windowFocused: false,
        tabSelected: false,
      );
      async.flushMicrotasks();
      expect(notifier.shown.last.body, 'again');
    });
  });

  test('reading a tab cancels its pending burst and removes the delivered '
      'notification', () {
    fakeAsync((async) {
      boot();
      n.arrived(
        msg(1, 'a'),
        title: 'api',
        windowFocused: false,
        tabSelected: false,
      );
      n.arrived(
        msg(1, 'b'),
        title: 'api',
        windowFocused: false,
        tabSelected: false,
      );
      n.tabRead(1);
      async.elapse(const Duration(seconds: 5));
      expect(notifier.shown, hasLength(1));
      expect(notifier.closed, [DesktopNotifications.idFor(1)]);
    });
  });

  test('a click opens the tab (D16); an OS failure is swallowed and logged '
      'without the text (N9)', () {
    fakeAsync((async) {
      boot();
      n.arrived(
        msg(7, 'a'),
        title: 'api',
        windowFocused: false,
        tabSelected: false,
      );
      async.flushMicrotasks();
      notifier.shown.single.onClick!();
      expect(opened, [7]);
      notifier.fail = true;
      n.arrived(
        msg(8, 'secret text'),
        title: 'secret title',
        windowFocused: false,
        tabSelected: false,
      );
      async.flushMicrotasks(); // no unhandled error
      expect(logs, hasLength(1));
      expect(logs.single, isNot(contains('secret')));
    });
  });

  test('title and body are cut (UI-A4 §6)', () {
    fakeAsync((async) {
      boot();
      n.arrived(
        msg(1, 'b' * 300),
        title: 't' * 100,
        windowFocused: false,
        tabSelected: false,
      );
      async.flushMicrotasks();
      expect(notifier.shown.single.title.runes.length, 80);
      expect(notifier.shown.single.title, endsWith('…'));
      expect(notifier.shown.single.body!.runes.length, 200);
    });
  });

  test('dispose cancels pending bursts', () {
    fakeAsync((async) {
      boot();
      for (final text in ['a', 'b']) {
        n.arrived(
          msg(1, text),
          title: 'api',
          windowFocused: false,
          tabSelected: false,
        );
      }
      n.dispose();
      async.elapse(const Duration(seconds: 5));
      expect(notifier.shown, hasLength(1));
    });
  });

  group('listenForDesktopNotifications', () {
    late FakeLocalSessions local;
    late ProviderContainer c;
    final en = lookupAppLocalizations(const Locale('en'));

    void setActive(bool active) {
      final router = c.read(windowRouterProvider.notifier);
      active ? router.showTerminal() : router.hideWindow();
      c.read(windowFocusProvider.notifier).set(active);
    }

    setUp(() {
      local = FakeLocalSessions();
      local.add(local.summary(1, origin: SessionOrigin.desktop, title: 'zsh'));
      local.add(local.summary(2, title: 'api'));
      boot();
      c = ProviderContainer.test(
        overrides: [
          localSessionsProvider.overrideWithValue(local),
          appL10nProvider.overrideWithValue(en),
          settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
        ],
      );
      c.read(terminalTabsProvider);
      c.read(sidebarWorkspacesProvider);
      listenForDesktopNotifications(container: c, notifications: n, l10n: en);
    });

    test('an arrival is posted with the tab label, the live window state '
        'and the selection; a read closes it', () async {
      setActive(true);
      c.read(terminalTabsProvider.notifier).select(1);
      local.notice(2, SessionNoticeKind.message, body: 'done');
      await pumpEventQueue();
      // Focused window, "only when not in front" on: nothing yet.
      expect(notifier.shown, isEmpty);

      setActive(false);
      local.notice(2, SessionNoticeKind.message, body: 'again');
      await pumpEventQueue();
      expect(notifier.shown.map((s) => (s.title, s.body)), [('api', 'again')]);

      c.read(tabAttentionProvider.notifier).markRead(2);
      await pumpEventQueue();
      expect(notifier.closed, [DesktopNotifications.idFor(2)]);
      n.dispose();
    });

    test('with workspace headers the title names the workspace '
        '(UI-A4 §6)', () async {
      await c.read(sidebarWorkspacesProvider.notifier).create(moveTab: 2);
      final sidebar = c.read(sidebarWorkspacesProvider);
      final ws = sidebar.workspace(sidebar.workspaceOf(2)!)!;
      setActive(false);
      local.notice(2, SessionNoticeKind.message, body: 'done');
      local.notice(1, SessionNoticeKind.message, body: 'here');
      await pumpEventQueue();
      expect(notifier.shown.map((s) => s.title), [
        'api · ${ws.displayName(en)}',
        'zsh · ${en.workspaceDefaultName}',
      ]);
      n.dispose();
    });
  });
}
