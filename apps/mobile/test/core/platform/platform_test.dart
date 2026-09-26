import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shellx_mobile/core/config/app_config.dart';
import 'package:shellx_mobile/core/platform/device_description.dart';
import 'package:shellx_mobile/core/platform/fresh_install.dart';
import 'package:shellx_mobile/core/platform/secure_key_value_store.dart';

void main() {
  group('SecureKeyValueStore', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({}));

    test('reads, writes and deletes through flutter_secure_storage', () async {
      final store = SecureKeyValueStore();
      expect(await store.read('auth_token'), isNull);
      await store.write('auth_token', 'tok');
      expect(await store.read('auth_token'), 'tok');
      await store.delete('auth_token');
      expect(await store.read('auth_token'), isNull);
    });

    test('deleteAll removes every key', () async {
      final store = SecureKeyValueStore();
      await store.write('a', '1');
      await store.write('b', '2');
      await store.deleteAll();
      expect(await store.read('a'), isNull);
      expect(await store.read('b'), isNull);
    });
  });

  group('wipeSecureStorageOnFreshInstall', () {
    test('wipes once on the first launch, then never again', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var wipes = 0;
      Future<void> wipe() async => wipes++;

      await wipeSecureStorageOnFreshInstall(prefs: prefs, wipe: wipe);
      await wipeSecureStorageOnFreshInstall(prefs: prefs, wipe: wipe);

      expect(wipes, 1);
      expect(prefs.getBool(installMarkerKey), isTrue);
    });

    test('a wipe that fails does not block launch and runs again on the next launch', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var wipes = 0;
      Object? error = StateError('keychain');
      Future<void> wipe() async {
        wipes++;
        final failure = error;
        if (failure != null) throw failure;
      }

      // Must complete instead of propagating the storage error.
      await wipeSecureStorageOnFreshInstall(prefs: prefs, wipe: wipe);
      expect(prefs.getBool(installMarkerKey), isNull);

      error = null;
      await wipeSecureStorageOnFreshInstall(prefs: prefs, wipe: wipe);
      expect(wipes, 2);
      expect(prefs.getBool(installMarkerKey), isTrue);
    });
  });

  test('describeThisDevice falls back to a generic name when the platform call fails', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // No device_info_plus implementation answers in a unit test: the call fails like a
    // PlatformException would on a phone.
    final device = await describeThisDevice();
    expect(device.name, Platform.isIOS ? 'iPhone' : 'Android');
  });

  group('formatAndroidModelName', () {
    test('prefixes the capitalised manufacturer unless the model already has it', () {
      expect(formatAndroidModelName('samsung', 'SM-S911B'), 'Samsung SM-S911B');
      expect(formatAndroidModelName('Google', 'Pixel 8'), 'Google Pixel 8');
      expect(formatAndroidModelName('Xiaomi', 'Xiaomi 13'), 'Xiaomi 13');
      expect(formatAndroidModelName('', 'Nokia G21'), 'Nokia G21');
    });
  });

  group('relayWebSocketUri', () {
    test('maps https to wss and http to ws on /v1/ws', () {
      expect(relayWebSocketUri(Uri.parse('https://relay.shellx.pro')).toString(), 'wss://relay.shellx.pro/v1/ws');
      expect(relayWebSocketUri(Uri.parse('http://127.0.0.1:8787')).toString(), 'ws://127.0.0.1:8787/v1/ws');
    });

    test('defaults to the production relay', () {
      expect(AppConfig.relayBaseUri.toString(), 'https://relay.shellx.pro');
    });
  });
}
