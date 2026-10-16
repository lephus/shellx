import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/tray/tray_action.dart';
import 'package:shellx_desktop/src/tray/tray_actions.dart';
import 'package:shellx_desktop/src/tray/tray_menu.dart';

import '../support/fakes.dart';

void main() {
  test('the default is one value, read by one helper', () {
    final store = InMemorySettingsStore();
    expect(SettingKeys.backgroundServiceDefault, isFalse);
    expect(
      backgroundServiceEnabled(store),
      SettingKeys.backgroundServiceDefault,
    );
    store.setBool(SettingKeys.backgroundService, true);
    expect(backgroundServiceEnabled(store), isTrue);
  });

  test('the menu state and its toggle follow the helper', () async {
    final h = TestHarness();
    final c = ProviderContainer.test(
      overrides: [desktopServicesProvider.overrideWithValue(h.services())],
    );
    c.listen(trayLocalStateProvider, (_, _) {});
    expect(
      c.read(trayLocalStateProvider).backgroundService,
      backgroundServiceEnabled(h.settings),
    );
    expect(
      const TrayLocalState().backgroundService,
      SettingKeys.backgroundServiceDefault,
    );
    await c.read(trayActionsProvider).handle(const ToggleBackgroundService());
    expect(
      h.settings.values[SettingKeys.backgroundService],
      !SettingKeys.backgroundServiceDefault,
    );
  });

  test('nothing else reads the key with its own default (main.dart, tray)', () {
    for (final f in ['lib/main.dart', 'lib/src/tray/tray_actions.dart']) {
      final text = File(f).readAsStringSync();
      expect(text, contains('backgroundServiceEnabled('), reason: f);
      expect(
        RegExp(r'getBool\(\s*SettingKeys\.backgroundService\b').hasMatch(text),
        isFalse,
        reason: f,
      );
    }
  });
}
