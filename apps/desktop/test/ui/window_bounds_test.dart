import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/ui/window_bounds.dart';

void main() {
  test('nothing stored: null (the host centres 1100×720)', () {
    expect(WindowBoundsStore(InMemorySettingsStore()).read(), isNull);
  });

  test('bounds round-trip through the settings', () async {
    final settings = InMemorySettingsStore();
    final store = WindowBoundsStore(settings);
    await store.write(const Rect.fromLTWH(40, 60, 1200, 800));
    expect(store.read(), const Rect.fromLTWH(40, 60, 1200, 800));
  });

  test('bounds below the minimum size are ignored', () async {
    final settings = InMemorySettingsStore();
    final store = WindowBoundsStore(settings);
    await store.write(const Rect.fromLTWH(0, 0, 300, 200));
    expect(store.read(), isNull);
  });

  test('a failing settings write is swallowed', () async {
    final settings = InMemorySettingsStore()..fail = true;
    await WindowBoundsStore(
      settings,
    ).write(const Rect.fromLTWH(0, 0, 900, 600));
  });

  test('the keys are in the shared_preferences allow-list', () {
    expect(
      SettingKeys.all,
      containsAll([
        SettingKeys.windowX,
        SettingKeys.windowY,
        SettingKeys.windowWidth,
        SettingKeys.windowHeight,
      ]),
    );
  });
}
