import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shellx_core/shellx_core.dart';

/// [KeyValueStore] over flutter_secure_storage.
///
/// The app must use a single shared [SecureKeyValueStore] instance
/// process-wide: `DeviceIdentity.loadOrCreate`'s guarantee that the device
/// key is generated exactly once under concurrent calls, and `TrustedStore`,
/// both depend on all callers going through the same instance (and
/// therefore the same in-flight-operation state) rather than separate
/// instances that happen to point at the same underlying storage.
///
/// * macOS: login keychain, service `pro.shellx.desktop`. The legacy
///   (file-based) keychain is used on purpose: the data-protection keychain
///   needs a `keychain-access-groups` entitlement backed by a provisioning
///   profile, which a Developer ID app outside the App Store does not have.
/// * Windows: flutter_secure_storage 10.x stores values in a DPAPI-encrypted
///   file (`flutter_secure_storage.dat` in the app support directory),
///   readable only by the current Windows user.
final class SecureKeyValueStore implements KeyValueStore {
  SecureKeyValueStore([FlutterSecureStorage? storage])
    : _storage = storage ?? defaultStorage;

  static const FlutterSecureStorage defaultStorage = FlutterSecureStorage(
    mOptions: MacOsOptions(
      accountName: 'pro.shellx.desktop',
      usesDataProtectionKeychain: false,
    ),
  );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
