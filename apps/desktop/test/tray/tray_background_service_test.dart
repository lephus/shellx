import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/agent/agent_state.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/tray/tray_action.dart';
import 'package:shellx_desktop/src/tray/tray_actions.dart';
import 'package:shellx_desktop/src/tray/tray_menu.dart';
import 'package:tray_manager/tray_manager.dart';

import '../support/fakes.dart';

MenuItem? find(List<MenuItem> items, String key) {
  for (final i in items) {
    if (i.key == key) return i;
    final hit = i.submenu == null ? null : find(i.submenu!.items!, key);
    if (hit != null) return hit;
  }
  return null;
}

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final vi = lookupAppLocalizations(const Locale('vi'));

  for (final signedIn in [false, true]) {
    test('the switch is in the Terminal submenu, off by default '
        '(signedIn: $signedIn)', () {
      final state = signedIn
          ? const AgentViewState(phase: AuthPhase.signedIn, email: 'a@b.c')
          : const AgentViewState(phase: AuthPhase.signedOut);
      List<MenuItem> items(AppLocalizations l, TrayLocalState local) =>
          buildTrayMenu(state, l, TrayMenuIds(), local: local).items!;
      final off = find(
        items(en, const TrayLocalState()),
        TrayKeys.backgroundService,
      )!;
      expect(off.label, 'Keep shells running when the window closes');
      expect(off.checked, isFalse);
      final on = find(
        items(vi, const TrayLocalState(backgroundService: true)),
        TrayKeys.backgroundService,
      )!;
      expect(on.label, 'Giữ shell chạy khi đóng cửa sổ');
      expect(on.checked, isTrue);
      final terminal = items(
        en,
        const TrayLocalState(),
      ).firstWhere((i) => i.key == TrayKeys.terminal);
      expect(
        terminal.submenu!.items!.map((i) => i.key),
        contains(TrayKeys.backgroundService),
      );
    });
  }

  test('no UI text says daemon', () {
    for (final l in [en, vi]) {
      expect(l.trayBackgroundService.toLowerCase(), isNot(contains('daemon')));
      expect(
        l.backgroundServiceNextLaunch.toLowerCase(),
        isNot(contains('daemon')),
      );
    }
  });

  test('the key maps to the action', () {
    expect(
      trayActionForKey(TrayKeys.backgroundService),
      isA<ToggleBackgroundService>(),
    );
  });

  test('toggling stores the UI-owned key, rebuilds the menu state and says '
      'it applies next launch', () async {
    final h = TestHarness();
    final c = ProviderContainer.test(
      overrides: [desktopServicesProvider.overrideWithValue(h.services())],
    );
    c.listen(trayLocalStateProvider, (_, _) {});
    expect(c.read(trayLocalStateProvider).backgroundService, isFalse);
    await c.read(trayActionsProvider).handle(const ToggleBackgroundService());
    await pumpEventQueue();
    expect(h.settings.values[SettingKeys.backgroundService], isTrue);
    expect(c.read(trayLocalStateProvider).backgroundService, isTrue);
    expect(h.notifier.shown.single.body, en.backgroundServiceNextLaunch);
    await c.read(trayActionsProvider).handle(const ToggleBackgroundService());
    expect(h.settings.values[SettingKeys.backgroundService], isFalse);
  });
}
