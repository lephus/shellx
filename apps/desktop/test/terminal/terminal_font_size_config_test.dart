import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/terminal/terminal_font_size.dart';

import '../support/config_harness.dart';
import '../support/fakes.dart';
import '../support/memory_config_fs.dart';

void main() {
  late MemoryConfigFs fs;
  late TestHarness h;
  late ProviderContainer c;
  setUp(() {
    fs = MemoryConfigFs();
    h = TestHarness();
    c = ProviderContainer(
      overrides: [
        desktopServicesProvider.overrideWithValue(h.services()),
        ...configOverrides(fs),
      ],
    );
  });
  tearDown(() => c.dispose());

  /// After the test seeded the saved size (as at app start).
  Future<void> start() async {
    c.listen(terminalFontSizeProvider, (_, _) {});
    await loadConfig(c);
  }

  double size() => c.read(terminalFontSizeProvider);
  TerminalFontSize notifier() => c.read(terminalFontSizeProvider.notifier);

  test('no font-size: today (persisted ⌘+, default 13)', () async {
    await start();
    expect(size(), 13);
    notifier().increase();
    expect(size(), 14);
    expect(h.settings.ints[SettingKeys.terminalFontSize], 14);
  });

  test('no font-size: the saved size still applies (D38 migration)', () async {
    h.settings.ints[SettingKeys.terminalFontSize] = 18;
    await start();
    expect(size(), 18);
  });

  test(
    'font-size wins at load; ⌘+ is not persisted; ⌘0 returns to it (D12)',
    () async {
      h.settings.ints[SettingKeys.terminalFontSize] = 20;
      fs.write(testConfigPaths().shellx, 'font-size = 15\n');
      await start();
      expect(size(), 15);
      notifier().increase(2);
      expect(size(), 17);
      notifier().decrease(0.5);
      expect(size(), 16.5);
      expect(h.settings.ints[SettingKeys.terminalFontSize], 20);
      notifier().reset();
      expect(size(), 15);
      expect(h.settings.ints[SettingKeys.terminalFontSize], 20);
    },
  );

  test('another edit keeps ⌘+; a new font-size replaces it', () async {
    fs.write(testConfigPaths().shellx, 'font-size = 15\n');
    await start();
    notifier().increase();
    fs.write(testConfigPaths().shellx, 'font-size = 15\ncursor-style = bar\n');
    await loadConfig(c);
    expect(size(), 16);
    fs.write(testConfigPaths().shellx, 'font-size = 12\n');
    await loadConfig(c);
    expect(size(), 12);
  });

  test('font-size removed: back to the saved size, ⌘+ saved again', () async {
    h.settings.ints[SettingKeys.terminalFontSize] = 18;
    fs.write(testConfigPaths().shellx, 'font-size = 15\n');
    await start();
    expect(size(), 15);
    fs.write(testConfigPaths().shellx, 'cursor-style = bar\n');
    await loadConfig(c);
    expect(size(), 18);
    notifier().increase();
    expect(h.settings.ints[SettingKeys.terminalFontSize], 19);
    notifier().reset();
    expect(size(), 13);
  });
}
