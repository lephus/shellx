import 'dart:ui' show Locale;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/agent/agent_controller.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/config/config_syntax.dart';
import 'package:shellx_desktop/src/config/shellx_config.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';
import 'package:shellx_desktop/src/terminal/pane_paste.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/terminal/user_commands.dart';
import 'package:shellx_desktop/src/tray/tray_action.dart';
import 'package:shellx_desktop/src/tray/tray_actions.dart';
import 'package:shellx_desktop/src/ui/terminal/close_tab.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

import '../support/config_harness.dart';
import '../support/fake_local_sessions.dart';
import '../support/fakes.dart';
import '../support/memory_config_fs.dart';

void main() {
  late FakeLocalSessions local;
  late ProviderContainer c;
  late MemoryConfigFs fs;
  late TestHarness h;
  final l10n = lookupAppLocalizations(const Locale('en'));

  setUp(() async {
    fs = MemoryConfigFs();
    local = FakeLocalSessions();
    h = TestHarness(settings: {'onboarding_done': true});
    c = ProviderContainer(
      overrides: [
        desktopServicesProvider.overrideWithValue(h.services()),
        localSessionsProvider.overrideWithValue(local),
        ...configOverrides(fs),
      ],
    );
    c.listen(terminalTabsProvider, (_, _) {});
    await h.seedSignedIn();
    await c
        .read(agentControllerProvider.notifier)
        .bootstrap(watchForWake: false);
    await c.read(terminalTabsProvider.notifier).openTab();
  });
  tearDown(() => c.dispose());

  TerminalTabs tabs() => c.read(terminalTabsProvider.notifier);
  TerminalTab tab() => c.read(terminalTabsProvider).selected!;
  WindowState window() => c.read(windowRouterProvider);

  Future<void> useConfirm(String value) async {
    fs.write(testConfigPaths().shellx, 'confirm-close-surface = $value\n');
    await loadConfig(c);
  }

  Future<void> splitTab() async {
    await tabs().split(SplitAxis.row);
    expect(tab().isSplit, isTrue);
  }

  Future<void> closePane(ConfirmClose mode, int paneId) => closePaneWithConfirm(
    tabs: tabs(),
    router: c.read(windowRouterProvider.notifier),
    l10n: l10n,
    tab: tab(),
    paneId: paneId,
    confirm: mode,
  );

  group('tray: close one session follows confirm-close-surface', () {
    test('never: a running one-pane tab closes without asking', () async {
      await useConfirm('false');
      final id = tab().id;
      local.setRunning(id, true);
      await pumpEventQueue();
      await c.read(trayActionsProvider).handle(CloseSession(id));
      expect(window().confirm, isNull);
      expect(local.closed, contains(id));
    });

    test('always: an idle one-pane tab asks; yes closes', () async {
      await useConfirm('always');
      final id = tab().id;
      final done = c.read(trayActionsProvider).handle(CloseSession(id));
      await pumpEventQueue();
      final request = window().confirm!;
      expect(request.body, l10n.confirmCloseAlwaysBody);
      request.complete(true);
      await done;
      expect(local.closed, contains(id));
    });
  });

  group('a pane of a split tab (D20)', () {
    test('always: an idle pane asks with the new body', () async {
      await splitTab();
      final pane = tab().paneOrder.last;
      final pending = closePane(ConfirmClose.always, pane);
      await pumpEventQueue();
      final request = window().confirm!;
      expect(request.body, l10n.confirmClosePaneAlwaysBody);
      request.complete(false);
      await pending;
      expect(tab().paneCount, 2);
    });

    test('never: a running pane closes without asking', () async {
      await splitTab();
      final pane = tab().paneOrder.last;
      local.setRunning(pane, true);
      await pumpEventQueue();
      await closePane(ConfirmClose.never, pane);
      expect(window().confirm, isNull);
      expect(tab().paneCount, 1);
    });

    test('closing the split tab: always asks with the pane count; never '
        'closes at once', () async {
      await splitTab();
      final id = tab().id;
      var pending = closeTabWithConfirm(
        tabs: tabs(),
        router: c.read(windowRouterProvider.notifier),
        l10n: l10n,
        tab: tab(),
        confirm: ConfirmClose.always,
      );
      await pumpEventQueue();
      expect(window().confirm!.body, l10n.confirmCloseAlwaysPanesBody(2));
      window().confirm!.complete(false);
      await pending;
      expect(c.read(terminalTabsProvider).tabs, isNotEmpty);
      pending = closeTabWithConfirm(
        tabs: tabs(),
        router: c.read(windowRouterProvider.notifier),
        l10n: l10n,
        tab: tab(),
        confirm: ConfirmClose.never,
      );
      await pending;
      expect(window().confirm, isNull);
      expect(
        c.read(terminalTabsProvider).tabs.where((t) => t.id == id),
        isEmpty,
      );
    });
  });

  test('text and commands to an exited pane do nothing', () async {
    final id = tab().focused.id;
    local.views[id]!.end(2);
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(tab().focused.exited, isTrue);
    local.views[id]!.writes.clear();
    final state = c.read(terminalTabsProvider);
    expect(sendTextToFocused(state, 'x'), CommandRun.noTerminal);
    final entry = ConfigEntry(file: '/c', line: 1, key: 'command', value: '');
    expect(
      runUserCommand(
        state,
        UserCommand(name: 'L', text: 'x', enter: true, origin: entry),
        sender: c.read(pasteSenderProvider),
        tabs: () => c.read(terminalTabsProvider),
      ),
      CommandRun.noTerminal,
    );
    expect(local.views[id]!.writes, isEmpty);
  });
}
