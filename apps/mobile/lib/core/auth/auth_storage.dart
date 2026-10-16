import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart';

/// Persistence of the signed-in account (spec §5.2, §9.5).
abstract class AuthStorage {
  static const String tokenKey = 'auth_token';
  static const String userIdKey = 'auth_user_id';
  static const String deviceIdKey = 'auth_device_id';
  static const String emailKey = 'auth_email';

  /// The saved session, or null when signed out.
  Future<AccountSession?> load();

  /// The email of the last account, kept after sign-out to prefill the login form.
  Future<String?> lastEmail();

  Future<void> save(AccountSession session);

  /// Spec §5.2: logging out on mobile deletes only the token. The device key
  /// and the machines pinned under `pinned_machines_<userId>` are kept so the
  /// same account can sign in again without re-pairing.
  Future<void> deleteToken();

  /// After `DELETE /v1/account`: forget everything tied to the deleted
  /// account — the session, the device private key, the machines pinned
  /// for [userId] (key `pinned_machines_<userId>`, overview §5.7) and its
  /// pending unpairs ([PendingUnpairs]; the relay deleted every pairing).
  Future<void> forgetAccount(String userId);
}

@LazySingleton(as: AuthStorage)
class AuthStorageImpl implements AuthStorage {
  AuthStorageImpl(this._store);

  final KeyValueStore _store;

  @override
  Future<AccountSession?> load() async {
    final token = await _store.read(AuthStorage.tokenKey);
    final userId = await _store.read(AuthStorage.userIdKey);
    final deviceId = await _store.read(AuthStorage.deviceIdKey);
    final email = await _store.read(AuthStorage.emailKey);
    if (token == null || userId == null || deviceId == null || email == null) return null;
    return AccountSession(userId: userId, deviceId: deviceId, token: token, email: email);
  }

  @override
  Future<String?> lastEmail() => _store.read(AuthStorage.emailKey);

  @override
  Future<void> save(AccountSession session) async {
    await _store.write(AuthStorage.userIdKey, session.userId);
    await _store.write(AuthStorage.deviceIdKey, session.deviceId);
    await _store.write(AuthStorage.emailKey, session.email);
    await _store.write(AuthStorage.tokenKey, session.token);
  }

  @override
  Future<void> deleteToken() => _store.delete(AuthStorage.tokenKey);

  @override
  Future<void> forgetAccount(String userId) async {
    for (final key in [AuthStorage.tokenKey, AuthStorage.userIdKey, AuthStorage.deviceIdKey, AuthStorage.emailKey]) {
      await _store.delete(key);
    }
    await _store.delete(DeviceIdentity.storageKey);
    await _store.delete('pinned_machines_$userId');
    await _store.delete(PendingUnpairs.storageKey(userId));
  }
}
