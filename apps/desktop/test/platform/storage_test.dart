import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shellx_desktop/src/platform/secure_key_value_store.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('SecureKeyValueStore reads, writes and deletes', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final store = SecureKeyValueStore();
    expect(await store.read('auth_token'), isNull);
    await store.write('auth_token', 'secret');
    expect(await store.read('auth_token'), 'secret');
    await store.delete('auth_token');
    expect(await store.read('auth_token'), isNull);
  });

  test('SharedPrefsSettingsStore persists switches with defaults', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final settings = await SharedPrefsSettingsStore.open();
    expect(
      settings.getBool(SettingKeys.remoteAccess, defaultValue: true),
      isTrue,
    );
    await settings.setBool(SettingKeys.remoteAccess, false);

    final reopened = await SharedPrefsSettingsStore.open();
    expect(
      reopened.getBool(SettingKeys.remoteAccess, defaultValue: true),
      isFalse,
    );
  });

  test('InMemorySettingsStore returns defaults until set', () async {
    final settings = InMemorySettingsStore();
    expect(settings.getBool(SettingKeys.keepAwake, defaultValue: true), isTrue);
    await settings.setBool(SettingKeys.keepAwake, false);
    expect(
      settings.getBool(SettingKeys.keepAwake, defaultValue: true),
      isFalse,
    );
  });
}
