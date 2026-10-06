import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/terminal/terminal_font_size.dart';

import '../support/fakes.dart';

void main() {
  test(
    '13 by default, steps of 1, clamped to 9–28, reset to 13, persisted',
    () {
      final h = TestHarness();
      final container = ProviderContainer.test(
        overrides: [desktopServicesProvider.overrideWithValue(h.services())],
      );
      final size = container.read(terminalFontSizeProvider.notifier);
      expect(container.read(terminalFontSizeProvider), 13);
      size.increase();
      expect(container.read(terminalFontSizeProvider), 14);
      expect(h.settings.ints[SettingKeys.terminalFontSize], 14);
      for (var i = 0; i < 40; i++) {
        size.increase();
      }
      expect(container.read(terminalFontSizeProvider), 28);
      for (var i = 0; i < 40; i++) {
        size.decrease();
      }
      expect(container.read(terminalFontSizeProvider), 9);
      size.reset();
      expect(container.read(terminalFontSizeProvider), 13);
    },
  );

  test('a stored size is read back (and clamped)', () {
    final h = TestHarness();
    h.settings.ints[SettingKeys.terminalFontSize] = 40;
    final container = ProviderContainer.test(
      overrides: [desktopServicesProvider.overrideWithValue(h.services())],
    );
    expect(container.read(terminalFontSizeProvider), 28);
  });

  test('the key is in the shared_preferences allow-list', () {
    expect(SettingKeys.all, contains(SettingKeys.terminalFontSize));
  });

  test('a failed save is logged by error type only', () async {
    final h = TestHarness();
    h.settings.fail = true;
    final logs = <String?>[];
    final original = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message);
    addTearDown(() => debugPrint = original);
    final container = ProviderContainer.test(
      overrides: [desktopServicesProvider.overrideWithValue(h.services())],
    );
    container.read(terminalFontSizeProvider.notifier).increase();
    await pumpEventQueue();
    expect(container.read(terminalFontSizeProvider), 14);
    expect(logs, ['terminal font size not saved: StateError']);
  });
}
