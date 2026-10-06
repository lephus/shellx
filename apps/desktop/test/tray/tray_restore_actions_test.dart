import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/restore/restore_persistence.dart';
import 'package:shellx_desktop/src/tray/tray_action.dart';
import 'package:shellx_desktop/src/tray/tray_actions.dart';
import 'package:shellx_desktop/src/tray/tray_menu.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

import '../support/fakes.dart';
import '../support/restore_fakes.dart';

void main() {
  late TestHarness h;
  late RecordingFiles files;
  late ProviderContainer c;

  setUp(() {
    h = TestHarness();
    files = RecordingFiles();
    c = ProviderContainer.test(
      overrides: [
        desktopServicesProvider.overrideWithValue(h.services()),
        restoreStoreProvider.overrideWithValue(files),
      ],
    );
  });

  TrayLocalState local() => c.read(trayLocalStateProvider);

  test('the switch: off deletes every saved text at once and is stored; '
      'on again deletes nothing (D13)', () async {
    files.scrollbacks['k' * 32] = 'secret';
    c.listen(trayLocalStateProvider, (_, _) {});
    await pumpEventQueue();
    expect(local(), const TrayLocalState(hasSavedScrollback: true));

    final tray = c.read(trayActionsProvider);
    await tray.handle(const ToggleRestoreScrollback());
    await pumpEventQueue();
    expect(h.settings.values[SettingKeys.terminalRestoreScrollback], isFalse);
    expect(files.clears, 1);
    expect(files.scrollbacks, isEmpty);
    expect(
      local(),
      const TrayLocalState(restoreScrollback: false, hasSavedScrollback: false),
    );

    await tray.handle(const ToggleRestoreScrollback());
    await pumpEventQueue();
    expect(h.settings.values[SettingKeys.terminalRestoreScrollback], isTrue);
    expect(files.clears, 1);
    expect(local(), const TrayLocalState());
  });

  test('"Xóa nội dung đã lưu" deletes at once, without asking, and keeps '
      'the switch on (UI-A5 §3)', () async {
    files.scrollbacks['k' * 32] = 'secret';
    c.listen(trayLocalStateProvider, (_, _) {});
    await pumpEventQueue();
    await c.read(trayActionsProvider).handle(const ClearSavedScrollback());
    await pumpEventQueue();
    expect(files.clears, 1);
    expect(c.read(windowRouterProvider).confirm, isNull);
    expect(h.settings.values[SettingKeys.terminalRestoreScrollback], isNull);
    expect(local(), const TrayLocalState());
  });

  test('a switch that fails to store still rebuilds the menu from what is '
      'stored', () async {
    c.listen(trayLocalStateProvider, (_, _) {});
    await pumpEventQueue();
    expect(local().restoreScrollback, isTrue);
    // Stored off behind the menu's back; then the write fails.
    h.settings.values[SettingKeys.terminalRestoreScrollback] = false;
    h.settings.fail = true;
    await c.read(trayActionsProvider).handle(const ToggleRestoreScrollback());
    await pumpEventQueue();
    expect(local().restoreScrollback, isFalse);
  });
}
