import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shellx_core/shellx_core.dart';

/// [KeyValueStore] backed by the iOS Keychain / Android Keystore (spec §5.1, §9.5).
///
/// The app registers exactly one instance (`Module.keyValueStore`, a lazy singleton): the
/// "one key even for concurrent calls" guarantee of `DeviceIdentity.loadOrCreate` only holds for
/// calls on the same instance (overview §5.5).
final class SecureKeyValueStore implements KeyValueStore {
  SecureKeyValueStore([FlutterSecureStorage? storage]) : _storage = storage ?? defaultStorage;

  /// `first_unlock_this_device`: Keychain items are never migrated to another
  /// device through a backup — the device private key must not leave the phone.
  static const FlutterSecureStorage defaultStorage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  /// Removes every item this app stored.
  Future<void> deleteAll() => _storage.deleteAll();
}
