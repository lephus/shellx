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

  group('saved bounds must still be on a display (a monitor unplugged)', () {
    const main = Rect.fromLTWH(0, 0, 1440, 900);
    const right = Rect.fromLTWH(1440, 0, 1920, 1080);
    const saved = Rect.fromLTWH(1600, 100, 1100, 720);

    test('on a connected display: restored', () {
      expect(restorableBounds(saved, [main, right]), saved);
    });

    test('its display is gone: null (the host centres the default)', () {
      expect(restorableBounds(saved, [main]), isNull);
    });

    test('only an edge on a display (centre off every display): null', () {
      expect(
        restorableBounds(const Rect.fromLTWH(1000, 100, 1100, 720), [main]),
        isNull,
      );
    });

    test('no display list (the query failed): kept as saved', () {
      expect(restorableBounds(saved, const []), saved);
    });

    test('nothing saved: null', () {
      expect(restorableBounds(null, [main]), isNull);
    });
  });
}
