import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/tab_attention.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/activation.dart';
import 'package:shellx_desktop/src/ui/window_focus.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

import '../support/fake_local_sessions.dart';

void main() {
  late FakeLocalSessions local;
  late ProviderContainer c;
  late int activations;

  setUp(() {
    local = FakeLocalSessions();
    local.add(local.summary(1, origin: SessionOrigin.desktop, title: 'zsh'));
    local.add(local.summary(2, title: 'api'));
    activations = 0;
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
    c.read(tabAttentionProvider);
    // The window is shown but behind another app.
    c.read(windowRouterProvider.notifier).showTerminal();
    c.read(windowFocusProvider.notifier).set(false);
  });

  void open(int tabId) =>
      openTabFromNotification(c, tabId, activateApp: () => activations++);

  test('a click raises the window, activates the app, selects the tab and '
      'reads it at once (D16)', () async {
    final workspaces = c.read(sidebarWorkspacesProvider.notifier);
    await workspaces.create(moveTab: 2);
    final ws = c.read(sidebarWorkspacesProvider).workspaceOf(2)!;
    workspaces.setCollapsed(ws, true);
    c.read(terminalTabsProvider.notifier).select(1);
    local.notice(2, SessionNoticeKind.message, body: 'done');
    await pumpEventQueue();
    expect(c.read(tabAttentionProvider).hasUnread(2), isTrue);
    final raise = c.read(windowRouterProvider).raise;

    open(2);

    final window = c.read(windowRouterProvider);
    expect(window.visible, isTrue);
    expect(window.raise, raise + 1);
    expect(activations, 1);
    expect(c.read(terminalTabsProvider).selectedId, 2);
    expect(c.read(sidebarWorkspacesProvider).workspace(ws)!.collapsed, isFalse);
    expect(c.read(tabAttentionProvider).hasUnread(2), isFalse);
    expect(c.read(terminalFocusRequestProvider), 1);
  });

  test('a hidden window is shown again', () {
    c.read(windowRouterProvider.notifier).hideWindow();
    open(2);
    expect(c.read(windowRouterProvider).visible, isTrue);
    expect(c.read(terminalTabsProvider).selectedId, 2);
  });

  test('a closed tab only raises the window', () {
    final before = c.read(terminalTabsProvider).selectedId;
    final raise = c.read(windowRouterProvider).raise;
    open(99);
    expect(c.read(windowRouterProvider).raise, raise + 1);
    expect(activations, 1);
    expect(c.read(terminalTabsProvider).selectedId, before);
    expect(c.read(terminalFocusRequestProvider), 0);
  });

  test('A7 review M5: a command-line notification raises the window and '
      'reads the command-line entries', () {
    final before = c.read(terminalTabsProvider).selectedId;
    final raise = c.read(windowRouterProvider).raise;
    c.read(tabAttentionProvider.notifier).addCommandLine(body: 'cron');
    open(kCommandLineTabId);
    expect(c.read(windowRouterProvider).raise, raise + 1);
    expect(c.read(terminalTabsProvider).selectedId, before);
    expect(c.read(tabAttentionProvider).history.first.read, isTrue);
  });
}
