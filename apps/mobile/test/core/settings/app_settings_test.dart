import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;

/// A Keychain/Keystore that cannot be read (locked, corrupted, or a platform error).
class _UnreadableStore implements KeyValueStore {
  @override
  Future<String?> read(String key) => Future.error(PlatformException(code: 'keychain'));

  @override
  Future<void> write(String key, String value) async {}

  @override
  Future<void> delete(String key) async {}
}

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

  test('a store that cannot be read keeps the defaults: the biometric lock stays on', () async {
    final settings = AppSettings(_UnreadableStore());

    // Must complete instead of propagating the storage error (it runs before the first frame).
    await settings.load();

    expect(settings.fontSize.value, AppSettings.defaultFontSize);
    expect(settings.biometricLock.value, isTrue);
  });
}
