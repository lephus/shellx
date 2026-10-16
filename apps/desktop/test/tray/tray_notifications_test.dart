import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/agent/agent_controller.dart';
import 'package:shellx_desktop/src/agent/agent_state.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/tray/tray_action.dart';
import 'package:shellx_desktop/src/tray/tray_actions.dart';
import 'package:shellx_desktop/src/tray/tray_menu.dart';
import 'package:tray_manager/tray_manager.dart';

import '../support/fakes.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('vi'));

  MenuItem notifications(Menu menu) =>
      menu.items!.firstWhere((i) => i.key == TrayKeys.notifications);

  for (final signedIn in [true, false]) {
    test('"Thông báo" submenu, signed in: $signedIn (D20)', () {
      final state = AgentViewState(
        phase: signedIn ? AuthPhase.signedIn : AuthPhase.signedOut,
        desktopNotifications: true,
        desktopNotificationsOnlyUnfocused: false,
      );
      final menu = buildTrayMenu(state, l10n, TrayMenuIds());
      final sub = notifications(menu);
      expect(sub.label, 'Thông báo');
      final items = sub.submenu!.items!;
      expect(items[0].key, TrayKeys.desktopNotifications);
      expect(items[0].label, 'Thông báo trên máy tính');
      expect(items[0].checked, isTrue);
      expect(items[1].key, TrayKeys.desktopNotificationsOnlyUnfocused);
      expect(items[1].label, 'Chỉ khi cửa sổ không ở phía trước');
      expect(items[1].checked, isFalse);
      expect(items[1].disabled, isFalse);
      expect(items[2].type, 'separator');
      expect(items.last.key, TrayKeys.notifyThreshold);
      expect(items.last.submenu!.items, hasLength(5));
    });
  }

  test('both switches default to on', () {
    const state = AgentViewState(phase: AuthPhase.signedOut);
    expect(state.desktopNotifications, isTrue);
    expect(state.desktopNotificationsOnlyUnfocused, isTrue);
    final copy = state.copyWith(desktopNotifications: false);
    expect(copy.desktopNotifications, isFalse);
    expect(copy.desktopNotificationsOnlyUnfocused, isTrue);
  });

  test('"only when not in front" is disabled while notifications are off', () {
    final menu = buildTrayMenu(
      const AgentViewState(
        phase: AuthPhase.signedOut,
        desktopNotifications: false,
      ),
      l10n,
      TrayMenuIds(),
    );
    expect(notifications(menu).submenu!.items![1].disabled, isTrue);
  });

  test('keys map to actions', () {
    expect(
      trayActionForKey(TrayKeys.desktopNotifications),
      isA<ToggleDesktopNotifications>(),
    );
    expect(
      trayActionForKey(TrayKeys.desktopNotificationsOnlyUnfocused),
      isA<ToggleDesktopNotificationsOnlyUnfocused>(),
    );
  });

  test('the toggles are stored and read back at start, signed out too '
      '(D20, N1)', () async {
    final h = TestHarness();
    final container = ProviderContainer.test(
      overrides: [desktopServicesProvider.overrideWithValue(h.services())],
    );
    final agent = container.read(agentControllerProvider.notifier);
    await agent.bootstrap(watchForWake: false);
    AgentViewState state() => container.read(agentControllerProvider);
    expect(state().signedIn, isFalse);
    expect(state().desktopNotifications, isTrue);
    expect(state().desktopNotificationsOnlyUnfocused, isTrue);

    final tray = container.read(trayActionsProvider);
    await tray.handle(const ToggleDesktopNotifications());
    await tray.handle(const ToggleDesktopNotificationsOnlyUnfocused());
    expect(state().desktopNotifications, isFalse);
    expect(state().desktopNotificationsOnlyUnfocused, isFalse);
    expect(h.settings.values[SettingKeys.desktopNotifications], isFalse);
    expect(
      h.settings.values[SettingKeys.desktopNotificationsOnlyUnfocused],
      isFalse,
    );

    await tray.handle(const ToggleDesktopNotifications());
    expect(state().desktopNotifications, isTrue);
    expect(h.settings.values[SettingKeys.desktopNotifications], isTrue);

    final again = ProviderContainer.test(
      overrides: [desktopServicesProvider.overrideWithValue(h.services())],
    );
    await again
        .read(agentControllerProvider.notifier)
        .bootstrap(watchForWake: false);
    expect(again.read(agentControllerProvider).desktopNotifications, isTrue);
    expect(
      again.read(agentControllerProvider).desktopNotificationsOnlyUnfocused,
      isFalse,
    );
  });
}
