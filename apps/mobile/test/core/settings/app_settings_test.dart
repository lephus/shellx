import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;

void main() {
  test('defaults: font size 14 and biometric lock on (spec §5.6)', () async {
    final settings = AppSettings(InMemoryKeyValueStore());
    await settings.load();
    expect(settings.fontSize.value, 14);
    expect(settings.biometricLock.value, isTrue);
  });

  test('persists values, clamps the font size to 8..32 and notifies watchers', () async {
    final store = InMemoryKeyValueStore();
    final settings = AppSettings(store);
    final seen = <(double, bool)>[];
    final stop = effect(() => seen.add((settings.fontSize.value, settings.biometricLock.value)));
    addTearDown(stop);

    await settings.setFontSize(99);
    await settings.setBiometricLock(false);

    final reloaded = AppSettings(store);
    await reloaded.load();
    expect(reloaded.fontSize.value, 32);
    expect(reloaded.biometricLock.value, isFalse);
    expect(seen, [(14.0, true), (32.0, true), (32.0, false)]);

    await settings.setFontSize(2);
    expect(settings.fontSize.value, 8);
  });

  test('ignores a corrupt stored font size', () async {
    final store = InMemoryKeyValueStore();
    await store.write(AppSettings.fontSizeKey, 'large');
    final settings = AppSettings(store);
    await settings.load();
    expect(settings.fontSize.value, AppSettings.defaultFontSize);
  });
}
