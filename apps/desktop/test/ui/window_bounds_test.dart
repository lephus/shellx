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

    test('centre off every display: null', () {
      expect(
        restorableBounds(const Rect.fromLTWH(1500, 100, 1100, 720), [main]),
        isNull,
      );
    });

    test('A10 D27: hanging over an edge moves inside the display', () {
      expect(
        restorableBounds(const Rect.fromLTWH(1000, 100, 1100, 720), [main]),
        const Rect.fromLTWH(340, 100, 1100, 720),
      );
      expect(
        restorableBounds(const Rect.fromLTWH(-300, -50, 1100, 720), [main]),
        const Rect.fromLTWH(0, 0, 1100, 720),
      );
    });

    test('A10 D27: bigger than the display shrinks to its visible area', () {
      expect(
        restorableBounds(const Rect.fromLTWH(10, 10, 3000, 2000), [main]),
        main,
      );
      const bar = Rect.fromLTWH(0, 25, 1440, 875); // below the menu bar
      expect(
        restorableBounds(const Rect.fromLTWH(0, 0, 1600, 1000), [bar]),
        bar,
      );
    });

    test('A10 D27: a window that fits is not touched', () {
      expect(
        restorableBounds(const Rect.fromLTWH(100, 100, 900, 600), [main]),
        const Rect.fromLTWH(100, 100, 900, 600),
      );
    });

    test('A10 D27: the home display is the one with the centre', () {
      const wide = Rect.fromLTWH(1440, 0, 1920, 1080);
      expect(
        restorableBounds(const Rect.fromLTWH(1300, 100, 1100, 720), [
          main,
          wide,
        ]),
        const Rect.fromLTWH(1440, 100, 1100, 720),
        reason: 'centre 1850 is on the second display',
      );
    });

    test(
      'A10 D27: a tiny display never shrinks the window below its minimum',
      () {
        const tiny = Rect.fromLTWH(0, 0, 500, 300);
        final r = restorableBounds(const Rect.fromLTWH(0, 0, 900, 600), [
          tiny,
        ])!;
        expect(r.size, const Size(640, 400));
        expect(r.topLeft, Offset.zero);
      },
    );

    test('no display list (the query failed): kept as saved', () {
      expect(restorableBounds(saved, const []), saved);
    });

    test('nothing saved: null', () {
      expect(restorableBounds(null, [main]), isNull);
    });
  });
}
