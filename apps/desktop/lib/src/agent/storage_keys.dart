/// Secure-storage keys owned by the desktop app. `device_private_key`
/// (DeviceIdentity.storageKey) and `trusted_devices` (TrustedStore.storageKey)
/// are owned by shellx_core / shellx_agent.
abstract final class DesktopStorageKeys {
  static const String token = 'auth_token';
  static const String deviceId = 'device_id';
  static const String userId = 'user_id';
  static const String email = 'email';
}
