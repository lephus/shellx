import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shellx_core/shellx_core.dart';

/// The bundle id of the released app (`macos/Runner/Configs/AppInfo.xcconfig`).
const String kProductionBundleId = 'pro.shellx.desktop';

/// The Keychain service (`kSecAttrService`, flutter_secure_storage's
/// `accountName`) of the app whose bundle id is [bundleId].
///
/// The released app keeps `pro.shellx.desktop`, where its users' items (the
/// device key, the sign-in, the trusted phones) already are. Any other
/// bundle id, such as an isolated test build (`pro.shellx.desktop.itest`,
/// `.smoketest`), gets a service of its own, equal to that id: it never
/// reads, writes or deletes the released app's items. An empty id (never
/// seen: every app bundle has one) is not the released app either.
String keychainServiceFor(String bundleId) =>
    bundleId.isEmpty ? '$kProductionBundleId.unknown' : bundleId;

/// [KeyValueStore] over flutter_secure_storage.
///
/// The app must construct exactly one [SecureKeyValueStore] and share that
/// same instance process-wide: `DeviceIdentity.loadOrCreate` (generate the
/// device key only once under concurrent calls) and `TrustedStore` both rely
/// on one instance per underlying storage, rather than separate instances
/// that happen to point at the same underlying storage.
///
/// * macOS: login keychain, service [keychainServiceFor] of the running
///   bundle id (`pro.shellx.desktop` for the released app). The legacy
///   (file-based) keychain is used on purpose: the data-protection keychain
///   needs a `keychain-access-groups` entitlement backed by a provisioning
///   profile, which a Developer ID app outside the App Store does not have.
/// * Windows: values are encrypted with a key held in the current user's
///   Windows Credential Manager and stored in the app's support directory,
///   readable only by the current Windows user.
final class SecureKeyValueStore implements KeyValueStore {
  /// [bundleId]: the running app's (`PackageInfo.packageName`, which is
  /// `CFBundleIdentifier` on macOS).
  SecureKeyValueStore({required String bundleId, FlutterSecureStorage? storage})
    : _storage = storage ?? storageFor(bundleId);

  /// The storage of the app whose bundle id is [bundleId].
  static FlutterSecureStorage storageFor(String bundleId) =>
      FlutterSecureStorage(
        mOptions: MacOsOptions(
          accountName: keychainServiceFor(bundleId),
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
