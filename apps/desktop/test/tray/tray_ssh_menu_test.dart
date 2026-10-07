import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/agent/agent_state.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/remote/ssh_settings.dart';
import 'package:shellx_desktop/src/restore/restore_persistence.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/tray/tray_action.dart';
import 'package:shellx_desktop/src/tray/tray_actions.dart';
import 'package:shellx_desktop/src/tray/tray_menu.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';
import 'package:tray_manager/tray_manager.dart';

import '../support/fakes.dart';
import '../support/restore_fakes.dart';

final vi = lookupAppLocalizations(const Locale('vi'));
final en = lookupAppLocalizations(const Locale('en'));

MenuItem? find(List<MenuItem> items, String key) {
  for (final i in items) {
    if (i.key == key) return i;
    final sub = i.submenu?.items;
    if (sub != null) {
      final hit = find(sub, key);
      if (hit != null) return hit;
    }
  }
  return null;
}

List<MenuItem> menu(
  AgentViewState state,
  AppLocalizations l10n, {
  TrayLocalState local = const TrayLocalState(),
}) => buildTrayMenu(state, l10n, TrayMenuIds(), local: local).items!;

void main() {
  const signedOut = AgentViewState(phase: AuthPhase.signedOut);
  const signedIn = AgentViewState(phase: AuthPhase.signedIn, email: 'a@b.c');

  for (final state in [signedOut, signedIn]) {
    test('"SSH" right after "Dòng lệnh" (signed in: ${state.signedIn})', () {
      for (final l10n in [en, vi]) {
        final items = menu(state, l10n);
        final cli = items.indexWhere((i) => i.key == TrayKeys.commandLine);
        expect(cli, greaterThanOrEqualTo(0));
        final ssh = items[cli + 1];
        expect(ssh.key, TrayKeys.ssh);
        expect(ssh.label, l10n.sshTrayMenu);
        expect(ssh.submenu!.items!.map((i) => i.key), [
          TrayKeys.sshConnect,
          TrayKeys.tmuxAttach,
          null,
          TrayKeys.sshHook,
          TrayKeys.sshClearRecent,
        ]);
        expect(ssh.submenu!.items![2].type, 'separator');
      }
      final items = menu(state, en);
      expect(find(items, TrayKeys.sshConnect)!.label, 'Connect over SSH…');
      expect(find(items, TrayKeys.tmuxAttach)!.label, 'Attach tmux session…');
      final hook = find(items, TrayKeys.sshHook)!;
      expect(hook.type, 'checkbox');
      expect(hook.checked, isTrue); // default on
      expect(
        find(items, TrayKeys.sshClearRecent)!.label,
        'Clear recent servers',
      );
      expect(find(menu(state, vi), TrayKeys.sshConnect)!.label, 'Kết nối SSH…');
    });
  }

  test('"Clear recent servers" is off with nothing to clear; the hook box '
      'follows the setting', () {
    var items = menu(signedOut, en);
    expect(find(items, TrayKeys.sshClearRecent)!.disabled, isTrue);
    items = menu(
      signedOut,
      en,
      local: const TrayLocalState(sshHook: false, hasRecentServers: true),
    );
    expect(find(items, TrayKeys.sshClearRecent)!.disabled, isFalse);
    expect(find(items, TrayKeys.sshHook)!.checked, isFalse);
  });

  test('keys map to actions', () {
    expect(trayActionForKey(TrayKeys.sshConnect), isA<OpenSshConnect>());
    expect(trayActionForKey(TrayKeys.tmuxAttach), isA<OpenTmuxAttach>());
    expect(trayActionForKey(TrayKeys.sshHook), isA<ToggleSshHook>());
    expect(
      trayActionForKey(TrayKeys.sshClearRecent),
      isA<ClearRecentServers>(),
    );
  });

  group('actions', () {
    late TestHarness h;
    late ProviderContainer c;

    setUp(() {
      h = TestHarness();
      c = ProviderContainer.test(
        overrides: [
          restoreStoreProvider.overrideWithValue(RecordingFiles()),
          desktopServicesProvider.overrideWithValue(h.services()),
        ],
      );
      c.listen(trayLocalStateProvider, (_, _) {});
    });

    Future<void> tap(TrayAction a) => c.read(trayActionsProvider).handle(a);
    TrayLocalState local() => c.read(trayLocalStateProvider);

    test(
      'Connect and Attach: the window, then the dialog on its tab',
      () async {
        await tap(const OpenSshConnect());
        var state = c.read(windowRouterProvider);
        expect(state.visible, isTrue);
        expect((state.route as SshConnectRoute).tab, SshDialogTab.ssh);
        await tap(const OpenTmuxAttach());
        state = c.read(windowRouterProvider);
        expect((state.route as SshConnectRoute).tab, SshDialogTab.tmux);
      },
    );

    test('the hook switch: stored, the menu re-renders, never asks', () async {
      expect(local().sshHook, isTrue);
      await tap(const ToggleSshHook());
      expect(h.settings.values[SettingKeys.sshRemoteHook], isFalse);
      expect(local().sshHook, isFalse);
      await tap(const ToggleSshHook());
      expect(h.settings.values[SettingKeys.sshRemoteHook], isTrue);
      expect(local().sshHook, isTrue);
      expect(c.read(windowRouterProvider).confirm, isNull);
    });

    test('Clear recent: at once, a neutral toast, the item goes off', () async {
      await rememberTarget(h.settings, SshTarget.parse('devbox')!);
      c.invalidate(trayLocalStateProvider);
      expect(local().hasRecentServers, isTrue);
      await tap(const ClearRecentServers());
      expect(recentTargets(h.settings), isEmpty);
      expect(local().hasRecentServers, isFalse);
      expect(
        c.read(terminalTabsProvider).notice,
        isA<SshRecentClearedNotice>(),
      );
      expect(c.read(windowRouterProvider).confirm, isNull);
    });
  });
}
